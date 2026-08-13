#!/bin/bash
# Builds OsumTimer.app and wraps it in a drag-and-drop .dmg under build/.
#
# Everything lands in build/, which is git-ignored: build/OsumTimer.app is the
# bundle itself, build/OsumTimer-<version>.dmg opens a window holding the app
# beside an /Applications shortcut to drop it into.
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
BUNDLE_ID="${BUNDLE_ID:-com.osumtimer.OsumTimer}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/OsumTimer.app"
STAGE="$BUILD/stage"

# A build/ left behind by a `sudo` run is root-owned and silently un-overwritable,
# so every later package would ship whatever stale bundle was already sitting there.
if [ -e "$BUILD" ] && ! rm -rf "$APP" "$STAGE" 2>/dev/null; then
	echo "error: cannot clear $BUILD — some of it is owned by another user." >&2
	find "$BUILD" ! -user "$(id -un)" -print 2>/dev/null | head -3 | sed 's/^/       /' >&2
	echo "       run: sudo rm -rf \"$BUILD\"" >&2
	exit 1
fi
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

echo "==> Building disk image"
# The staged folder is what the mounted volume shows: the app, and a symlink to
# /Applications to drag it onto. That pair is the whole install flow.
cp -R "$APP" "$STAGE/OsumTimer.app"
ln -s /Applications "$STAGE/Applications"

DMG="$BUILD/OsumTimer-$VERSION.dmg"
RW="$BUILD/rw.dmg"
VOLUME="OsumTimer $VERSION"

rm -f "$DMG" "$RW"
# Built read/write first so Finder can be told where the two icons sit; a
# read-only image cannot have its window laid out after the fact.
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" \
	-fs HFS+ -format UDRW -ov "$RW" >/dev/null

MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | head -1)"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT

# Cosmetic only. Finder scripting needs Automation permission, which a fresh
# machine or a CI box will not have — so a failure here must not fail the build.
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "    (skipped window layout — Finder scripting unavailable)"
tell application "Finder"
	tell disk "$VOLUME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 150, 800, 570}
		set theViewOptions to the icon view options of container window
		set arrangement of theViewOptions to not arranged
		set icon size of theViewOptions to 128
		set position of item "OsumTimer.app" of container window to {150, 190}
		set position of item "Applications" of container window to {450, 190}
		close
		open
		update without registering applications
		delay 2
		close
	end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet
trap - EXIT

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"

echo
echo "App:  $APP"
echo "Disk image: $DMG"
