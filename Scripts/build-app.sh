#!/bin/zsh
# build-app.sh — build Capsid.app into ./build (release, this Mac's
# architecture, ad-hoc signed). Usage: Scripts/build-app.sh [--open]
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

# The icon: an Icon Composer document, Capsid's own in Solanum's product
# family (a Clay tile, the broken ring with its escaped dot, an icosahedral
# capsid), compiled. actool is given absolute paths only (its helper
# resolves relative ones against wherever another run started it).
ICON="$ROOT/Resources/AppIcon.icon"
if [ -d "$ICON" ]; then
    WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/capsid-icon.XXXXXX")"
    cp -R "$ICON" "$WORK/AppIcon.icon"
    xcrun actool "$WORK/AppIcon.icon" --compile "$APP/Contents/Resources" \
        --app-icon AppIcon --output-partial-info-plist "$WORK/partial.plist" \
        --platform macosx --minimum-deployment-target 27.0 --target-device mac \
        --output-format human-readable-text >/dev/null || echo "warning: icon not compiled"
    rm -rf "$WORK"
fi

# The other icons Settings → General → App icon offers (since 0.9.5): one
# Icon Composer document per choice in Resources/AppIconVariants (cut from the
# glyph by Scripts/make-icon-variants.py), each compiled the same way into a
# folder of its own, since actool also writes an Assets.car that would replace
# the app's, and only its .icns kept, in Contents/Resources/AppIcons/<id>.icns.
# Capsid sets the chosen one as its Dock icon while it runs; the bundle's own
# icon, in Finder and Launchpad, is not touched. Clay is that icon, so it is
# copied. An icon that doesn't compile is skipped: Capsid then keeps Clay.
VARIANTS="$ROOT/Resources/AppIconVariants"
if [ -d "$VARIANTS" ] && [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    mkdir -p "$APP/Contents/Resources/AppIcons"
    cp "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcons/clay.icns"
    for DOC in "$VARIANTS"/*.icon(N); do
        ID="${DOC:t:r}"
        [[ "$ID" == clay ]] && continue
        WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/capsid-icon.XXXXXX")"
        cp -R "$DOC" "$WORK/$ID.icon"
        if xcrun actool "$WORK/$ID.icon" --compile "$WORK" \
            --app-icon "$ID" --output-partial-info-plist "$WORK/partial.plist" \
            --platform macosx --minimum-deployment-target 27.0 --target-device mac \
            --output-format human-readable-text >/dev/null && [ -f "$WORK/$ID.icns" ]; then
            cp "$WORK/$ID.icns" "$APP/Contents/Resources/AppIcons/$ID.icns"
        else
            echo "warning: icon $ID not compiled"
        fi
        rm -rf "$WORK"
    done
fi

# The Focus filter (App/PresentingFocusFilter.swift): Xcode extracts its App
# Intents metadata into the bundle, and SwiftPM doesn't, so this does. Before
# signing, which seals Resources.
"$ROOT/Scripts/appintents-metadata.sh" "$APP"

# Signed with "Solanum Code Signing" when this Mac has that certificate (a
# self-signed one in the login keychain): the signature then names the
# certificate rather than this exact build, so macOS keeps the permissions it
# granted (microphone, browser control) across updates. Without it, ad-hoc,
# as anyone building from source gets.
IDENTITY=$(security find-certificate -c "Solanum Code Signing" -Z 2>/dev/null | awk '/SHA-1/ {print $3; exit}' || true)
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
else
    codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"
[[ "${1:-}" == "--open" ]] && open "$APP"
exit 0
