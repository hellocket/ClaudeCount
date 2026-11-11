#!/bin/zsh
# Build ClaudeCount.app and install it to /Applications
# The build goes into build.noindex/ — Spotlight and Launchpad skip folders ending in .noindex,
# so only the installed copy shows up in search.
set -e
cd "$(dirname "$0")"
BUILD="build.noindex"
APP="$BUILD/ClaudeCount.app"
mkdir -p "$BUILD"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
# Universal binary: Apple Silicon + Intel
swiftc -O -swift-version 5 -target arm64-apple-macos13 -o /tmp/cub-arm64 main.swift
swiftc -O -swift-version 5 -target x86_64-apple-macos13 -o /tmp/cub-x86 main.swift
lipo -create /tmp/cub-arm64 /tmp/cub-x86 -output "$APP/Contents/MacOS/ClaudeCount"
rm -f /tmp/cub-arm64 /tmp/cub-x86
mkdir -p "$APP/Contents/Resources/Fonts" && cp fonts/*.ttf fonts/Monoplex-LICENSE.md "$APP/Contents/Resources/Fonts/"
# App icon (icon-1024.png → AppIcon.icns). To redraw it: swift make-icon.swift icon-1024.png
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz icon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) icon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeCount</string>
  <key>CFBundleIdentifier</key><string>io.github.hellocket.claudecount</string>
  <key>CFBundleExecutable</key><string>ClaudeCount</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.3</string>
  <key>CFBundleVersion</key><string>1.0.3</string>
  <key>CFBundleDisplayName</key><string>ClaudeCount</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
</dict></plist>
EOF
# Sign with the "ClaudeCount Code Signing" certificate (login keychain) so macOS keeps
# recognizing the app across updates (Menu Bar allow list, Login Items).
# Falls back to ad-hoc signing when the certificate is missing.
SIGN_ID="ClaudeCount Code Signing"
if security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
  codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "WARNING: \"$SIGN_ID\" certificate not found, using ad-hoc signing" >&2
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
# install (replaces the copy in /Applications; quit ClaudeCount first if it is running)
pkill -x ClaudeCount 2>/dev/null || true
rm -rf /Applications/ClaudeCount.app
cp -R "$APP" /Applications/
touch /Applications/ClaudeCount.app
echo "Installed: /Applications/ClaudeCount.app"
# Distributable zip
rm -f ClaudeCount.zip
# Contents: app + install guide(s) + font license
DIST=$(mktemp -d)/ClaudeCount
mkdir -p "$DIST"
cp -R "$APP" "$DIST/"
to_txt() { sed -E -e '/^```/d' -e '/^!\[/d' -e '/README(\.ko)?\.md\)/d' -e 's/\*\*//g' -e 's/`//g' -e 's/^#+ //' -e 's/^> //' -e 's/\[([^]]*)\]\(([^)]*)\)/\1 (\2)/g' "$1"; }
to_txt README.md > "$DIST/Install Guide (English).txt"
[ -f README.ko.md ] && to_txt README.ko.md > "$DIST/Install Guide (Korean).txt"  # optional Korean guide, kept outside the repo
to_txt fonts/Monoplex-LICENSE.md > "$DIST/FONT-LICENSE (Monoplex OFL).txt"
ditto -c -k --norsrc --keepParent "$DIST" ClaudeCount.zip
rm -rf "$(dirname "$DIST")"
echo "Zip: $(pwd)/ClaudeCount.zip"

# Installer DMG
./make-dmg.sh
