# CraftMeter Release Checklist

## Repository and version

- Work from a clean release branch in `HeyHuazi/CraftMeter`.
- Confirm `VERSION` matches the intended `v*` tag.
- Confirm `AppUpdateService` points to `HeyHuazi/CraftMeter`.
- Confirm `README.md`, `LICENSE`, and `NOTICE` are current.

## Distribution mode

CraftMeter packaging has explicit modes:

- `PACKAGE_MODE=development`: local packaging; ad-hoc signing is allowed.
- `PACKAGE_MODE=preview`: public, non-notarized Preview; ad-hoc signing is allowed but must be disclosed.
- `PACKAGE_MODE=release`: requires Developer ID signing and Apple notarization; missing credentials must fail packaging.

Until Apple Developer credentials are available, GitHub Actions must use `PACKAGE_MODE=preview`. Do not describe those artifacts as notarized or silently treat them as a production release.

## Verification

```bash
swift build
swift test
PACKAGE_MODE=preview APP_VERSION=$(cat VERSION) ./scripts/package_dmg.sh
```

Expected test baseline after the Swift migration: at least 881 XCTest tests.

## Artifact inspection

Confirm these files exist and are non-empty:

```text
dist/CraftMeter.dmg
dist/CraftMeter-macOS.zip
```

Mount the DMG and verify:

- `CraftMeter.app` can be opened through Finder's **Open** context-menu path on a clean Preview install.
- Bundle identifier is `com.heyhuazi.craftmeter.app`.
- The first successful launch opens Settings once and explains the visible app state; later launches remain menu-bar only.
- Menu-bar UI opens, including when the Dock icon is absent.
- Settings opens and Usage Analytics can refresh.
- Existing OhMyUsage config imports without deleting the old directory.
- Confirm the DMG contains `安装说明（请先看这里）.txt` and that it:
  - discloses ad-hoc signing and missing notarization;
  - recommends right-click **Open** and System Settings **Open Anyway**;
  - explains menu-bar-only behavior;
  - never recommends globally disabling Gatekeeper.

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
