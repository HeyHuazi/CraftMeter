/**
 * [INPUT]: 依赖 OhMyUsageDomain 的实时额度与健康状态，并消费 Services 提供的脱敏浏览器导入发现结果
 * [OUTPUT]: 对外提供 Relay 连接诊断、快照预览与浏览器导入工作流结果
 * [POS]: Models 的 Provider 诊断展示契约，连接秘密不得进入这些可观察值类型
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import OhMyUsageDomain

struct RelayDiagnosticSnapshotPreview: Equatable {
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
}

struct RelayDiagnosticResult: Equatable {
    var success: Bool
    var fetchHealth: FetchHealth
    var resolvedAdapterID: String
    var resolvedAuthSource: String?
    var message: String
    var snapshotPreview: RelayDiagnosticSnapshotPreview?
}

struct RelayBrowserImportResult: Equatable {
    var discovery: RelayBrowserImportDiscovery
    var diagnostic: RelayDiagnosticResult?

    var isReadyToSave: Bool {
        diagnostic?.success == true
    }
}
