#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CraftMeter"
EXECUTABLE_NAME="CraftMeter"
SWIFTPM_RESOURCE_TARGET="OhMyUsage"
BUNDLE_ID="com.heyhuazi.craftmeter.app"
DIST_DIR="$ROOT_DIR/dist"
TMP_ROOT="$(mktemp -d /tmp/aibm_pkg.XXXXXX)"
APP_DIR="$TMP_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
DMG_STAGING="$TMP_ROOT/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
ZIP_NAME="CraftMeter-macOS.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
RW_DMG_PATH="$TMP_ROOT/$APP_NAME-rw.dmg"
MOUNT_POINT="$TMP_ROOT/mount"
APP_ZIP_PATH="$TMP_ROOT/$APP_NAME.zip"
INSTALL_GUIDE_NAME="安装说明（请先看这里）.txt"
ICON_SOURCE_PATH="$ROOT_DIR/Sources/OhMyUsage/Resources/app_icon_source.png"
ICONSET_DIR="$TMP_ROOT/AppIcon.iconset"
ICNS_PATH="$TMP_ROOT/AppIcon.icns"
INSTALL_GUIDE_PATH="$DMG_STAGING/$INSTALL_GUIDE_NAME"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_VERSION="${APP_VERSION:-}"
PACKAGE_MODE="${PACKAGE_MODE:-development}"

if [[ -z "$APP_VERSION" && -f "$VERSION_FILE" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="0.0.0"
fi

log() {
  echo "[$APP_NAME] $*"
}

warn() {
  echo "[$APP_NAME] warning: $*" >&2
}

die() {
  echo "[$APP_NAME] error: $*" >&2
  exit 1
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || die "missing required command: $1"
}

clean_previous_artifacts() {
  mkdir -p "$DIST_DIR"
  log "Cleaning previous package artifacts"

  local artifact
  while IFS= read -r -d '' artifact; do
    log "Removing previous artifact: ${artifact#$ROOT_DIR/}"
    rm -rf "$artifact"
  done < <(
    find "$DIST_DIR" -maxdepth 1 \( \
      -name "$APP_NAME.app" -o \
      -name "$APP_NAME.dmg" -o \
      -name "$APP_NAME [0-9]*.dmg" -o \
      -name "$ZIP_NAME" -o \
      -name "${ZIP_NAME%.zip} [0-9]*.zip" -o \
      -name "AI Plan Monitor.app" -o \
      -name "AI Plan Monitor.dmg" -o \
      -name "AI Plan Monitor [0-9]*.dmg" -o \
      -name "AI-Plan-Monitor-macOS.zip" -o \
      -name "AI-Plan-Monitor-macOS [0-9]*.zip" -o \
      -name "dmg-root" \
    \) -print0
  )
}

has_notary_profile() {
  [[ -n "${NOTARYTOOL_PROFILE:-}" ]]
}

has_notary_apple_id() {
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]
}

has_notary_api_key() {
  [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]
}

should_notarize() {
  if [[ "${NOTARIZE_DMG:-}" == "" ]]; then
    has_notary_profile || has_notary_apple_id || has_notary_api_key
    return
  fi

  is_truthy "${NOTARIZE_DMG:-false}"
}

signing_identity() {
  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "$DEVELOPER_ID_APPLICATION"
  elif [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
  else
    echo ""
  fi
}

sign_mode() {
  local identity
  identity="$(signing_identity)"
  if [[ -n "$identity" ]]; then
    echo "developer-id"
  else
    echo "ad-hoc"
  fi
}

validate_package_mode() {
  case "$PACKAGE_MODE" in
    development)
      ;;
    preview)
      if [[ -z "$(signing_identity)" ]]; then
        warn "Building an ad-hoc signed, non-notarized Preview package"
      fi
      ;;
    release)
      [[ -n "$(signing_identity)" ]] || \
        die "release mode requires DEVELOPER_ID_APPLICATION or CODESIGN_IDENTITY"
      should_notarize || \
        die "release mode requires notarization credentials and NOTARIZE_DMG=true (or automatic notarization)"
      ;;
    *)
      die "unknown PACKAGE_MODE '$PACKAGE_MODE'; expected development, preview, or release"
      ;;
  esac
}

