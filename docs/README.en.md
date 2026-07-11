# CraftMeter

CraftMeter is a native macOS menu-bar app for **AI quota monitoring and privacy-preserving local usage analytics**.

It is based on [Four-JJJJ/oh-myusage](https://github.com/Four-JJJJ/oh-myusage) v2.2.2 and extends the upstream provider runtime with CraftMeter analytics for Craft Agents, Gemini CLI, Qwen Code, Claude Code, Codex, Kimi, and CCSwitch.

## Highlights

- Official subscription quota, reset windows, balances, and auth health
- Account slots, macOS Keychain storage, menu-bar summaries, cache fallback, and updates
- Request/session counts and input/output/cache/reasoning tokens
- Client, provider, model, project, MCP, Skill, and Craft-specific facets
- Explicit known/unknown pricing state

## Privacy

CraftMeter extracts statistical facts only. It does not persist prompt text, assistant responses, tool inputs/results, or attachment bodies.

Configuration and analytics cache are stored under:

```text
~/Library/Application Support/CraftMeter
```

Legacy OhMyUsage configuration and Keychain entries are imported one way without deleting the old directory.

## Requirements and development

- macOS 14+
- Swift 6.2+

```bash
swift build
swift run CraftMeter
swift test
```

See [ARCHITECTURE.md](ARCHITECTURE.md), [PROVIDERS.md](PROVIDERS.md), and [DOWNLOAD.md](DOWNLOAD.md).

## Attribution

CraftMeter contains MIT-licensed code from oh-myusage, Copyright (c) 2026 FourJ. See the repository `LICENSE` and `NOTICE` files.
