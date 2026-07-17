import XCTest
import Security
@testable import OhMyUsage

/**
 * [INPUT]: 依赖 KeychainService 的可注入 SecureStoreAdapter 与 KeychainGenericPasswordWriter 状态机。
 * [OUTPUT]: 验证 vault 显式解锁、进程级失败熔断、后台零 Security 调用、迁移、同值零写入及失败回滚。
 * [POS]: CraftMeterTests 的 CraftMeter vault 安全回归测试；全部系统存储调用均由 fake adapter 隔离。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class KeychainServiceTests: XCTestCase {
    func testEnumeratedKeychainRowsReuseReturnedData() {
        let rows: [[String: Any]] = [
            [
                kSecAttrAccount as String: "account-a",
                kSecValueData as String: Data("token-a".utf8)
            ],
            [
                kSecAttrAccount as String: "account-b",
                kSecValueData as String: Data("token-b".utf8)
            ],
            [
                kSecAttrAccount as String: "missing-data"
            ]
        ]

        let result = KeychainService.tokensFromEnumeratedKeychainRows(rows as CFTypeRef)

        XCTAssertEqual(result, [
            "account-a": "token-a",
            "account-b": "token-b"
        ])
    }

    func testLegacyServiceNameIsNormalizedToOhMyUsage() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = KeychainService(storageURL: tempURL)
        XCTAssertTrue(store.saveToken("secret", service: KeychainService.legacyServiceName, account: "demo"))

        let reloaded = KeychainService(storageURL: tempURL)
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo"), "secret")
        XCTAssertEqual(reloaded.readToken(service: KeychainService.legacyServiceName, account: "demo"), "secret")
    }

    func testHistoricalAIPlanMonitorServiceNamesNormalizeToOhMyUsage() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = KeychainService(storageURL: tempURL)
        XCTAssertTrue(store.saveToken("secret-a", service: "AI Plan Monitor", account: "demo-a"))
        XCTAssertTrue(store.saveToken("secret-b", service: "AIPlanMonitor", account: "demo-b"))

        let reloaded = KeychainService(storageURL: tempURL)
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo-a"), "secret-a")
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo-b"), "secret-b")
    }

    func testPrepareSecureStoreAccessMigratesHistoricalAIPlanMonitorServices() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let aiPlanKey = "\(KeychainService.defaultServiceName)::ai-plan-account"
        let aiPlanNoSpaceKey = "\(KeychainService.defaultServiceName)::aiplan-account"
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                guard !interactive else { return nil }
                if service == "AI Plan Monitor" {
                    return ["ai-plan-account": "ai-plan-token"]
                }
                if service == "AIPlanMonitor" {
                    return ["aiplan-account": "aiplan-token"]
                }
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[aiPlanKey], "ai-plan-token")
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[aiPlanNoSpaceKey], "aiplan-token")
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "ai-plan-account"), "ai-plan-token")
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "aiplan-account"), "aiplan-token")
    }

    func testLockedBackgroundReadsNeverTouchSecureStore() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        DispatchQueue.concurrentPerform(iterations: 20) { index in
            XCTAssertNil(store.readToken(service: KeychainService.defaultServiceName, account: "account-\(index)"))
        }

        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
        XCTAssertEqual(recorder.counts.saveData, 0)
        XCTAssertFalse(store.isSecureStoreReady())
    }

    func testReadTokenDoesNotMigrateHistoricalServiceBeforeExplicitUnlock() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if service == "AI Plan Monitor", account == "legacy-account" {
                    return Data("legacy-token".utf8)
                }
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        XCTAssertNil(store.readToken(service: KeychainService.defaultServiceName, account: "legacy-account"))
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
        XCTAssertEqual(recorder.counts.saveData, 0)
    }

    func testPrepareSecureStoreAccessReloadsVaultAfterNonInteractiveMiss() throws {
        let defaults = makeDefaults()
        let snapshot = [
            "\(KeychainService.defaultServiceName)::open.ailinyu.de/session-cookie": "cookie-value"
        ]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__",
                      interactive else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { _, _ in nil },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertNil(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/session-cookie"
            )
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/session-cookie"
            ),
            "cookie-value"
        )
    }

    func testPrepareSecureStoreAccessKeepsMigrationNonInteractive() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let looseKey = "\(KeychainService.defaultServiceName)::loose-account"
        let legacyKey = "\(KeychainService.defaultServiceName)::legacy-account"
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                guard !interactive else { return nil }
                if service == KeychainService.defaultServiceName {
                    return [
                        "__credential_vault__": "ignored",
                        "loose-account": "loose-token"
                    ]
                }
                if service == KeychainService.legacyServiceName {
                    return ["legacy-account": "legacy-token"]
                }
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "loose-account"), "loose-token")
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "legacy-account"), "legacy-token")
        XCTAssertEqual(recorder.counts.interactiveReadData, 1)
        XCTAssertEqual(recorder.counts.interactiveReadAll, 0)
        XCTAssertEqual(recorder.counts.interactiveSaveData, 0)
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[looseKey], "loose-token")
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[legacyKey], "legacy-token")
    }

    func testIsSecureStoreReadyDoesNotReadKeychainWithoutPreparedDefaults() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return nil
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return nil
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertFalse(defaults.bool(forKey: "CraftMeter.Keychain.SecureAccessPrepared"))
        XCTAssertFalse(store.isSecureStoreReady())
        XCTAssertFalse(defaults.bool(forKey: "CraftMeter.Keychain.SecureAccessPrepared"))
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
    }

    func testPreparedDefaultsDoNotUnlockCurrentProcess() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "CraftMeter.Keychain.SecureAccessPrepared")
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return nil
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return nil
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertFalse(store.isSecureStoreReady())
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
    }

    func testCachedCredentialLengthMemoizesDefaultsSnapshotUntilLocalWrite() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return nil
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let account = "display-account"
        let key = "\(KeychainService.defaultServiceName)::\(account)"
        defaults.set([key: 12], forKey: "CraftMeter.Keychain.CredentialLengths")

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertEqual(
            store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: account),
            12
        )

        defaults.set([key: 99], forKey: "CraftMeter.Keychain.CredentialLengths")

        XCTAssertEqual(
            store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: account),
            12
        )
        XCTAssertTrue(store.prepareSecureStoreAccess())
        recorder.reset()
        XCTAssertTrue(store.saveToken("updated-secret", service: KeychainService.defaultServiceName, account: account))
        XCTAssertEqual(
            store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: account),
            "updated-secret".count
        )
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
        XCTAssertEqual(recorder.counts.interactiveReadData, 0)
        XCTAssertEqual(recorder.counts.interactiveReadAll, 0)
    }

    func testPrepareSecureStoreAccessIsIdempotentAfterSuccess() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertTrue(store.prepareSecureStoreAccess())

        XCTAssertEqual(recorder.counts.readData, 2)
        XCTAssertEqual(recorder.counts.saveData, 1)
        XCTAssertEqual(recorder.counts.interactiveReadData, 1)
        XCTAssertEqual(recorder.counts.interactiveSaveData, 0)
    }

    func testPrepareSecureStoreAccessUsesNonInteractiveVaultWhenAvailable() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let snapshot = [
            "\(KeychainService.defaultServiceName)::cached-account": "cached-token"
        ]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__",
                      !interactive else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(
            store.readToken(service: KeychainService.defaultServiceName, account: "cached-account"),
            "cached-token"
        )
        XCTAssertEqual(recorder.counts.readData, 1)
        XCTAssertEqual(recorder.counts.interactiveReadData, 0)
        XCTAssertEqual(recorder.counts.saveData, 0)
    }

    func testSaveTokenSkipsRepeatedSecureVaultWriteForSameValue() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        XCTAssertTrue(store.prepareSecureStoreAccess())
        recorder.reset()

        XCTAssertTrue(store.saveToken("same-token", service: KeychainService.defaultServiceName, account: "account"))
        XCTAssertTrue(store.saveToken("same-token", service: KeychainService.defaultServiceName, account: "account"))

        XCTAssertEqual(recorder.counts.saveData, 1)
        XCTAssertEqual(recorder.counts.interactiveSaveData, 0)
    }

    func testSaveTokenLoadsExistingVaultNonInteractivelyAndSkipsSameValue() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let snapshot = ["\(KeychainService.defaultServiceName)::account": "same-token"]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__",
                      !interactive else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        XCTAssertTrue(store.saveToken("same-token", service: KeychainService.defaultServiceName, account: "account"))

        XCTAssertEqual(recorder.counts.readData, 1)
        XCTAssertEqual(recorder.counts.interactiveReadData, 0)
        XCTAssertEqual(recorder.counts.saveData, 0)
    }

    func testFailedSavePreservesPreviousCachedTokenAndLength() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let snapshot = ["\(KeychainService.defaultServiceName)::account": "old-token"]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__",
                      !interactive else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { _, _ in nil },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return false
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "account"), "old-token")
        XCTAssertEqual(store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: "account"), 9)
        recorder.reset()
        XCTAssertFalse(store.saveToken("new-token-value", service: KeychainService.defaultServiceName, account: "account"))

        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "account"), "old-token")
        XCTAssertEqual(store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: "account"), 9)
        XCTAssertEqual(recorder.counts.saveData, 1)
        XCTAssertEqual(recorder.counts.interactiveSaveData, 0)
    }

    func testBackgroundPersistenceSkipsLockedVaultWithoutSecureStoreCalls() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = makeRecordingAdapter(recorder: recorder, saveResult: true)
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        XCTAssertFalse(store.saveToken(
            "candidate",
            service: KeychainService.defaultServiceName,
            account: "account",
            intent: .backgroundPersistence
        ))
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
        XCTAssertEqual(recorder.counts.saveData, 0)
    }

    func testFailedExplicitUnlockIsProcessFused() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = makeRecordingAdapter(recorder: recorder, saveResult: false)
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)

        XCTAssertFalse(store.prepareSecureStoreAccess())
        let countsAfterFailure = recorder.counts
        XCTAssertFalse(store.prepareSecureStoreAccess())
        XCTAssertNil(store.readToken(service: KeychainService.defaultServiceName, account: "account"))
        XCTAssertFalse(store.saveToken(
            "candidate",
            service: KeychainService.defaultServiceName,
            account: "account",
            intent: .backgroundPersistence
        ))
        XCTAssertEqual(recorder.counts.readData, countsAfterFailure.readData)
        XCTAssertEqual(recorder.counts.readAll, countsAfterFailure.readAll)
        XCTAssertEqual(recorder.counts.saveData, countsAfterFailure.saveData)
    }

    func testConcurrentExplicitUnlockUsesSingleFlight() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let snapshot = ["\(KeychainService.defaultServiceName)::account": "token"]
        let encoded = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                Thread.sleep(forTimeInterval: 0.02)
                return encoded
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let store = KeychainService(defaults: defaults, forceSecureStore: true, secureStore: adapter)
        let results = ConcurrentBoolRecorder()

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            results.append(store.prepareSecureStoreAccess())
        }

        XCTAssertEqual(results.values.count, 20)
        XCTAssertTrue(results.values.allSatisfy { $0 })
        XCTAssertEqual(recorder.counts.readData, 1)
        XCTAssertEqual(recorder.counts.readAll, 4)
        XCTAssertEqual(recorder.counts.saveData, 0)
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "account"), "token")
    }

    func testGenericPasswordWriterAddsOnlyWhenUpdateCannotFindItem() {
        var addCount = 0

        XCTAssertTrue(KeychainGenericPasswordWriter.updateOrAdd(
            update: { errSecItemNotFound },
            add: {
                addCount += 1
                return errSecSuccess
            }
        ))
        XCTAssertEqual(addCount, 1)

        XCTAssertFalse(KeychainGenericPasswordWriter.updateOrAdd(
            update: { errSecInteractionNotAllowed },
            add: {
                addCount += 1
                return errSecSuccess
            }
        ))
        XCTAssertEqual(addCount, 1)
    }

    private func makeRecordingAdapter(
        recorder: KeychainReadRecorder,
        saveResult: Bool
    ) -> KeychainService.SecureStoreAdapter {
        KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return saveResult
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "KeychainServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class KeychainReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var readDataCount = 0
    private var readAllCount = 0
    private var saveDataCount = 0
    private var interactiveReadDataCount = 0
    private var interactiveReadAllCount = 0
    private var interactiveSaveDataCount = 0
    private var savedVaultSnapshots: [[String: String]] = []

    var counts: (
        readData: Int,
        readAll: Int,
        saveData: Int,
        interactiveReadData: Int,
        interactiveReadAll: Int,
        interactiveSaveData: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            readDataCount,
            readAllCount,
            saveDataCount,
            interactiveReadDataCount,
            interactiveReadAllCount,
            interactiveSaveDataCount
        )
    }

    var latestSavedVaultSnapshot: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return savedVaultSnapshots.last
    }

    func reset() {
        lock.lock()
        readDataCount = 0
        readAllCount = 0
        saveDataCount = 0
        interactiveReadDataCount = 0
        interactiveReadAllCount = 0
        interactiveSaveDataCount = 0
        savedVaultSnapshots.removeAll()
        lock.unlock()
    }

    func recordReadData(service: String, account: String, interactive: Bool = false) {
        _ = service
        _ = account
        lock.lock()
        readDataCount += 1
        if interactive {
            interactiveReadDataCount += 1
        }
        lock.unlock()
    }

    func recordReadAll(service: String, interactive: Bool = false) {
        _ = service
        lock.lock()
        readAllCount += 1
        if interactive {
            interactiveReadAllCount += 1
        }
        lock.unlock()
    }

    func recordSaveData(data: Data, service: String, account: String, interactive: Bool) {
        lock.lock()
        saveDataCount += 1
        if interactive {
            interactiveSaveDataCount += 1
        }
        if service == KeychainService.defaultServiceName,
           account == "__credential_vault__",
           let snapshot = try? JSONDecoder().decode([String: String].self, from: data) {
            savedVaultSnapshots.append(snapshot)
        }
        lock.unlock()
    }
}

private final class ConcurrentBoolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Bool) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
