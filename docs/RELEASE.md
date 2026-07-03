# CraftMeter Release Process

CraftMeter keeps source code in Git and binary artifacts in **GitHub Releases**.

The rule is simple: `.app`, `.dmg`, installers, archives, and checksums are release assets, not repository files.

## Where users download builds

Stable builds live on GitHub Releases:

```text
https://github.com/HeyHuazi/CraftMeter/releases
```

A typical release contains:

```text
CraftMeter_1.0.0_aarch64.dmg
checksums.txt
```

## Local validation

Before tagging a release, run:

```bash
npm run build
npm run test:rust
```

For a local macOS bundle, run:

```bash
npm run tauri:build
```

Local bundle output is generated under:

```text
src-tauri/target/release/bundle/macos/CraftMeter.app
src-tauri/target/release/bundle/dmg/*.dmg
```

Those files are intentionally ignored by Git.

## Publish a release

Create and push a semver tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The `Release` GitHub Actions workflow builds the app on `macos-latest`, runs the frontend build and Rust tests, creates the Tauri bundles, writes `checksums.txt`, and uploads the DMG to the matching GitHub Release.

You can also run the workflow manually from GitHub Actions with a tag input, but the tag must already exist.

## Notarization

Current CI builds are unsigned or ad-hoc signed unless Apple signing and notarization secrets are configured. For public macOS distribution, add Apple Developer credentials and notarization to the release workflow before calling the build fully trusted.

Until then, the release DMG is useful for testing and direct distribution, but macOS Gatekeeper may show the usual warning.

## Artifact policy

Do commit:

- source files
- lockfiles
- docs
- workflow configuration
- small deterministic fixtures

Do not commit:

- `.app`
- `.dmg`
- `.pkg`
- `.zip`
- `.tar.gz`
- `src-tauri/target/`
- `dist/`
- real user session logs

Git history should describe the product. GitHub Releases should carry the product.
