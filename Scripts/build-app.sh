#!/bin/zsh
# build-app.sh — build Capsid.app into ./build (release, this Mac's
# architecture, signed by Scripts/sign-app.sh). Usage: Scripts/build-app.sh [--open]
# The Swift target is still named Bench; its product, Capsid, names the binary.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

# One build at a time: a second run would delete the app while the first one
# signs or opens it.
mkdir -p build
LOCK="$ROOT/build/.build-app.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another build-app.sh is already running. Wait for it to finish (or delete $LOCK if none is)." >&2
    exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build -c release --product Capsid --jobs "${CAPSID_BUILD_JOBS:-2}"
BIN="$(swift build -c release --product Capsid --show-bin-path)/Capsid"

APP="$ROOT/build/Capsid.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Capsid"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# The last step of a native update (App/UpdateInstall.swift): Capsid copies it
# out of the bundle and runs it once the new copy has been checked.
cp "$ROOT/Resources/swap.sh" "$APP/Contents/Resources/swap.sh"
# The panel's four sounds (Lab/PanelSound.swift): Capsid's own, since 1.0.1.
mkdir -p "$APP/Contents/Resources/Sounds"
cp "$ROOT"/Resources/Sounds/*.caf "$APP/Contents/Resources/Sounds/"

# The icons: Capsid's own, an Icon Composer document in Solanum's product
# family (a Clay tile, the broken ring with its escaped dot, an icosahedral
# capsid), and the five others Settings → General → App icon offers (since
# 0.9.5), compiled together into AppIcon.icns and the app's Assets.car, the
# others as alternate app icons. Capsid sets the chosen one as its Dock icon
# while it runs; the bundle's own icon, in Finder and Launchpad, is not touched.
# See Scripts/compile-icons.sh, which warns and falls back to AppIcon alone.
"$ROOT/Scripts/compile-icons.sh" "$APP/Contents/Resources"

# The Focus filter (App/PresentingFocusFilter.swift): Xcode extracts its App
# Intents metadata into the bundle, and SwiftPM doesn't, so this does. Before
# signing, which seals Resources.
"$ROOT/Scripts/appintents-metadata.sh" "$APP"

# Signed inside-out by Scripts/sign-app.sh: with "Solanum Code Signing" when
# this Mac has that certificate, so permissions and Capsid's own updater carry
# over between releases, else ad-hoc. CAPSID_SIGN_IDENTITY overrides it ("-"
# for ad-hoc, or a Developer ID later). See the script for why.
"$ROOT/Scripts/sign-app.sh" "$APP"
echo "Built $APP"
[[ "${1:-}" == "--open" ]] && open "$APP"
exit 0
