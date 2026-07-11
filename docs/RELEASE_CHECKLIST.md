# CraftMeter Release Checklist

## Repository and version

- Work from a clean release branch in `HeyHuazi/CraftMeter`.
- Confirm `VERSION` matches the intended `v*` tag.
- Confirm `AppUpdateService` points to `HeyHuazi/CraftMeter`.
- Confirm `README.md`, `LICENSE`, and `NOTICE` are current.

## Verification

```bash
swift build
swift test
APP_VERSION=$(cat VERSION) ./scripts/package_dmg.sh
```

Expected test baseline after the Swift migration: 881 XCTest tests.

## Artifact inspection

Confirm these files exist and are non-empty:

```text
dist/CraftMeter.dmg
dist/CraftMeter-macOS.zip
```

Mount the DMG and verify:

- `CraftMeter.app` launches.
- Bundle identifier is `com.heyhuazi.craftmeter.app`.
- Menu-bar UI opens.
- Settings opens and Usage Analytics can refresh.
- Existing OhMyUsage config imports without deleting the old directory.
- Keychain import does not expose credentials in logs.

## Analytics smoke test

- Claude Code, Codex, Kimi, Gemini CLI, Qwen Code, Craft Agents, and CCSwitch failures are isolated per source.
- reasoning token and cost UI render correctly.
- unknown pricing displays as a lower bound, not zero.
- no prompt, assistant, tool result, or attachment body appears in cache files.

## GitHub Release

- Push a `v*` tag or dispatch `.github/workflows/release.yml`.
- Confirm release assets:
  - `latest.json`
  - `CraftMeter.dmg`
  - `CraftMeter-macOS.zip`
- Confirm the published manifest resolves at:

```text
https://github.com/HeyHuazi/CraftMeter/releases/latest/download/latest.json
```

- Verify SHA-256 and size fields match uploaded files.
