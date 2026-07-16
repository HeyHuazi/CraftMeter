# CraftMeter - macOS AI 额度与本地用量工作台
Swift 6.2 + SwiftUI/AppKit + SwiftPM + XCTest，macOS 14+

> 基于 oh-myusage v2.2.2 (`46f0ca7`)；产品、存储与发布身份为 CraftMeter，Swift target 名暂保留。

<directory>
Sources/ - 生产代码 (8 targets: OhMyUsage executable + Domain/Infrastructure/Providers/Application/Presentation/Features/Bootstrap)
Tests/ - XCTest、架构依赖边界与 GEB 文档同构门禁 (1 target: OhMyUsageTests)
docs/ - 架构、Provider、安装与发布说明
scripts/ - CraftMeter DMG/ZIP 构建脚本
.github/ - Swift debug/release CI 与 GitHub Preview Release 工作流
</directory>

<config>
Package.swift - macOS 14+ SwiftPM 产品与 target 依赖图
VERSION - 发布版本单一真相源
LICENSE - 上游 MIT 许可证与版权声明
NOTICE - oh-myusage 导入基线与 CraftMeter 派生说明
README.md - 产品能力、隐私和构建入口
docs/ARCHITECTURE.md - 额度流、历史 analytics、首次启动与分发模式的权威设计
scripts/package_dmg.sh - development/preview/release 三态 DMG/ZIP 构建、SwiftPM 资源完整性门禁、签名与公证入口
</config>

## 架构法则

- 实时额度使用 `UsageSnapshot`；历史消费使用 `UsageAnalyticsSnapshot`，禁止混用。
- Scanner 只提取统计事实；Aggregator 必须是纯函数；SwiftUI 不触碰日志。
- 历史事实索引只保存 enrichment 前 records 与安全 cursor/checkpoint；offset 与 events 必须事务提交，原始 JSONL 正文不得进入派生库。
- 未定价是 `unknown`，不能展示成零成本。
- 不保存 prompt、assistant content、tool input/result 或附件正文。
- 新运行时数据写入 `~/Library/Application Support/CraftMeter`；旧 OhMyUsage 只读迁移。
- 单文件超过 800 行必须拆分；新增文件必须同步 L2 与 L3。

## 数据流

```text
Official/Relay -> Provider Runtime -> UsageSnapshot -> AppSessionStore -> Menu Bar
Local Logs -> Scanners/Incremental Adapters -> UsageAnalyticsRecord/Facets
                                             \-> Fingerprint-matched SQLite Facts
                                             \-> Repository indexed-first/legacy fallback -> Pricing -> Aggregator -> Cache -> Settings
```

## 文档回环

代码修改完成后：

1. 检查业务文件 L3 `[INPUT]/[OUTPUT]/[POS]`。
2. 文件增删、职责或接口变化时更新最近的 L2 `CLAUDE.md`。
3. target、顶级目录、技术栈或全局数据流变化时更新本文件。
4. 运行 `swift build`、`swift build -c release` 与 `swift test`。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
