# Download and Install

## GitHub Preview Release

- [Latest CraftMeter Release](https://github.com/HeyHuazi/CraftMeter/releases/latest)
- Recommended asset: `CraftMeter.dmg`

> **安全提示：** 当前 GitHub Release 是 ad-hoc 签名、未经 Apple 公证的 Preview。macOS 无法验证发布者身份，首次启动通常需要在“应用程序”中右键 CraftMeter 并选择 **Open / 打开**。

## Install

1. Download `CraftMeter.dmg` from the official repository.
2. Open the disk image and drag `CraftMeter.app` into `/Applications`.
3. In Finder, open **Applications**.
4. Control-click or right-click `CraftMeter.app`, choose **Open**, then confirm once.
5. If macOS still blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway** for CraftMeter.

CraftMeter is a menu-bar app. It does not normally show a Dock icon. On the first successful launch it opens Settings once; after that, look for its icon on the right side of the menu bar. Bartender, Ice, or limited notch space may hide it.

For a trusted artifact downloaded from the official repository whose SHA-256 matches the Release page, quarantine can be removed as a last resort:

```bash
xattr -dr com.apple.quarantine "/Applications/CraftMeter.app"
```

This removes quarantine only from CraftMeter. Do **not** disable Gatekeeper globally with `sudo spctl --master-disable`.

To diagnose a launch failure:

```bash
/Applications/CraftMeter.app/Contents/MacOS/CraftMeter
```

Report the terminal output, macOS version, and Mac chip at [CraftMeter Issues](https://github.com/HeyHuazi/CraftMeter/issues).

## Build from source

Requirements:

- macOS 14+
- Swift 6.2+

```bash
swift build
swift test
PACKAGE_MODE=development APP_VERSION=$(cat VERSION) ./scripts/package_dmg.sh
```

Artifacts:

```text
dist/CraftMeter.dmg
dist/CraftMeter-macOS.zip
```

## Automatic updates

CraftMeter checks:

```text
https://github.com/HeyHuazi/CraftMeter/releases/latest/download/latest.json
```

The manifest contains release URLs, SHA-256 hashes, and asset sizes. The updater verifies the downloaded archive before installation.
