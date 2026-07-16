import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: Reads bundled, cached, and public Models.dev provider catalogs plus normalized analytics records.
 * [OUTPUT]: Resolves provider-first, exact-model fallback ModelPricingQuote values and maintains a validated last-known-good cache.
 * [POS]: OhMyUsage Services pricing adapter; isolates external schema, networking, and persistence from scanners and aggregation.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class ModelPricingCatalog: @unchecked Sendable {
    typealias DataLoader = @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)

    private struct CatalogPayload: Codable {
        var schemaVersion: Int
        var fetchedAt: Date
        var sourceURL: String
        var providers: [Provider]
    }

    private struct Provider: Codable {
        var id: String
        var models: [Model]
    }

    private struct Model: Codable {
        var id: String
        var cost: Cost
    }

    private struct Cost: Codable, Equatable {
        var input: Decimal?
        var output: Decimal?
        var reasoning: Decimal?
        var cacheRead: Decimal?
        var cacheWrite: Decimal?

        enum CodingKeys: String, CodingKey {
            case input
            case output
            case reasoning
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }

    private struct RemoteProvider: Decodable {
        var id: String
        var models: [String: RemoteModel]
    }

    private struct RemoteModel: Decodable {
        var id: String
        var cost: Cost?
    }

    private static let schemaVersion = 1
    private static let sourceURL = URL(string: "https://models.dev/api.json")!
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let supportedProviders = Set(["openai", "anthropic", "google", "alibaba", "moonshotai", "deepseek"])

    private let fileManager: FileManager
    private let cacheURL: URL
    private let nowProvider: () -> Date
    private let dataLoader: DataLoader
    private let lock = NSLock()
    private var payload: CatalogPayload
    private var refreshTask: Task<Void, Never>?

    init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init,
        dataLoader: DataLoader? = nil,
        bundledData: Data? = nil
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.dataLoader = dataLoader ?? { request in
            try await URLSession.shared.data(for: request)
        }
        let root = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("CraftMeter", isDirectory: true)
        self.cacheURL = root.appendingPathComponent("model_pricing_catalog.json")

        let decoder = Self.decoder()
        let cached = try? Data(contentsOf: cacheURL)
        let bundled = bundledData ?? Self.bundledCatalogData()
        self.payload = [cached, bundled]
            .compactMap { $0 }
            .compactMap { try? decoder.decode(CatalogPayload.self, from: $0) }
            .first(where: Self.isValid)
            ?? CatalogPayload(
                schemaVersion: Self.schemaVersion,
                fetchedAt: .distantPast,
                sourceURL: Self.sourceURL.absoluteString,
                providers: []
            )
    }

    deinit {
        refreshTask?.cancel()
    }

    func quote(for record: UsageAnalyticsRecord) -> ModelPricingQuote? {
        guard !Self.disallowsCatalogFallback(for: record) else { return nil }
        lock.lock()
        let currentPayload = payload
        lock.unlock()

        if let providerID = Self.catalogProviderID(for: record),
           let match = Self.exactMatch(
               modelID: record.modelID,
               providerID: providerID,
               providers: currentPayload.providers
           ) {
            return Self.quote(
                providerID: providerID,
                model: match,
                payload: currentPayload
            )
        }

        let fallbackMatches = Self.exactMatches(
            modelID: record.modelID,
            providers: currentPayload.providers
        )
        guard let first = fallbackMatches.first,
              fallbackMatches.dropFirst().allSatisfy({ $0.model.cost == first.model.cost }) else {
            return nil
        }
        return Self.quote(
            providerID: first.providerID,
            model: first.model,
            payload: currentPayload
        )
    }

    private static func exactMatch(
        modelID: String,
        providerID: String,
        providers: [Provider]
    ) -> Model? {
        let normalizedID = normalizedModelID(modelID, providerID: providerID)
        return providers
            .first(where: { $0.id == providerID })?
            .models
            .first(where: { normalizedModelID($0.id, providerID: providerID) == normalizedID })
    }

    private static func exactMatches(
        modelID: String,
        providers: [Provider]
    ) -> [(providerID: String, model: Model)] {
        let exactModelID = exactFallbackModelID(modelID)
        return providers.flatMap { provider in
            provider.models.compactMap { model in
                exactFallbackModelID(model.id) == exactModelID
                    ? (provider.id, model)
                    : nil
            }
        }
    }

    private static func exactFallbackModelID(_ value: String) -> String {
        var normalizedValue = normalized(value)
        for prefix in ["models/", "openai/", "anthropic/", "google/", "alibaba/", "moonshotai/", "deepseek/"] {
            if normalizedValue.hasPrefix(prefix) {
                normalizedValue.removeFirst(prefix.count)
            }
        }
        return normalizedValue
    }

    private static func quote(
        providerID: String,
        model: Model,
        payload: CatalogPayload
    ) -> ModelPricingQuote {
        ModelPricingQuote(
            providerID: providerID,
            modelID: model.id,
            inputUSDPerMillion: model.cost.input,
            outputUSDPerMillion: model.cost.output,
            reasoningUSDPerMillion: model.cost.reasoning,
            cacheReadUSDPerMillion: model.cost.cacheRead,
            cacheWriteUSDPerMillion: model.cost.cacheWrite,
            source: .modelsDev,
            sourceURL: payload.sourceURL,
            fetchedAt: payload.fetchedAt
        )
    }

    func enrich(_ records: [UsageAnalyticsRecord]) -> [UsageAnalyticsRecord] {
        records.map { record in
            var enriched = record
            enriched.totals = UsageCostEstimator.enrich(totals: record.totals, quote: quote(for: record))
            return enriched
        }
    }

    func refreshIfNeeded() {
        let currentDate = nowProvider()
        lock.lock()
        let shouldRefresh = currentDate.timeIntervalSince(payload.fetchedAt) >= Self.refreshInterval && refreshTask == nil
        if shouldRefresh {
            refreshTask = Task { [weak self] in
                await self?.refresh()
            }
        }
        lock.unlock()
    }

    func waitForRefreshForTesting() async {
        let task = lock.withLock { refreshTask }
        await task?.value
    }

    private func refresh() async {
        defer {
            lock.withLock {
                refreshTask = nil
            }
        }
        do {
            var request = URLRequest(url: Self.sourceURL)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 30
            let (data, response) = try await dataLoader(request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return
            }
            let remote = try Self.decoder().decode([String: RemoteProvider].self, from: data)
            let next = Self.catalogPayload(from: remote, fetchedAt: nowProvider())
            guard Self.isValid(next) else { return }
            let encoded = try Self.encoder().encode(next)
            try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: cacheURL, options: .atomic)
            lock.withLock {
                payload = next
            }
        } catch {
            return
        }
    }

    private static func catalogPayload(
        from remote: [String: RemoteProvider],
        fetchedAt: Date
    ) -> CatalogPayload {
        let providers = remote.values.compactMap { provider -> Provider? in
            guard supportedProviders.contains(provider.id) else { return nil }
            let models = provider.models.values.compactMap { remoteModel -> Model? in
                guard let cost = remoteModel.cost else { return nil }
                return Model(id: remoteModel.id, cost: cost)
            }.sorted { $0.id < $1.id }
            guard !models.isEmpty else { return nil }
            return Provider(id: provider.id, models: models)
        }.sorted { $0.id < $1.id }
        return CatalogPayload(
            schemaVersion: schemaVersion,
            fetchedAt: fetchedAt,
            sourceURL: sourceURL.absoluteString,
            providers: providers
        )
    }

    private static func catalogProviderID(for record: UsageAnalyticsRecord) -> String? {
        let provider = normalized(record.providerID + " " + record.providerName + " " + record.providerCategory)
        let app = normalized(record.appType + " " + record.clientID)

        if disallowsCatalogFallback(for: record) {
            return nil
        }
        if provider.contains("openai") || provider.contains("codex") || app.contains("codex") {
            return "openai"
        }
        if provider.contains("anthropic") || provider.contains("claude") || app.contains("claude") {
            return "anthropic"
        }
        if provider.contains("google") || provider.contains("gemini") || app.contains("gemini") {
            return "google"
        }
        if provider.contains("alibaba") || provider.contains("qwen") || app.contains("qwen") {
            return "alibaba"
        }
        if provider.contains("moonshot") || provider.contains("kimi") || app.contains("kimi") {
            return "moonshotai"
        }
        if provider.contains("deepseek") || app.contains("deepseek") {
            return "deepseek"
        }
        return nil
    }

    private static func disallowsCatalogFallback(for record: UsageAnalyticsRecord) -> Bool {
        let provider = normalized(record.providerID + " " + record.providerName + " " + record.providerCategory)
        return provider.contains("openrouter")
            || provider.contains("vertex")
            || provider.contains("azure")
            || provider.contains("bedrock")
            || provider.contains("relay")
            || provider.contains("中转")
            || record.source == .ccswitchProxy
    }

    private static func normalizedModelID(_ value: String, providerID: String) -> String {
        var normalizedValue = normalized(value)
        for prefix in ["models/", "openai/", "anthropic/", "google/", "alibaba/", "moonshotai/", "deepseek/"] {
            if normalizedValue.hasPrefix(prefix) {
                normalizedValue.removeFirst(prefix.count)
            }
        }
        if providerID == "google", normalizedValue.hasSuffix("-latest") {
            normalizedValue.removeLast("-latest".count)
        }
        return normalizedValue
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValid(_ payload: CatalogPayload) -> Bool {
        guard payload.schemaVersion == schemaVersion,
              !payload.providers.isEmpty,
              payload.providers.allSatisfy({ supportedProviders.contains($0.id) }) else {
            return false
        }
        return payload.providers.allSatisfy { provider in
            !provider.models.isEmpty && provider.models.allSatisfy { model in
                !model.id.isEmpty && Self.validRates(model.cost)
            }
        }
    }

    private static func validRates(_ cost: Cost) -> Bool {
        let rates = [cost.input, cost.output, cost.reasoning, cost.cacheRead, cost.cacheWrite].compactMap { $0 }
        return !rates.isEmpty && rates.allSatisfy { $0 >= 0 && $0 <= 10_000 }
    }

    private static func bundledCatalogData() -> Data? {
        guard let url = Bundle.module.url(forResource: "model_pricing_catalog", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
