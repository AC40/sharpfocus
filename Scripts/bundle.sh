#!/bin/bash
# Builds SharpFocus.app (release) into build/.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/SharpFocus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SharpFocus "$APP/Contents/MacOS/SharpFocus"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
