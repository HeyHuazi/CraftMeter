# CraftMeter

macOS menubar 应用，给 [Craft Agent](https://github.com/craft-ai-agents/craft-agents-oss) 的 token 用量做个看得见的仪表盘。

## 这是什么

Craft Agent 把每个会话的完整 token 用量（输入/输出/缓存）和成本存在本地：

```
~/.craft-agent/workspaces/{workspace}/sessions/{sessionId}/session.jsonl
```

每个 `session.jsonl` 第一行就是一个完整的账本——`model`、`llmConnection`、`costUsd`、四种 token 计数、`labels`、`sessionStatus`、`preview`、`thinkingLevel` 等。但 Craft Agent 自己不暴露这些数据的统计视图，于是**看不见的漏水**就开始了。

CraftMeter 扫所有 session，给出：

1. **三卡横排** — 今日 $ 橙 · 总 $ 绿 · 总 tokens 紫 + 微型 sparkline
2. **30 日趋势** — gradient bar chart + 异常日红点 + 可点击 drill-down
3. **Top sessions** — 按 billable tokens 排序（剔除 cacheRead），带日期徽章，可点击详情
4. **Workspaces** — 进度条 + 多色 dot，可点击 drill-down
5. **drill-down overlay** — 单 session 详情 / 当日列表 / workspace 列表 / all
6. **状态栏实时数字** — 今日 $ 默认，可在 Settings 切换为总 $ / 今日 tokens / 仅图标

两种界面：**menubar 应用**（状态栏图标 + popover）+ **CLI**（stdout 文本/JSON）。

## 安装

```bash
git clone https://github.com/<owner>/CraftMeter.git
cd CraftMeter
swift build -c release
```

两个产物：

- `.build/release/CraftMeterApp` — menubar app，双击启动，状态栏出现 💲 图标
- `.build/release/meter` — CLI，直接跑出文本/JSON 报表

### 把 menubar app 加到登录项

System Settings → General → Login Items → 加 `.build/release/CraftMeterApp`。

## 使用

### CLI

```bash
# 默认全局视图
$ meter

CraftMeter  —  Craft Agent 用量仪表盘
════════════════════════════════════════════════════════
  Total reported cost   $301.07
  Total tokens          29.9M
  Sessions              312
  Workspaces            3
  Last scan             2026-06-25 21:50:15

Top 5 sessions (by billable tokens)
  1. 260225-vast-moon [my-workspace]
     400.3K · $206.47 · claude-sonnet-4-6
  ...

30-day token trend
  6月19日 ████████ 1.4M
  6月20日 ███      616.0K
  ...
```

带过滤参数：

```bash
meter --workspace Voyager           # 只看某 workspace
meter --model claude-sonnet-4-6     # 只看某模型
meter --label "design::界面"         # 只看某 label
meter --since 7d                    # 最近 7 天
meter --since 2026-06-01            # 自某日起
meter --json | jq .                 # JSON 输出
meter --workspace X --since 30d --json
```

退出码：`0` 成功，`1` 参数错误，`2` 没扫到 session 或过滤为空。`meter --help` 看完整选项。

### Menubar app

启动后状态栏出现 `$` 图标 + 实时今日 $ 数字。点击弹出 380×500 popover：

- 顶部三卡横排（Today $ / Total $ / Tokens）
- 30 日趋势图（点击柱子看当日 sessions）
- Top 5 sessions（点击行看详情）
- Workspaces 进度条（点击行看该 workspace sessions）
- 底部 Refresh / Quit 按钮

**命令 + 逗号** 打开 Settings，切换状态栏显示模式（今日 $ / 总 $ / 今日 tokens / 仅图标）。

每 5 分钟自动后台刷新；启动时读 cache 秒开。

## Privacy

CraftMeter 只读取本机 `~/.craft-agent/workspaces/*/sessions/*/session.jsonl` 的第一行元数据，用于计算本地统计视图。它不会上传 session 内容、token 用量、成本、路径或任何个人数据。

请不要在 issue、PR 或测试 fixture 中提交真实 `session.jsonl` 内容。

## 开源与贡献

- [LICENSE](LICENSE) — Apache-2.0
- [CONTRIBUTING.md](CONTRIBUTING.md) — 开发环境、验证命令和贡献规则
- [CHANGELOG.md](CHANGELOG.md) — 公开变更记录
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 公开架构说明

## 设计决策

| 决策 | 理由 |
|---|---|
| Swift 原生（不用 Tauri/Electron） | 二进制 ~2MB、启动 <50ms、零第三方运行时依赖 |
| SwiftPM 三 target（Core + GUI + CLI） | 数据层单向依赖，Core 改动同步影响 GUI 与 CLI |
| 顺序扫描，no rayon/async | 388 文件 × 只读首行 ≈ 200KB IO，sub-second |
| **Top 5 按 billable tokens**（剔除 cacheRead） | cacheRead 是 cache 命中近免费，与代理 costUsd=0 同性质；剔除它让排序真正反映"烧了多少" |
| 整数 cents 聚合（`Int`） | f64 累加 388 次会有精度漂移，cents 零误差 |
| 5min 轮询 + 启动一次扫 | fs_watch 在分散目录上不可靠；同一 `refresh()` 入口 |
| cache 内嵌 Store + cacheVersion | cache 是 refresh 的记忆化；schema 演进靠 cacheVersion 比对，老版本自动失效 |
| Stats 携带 records（方案 B） | 388 × ~250B ≈ 100KB 无感；前端 filter+sort 微秒级，无需预聚合 |
| **Popover 380×500 + 三卡横排**（B-layout） | 横排卡片承载多维信号同屏可比；视觉密度优于 segmented tab |
| **多色语义 Palette** | Today 橙 / Total 绿 / Tokens 紫 / 异常 红 / workspace 多色 hash；色彩承担分类信号，单色蓝单调 |
| drill-down 自管 @State，不用 NavigationStack | NavigationStack 在 MenuBarExtra popover 内行为不稳定 |
| workspace 多色 djb2 hash | String.hashValue 每次启动随机化会导致颜色跳变，需稳定 hash |
| **365 天热力图**（GitHub 风格） | 按 billable tokens 四档百分位色阶；一眼识别使用节奏（密集/空白/间断），趋势柱状图无法提供的粒度信号 |

详见 [docs/L2-*.md](docs/) 和源码顶部 L3 契约注释。

## 开发

```bash
swift build                            # debug build
swift run CraftMeterApp                # 启动 GUI（debug）
swift run meter                        # CLI 输出
swift run meter --json | jq .          # JSON
swift test                             # 单元测试（**需要完整 Xcode**，CLT 不带 XCTest）
```

### 已知限制

- **测试需要完整 Xcode**：XCTest 框架在 Command Line Tools 里不可用。装了 Xcode 后 `swift test` 可用。
- **部分代理 session 可能没有 costUsd**：某些自定义代理写入的 session `costUsd=0` 是真实记录，不一定是缺失。按 billable tokens 排序可以绕过这个分支。
- **仅扫 `~/.craft-agent/workspaces/` 下**：外部路径的 workspace（如 `~/Documents/.../Voyager`）的 session 也存在这里，所以扫这一处足够。
- **多 workspace hash 碰撞**：workspace 数量 > 8 时多色 dot 必有同色，dot 仅作分类锚点不依赖唯一性。

## License

Apache-2.0（与上游 craft-agents-oss 一致）
