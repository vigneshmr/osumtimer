#!/bin/bash
# Builds OsumTimer.app and wraps it in an installer .pkg under build/.
#
# Everything lands in build/, which is git-ignored: build/OsumTimer.app is the
# bundle itself, build/OsumTimer-<version>.pkg installs it to /Applications.
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
BUNDLE_ID="${BUNDLE_ID:-com.osumtimer.OsumTimer}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/OsumTimer.app"
STAGE="$BUILD/stage"

rm -rf "$APP" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT"
cp "$(swift build -c release --package-path "$ROOT" --show-bin-path)/OsumTimer" "$APP/Contents/MacOS/OsumTimer"

echo "==> Drawing icon"
swift "$ROOT/scripts/make-icon.swift" "$APP/Contents/Resources/OsumTimer.icns"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>              <string>OsumTimer</string>
	<key>CFBundleDisplayName</key>       <string>OsumTimer</string>
	<key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
	<key>CFBundleExecutable</key>        <string>OsumTimer</string>
	<key>CFBundleIconFile</key>          <string>OsumTimer</string>
	<key>CFBundlePackageType</key>       <string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key>           <string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>    <string>14.0</string>
	<!-- Menu bar only: no Dock icon, no app switcher entry. -->
	<key>LSUIElement</key>               <true/>
	<key>NSHumanReadableCopyright</key>  <string>OsumTimer $VERSION</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
# Ad-hoc: enough for the bundle to launch locally and to have a stable identity
# for notification permissions. Distribution would need a Developer ID here.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "==> Building installer"
cp -R "$APP" "$STAGE/OsumTimer.app"
PKG="$BUILD/OsumTimer-$VERSION.pkg"
pkgbuild \
	--root "$STAGE" \
	--identifier "$BUNDLE_ID" \
	--version "$VERSION" \
	--install-location /Applications \
	"$PKG" >/dev/null

rm -rf "$STAGE"

echo
echo "App:       $APP"
echo "Installer: $PKG"
