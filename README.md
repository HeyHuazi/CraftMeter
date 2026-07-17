# CraftMeter

CraftMeter 是一款面向 macOS 菜单栏的 AI **额度监控 + 本地使用分析**应用。

它以 [Four-JJJJ/oh-myusage](https://github.com/Four-JJJJ/oh-myusage) v2.2.2（commit `46f0ca7`）为 Swift 原生基础，保留成熟的 Provider、账号、Keychain、菜单栏、设置和更新体系，并迁入原 CraftMeter 的本地统计语义，重点增强 Craft Agents、Gemini CLI 与 Qwen Code。

当前维护版本：**v0.0.2**。版本号以仓库根目录的 [`VERSION`](VERSION) 为唯一发布基准；功能提交、README、打包产物与 Git tag 必须同步维护。

版本线已于 2026-07-16 重置为 v0.0.1；v0.0.2 完成 CraftMeter 测试身份、凭据安全与正式发布打包版本同步；此前 v2.3.1 修复了更新流程测试读取宿主机 `/Applications` 已安装版本而产生的环境污染，并将 CI/Release 固定到 macOS 15 与 Node.js 24 兼容的 Actions 运行时；生产环境的已安装版本防降级检查保持不变。

## 核心能力

### 实时额度与账号

- 官方订阅额度、重置窗口、余额和鉴权健康度
- Codex / Claude OAuth 导入与本地账号管理
- 第三方 Relay / New API 余额与 Token 通道
- 菜单栏摘要、异常诊断、缓存回退和应用内更新

### 本地使用分析

当前可聚合：

- Claude Code
- Codex
- Kimi
- Gemini CLI
- Qwen Code
- Craft Agents
- CCSwitch 日志

统计维度包括：

- 请求、成功率、会话
- input / output / cache read / cache write / reasoning token
- 客户端、Provider、项目、模型的组合筛选与统一聚合
- 模型品牌图标与按维度统计明细
- MCP、Skills
- Craft Agents enabled sources、tool、category、status、permission mode、thinking level

总览、趋势、环形图和统计明细始终消费同一套筛选结果。各选项采用 faceted-search 语义：更新某一维度时保留其他已选条件，避免不同图表出现统计口径漂移。

### Provider 感知费用估算

费用分为五种可审计状态：

- **上游报告（reported）**：日志明确提供的费用，例如 Craft Agents `costCents`；始终优先，绝不重新计价。
- **公开价格估算（estimated）**：缺少上游费用时，按 Models.dev 的 Provider + Model 费率和实际 Token 估算。
- **混合来源（mixed）**：同一汇总同时包含上游报告和本地估算。
- **部分定价（partial）**：只有已知费用下界，显示为 `≥金额`。
- **未知（unknown）**：无法可靠定价，显示为“未知”或 `--`，不会伪装成 `$0.00`。

价格计算使用 `Decimal`，支持 input、output、reasoning、cache read 和 cache write。价格目录随应用内置，并使用经过校验的 last-known-good 缓存进行最多每日一次的后台更新。

价格匹配是 Provider 感知的。官方本地 Codex、Claude、Gemini、Qwen、Kimi 和 DeepSeek 记录可以使用对应直连目录；CCSwitch proxy、Relay、OpenRouter、Azure、Vertex、Bedrock 及归属不明确的渠道不会借用同名模型的官方价格。

Craft Agents 的 enabled source 属于**可重叠归因**，不能把各 source 的归因费用简单求和当作总费用。

## 隐私边界

CraftMeter 只提取统计事实，不保存：

- prompt 正文
- assistant 回复正文
- tool input / tool result 正文
- 附件正文

Token、Cookie 与 API Key 使用 macOS Keychain；统计缓存与配置默认保存在：

```text
~/Library/Application Support/CraftMeter
```

首次启动会将旧 `OhMyUsage` 配置和 Keychain 凭据单向迁移到 CraftMeter。旧 Application Support 目录只读保留，不主动删除。

## 系统要求

- macOS 14+
- Swift 6.2+
- Xcode 26 或兼容工具链

## 下载与首次启动

[下载最新 CraftMeter Preview](https://github.com/HeyHuazi/CraftMeter/releases/latest)，推荐使用 `CraftMeter.dmg`。

> **macOS 安全提示：** 当前 GitHub Preview 使用 ad-hoc 签名，未经 Apple Developer ID 签名和 Apple 公证。将应用拖入“应用程序”后，请右键 CraftMeter 并选择“打开”；若仍被阻止，请前往“系统设置 → 隐私与安全性 → 仍要打开”。

CraftMeter 是菜单栏应用，通常不显示 Dock 图标。首次成功启动会自动打开一次设置窗口；之后请在屏幕顶部菜单栏右侧寻找 CraftMeter 图标。Bartender、Ice 或刘海区域空间不足可能隐藏该图标。

完整步骤与安全说明见 [docs/DOWNLOAD.md](docs/DOWNLOAD.md)。

## 从源码运行

```bash
swift build
swift run CraftMeter
swift test
```

打包：

```bash
PACKAGE_MODE=development APP_VERSION=$(cat VERSION) ./scripts/package_dmg.sh
```

产物：

```text
dist/CraftMeter.dmg
dist/CraftMeter-macOS.zip
```

## 架构

```text
Sources/
├── OhMyUsageDomain          # 稳定领域模型
├── OhMyUsageInfrastructure  # Keychain 等基础设施契约
├── OhMyUsageProviders       # Provider runtime 协议
├── OhMyUsageApplication     # 统计契约、聚合、缓存、调度
├── OhMyUsagePresentation    # 纯展示模型
├── OhMyUsageFeatures        # Feature 组装
├── OhMyUsageBootstrap       # Composition root
└── OhMyUsage                # CraftMeter executable：App/UI/Services/Providers/Resources

Tests/OhMyUsageTests         # XCTest 回归与架构边界测试
scripts/                     # DMG/ZIP 打包
```

Swift target 暂时保留 `OhMyUsage*` 名称，以避免首轮迁移出现无收益的大规模符号重命名；产品名、可执行文件、bundle ID、数据目录与发布产物均已切换为 CraftMeter。

完整设计见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 开发原则

- Scanner 只产生事实，不负责 UI、时间窗口或第三方价格目录。
- Repository 在聚合前统一进行价格 enrichment；费用公式属于 Application 层纯函数。
- Aggregator 是纯函数，不执行文件 IO；总览、趋势和统计明细必须使用同一筛选管线。
- 上游报告费用永远优先；未知费用不能伪装成零成本。
- Provider 与模型共同决定价格归属，不能仅凭同名模型跨渠道套价。
- 单一来源失败不清空其他来源数据。
- 新行为必须有 focused XCTest，并运行 Debug、Release 与完整 `swift test`。
- 每次功能版本维护必须同步 `VERSION`、README、用户可见发布说明和 `v*` Git tag。

## 上游与许可证

CraftMeter 包含基于 oh-myusage 的 MIT 许可代码：

- Copyright (c) 2026 FourJ
- Upstream: https://github.com/Four-JJJJ/oh-myusage
- Imported baseline: v2.2.2 / `46f0ca716348b9311dbfcde21cc7979a37a700eb`

详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
