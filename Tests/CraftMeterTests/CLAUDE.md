# Tests/CraftMeterTests/
> L2 | 父级: ../../CLAUDE.md

成员清单（使用统计展示）

UsageAnalyticsFacetPresentationTests.swift: 验证 Craft 活动类型的中文展示标题与稳定 rawValue 分离，并覆盖稳定 facet 顺序、失效选择回退、Top 12 截断及重叠覆盖率不求和；纯展示模型测试不启动 SwiftUI、不读取日志或缓存。

成员清单（凭据与系统边界）

SecurityCredentialReaderTests.swift: 验证 XCTest 默认短路、非交互 query 同时包含禁止交互 context 与 `kSecUseAuthenticationUIFail`，并以注入 writer 覆盖严格 update-or-add，禁止真实 Keychain 与 shell fallback。
BrowserCredentialServiceTests.swift: 验证浏览器路径/Safe Storage 缓存与访问意图；`.background` 不执行实时查找，也不复用 `.interactiveImport` 产生的 Bearer/Cookie 缓存。
CodexDesktopAuthServiceTests.swift / ClaudeDesktopAuthServiceTests.swift: 验证后台 current credential API 仅读文件且不调用外部 Keychain reader，用户显式账户切换仍写文件和外部 Keychain。
CopilotProviderTests.swift: 验证后台只接受环境变量，不读取 Copilot/GitHub CLI Keychain、不执行 `gh auth token`。
OfficialProviderTests.swift / RelayProviderTests.swift / TraeProviderTests.swift / KimiProviderTests.swift / OpenCodeGoProviderTests.swift: 验证普通与强制刷新都不会升级为浏览器 import/auth-recovery，失效凭据要求显式重新导入。
TestKeychainHelpers.swift: 为 Provider 与凭据测试提供 file-backed `KeychainService` 临时存储，避免测试依赖系统钥匙串。
KeychainServiceTests.swift: 以注入的 `SecureStoreAdapter` 验证进程锁定时并发后台读写零 Security 调用、显式解锁 single-flight、失败后进程级熔断、历史迁移、同值零写入、失败回滚及严格 update-or-add，不触达真实 Keychain。
CredentialAccessServiceTests.swift: 验证显示态凭据长度、缺失缓存与后台 lookup 策略，保护设置 UI 不因展示状态触发 secure store 读取。
RelayCurlImportParserTests.swift: 覆盖浏览器 Copy as cURL 的引号、续行、header/cookie/url 参数、端点白名单与错误脱敏；测试文本中的秘密不得出现在错误描述。
RelayCurlImportCoordinatorTests.swift: 通过自定义 URLProtocol 隔离真实网络，验证 Bearer、Cookie、Cookie-only User ID 补全及确定性回退，结果只暴露脱敏元数据。
AppViewModelConfigurationPersistenceTests.swift: 覆盖 cURL 验证成功后的配置/Keychain 一致性与失败零副作用；使用 file-backed Keychain 并断言配置 JSON 不含秘密。

边界

- 默认 `swift test` 不允许触达真实 macOS Keychain；需要系统钥匙串行为时必须通过 fake adapter 或显式 opt-in 的独立集成测试承载。
- `forceRefresh` 安全回归必须断言它不等价于用户授权：Provider 强制刷新不得调用外部 Keychain、浏览器 Cookie/localStorage、CLI credential discovery，也不得显式解锁 CraftMeter vault。
- 测试文件新增时优先补充最邻近的 L3 头部契约；涉及系统资源、网络、文件或进程边界的测试必须说明隔离策略。
- 大规模测试成员清单暂按领域分段生长，避免实习生式罗列所有文件；新增分段时保持职责边界清晰。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
