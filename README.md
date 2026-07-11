# CraftMeter

CraftMeter 是一款面向 macOS 菜单栏的 AI **额度监控 + 本地使用分析**应用。

它以 [Four-JJJJ/oh-myusage](https://github.com/Four-JJJJ/oh-myusage) v2.2.2（commit `46f0ca7`）为 Swift 原生基础，保留成熟的 Provider、账号、Keychain、菜单栏、设置和更新体系，并迁入原 CraftMeter 的本地统计语义，重点增强 Craft Agents、Gemini CLI 与 Qwen Code。

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
- 模型、Provider、客户端、项目
- 已知费用与未定价状态
- MCP、Skills
- Craft Agents enabled sources、tool、category、status、permission mode、thinking level

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

## 从源码运行

```bash
swift build
swift run CraftMeter
swift test
```

打包：

```bash
APP_VERSION=2.2.2 ./scripts/package_dmg.sh
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

- Scanner 只产生事实，不负责 UI 或时间窗口。
- Aggregator 是纯函数，不执行文件 IO。
- 未定价必须展示为 unknown，不能伪装成零成本。
- 单一来源失败不清空其他来源数据。
- 新行为必须有 focused XCTest，并运行完整 `swift test`。

## 上游与许可证

CraftMeter 包含基于 oh-myusage 的 MIT 许可代码：

- Copyright (c) 2026 FourJ
- Upstream: https://github.com/Four-JJJJ/oh-myusage
- Imported baseline: v2.2.2 / `46f0ca716348b9311dbfcde21cc7979a37a700eb`

详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
