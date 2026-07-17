import Foundation
import OhMyUsageDomain
import OhMyUsageInfrastructure
import Security

/**
 * [INPUT]: Reads and writes provider credentials through the unified KeychainAccessPolicy or isolated test storage.
 * [OUTPUT]: Exposes CraftMeter's process-gated credential vault; background reads/writes are memory-only until an explicit user unlock, with unchanged-value suppression and one-way historical migration.
 * [POS]: OhMyUsage Services security boundary; unstable Xcode/ad-hoc identities cannot turn startup refresh into Security.framework access, and failed mutations preserve prior state.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class KeychainService: @unchecked Sendable {
    enum SecureMutationIntent {
        case interactiveUserMutation
        case backgroundPersistence
    }

    private enum SecureVaultState {
        case locked
        case loading
        case available
        case unavailable
    }

    struct SecureStoreAdapter {
        var readData: @Sendable (_ service: String, _ account: String, _ interactive: Bool) -> Data?
        var readAll: @Sendable (_ service: String, _ interactive: Bool) -> [String: String]?
        var saveData: @Sendable (_ data: Data, _ service: String, _ account: String, _ interactive: Bool) -> Bool
        var deleteItem: @Sendable (_ service: String, _ account: String) -> Void
        var deleteAll: @Sendable (_ service: String) -> Void

        static let live = SecureStoreAdapter(
            readData: { service, account, interactive in
                KeychainService.liveReadData(service: service, account: account, interactive: interactive)
            },
            readAll: { service, interactive in
                KeychainService.liveReadAll(service: service, interactive: interactive)
            },
            saveData: { data, service, account, interactive in
                KeychainService.liveSaveData(data, service: service, account: account, interactive: interactive)
            },
            deleteItem: { service, account in
                KeychainService.liveDeleteItem(service: service, account: account)
            },
            deleteAll: { service in
                KeychainService.liveDeleteAll(service: service)
            }
        )
    }

    static let defaultServiceName = "craftmeter"
    static let legacyServiceName = "oh-myusage"
    static let historicalLegacyServiceNames = [
        "oh-myusage",
        "OhMyUsage",
        "AI Plan Monitor",
        "AIPlanMonitor"
    ]
    private static let vaultAccount = "__credential_vault__"
    private static let legacyMigrationDefaultsKey = "CraftMeter.Keychain.LegacyMigrationComplete"
    private static let secureAccessPreparedDefaultsKey = "CraftMeter.Keychain.SecureAccessPrepared"
    private static let credentialLengthDefaultsKey = "CraftMeter.Keychain.CredentialLengths"

    private let lock = NSLock()
    private let mutationLock = NSRecursiveLock()
    private let vaultStateCondition = NSCondition()
    private let fileManager: FileManager
    private let storageURL: URL?
    private let useFileStorage: Bool
    private let defaults: UserDefaults
    private let secureStore: SecureStoreAdapter
    private var tokenCache: [String: String] = [:]
    private var missingCache: Set<String> = []
    private var credentialLengthCache: [String: Int]?
    private var secureVaultState: SecureVaultState = .locked

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        defaults: UserDefaults = .standard,
        forceSecureStore: Bool = false,
        secureStore: SecureStoreAdapter = .live
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.secureStore = secureStore
        let resolvedStorageURL = storageURL ?? Self.defaultTestingStorageURL(
            fileManager: fileManager,
            forceSecureStore: forceSecureStore
        )
        self.storageURL = resolvedStorageURL
        self.useFileStorage = !forceSecureStore && resolvedStorageURL != nil
        if useFileStorage {
            loadFromDisk()
        }
    }

    private static func defaultTestingStorageURL(
        fileManager: FileManager,
        forceSecureStore: Bool
    ) -> URL? {
        guard !forceSecureStore else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTest_SESSION_IDENTIFIER"] != nil ||
            ProcessInfo.processInfo.processName.lowercased().contains("xctest") ||
            Bundle.main.bundlePath.lowercased().contains(".xctest") else {
            return nil
        }
        return fileManager.temporaryDirectory
            .appendingPathComponent("CraftMeterTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
    }

    private func cacheKey(service: String, account: String) -> String {
        "\(normalizedServiceName(service))::\(account)"
    }

    func cachedToken(service: String, account: String) -> String? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)
        lock.lock()
        defer { lock.unlock() }
        return tokenCache[key]
    }

    func cachedCredentialLength(service: String, account: String) -> Int? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        if let token = tokenCache[key], !token.isEmpty {
            lock.unlock()
            return token.count
        }
        lock.unlock()

        return credentialLengthSnapshot()[key]
    }

    func readToken(service: String, account: String) -> String? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        if let cached = tokenCache[key] {
            lock.unlock()
            return cached
        }
        if missingCache.contains(key) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let token: String?
        if useFileStorage {
            token = readFromDisk(service: normalizedService, account: account)
        } else {
            token = cachedSecureTokenIfAvailable(key: key)
        }

        lock.lock()
        if let token, !token.isEmpty {
            tokenCache[key] = token
            missingCache.remove(key)
        } else {
            missingCache.insert(key)
        }
        lock.unlock()
        if let token, !token.isEmpty, !useFileStorage {
            recordCredentialLengths([key: token.count])
        }
        return token
    }

    @discardableResult
    func saveToken(
        _ token: String,
        service: String,
        account: String,
        intent: SecureMutationIntent = .interactiveUserMutation
    ) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        if !useFileStorage {
            switch intent {
            case .interactiveUserMutation:
                guard prepareSecureStoreAccess() else { return false }
            case .backgroundPersistence:
                guard isVaultAvailableInCurrentProcess else { return false }
            }
        }

        lock.lock()
        if tokenCache[key] == token {
            missingCache.remove(key)
            lock.unlock()
            return true
        }
        var snapshot = tokenCache
        snapshot[key] = token
        lock.unlock()

        let ok: Bool
        if useFileStorage {
            ok = persist(snapshot)
        } else {
            ok = persistSecureSnapshot(snapshot, interactive: false)
        }
        guard ok else {
            return false
        }

        lock.lock()
        tokenCache[key] = token
        missingCache.remove(key)
        lock.unlock()

        if !useFileStorage {
            recordCredentialLengths([key: token.count])
            markSecureStorePrepared()
        }
        return true
    }

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        if !useFileStorage, !isVaultAvailableInCurrentProcess {
            guard prepareSecureStoreAccess() else { return false }
        }

        lock.lock()
        var snapshot = tokenCache
        snapshot.removeValue(forKey: key)
        lock.unlock()

        let ok = useFileStorage
            ? persist(snapshot)
            : persistSecureSnapshot(snapshot, interactive: false)
        guard ok else { return false }

        lock.lock()
        tokenCache.removeValue(forKey: key)
        missingCache.insert(key)
        lock.unlock()
        removeCredentialLength(for: key)
        return true
    }

    private var isVaultAvailableInCurrentProcess: Bool {
        guard !useFileStorage else { return true }
        vaultStateCondition.lock()
        defer { vaultStateCondition.unlock() }
        return secureVaultState == .available
    }

    private func markSecureStorePrepared() {
        defaults.set(true, forKey: Self.secureAccessPreparedDefaultsKey)
    }

    private func normalizedServiceName(_ service: String) -> String {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || Self.isLegacyServiceName(trimmed) {
            return Self.defaultServiceName
        }
        return trimmed
    }

    static func isLegacyServiceName(_ service: String) -> Bool {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        return historicalLegacyServiceNames.contains(trimmed)
    }

    private func cachedSecureTokenIfAvailable(key: String) -> String? {
        guard isVaultAvailableInCurrentProcess else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return tokenCache[key]
    }

    func prepareSecureStoreAccess() -> Bool {
        guard !useFileStorage else {
            return true
        }

        vaultStateCondition.lock()
        switch secureVaultState {
        case .available:
            vaultStateCondition.unlock()
            return true
        case .loading:
            repeat {
                vaultStateCondition.wait()
            } while secureVaultState == .loading
            let available = secureVaultState == .available
            vaultStateCondition.unlock()
            return available
        case .unavailable:
            vaultStateCondition.unlock()
            return false
        case .locked:
            secureVaultState = .loading
            vaultStateCondition.unlock()
        }

        let prepared = performExplicitSecureStorePreparation()

        vaultStateCondition.lock()
        secureVaultState = prepared ? .available : .unavailable
        vaultStateCondition.broadcast()
        vaultStateCondition.unlock()
        return prepared
    }

    private func performExplicitSecureStorePreparation() -> Bool {
        let vaultSnapshot = readVaultSnapshotFromSecureStore(interactive: false)
            ?? readVaultSnapshotFromSecureStore(interactive: true)
        if let vaultSnapshot {
            mergeIntoCache(vaultSnapshot)
        }

        let currentItems = vaultSnapshot == nil
            ? readCurrentServiceItemsForMigration(interactive: false) ?? [:]
            : [:]
        if !currentItems.isEmpty {
            mergeIntoCache(currentItems)
        }

        let legacyMigration = readLegacyItemsForMigration(interactive: false)
        if let legacyMigration, !legacyMigration.items.isEmpty {
            mergeIntoCache(legacyMigration.items)
        }

        let hasVault = vaultSnapshot != nil
        let needsPersist = !hasVault || !currentItems.isEmpty || !(legacyMigration?.items.isEmpty ?? true)
        let didPersistSnapshot: Bool
        if needsPersist {
            let snapshot = cachedSnapshot()
            didPersistSnapshot = persistSecureSnapshot(snapshot, interactive: false)
                || persistSecureSnapshot(snapshot, interactive: true)
        } else {
            didPersistSnapshot = true
        }

        guard hasVault || didPersistSnapshot else {
            return false
        }

        finishSecureStorePreparation()
        if didPersistSnapshot, let legacyMigration {
            completeLegacyMigration(accountsByService: legacyMigration.accountsByService)
        }
        return true
    }

    func isSecureStoreReady() -> Bool {
        isVaultAvailableInCurrentProcess
    }

    func resetAllStoredCredentials() {
        guard !useFileStorage else {
            lock.lock()
            tokenCache.removeAll()
            missingCache.removeAll()
            credentialLengthCache = nil
            lock.unlock()
            vaultStateCondition.lock()
            secureVaultState = .locked
            vaultStateCondition.broadcast()
            vaultStateCondition.unlock()
            defaults.removeObject(forKey: Self.credentialLengthDefaultsKey)
            if let storageURL {
                try? fileManager.removeItem(at: storageURL)
            }
            return
        }

        deleteAllSecureStoreItems(service: Self.defaultServiceName)
        for legacyService in Self.historicalLegacyServiceNames {
            deleteAllSecureStoreItems(service: legacyService)
        }
        defaults.removeObject(forKey: Self.legacyMigrationDefaultsKey)
        for legacyService in Self.historicalLegacyServiceNames {
            defaults.removeObject(forKey: Self.legacyMigrationDefaultsKey(for: legacyService))
        }
        defaults.removeObject(forKey: Self.secureAccessPreparedDefaultsKey)
        defaults.removeObject(forKey: Self.credentialLengthDefaultsKey)

        lock.lock()
        tokenCache.removeAll()
        missingCache.removeAll()
        credentialLengthCache = nil
        lock.unlock()
        vaultStateCondition.lock()
        secureVaultState = .locked
        vaultStateCondition.broadcast()
        vaultStateCondition.unlock()
    }

    private func readCurrentServiceItemsForMigration(interactive: Bool) -> [String: String]? {
        readAllFromSecureStore(service: Self.defaultServiceName, interactive: interactive)?
            .filter({ $0.key != Self.vaultAccount && !$0.key.isEmpty && !$0.value.isEmpty })
            .reduce(into: [String: String]()) { partialResult, entry in
                partialResult[cacheKey(service: Self.defaultServiceName, account: entry.key)] = entry.value
            }
    }

    private func readLegacyItemsForMigration(
        interactive: Bool
    ) -> (items: [String: String], accountsByService: [(service: String, accounts: [String])])? {
        var normalizedItems: [String: String] = [:]
        var accountsByService: [(service: String, accounts: [String])] = []

        for legacyService in Self.historicalLegacyServiceNames where !isLegacyMigrationComplete(for: legacyService) {
            guard let legacyItems = readAllFromSecureStore(service: legacyService, interactive: interactive)?
                .filter({ !$0.key.isEmpty && !$0.value.isEmpty }) else {
                continue
            }
            for entry in legacyItems {
                normalizedItems[cacheKey(service: Self.defaultServiceName, account: entry.key)] = entry.value
            }
            accountsByService.append((service: legacyService, accounts: Array(legacyItems.keys)))
        }

        guard !normalizedItems.isEmpty || !accountsByService.isEmpty else {
            return nil
        }

        return (normalizedItems, accountsByService)
    }

    private func completeLegacyMigration(accountsByService: [(service: String, accounts: [String])]) {
        for record in accountsByService {
            for account in record.accounts {
                deleteSecureStoreItem(service: record.service, account: account)
            }
            markLegacyMigrationComplete(for: record.service)
        }
    }

    private func isLegacyMigrationComplete(for service: String) -> Bool {
        if service == Self.legacyServiceName, defaults.bool(forKey: Self.legacyMigrationDefaultsKey) {
            return true
        }
        return defaults.bool(forKey: Self.legacyMigrationDefaultsKey(for: service))
    }

    private func markLegacyMigrationComplete(for service: String) {
        defaults.set(true, forKey: Self.legacyMigrationDefaultsKey(for: service))
        if service == Self.legacyServiceName {
            defaults.set(true, forKey: Self.legacyMigrationDefaultsKey)
        }
    }

    private static func legacyMigrationDefaultsKey(for service: String) -> String {
        let suffix = service
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        return "\(legacyMigrationDefaultsKey).\(suffix)"
    }

    private func cachedSnapshot() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return tokenCache
    }

    private func finishSecureStorePreparation() {
        lock.lock()
        missingCache.removeAll()
        lock.unlock()
        markSecureStorePrepared()
    }

    private func mergeIntoCache(_ items: [String: String]) {
        var lengths: [String: Int] = [:]
        lock.lock()
        for (key, value) in items where !value.isEmpty {
            tokenCache[key] = value
            missingCache.remove(key)
            lengths[key] = value.count
        }
        lock.unlock()
        if !lengths.isEmpty {
            recordCredentialLengths(lengths)
        }
    }

    private func credentialLengthSnapshot() -> [String: Int] {
        lock.lock()
        if let credentialLengthCache {
            lock.unlock()
            return credentialLengthCache
        }
        lock.unlock()

        let raw = defaults.dictionary(forKey: Self.credentialLengthDefaultsKey) ?? [:]
        let snapshot = raw.reduce(into: [String: Int]()) { partialResult, entry in
            if let length = entry.value as? Int {
                partialResult[entry.key] = length
            } else if let number = entry.value as? NSNumber {
                partialResult[entry.key] = number.intValue
            }
        }

        lock.lock()
        if let credentialLengthCache {
            lock.unlock()
            return credentialLengthCache
        }
        credentialLengthCache = snapshot
        lock.unlock()
        return snapshot
    }

    private func recordCredentialLengths(_ lengths: [String: Int]) {
        guard !lengths.isEmpty else { return }
        var snapshot = credentialLengthSnapshot()
        for (key, length) in lengths where length > 0 {
            snapshot[key] = length
        }
        lock.lock()
        credentialLengthCache = snapshot
        lock.unlock()
        defaults.set(snapshot, forKey: Self.credentialLengthDefaultsKey)
    }

    private func removeCredentialLength(for key: String) {
        var snapshot = credentialLengthSnapshot()
        snapshot.removeValue(forKey: key)
        lock.lock()
        credentialLengthCache = snapshot
        lock.unlock()
        defaults.set(snapshot, forKey: Self.credentialLengthDefaultsKey)
    }

    private func readVaultSnapshotFromSecureStore(interactive: Bool) -> [String: String]? {
        guard let data = readDataFromSecureStore(
            service: Self.defaultServiceName,
            account: Self.vaultAccount,
            interactive: interactive
        ) else {
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func persistSecureSnapshot(_ snapshot: [String: String], interactive: Bool) -> Bool {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(snapshot)
        } catch {
            return false
        }
        return saveDataToSecureStore(
            encoded,
            service: Self.defaultServiceName,
            account: Self.vaultAccount,
            interactive: interactive
        )
    }

    private func readDataFromSecureStore(service: String, account: String, interactive: Bool) -> Data? {
        secureStore.readData(service, account, interactive)
    }

    private func readAllFromSecureStore(service: String, interactive: Bool) -> [String: String]? {
        secureStore.readAll(service, interactive)
    }

    private func saveDataToSecureStore(_ data: Data, service: String, account: String, interactive: Bool) -> Bool {
        secureStore.saveData(data, service, account, interactive)
    }

    private func deleteSecureStoreItem(service: String, account: String) {
        secureStore.deleteItem(service, account)
    }

    private func deleteAllSecureStoreItems(service: String) {
        secureStore.deleteAll(service)
    }

    private func readFromDisk(service: String, account: String) -> String? {
        tokenCache["\(service)::\(account)"]
    }

    private func loadFromDisk() {
        guard let storageURL,
              fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        lock.lock()
        tokenCache = decoded
        missingCache.removeAll()
        lock.unlock()
    }

    private func persist(_ snapshot: [String: String]) -> Bool {
        guard let storageURL else { return false }
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func tokensFromEnumeratedKeychainRows(_ item: CFTypeRef?) -> [String: String]? {
        let rows: [[String: Any]]
        if let array = item as? [[String: Any]] {
            rows = array
        } else if let dict = item as? [String: Any] {
            rows = [dict]
        } else {
            return nil
        }

        var result: [String: String] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                continue
            }
            result[account] = token
        }
        return result
    }

}
