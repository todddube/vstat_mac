#!/usr/bin/env bash
# Build a distributable DMG from the exported (or Debug) app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="Vibe Stats"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :MARKETING_VERSION" /dev/stdin \
  <<< "$(plutil -convert xml1 -o - "$ROOT/project.yml" 2>/dev/null)" 2>/dev/null || echo "")"
[ -n "$VERSION" ] || VERSION="$(grep -m1 'MARKETING_VERSION:' "$ROOT/project.yml" | tr -d ' "' | cut -d: -f2)"

APP="$ROOT/build/export/VibeStats.app"
if [ ! -d "$APP" ]; then
  APP="$HOME/Library/Developer/Xcode/DerivedData/VibeStats-build/Build/Products/Debug/VibeStats.app"
  echo "note: no exported archive found, packaging the Debug build at $APP"
fi
[ -d "$APP" ] || { echo "error: no app to package. Run 'make build' or 'make notarize' first." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/VibeStats-$VERSION.dmg"
rm -f "$DMG"

hdiutil create \
  -volname "$NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "Wrote $DMG"
