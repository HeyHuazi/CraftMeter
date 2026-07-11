# Download and Install

## GitHub Release

- [Latest CraftMeter Release](https://github.com/HeyHuazi/CraftMeter/releases/latest)
- Recommended asset: `CraftMeter.dmg`

## Install

1. Download `CraftMeter.dmg`.
2. Open the disk image.
3. Drag `CraftMeter.app` into `/Applications`.
4. Start CraftMeter and finish the permission onboarding.

The app is currently distributed outside the Mac App Store. If macOS blocks a locally built or unsigned copy, right-click `CraftMeter.app` and choose **Open**, then confirm once.

For a trusted build downloaded from this repository, quarantine can also be removed manually:

```bash
xattr -dr com.apple.quarantine "/Applications/CraftMeter.app"
```

## Build from source

Requirements:

- macOS 14+
- Swift 6.2+

```bash
swift build
swift test
APP_VERSION=$(cat VERSION) ./scripts/package_dmg.sh
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
