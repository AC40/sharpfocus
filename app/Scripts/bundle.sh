#!/bin/bash
# Builds SharpFocus.app into build/. Defaults to release; pass -c debug for a debuggable build.
# Usage: ./Scripts/bundle.sh [-c debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config) CONFIG="$2"; shift 2 ;;
    debug|release) CONFIG="$1"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

swift build -c "$CONFIG"

APP=build/SharpFocus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/SharpFocus" "$APP/Contents/MacOS/SharpFocus"
cp ".build/$CONFIG/sfctl" "$APP/Contents/MacOS/sfctl"

# App icon (rendered from Scripts/make-icon.swift, cached in build/).
if [ ! -f build/AppIcon.icns ]; then
  swift Scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# App resources (SVGs, images) — copy Resources into bundle.
if [ -d Sources/SharpFocus/Resources ]; then
  cp -R Sources/SharpFocus/Resources/* "$APP/Contents/Resources/"
fi
# Also copy SPM resource bundle if present (Bundle.module support).
for bundle in ".build/$CONFIG/"*.bundle ".build/$CONFIG/SharpFocus_"*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/" 2>/dev/null || true
done

VERSION="${SHARPFOCUS_VERSION:-0.2.0}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleName</key>
	<string>SharpFocus</string>
	<key>CFBundleDisplayName</key>
	<string>Sharp Focus</string>
	<key>CFBundleIdentifier</key>
	<string>de.beyond925.SharpFocus</string>
	<key>CFBundleExecutable</key>
	<string>SharpFocus</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© Aaron Richter. MIT License.</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>de.beyond925.SharpFocus</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>sharpfocus</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
