#!/bin/zsh
# build-app.sh — build Bench.app into ./build (release, universal not needed:
# internal, this Mac only). Usage: Scripts/build-app.sh [--open]
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build -c release --product Bench
BIN="$(swift build -c release --product Bench --show-bin-path)/Bench"

APP="$ROOT/build/Bench.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bench"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# The icon: the Science Status droplet's Icon Composer document, compiled.
# actool is given absolute paths only (its helper resolves relative ones
# against wherever another run started it).
ICON="$ROOT/../droplets/science-status/ScienceStatus.icon"
if [ -d "$ICON" ]; then
    WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/bench-icon.XXXXXX")"
    cp -R "$ICON" "$WORK/AppIcon.icon"
    xcrun actool "$WORK/AppIcon.icon" --compile "$APP/Contents/Resources" \
        --app-icon AppIcon --output-partial-info-plist "$WORK/partial.plist" \
        --platform macosx --minimum-deployment-target 26.0 --target-device mac \
        --output-format human-readable-text >/dev/null || echo "warning: icon not compiled"
    rm -rf "$WORK"
fi

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
[[ "${1:-}" == "--open" ]] && open "$APP"
exit 0
