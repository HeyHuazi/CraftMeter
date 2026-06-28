# Contributing to CraftMeter

感谢你愿意改进 CraftMeter。这个项目刻意保持小而直：SwiftPM、SwiftUI、Foundation，没有第三方依赖。

## 开发环境

- macOS 13+
- Swift 6+
- 完整 Xcode（运行 `swift test` 需要 XCTest；仅 Command Line Tools 可能不够）

## 常用命令

```bash
swift build
swift run meter
swift run meter --json
swift run CraftMeterApp
swift test
```

## 架构边界

```text
CraftMeterApp  ─┐
                ├─> CraftMeterCore
meter CLI      ─┘

Tests ───────────> CraftMeterCore
```

- `CraftMeterCore` 是唯一业务真相源：解析、聚合、格式化、文件扫描。
- `Store` 是唯一文件系统 IO 边界。
- GUI 和 CLI 只能消费 Core 的 `Stats` / `SessionRecord`，不要复制聚合逻辑。
- UI 不直接解析 `session.jsonl`。
- 成本用整数 cents 聚合，避免浮点货币误差。
- `cacheReadTokens` 不计入 billable tokens。

## PR 规则

- 修改 Core 语义：必须补测试。
- 修改 CLI 参数或输出：必须更新 README。
- 修改 UI 行为：请说明手工验证路径，最好附截图。
- 新增依赖前先证明必要性；默认答案是不加。

## 隐私原则

CraftMeter 只读取本机 `~/.craft-agent/workspaces/*/sessions/*/session.jsonl` 第一行元数据，不上传任何数据。请不要在 issue、PR 或测试 fixture 中提交真实 session 内容。
