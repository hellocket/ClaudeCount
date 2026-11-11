#!/bin/zsh
# Build ClaudeCount.dmg: a disk image showing the app next to an "Applications" shortcut
# build.sh runs this at the end. You can also run it on its own once ClaudeCount.app is built.
set -e
cd "$(dirname "$0")"
APP="build.noindex/ClaudeCount.app"
[ -d "$APP" ] || { echo "Run ./build.sh first"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)/ClaudeCount
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Guides and license as plain .txt so anyone can open them (Markdown symbols stripped)
to_txt() { sed -E -e '/^```/d' -e '/^!\[/d' -e '/README(\.ko)?\.md\)/d' -e 's/\*\*//g' -e 's/`//g' -e 's/^#+ //' -e 's/^> //' -e 's/\[([^]]*)\]\(([^)]*)\)/\1 (\2)/g' "$1"; }
to_txt README.md > "$STAGE/Install Guide (English).txt"
[ -f README.ko.md ] && to_txt README.ko.md > "$STAGE/Install Guide (Korean).txt"  # optional Korean guide, kept outside the repo
to_txt fonts/Monoplex-LICENSE.md > "$STAGE/FONT-LICENSE (Monoplex OFL).txt"

rm -f ClaudeCount.dmg
hdiutil create -volname "ClaudeCount $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov ClaudeCount.dmg >/dev/null
rm -rf "$(dirname "$STAGE")"
echo "DMG: $(pwd)/ClaudeCount.dmg"
