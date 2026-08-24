#!/usr/bin/env bash
#
# install.sh — build BarTab and install it to /Applications.
#
# Why this exists: derived data must never live inside the repo or a
# cloud-synced folder, so builds go to /tmp. But /tmp is cleared by macOS,
# and BarTab registers itself as a login item pointing at its own bundle
# path — so an app left in /tmp silently stops launching at login after a
# reboot. The app's permanent home is /Applications; /tmp is only ever a
# build scratch directory.
#
# Usage: ./scripts/install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="/tmp/bartab-dd"
BUILT="$DERIVED/Build/Products/Release/BarTab.app"
DEST="/Applications/BarTab.app"

cd "$REPO_DIR"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Release, derived data in $DERIVED)"
xcodebuild -project BarTab.xcodeproj -scheme BarTab -configuration Release \
    -derivedDataPath "$DERIVED" build

if [ ! -d "$BUILT" ]; then
    echo "Build succeeded but $BUILT is missing. Aborting." >&2
    exit 1
fi

echo "==> Stopping any running BarTab"
killall BarTab 2>/dev/null || true
sleep 1

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

echo "==> Launching from its permanent home"
open "$DEST"
sleep 2

echo
echo "Installed. BarTab is running from $DEST and registers itself as a"
echo "login item from that path, so it survives reboots and /tmp being cleared."
echo
echo "If the icon is not visible, a menu bar manager (Ice, Bartender) may be"
echo "hiding it — drag it out of the hidden section."
