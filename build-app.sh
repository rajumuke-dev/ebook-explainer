#!/usr/bin/env bash
# Builds a release binary and wraps it in "Ebook Explainer.app".
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/Ebook Explainer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/EbookExplainer" "$APP/Contents/MacOS/EbookExplainer"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ebook Explainer</string>
  <key>CFBundleDisplayName</key><string>Ebook Explainer</string>
  <key>CFBundleIdentifier</key><string>local.ebook-explainer</string>
  <key>CFBundleExecutable</key><string>EbookExplainer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"
