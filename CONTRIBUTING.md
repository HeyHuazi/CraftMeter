# Contributing to CraftMeter

感谢你愿意改进 CraftMeter。当前主线是 **Tauri + React + Rust**：Rust 做日志扫描与聚合，React 做展示，Tauri 做 menubar app shell。

## 开发环境

- macOS 13+
- Node.js 18+
- Rust stable
- Tauri 2 所需系统依赖

## 常用命令

```bash
npm install
npm run tauri:dev
npm run build
npm run test:rust
npm run tauri:build
```

`npm run tauri:build` 的 macOS 产物通常在：

```text
src-tauri/target/release/bundle/macos/CraftMeter.app
src-tauri/target/release/bundle/dmg/*.dmg
```

## 发布流程

二进制产物不进入 Git 历史。`.app`、`.dmg`、installer 和 archive 都放在 GitHub Releases。

本地发布前验证：

```bash
npm run build
npm run test:rust
```

创建正式 release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 的 `Release` workflow 会构建 macOS DMG、生成 `checksums.txt`，并上传到对应 GitHub Release。详细规则见 [docs/RELEASE.md](docs/RELEASE.md)。

## 架构边界

```text
React UI ──invoke(get_dashboard)──> Tauri command ──> Rust parser
                                                     │
                                                     ├── Store: incremental logs/cache
                                                     ├── Pricing: LiteLLM prices
                                                     └── Config: MCP/Skills discovery
```

- `src-tauri/src/store.rs` 是日志 ingestion 和 cache 边界。
- `src-tauri/src/parser.rs` 是 dashboard 聚合边界。
- `src-tauri/src/model.rs` 定义 Rust → React 的序列化契约。
- `src/data.ts` 必须匹配 Rust `Dashboard` shape，不要引入第二套 backend 协议。
- React 不直接读文件、不解析 JSONL、不计算价格。

## PR 规则

- 修改 Rust 数据模型：同步 `src/data.ts` 类型和 `docs/ARCHITECTURE.md`。
- 修改 ingestion 语义：补 Rust 测试，并考虑 bump `STORE_VERSION`。
- 修改 UI 行为：说明手工验证路径，最好附截图。
- 修改构建/打包：更新 README。
- 新增依赖前先证明必要性；默认答案是不加。

## 隐私原则

CraftMeter 只读取本机日志并在本机聚合。请不要在 issue、PR、测试 fixture、snapshot 或 `public/dev-dashboard.json` 中提交真实 prompt、tool result、附件正文或 session 内容。
