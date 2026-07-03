# CraftMeter

CraftMeter 是一个 **Tauri + React + Rust** 的本机 AI coding usage menubar dashboard。它读取本机 AI 编程工具日志，在本机聚合 token、费用、模型、项目、客户端来源、MCP、Skills 与 Craft Agent attribution，用一个轻量 popover 告诉你：今天、这周、这个月到底把 token 花在了哪里。

> Rust 是业务真相源：日志扫描、增量 cache、聚合、定价都在后端完成；React 只消费 Rust 返回的 `Dashboard`。

## 功能

- **menubar 常驻**：状态栏显示今日 token，点击打开 dashboard popover。
- **自然周期视图**：Day / Week / Month 三个窗口；支持左右按钮查看上一日、上一周、上一月，并可向前回到当前窗口。
- **token 分层**：展示 input、cache、output、reasoning token；总 token 口径包含 reasoning。
- **费用估算**：基于 models.dev / LiteLLM 价格表估算成本，并提示未定价模型。
- **模型分布**：按模型统计 token、费用、请求与会话。
- **客户端分布**：按 AI coding 客户端归因，例如 Claude Code、Craft Agent、Codex、Gemini CLI、Qwen Code。
- **项目分布**：按项目聚合 token、费用、请求与会话，回答“钱花在哪个代码库”。
- **MCP / Skills 归因**：识别用户安装的 MCP server 与全局 Skills，减少噪音。
- **Craft Agent attribution**：后端保留 source、category、status、permission、thinking level 与 tool call 统计；当前 UI 暂时隐藏工具调用列表。
- **增量扫描**：Rust store 只读取日志新增字节，用 manifest、dedupe 与 source purge 保持幂等。
- **本地优先**：只读取本机日志，cache 写入本机应用目录，不上传 prompt、正文或 tool result。
- **截图导出**：popover 可保存为桌面 PNG。
- **登录启动**：通过 Tauri autostart 插件管理 Launch at Login。

## 数据来源

当前 Rust 后端扫描以下本机路径：

```text
~/.claude/projects/**/*.jsonl
~/.craft-agent/workspaces/**/session.jsonl
~/.codex/sessions/**/*.jsonl
~/.gemini/tmp/**/chats/*.jsonl
~/.qwen/tmp/**/chats/*.jsonl
~/.claude.json
~/.claude/skills/*
```

来源语义：

- **Claude Code**：读取 assistant message token、tool use、MCP 与 Skill 调用。
- **Craft Agent**：读取 session attribution，例如 source、permission、thinking、category、status 与工具调用状态。
- **Codex CLI**：读取 `token_count.last_token_usage`，避免累计值重复计数；reasoning token 独立建模。
- **Gemini CLI / Qwen Code**：读取 assistant `usageMetadata`；`promptTokenCount` 扣除 `cachedContentTokenCount`，`thoughtsTokenCount` 进入 reasoning。
- **Claude config / Skills**：`~/.claude.json` 用于识别 MCP server，`~/.claude/skills/` 用于识别全局 Skills。

## 下载

稳定版本放在 [GitHub Releases](https://github.com/HeyHuazi/CraftMeter/releases)。

`.app`、`.dmg` 和安装包不提交到 Git 仓库；它们是 release assets。源码在 Git，产物在 Releases，这是唯一干净的边界。

## 安装与开发

### 环境

- macOS 13+
- Node.js 18+
- Rust stable
- Tauri 2 toolchain 依赖：Xcode Command Line Tools 等系统组件

### 安装依赖

```bash
npm install
```

### 开发运行

```bash
npm run tauri:dev
```

### 前端构建

```bash
npm run build
```

### Rust 测试

```bash
npm run test:rust
```

### 打包应用

```bash
npm run tauri:build
```

macOS 产物通常位于：

```text
src-tauri/target/release/bundle/macos/CraftMeter.app
src-tauri/target/release/bundle/dmg/*.dmg
```

当前 `tauri.conf.json` 开启了 app/dmg/nsis targets；在 macOS 本机主要产出 `.app` 与 `.dmg`，Windows NSIS 产物取决于本机工具链支持。

发布流程见 [docs/RELEASE.md](docs/RELEASE.md)。打 tag 后 GitHub Actions 会构建 macOS DMG 并上传到对应 GitHub Release。

## 项目结构

```text
CraftMeter/
├── package.json              # npm scripts: Vite + Tauri
├── index.html                # Vite HTML shell
├── src/                      # React frontend
│   ├── App.tsx               # dashboard shell, period offset, theme, screenshot
│   ├── charts.tsx            # chart and visual primitives
│   ├── data.ts               # Dashboard types, fetch adapter, formatting, theme
│   └── main.tsx              # React entry
├── public/                   # static assets / optional dev snapshot
├── src-tauri/                # Rust backend and Tauri app shell
│   ├── Cargo.toml            # Rust dependencies
│   ├── tauri.conf.json       # Tauri app/window/bundle config
│   ├── icons/                # app/tray icons
│   └── src/
│       ├── lib.rs            # Tauri builder, tray, windows, commands, refresh/watchers
│       ├── main.rs           # native entry
│       ├── model.rs          # serialized Dashboard model
│       ├── store.rs          # incremental log ingestion, manifest, cache, dedupe
│       ├── codex.rs          # Codex JSONL state machine
│       ├── parser.rs         # RawEvent -> Dashboard aggregation
│       ├── pricing.rs        # LiteLLM/models.dev price table cache
│       └── config.rs         # MCP/Skill user config discovery
├── docs/
│   ├── ARCHITECTURE.md      # architecture map
│   └── RELEASE.md           # release process and artifact policy
├── CONTRIBUTING.md           # contributor workflow
├── CHANGELOG.md              # release notes
└── README.md
```

## 架构原则

1. **Rust 是业务真相源**：日志扫描、cache、聚合、定价都在 `src-tauri/src`。
2. **React 只展示 Dashboard**：前端消费 Rust 返回的 `Dashboard`，不重新解释日志。
3. **Store 只存事实**：`RawEvent` 不绑定当前价格表和时间窗口，聚合时再计算。
4. **自然窗口由后端计算**：Day / Week / Month 与历史 offset 都在 Rust 聚合，前端只传请求意图。
5. **增量读取必须幂等**：manifest、source purge、message-id dedupe 防止重复计数。
6. **隐私优先**：只缓存统计字段，不上传 prompt、tool result 或正文。

## 隐私

CraftMeter 只读取本机 AI 工具日志，用于本地统计。它不会上传数据。cache 中只保存统计事实，例如时间戳、模型、项目、token、费用归因、工具/source/status 等轻量字段。

请不要在 issue、PR、测试 fixture、snapshot 或 `public/dev-dashboard.json` 中提交真实会话内容。

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

Apache-2.0
