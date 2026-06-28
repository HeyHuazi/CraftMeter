# CraftMeter Architecture

CraftMeter 是一个 SwiftPM 项目，包含 macOS 菜单栏应用、CLI 和共享 Core。

## 目录结构

```text
CraftMeter/
├── Package.swift
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CHANGELOG.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── L2-app.md
│   ├── L2-cli.md
│   ├── L2-components.md
│   └── L2-core.md
├── Sources/
│   ├── CraftMeterApp/
│   ├── CraftMeterCore/
│   └── meter/
└── Tests/
    └── CraftMeterCoreTests/
```

## Targets

- `CraftMeterCore`: 纯数据层。解析 session 元数据，聚合成本、tokens、workspace、model、趋势和热力图。
- `CraftMeterApp`: SwiftUI macOS MenuBarExtra 应用。展示 Core 聚合结果。
- `meter`: CLI 可执行文件。提供文本和 JSON 报表。
- `CraftMeterCoreTests`: Core 语义测试。

## 依赖方向

```text
CraftMeterApp  ─┐
                ├─> CraftMeterCore
meter CLI      ─┘

CraftMeterCoreTests ─> CraftMeterCore
```

Core 不依赖 GUI 或 CLI。GUI/CLI 不复制业务聚合逻辑。

## 数据流

```text
~/.craft-agent/workspaces/*/sessions/*/session.jsonl
        │
        ▼
Store.scanRoot() / Store.refresh()
        │
        ▼
SessionRecord.from(firstLine:)
        │
        ▼
aggregate(records:)
        │
        ├─> CraftMeterApp / StatsViewModel
        └─> meter CLI renderer / JSON encoder
```

## 核心语义

- `billableTokens = inputTokens + outputTokens + cacheCreationTokens`
- `cacheReadTokens` 近似免费，不参与 billable 排序。
- `costCents` 用 `Int` 聚合，避免浮点货币漂移。
- `Store` 是唯一文件系统 IO 边界。
- `aggregate(records:)` 是纯函数。

## 缓存

`Store` 将聚合结果写入本机 cache，用于 GUI 秒开。cache schema 变化应提升 `Store.currentCacheVersion`。

## 设计原则

1. 单一真相源：token 和成本语义只在 Core 定义。
2. 小而直：无第三方依赖，避免过度工程。
3. IO 收口：文件系统只在 Store 层出现。
4. UI 只展示：SwiftUI 组件不承担 session 解析。
