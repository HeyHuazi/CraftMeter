# Sources/OhMyUsage/Providers/
> L2 | 父级: ../CLAUDE.md

成员清单

AmpProvider.swift: Amp 官方额度 HTTP 适配器，解析免费与付费 credit 窗口。
ClaudeProvider.swift: Claude API/CLI/Web quota 编排；后台 OAuth 仅读 `.credentials.json`/环境变量，Web 只消费 CraftMeter 已保存 Cookie。
CodexProvider.swift: Codex API/CLI/Web quota 编排；后台 OAuth 仅读 `auth.json`，Web 只消费 CraftMeter 已保存 Cookie。
CopilotProvider.swift: GitHub Copilot quota API 适配器；后台凭据只接受环境变量，不读取 CLI Keychain 或执行 `gh auth token`。
CursorProvider.swift: Cursor 官方额度适配器。
DragonProvider.swift: Dragon Provider 兼容入口。
GeminiProvider.swift: Gemini CLI OAuth 与 quota 适配器。
JetBrainsProvider.swift: JetBrains AI XML/本地状态额度适配器。
KimiOfficialProvider.swift: Kimi 官方 OAuth quota 适配器。
KimiProvider.swift: Kimi Coding quota 适配器；普通与强制刷新只消费已保存 token，不扫描浏览器。
KimiSmartProvider.swift: Kimi 官方/legacy 数据源选择与兼容编排。
KiroProvider.swift: Kiro CLI/IDE 状态解析与额度适配器。
MicrosoftCopilotProvider.swift: Microsoft Graph Copilot 报告适配器；只读取环境变量或 CraftMeter vault。
OfficialProviderAuthRuntime.swift: 官方 OAuth refresh、JSON 文件更新与通用鉴权请求辅助。
OfficialProviderCredentialModels.swift: Codex/Claude 文件或环境凭据值模型；不拥有持久化、Keychain 或日志。
OfficialProviderFetchRuntime.swift: 官方 Provider cache、force-refresh 与串行 fetch 通用编排。
OfficialProviderWebOverlayRuntime.swift: 官方 Web quota overlay；Provider fetch 只读 CraftMeter 已保存 Cookie，浏览器导入必须走专用用户动作。
OfficialSnapshotFallback.swift: 官方快照失败时的回退与状态归一化。
OllamaCloudProvider.swift: Ollama Cloud quota 适配器。
OpenCodeGoProvider.swift: OpenCode Go 远端/本地 usage 适配器；force-refresh 不触发浏览器 Cookie 导入。
OpenRouterProvider.swift: OpenRouter credits/API quota 适配器，凭据来自 CraftMeter vault。
ProviderProtocol.swift: executable target 的 Provider 获取协议与错误契约。
RelayBalanceChannelExecutor.swift: Relay 账户余额请求候选遍历；后台仅使用已保存凭据，不执行浏览器恢复。
RelayCredentialResolver.swift: Relay saved/browser 候选标准化；实时浏览器候选仅由显式 import intent 调用，运行期候选仅在当前进程 vault 已解锁时以 `backgroundPersistence` 保存。
RelayHTTPClient.swift: Relay HTTP/JSON 请求边界。
RelayProvider.swift: Relay token/balance 通道编排；`forceRefresh` 仅控制网络刷新，不授予浏览器访问。
RelayRecoveryPolicy.swift: Relay 错误解释、友好提示与历史 recovery 元数据策略。
RelayRequestResolver.swift: 将 adapter manifest 解析为具体 token/balance 请求。
RelayResponseInterpreter.swift: Relay 响应字段、表达式与账户值解释器。
RelayTokenChannelExecutor.swift: Relay token quota 通道；后台仅使用已保存凭据，不执行浏览器恢复。
TraeProvider.swift: Trae quota API 适配器；凭据失效时要求显式重导入，不在后台扫描浏览器。
WindsurfProvider.swift: Windsurf IDE SQLite 状态与 quota API 适配器。
ZaiProvider.swift: Z.ai quota API 适配器。

边界

- Provider `fetch(forceRefresh:)` 的 `forceRefresh` 只代表跳过数据缓存/重新请求网络，绝不等同用户授权访问外部 Keychain、浏览器 Cookie 或 localStorage。
- 后台 Provider 只能读取 CraftMeter vault、明确配置文件与环境变量；Codex/Claude/浏览器/CLI 外部凭据读取必须位于专用用户导入协调器。
- BrowserCredentialAccessIntent `.interactiveImport` 只能从显式 UI 导入流程进入；Provider 不得使用 `.authRecovery` 自动升级权限。
- 凭据正文不得进入 snapshot metadata、日志、错误或缓存键；只允许脱敏来源标签。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
