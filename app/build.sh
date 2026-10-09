#!/bin/bash
# يبني تطبيق «khaled_cli HQ» ويحطه في مجلد التطبيقات.
# التطبيق واجهة بس: يشغّل tiktok-hq.sh من مجلد الأداة (مساره ينكتب داخل التطبيق).
# الاستخدام (install.sh يشغّله بروحه): build.sh <مجلد_الأداة> <مجلد_التطبيقات>
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_DIR="${1:?مجلد الأداة ناقص}"
DEST="${2:-/Applications}"
NAME="khaled_cli HQ"
WORK="$APP_DIR/.build/bundle"
APP="$WORK/$NAME.app"

cd "$APP_DIR"
swift build -c release 2>&1 | grep -v "warning:" | tail -1
[[ -x .build/release/KhaledCLIHQ ]] || { echo "!! فشل بناء التطبيق" >&2; exit 1; }
rm -rf "$WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/KhaledCLIHQ" "$APP/Contents/MacOS/KhaledCLIHQ"

# الأيقونة
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
swift make-icon.swift "$WORK/icon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.khaled.khaledcli-hq</string>
  <key>CFBundleExecutable</key><string>KhaledCLIHQ</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>ar</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>HQToolDir</key><string>$(printf '%s' "$TOOL_DIR" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Video</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.movie</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
mkdir -p "$DEST"
rm -rf "${DEST:?}/$NAME.app"
cp -R "$APP" "$DEST/"
echo "-- التطبيق: $DEST/$NAME.app"
