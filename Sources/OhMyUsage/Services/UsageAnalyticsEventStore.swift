import Foundation
import OhMyUsageApplication
import SQLite3

private let analyticsSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/**
 * [INPUT]: 依赖系统 SQLite3，接收 enrichment 前 UsageAnalyticsRecord、source file cursor 与安全 checkpoint。
 * [OUTPUT]: 对外提供 cursor 查询、按文件原子 ingest、时间范围 facts 查询和派生索引清理。
 * [POS]: Services analytics 的事务事实库；确保 event 与 byte offset 同提交，不承担 scanner 解析、pricing 或聚合职责。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsEventStore: @unchecked Sendable {
    enum StoreError: Error, CustomStringConvertible {
        case open(String)
        case sqlite(operation: String, message: String)
        case encodeFacets
        case decodeFacets

        var description: String {
            switch self {
            case let .open(path): return "无法打开 analytics event store：\(path)"
            case let .sqlite(operation, message): return "analytics event store \(operation) 失败：\(message)"
            case .encodeFacets: return "analytics facets 编码失败"
            case .decodeFacets: return "analytics facets 解码失败"
            }
        }
    }

    private static let schemaVersion = 1
    private let databasePath: String
    private let beforeCursorCommit: (() throws -> Void)?
    private let queue = DispatchQueue(label: "com.heyhuazi.craftmeter.analytics-event-store", qos: .utility)
    private var database: OpaquePointer?

    init(
        databaseURL: URL,
        beforeCursorCommit: (() throws -> Void)? = nil
    ) throws {
        databasePath = databaseURL.path
        self.beforeCursorCommit = beforeCursorCommit
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open_v2(
            databasePath,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? databasePath
            if let database { sqlite3_close(database) }
            database = nil
            throw StoreError.open(message)
        }
        do {
            try configureAndMigrate()
        } catch {
            if let database { sqlite3_close(database) }
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func cursor(
        source: UsageAnalyticsIndexedSource,
        normalizedPath: String
    ) throws -> UsageAnalyticsSourceFileCursor? {
        try queue.sync {
            let statement = try prepare("""
                SELECT volume_id, file_id, observed_size, observed_mtime, committed_offset,
                       parser_schema, checkpoint, last_complete_event_at
                FROM source_files
                WHERE source_kind = ? AND normalized_path = ?
                LIMIT 1
                """)
            defer { sqlite3_finalize(statement) }
            bind(source.rawValue, at: 1, to: statement)
            bind(normalizedPath, at: 2, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return UsageAnalyticsSourceFileCursor(
                source: source,
                normalizedPath: normalizedPath,
                identity: UsageAnalyticsFileIdentity(
                    volumeIdentifier: optionalUInt64(statement, column: 0),
                    fileIdentifier: optionalUInt64(statement, column: 1)
                ),
                observedSize: UInt64(max(0, sqlite3_column_int64(statement, 2))),
                observedModificationTime: optionalDouble(statement, column: 3),
                committedOffset: UInt64(max(0, sqlite3_column_int64(statement, 4))),
                parserSchema: Int(sqlite3_column_int(statement, 5)),
                checkpoint: optionalData(statement, column: 6),
                lastCompleteEventAt: optionalDouble(statement, column: 7).map(Date.init(timeIntervalSinceReferenceDate:))
            )
        }
    }

    func commitFileIngest(
        cursor: UsageAnalyticsSourceFileCursor,
        records: [UsageAnalyticsRecord],
        replaceExistingFileRecords: Bool
    ) throws {
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                if replaceExistingFileRecords {
                    try deleteRecords(source: cursor.source, normalizedPath: cursor.normalizedPath)
                }
                for record in records {
                    try upsert(record: record, source: cursor.source, normalizedPath: cursor.normalizedPath)
                }
                try beforeCursorCommit?()
                try upsert(cursor: cursor)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    func commitCCSwitchIngest(
        cursor: UsageAnalyticsSourceFileCursor,
        proxyRecords: [UsageAnalyticsRecord],
        refreshedRollupRecords: [UsageAnalyticsRecord],
        rollupSince: Date
    ) throws {
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for record in proxyRecords {
                    try upsert(record: record, source: cursor.source, normalizedPath: cursor.normalizedPath)
                }
                try deleteRecords(
                    source: cursor.source,
                    normalizedPath: cursor.normalizedPath,
                    recordSource: .ccswitchDailyRollup,
                    since: rollupSince
                )
                for record in refreshedRollupRecords {
                    try upsert(record: record, source: cursor.source, normalizedPath: cursor.normalizedPath)
                }
                try beforeCursorCommit?()
                try upsert(cursor: cursor)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    func records(
        since: Date = .distantPast,
        until: Date = .distantFuture,
        sources: Set<UsageAnalyticsIndexedSource>? = nil
    ) throws -> [UsageAnalyticsRecord] {
        try queue.sync {
            var query = """
                SELECT record_source, event_at, app_type, client_id, client_name,
                       provider_id, provider_name, provider_category, model_id,
                       project_id, project_name, session_id, request_id,
                       request_count, success_count, input_tokens, output_tokens,
                       cache_read_tokens, cache_write_tokens, reasoning_tokens,
                       estimated_cost_usd, reported_cost_request_count,
                       estimated_cost_request_count, unpriced_request_count, facets, source_kind
                FROM events
                WHERE event_at >= ? AND event_at < ?
                """
            let sortedSources = sources?.map(\.rawValue).sorted() ?? []
            if !sortedSources.isEmpty {
                query += " AND source_kind IN (\(Array(repeating: "?", count: sortedSources.count).joined(separator: ",")))"
            }
            query += " ORDER BY event_at ASC, record_key ASC"

            let statement = try prepare(query)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, since.timeIntervalSinceReferenceDate)
            sqlite3_bind_double(statement, 2, until.timeIntervalSinceReferenceDate)
            for (index, source) in sortedSources.enumerated() {
                bind(source, at: Int32(index + 3), to: statement)
            }

            var output: [UsageAnalyticsRecord] = []
            var claudeRecordsByRequestID: [String: UsageAnalyticsRecord] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let record = try decodeRecord(statement)
                if text(statement, column: 25) == UsageAnalyticsIndexedSource.claude.rawValue {
                    if let existing = claudeRecordsByRequestID[record.requestID] {
                        if record.totals.totalTokens > existing.totals.totalTokens
                            || (record.totals.totalTokens == existing.totals.totalTokens
                                && record.eventAt > existing.eventAt) {
                            claudeRecordsByRequestID[record.requestID] = record
                        }
                    } else {
                        claudeRecordsByRequestID[record.requestID] = record
                    }
                } else {
                    output.append(record)
                }
            }
            output.append(contentsOf: claudeRecordsByRequestID.values)
            return output.sorted {
                if $0.eventAt != $1.eventAt { return $0.eventAt < $1.eventAt }
                return $0.requestID < $1.requestID
            }
        }
    }

    func removeAll() throws {
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM events")
                try execute("DELETE FROM source_files")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    private func configureAndMigrate() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA busy_timeout=5000")
        let version = try scalarInt("PRAGMA user_version")
        guard version <= Self.schemaVersion else {
            throw StoreError.sqlite(operation: "schema", message: "unsupported version \(version)")
        }
        if version == 0 {
            try execute("""
                CREATE TABLE IF NOT EXISTS source_files (
                    source_kind TEXT NOT NULL,
                    normalized_path TEXT NOT NULL,
                    volume_id INTEGER,
                    file_id INTEGER,
                    observed_size INTEGER NOT NULL,
                    observed_mtime REAL,
                    committed_offset INTEGER NOT NULL,
                    parser_schema INTEGER NOT NULL,
                    checkpoint BLOB,
                    last_complete_event_at REAL,
                    PRIMARY KEY (source_kind, normalized_path)
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS events (
                    record_key TEXT PRIMARY KEY,
                    source_kind TEXT NOT NULL,
                    origin_path TEXT NOT NULL,
                    record_source INTEGER NOT NULL,
                    event_at REAL NOT NULL,
                    app_type TEXT NOT NULL,
                    client_id TEXT NOT NULL,
                    client_name TEXT NOT NULL,
                    provider_id TEXT NOT NULL,
                    provider_name TEXT NOT NULL,
                    provider_category TEXT NOT NULL,
                    model_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    project_name TEXT NOT NULL,
                    session_id TEXT NOT NULL,
                    request_id TEXT NOT NULL,
                    request_count INTEGER NOT NULL,
                    success_count INTEGER NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cache_read_tokens INTEGER NOT NULL,
                    cache_write_tokens INTEGER NOT NULL,
                    reasoning_tokens INTEGER NOT NULL,
                    estimated_cost_usd REAL NOT NULL,
                    reported_cost_request_count INTEGER NOT NULL,
                    estimated_cost_request_count INTEGER NOT NULL,
                    unpriced_request_count INTEGER NOT NULL,
                    facets BLOB NOT NULL
                )
                """)
            for indexSQL in [
                "CREATE INDEX IF NOT EXISTS events_event_at_idx ON events(event_at)",
                "CREATE INDEX IF NOT EXISTS events_source_event_at_idx ON events(source_kind, event_at)",
                "CREATE INDEX IF NOT EXISTS events_client_event_at_idx ON events(client_id, event_at)",
                "CREATE INDEX IF NOT EXISTS events_provider_event_at_idx ON events(provider_id, event_at)",
                "CREATE INDEX IF NOT EXISTS events_model_event_at_idx ON events(model_id, event_at)",
                "CREATE INDEX IF NOT EXISTS events_project_event_at_idx ON events(project_id, event_at)",
                "CREATE INDEX IF NOT EXISTS events_origin_idx ON events(source_kind, origin_path)"
            ] {
                try execute(indexSQL)
            }
            try execute("PRAGMA user_version=\(Self.schemaVersion)")
        }
    }

    private func upsert(cursor: UsageAnalyticsSourceFileCursor) throws {
        let statement = try prepare("""
            INSERT INTO source_files (
                source_kind, normalized_path, volume_id, file_id, observed_size,
                observed_mtime, committed_offset, parser_schema, checkpoint, last_complete_event_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_kind, normalized_path) DO UPDATE SET
                volume_id=excluded.volume_id,
                file_id=excluded.file_id,
                observed_size=excluded.observed_size,
                observed_mtime=excluded.observed_mtime,
                committed_offset=excluded.committed_offset,
                parser_schema=excluded.parser_schema,
                checkpoint=excluded.checkpoint,
                last_complete_event_at=excluded.last_complete_event_at
            """)
        defer { sqlite3_finalize(statement) }
        bind(cursor.source.rawValue, at: 1, to: statement)
        bind(cursor.normalizedPath, at: 2, to: statement)
        bind(cursor.identity.volumeIdentifier, at: 3, to: statement)
        bind(cursor.identity.fileIdentifier, at: 4, to: statement)
        bind(cursor.observedSize, at: 5, to: statement)
        bind(cursor.observedModificationTime, at: 6, to: statement)
        bind(cursor.committedOffset, at: 7, to: statement)
        sqlite3_bind_int(statement, 8, Int32(cursor.parserSchema))
        bind(cursor.checkpoint, at: 9, to: statement)
        bind(cursor.lastCompleteEventAt?.timeIntervalSinceReferenceDate, at: 10, to: statement)
        try stepDone(statement, operation: "upsert cursor")
    }

    private func upsert(
        record: UsageAnalyticsRecord,
        source: UsageAnalyticsIndexedSource,
        normalizedPath: String
    ) throws {
        guard let facets = try? JSONEncoder().encode(record.facets) else {
            throw StoreError.encodeFacets
        }
        let statement = try prepare("""
            INSERT INTO events VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            ) ON CONFLICT(record_key) DO UPDATE SET
                source_kind=excluded.source_kind,
                origin_path=excluded.origin_path,
                record_source=excluded.record_source,
                event_at=excluded.event_at,
                app_type=excluded.app_type,
                client_id=excluded.client_id,
                client_name=excluded.client_name,
                provider_id=excluded.provider_id,
                provider_name=excluded.provider_name,
                provider_category=excluded.provider_category,
                model_id=excluded.model_id,
                project_id=excluded.project_id,
                project_name=excluded.project_name,
                session_id=excluded.session_id,
                request_id=excluded.request_id,
                request_count=excluded.request_count,
                success_count=excluded.success_count,
                input_tokens=excluded.input_tokens,
                output_tokens=excluded.output_tokens,
                cache_read_tokens=excluded.cache_read_tokens,
                cache_write_tokens=excluded.cache_write_tokens,
                reasoning_tokens=excluded.reasoning_tokens,
                estimated_cost_usd=excluded.estimated_cost_usd,
                reported_cost_request_count=excluded.reported_cost_request_count,
                estimated_cost_request_count=excluded.estimated_cost_request_count,
                unpriced_request_count=excluded.unpriced_request_count,
                facets=excluded.facets
            """)
        defer { sqlite3_finalize(statement) }
        let recordKey = "\(source.rawValue)|\(normalizedPath)|\(record.requestID)"
        let strings = [
            recordKey, source.rawValue, normalizedPath, record.appType, record.clientID,
            record.clientName, record.providerID, record.providerName, record.providerCategory,
            record.modelID, record.projectID, record.projectName, record.sessionID, record.requestID
        ]
        bind(strings[0], at: 1, to: statement)
        bind(strings[1], at: 2, to: statement)
        bind(strings[2], at: 3, to: statement)
        sqlite3_bind_int(statement, 4, Int32(record.source.rawValue))
        sqlite3_bind_double(statement, 5, record.eventAt.timeIntervalSinceReferenceDate)
        for (offset, value) in strings.dropFirst(3).enumerated() {
            bind(value, at: Int32(offset + 6), to: statement)
        }
        let totals = record.totals
        let integers = [
            totals.requestCount, totals.successCount, totals.inputTokens, totals.outputTokens,
            totals.cacheReadTokens, totals.cacheWriteTokens, totals.reasoningTokens
        ]
        for (offset, value) in integers.enumerated() {
            sqlite3_bind_int64(statement, Int32(offset + 17), sqlite3_int64(value))
        }
        sqlite3_bind_double(statement, 24, totals.estimatedCostUSD)
        sqlite3_bind_int64(statement, 25, sqlite3_int64(totals.reportedCostRequestCount))
        sqlite3_bind_int64(statement, 26, sqlite3_int64(totals.estimatedCostRequestCount))
        sqlite3_bind_int64(statement, 27, sqlite3_int64(totals.unpricedRequestCount))
        bind(facets, at: 28, to: statement)
        try stepDone(statement, operation: "upsert event")
    }

    private func deleteRecords(source: UsageAnalyticsIndexedSource, normalizedPath: String) throws {
        let statement = try prepare("DELETE FROM events WHERE source_kind = ? AND origin_path = ?")
        defer { sqlite3_finalize(statement) }
        bind(source.rawValue, at: 1, to: statement)
        bind(normalizedPath, at: 2, to: statement)
        try stepDone(statement, operation: "delete file events")
    }

    private func deleteRecords(
        source: UsageAnalyticsIndexedSource,
        normalizedPath: String,
        recordSource: UsageAnalyticsRecordSource,
        since: Date
    ) throws {
        let statement = try prepare("""
            DELETE FROM events
            WHERE source_kind = ? AND origin_path = ? AND record_source = ? AND event_at >= ?
            """)
        defer { sqlite3_finalize(statement) }
        bind(source.rawValue, at: 1, to: statement)
        bind(normalizedPath, at: 2, to: statement)
        sqlite3_bind_int(statement, 3, Int32(recordSource.rawValue))
        sqlite3_bind_double(statement, 4, since.timeIntervalSinceReferenceDate)
        try stepDone(statement, operation: "delete bounded source events")
    }

    private func decodeRecord(_ statement: OpaquePointer) throws -> UsageAnalyticsRecord {
        guard let source = UsageAnalyticsRecordSource(rawValue: Int(sqlite3_column_int(statement, 0))) else {
            throw StoreError.sqlite(operation: "decode event", message: "invalid record source")
        }
        guard let facetsData = optionalData(statement, column: 24),
              let facets = try? JSONDecoder().decode([UsageAnalyticsFacetEvent].self, from: facetsData) else {
            throw StoreError.decodeFacets
        }
        return UsageAnalyticsRecord(
            source: source,
            eventAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
            appType: text(statement, column: 2),
            clientID: text(statement, column: 3),
            clientName: text(statement, column: 4),
            providerID: text(statement, column: 5),
            providerName: text(statement, column: 6),
            providerCategory: text(statement, column: 7),
            modelID: text(statement, column: 8),
            projectID: text(statement, column: 9),
            projectName: text(statement, column: 10),
            sessionID: text(statement, column: 11),
            requestID: text(statement, column: 12),
            totals: UsageMetricTotals(
                requestCount: Int(sqlite3_column_int64(statement, 13)),
                successCount: Int(sqlite3_column_int64(statement, 14)),
                inputTokens: Int(sqlite3_column_int64(statement, 15)),
                outputTokens: Int(sqlite3_column_int64(statement, 16)),
                cacheReadTokens: Int(sqlite3_column_int64(statement, 17)),
                cacheWriteTokens: Int(sqlite3_column_int64(statement, 18)),
                reasoningTokens: Int(sqlite3_column_int64(statement, 19)),
                estimatedCostUSD: sqlite3_column_double(statement, 20),
                reportedCostRequestCount: Int(sqlite3_column_int64(statement, 21)),
                estimatedCostRequestCount: Int(sqlite3_column_int64(statement, 22)),
                unpricedRequestCount: Int(sqlite3_column_int64(statement, 23))
            ),
            facets: facets
        )
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw StoreError.open(databasePath) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw StoreError.sqlite(operation: sql, message: message)
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw StoreError.open(databasePath) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(operation: "prepare", message: String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, operation: String) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? operation
            throw StoreError.sqlite(operation: operation, message: message)
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func optionalDouble(_ statement: OpaquePointer, column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    private func optionalUInt64(_ statement: OpaquePointer, column: Int32) -> UInt64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return UInt64(bitPattern: sqlite3_column_int64(statement, column))
    }

    private func optionalData(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, analyticsSQLiteTransient)
    }

    private func bind(_ value: UInt64?, at index: Int32, to statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        sqlite3_bind_int64(statement, index, sqlite3_int64(bitPattern: value))
    }

    private func bind(_ value: UInt64, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(bitPattern: value))
    }

    private func bind(_ value: Double?, at index: Int32, to statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ value: Data?, at index: Int32, to statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), analyticsSQLiteTransient)
        }
    }
}