resolve_binary_path() {
  local candidates=(
    "$ROOT_DIR/.build/apple/Products/Release/$EXECUTABLE_NAME"
    "$ROOT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
    "$ROOT_DIR/.build/x86_64-apple-macosx/release/$EXECUTABLE_NAME"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

build_products_dir() {
  local binary_path="$1"
  dirname "$binary_path"
}

copy_support_files() {
  local products_dir="$1"
  mkdir -p "$RES_DIR" "$FRAMEWORKS_DIR"

  # SwiftPM resource bundles use <package>_<target>.bundle, not the executable product name twice.
  # Bundle.module asserts at runtime when this bundle is absent, so packaging must fail closed.
  local resource_bundle="$products_dir/${APP_NAME}_${SWIFTPM_RESOURCE_TARGET}.bundle"
  [[ -d "$resource_bundle" ]] || \
    die "SwiftPM resource bundle not found at: $resource_bundle"

  log "Copying SwiftPM resource bundle: $(basename "$resource_bundle")"
  cp -R "$resource_bundle" "$RES_DIR/"

  local package_frameworks="$products_dir/PackageFrameworks"
  if [[ -d "$package_frameworks" ]]; then
    log "Copying PackageFrameworks"
    cp -R "$package_frameworks"/. "$FRAMEWORKS_DIR/"
  fi
}

generate_icns() {
  [[ -f "$ICON_SOURCE_PATH" ]] || return 0
  require_cmd sips
  require_cmd iconutil

  rm -rf "$ICONSET_DIR" "$ICNS_PATH"
  mkdir -p "$ICONSET_DIR"

  local sizes=(16 32 128 256 512)
  for size in "${sizes[@]}"; do
    sips -z "$size" "$size" "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    local retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done

  log "Generating AppIcon.icns"
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
  cp "$ICNS_PATH" "$RES_DIR/AppIcon.icns"
}

sign_app_bundle() {
  local target="$1"
  local identity
  identity="$(signing_identity)"

  if ! have_cmd codesign; then
    warn "codesign not found; app bundle will remain unsigned"
    return 0
  fi

  if [[ -n "$identity" ]]; then
    log "Signing app bundle with Developer ID identity"
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$target"
  else
    log "Signing app bundle with ad-hoc identity"
    codesign --force --deep --sign - --timestamp=none "$target"
  fi

  codesign --verify --deep --strict --verbose=2 "$target" >/dev/null
}

sign_disk_image() {
  local target="$1"
  local identity
  identity="$(signing_identity)"

  if ! have_cmd codesign; then
    return 0
  fi

  if [[ -n "$identity" ]]; then
    log "Signing disk image with Developer ID identity"
    codesign --force --timestamp --sign "$identity" "$target"
    codesign --verify --strict --verbose=2 "$target" >/dev/null
  fi
}

assess_bundle() {
  local target="$1"
  if have_cmd spctl; then
    spctl --assess --type exec --verbose=2 "$target" || true
  fi
}

notary_submit() {
  local artifact="$1"
  require_cmd xcrun

  if has_notary_profile; then
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    return 0
  fi

  if has_notary_api_key; then
    xcrun notarytool submit "$artifact" \
      --key "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      --wait
    return 0
  fi

  if has_notary_apple_id; then
    xcrun notarytool submit "$artifact" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
    return 0
  fi

  die "NOTARIZE_DMG is enabled but no notarization credentials were provided"
}

staple_artifact() {
  local target="$1"
  require_cmd xcrun
  xcrun stapler staple "$target"
}

prepare_install_guide() {
  cat > "$INSTALL_GUIDE_PATH" <<EOF
${APP_NAME} Preview 安装与首次启动说明
====================================

重要说明
--------
当前 GitHub Preview 未经 Apple Developer ID 签名和 Apple 公证。
从浏览器下载后，macOS Gatekeeper 可能阻止首次双击启动；这表示系统无法验证发布者身份。

请仅从官方地址下载：
https://github.com/HeyHuazi/CraftMeter/releases

系统要求
--------
macOS 14 Sonoma 或更高版本。

安装步骤
--------
1. 将“${APP_NAME}.app”拖入“Applications”文件夹。
2. 打开 Finder，进入“应用程序”。
3. 按住 Control 点击或右键点击 ${APP_NAME}。
4. 选择“打开”，并在随后出现的对话框中再次选择“打开”。

如果没有“打开”按钮
------------------
1. 尝试启动一次 ${APP_NAME}。
2. 打开“系统设置” -> “隐私与安全性”。
3. 找到 ${APP_NAME} 被阻止的提示，点击“仍要打开”。
4. 根据系统提示确认。

启动后没有窗口？
----------------
${APP_NAME} 是菜单栏应用，不显示 Dock 图标，启动后驻留在屏幕顶部菜单栏。
首次成功启动会自动打开设置窗口；关闭设置窗口不会退出应用。

如果使用 Bartender、Ice 等菜单栏管理工具，请检查隐藏区域。
带刘海的 Mac 也可能因菜单栏空间不足而隐藏图标。

确认应用是否运行：
打开“活动监视器”搜索 ${APP_NAME}，或在终端执行：

pgrep -fl ${APP_NAME}

如果系统提示“App 已损坏”
------------------------
仅当文件来自上述官方 GitHub Release，且校验值与 Release 页面一致时，才在终端执行：

xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app
open /Applications/${APP_NAME}.app

该命令只移除 ${APP_NAME} 的下载隔离属性，不会全局关闭 Gatekeeper。

查看启动错误
------------
在终端执行：

/Applications/${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}

如果仍无法启动，请将终端输出、macOS 版本和 Mac 芯片型号提交到：
https://github.com/HeyHuazi/CraftMeter/issues

安全警告
--------
不要执行 sudo spctl --master-disable。
${APP_NAME} 不要求关闭整台 Mac 的 Gatekeeper。
EOF
}

customize_dmg_window() {
  local volume_name="$1"
  require_cmd osascript

  osascript <<EOF || warn "Skipping Finder DMG window customization"
tell application "Finder"
  tell disk "$volume_name"
    open
    delay 1
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {120, 120, 840, 540}
    end tell
    tell icon view options of container window
      set arrangement to not arranged
      set icon size to 128
      set text size to 14
    end tell
    set position of item "$APP_NAME.app" of container window to {180, 360}
    set position of item "Applications" of container window to {540, 360}
    update without registering applications
    delay 2
    close
    open
    delay 2
    close
  end tell
end tell
EOF
}

# Remove old distributables first so a failed package run cannot leave stale output.
validate_package_mode
clean_previous_artifacts

# Always build fresh release before packaging to avoid stale DMG content.
log "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(resolve_binary_path || true)"

if [[ ! -x "$BIN_PATH" ]]; then
  die "release binary not found at: $BIN_PATH"
fi

PRODUCTS_DIR="$(build_products_dir "$BIN_PATH")"

mkdir -p "$MACOS_DIR" "$RES_DIR" "$FRAMEWORKS_DIR" "$DMG_STAGING"

cp "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
copy_support_files "$PRODUCTS_DIR"
generate_icns
log "Using binary: $BIN_PATH"
file "$MACOS_DIR/$EXECUTABLE_NAME" || true

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>CraftMeter</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>NSApplicationIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFile</key>
      <string>AppIcon</string>
      <key>CFBundleIconName</key>
      <string>AppIcon</string>
    </dict>
  </dict>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Remove filesystem metadata that can invalidate app bundles (e.g. FinderInfo).
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
fi

if should_notarize && [[ -z "$(signing_identity)" ]]; then
  die "notarization requires DEVELOPER_ID_APPLICATION (or CODESIGN_IDENTITY) to be set"
fi

log "Packaging mode: $PACKAGE_MODE ($(sign_mode))"
sign_app_bundle "$APP_DIR"
assess_bundle "$APP_DIR"

if should_notarize; then
  log "Creating app zip for notarization"
  require_cmd ditto
  rm -f "$APP_ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"
  log "Submitting app zip for notarization"
  notary_submit "$APP_ZIP_PATH"
  log "Stapling app bundle"
  staple_artifact "$APP_DIR"
fi

require_cmd ditto
log "Creating distributable ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

cp -R "$APP_DIR" "$DMG_STAGING/"
prepare_install_guide
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH" >/dev/null

mkdir -p "$MOUNT_POINT"
hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_POINT" -noautoopen >/dev/null
customize_dmg_window "$APP_NAME"
hdiutil detach "$MOUNT_POINT" >/dev/null

hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -o "$DMG_PATH" >/dev/null

sign_disk_image "$DMG_PATH"

if should_notarize; then
  log "Submitting DMG for notarization"
  notary_submit "$DMG_PATH"
  log "Stapling DMG"
  staple_artifact "$DMG_PATH"
fi

log "DMG: $DMG_PATH"
log "ZIP: $ZIP_PATH"
log "TMP_APP: $APP_DIR"
