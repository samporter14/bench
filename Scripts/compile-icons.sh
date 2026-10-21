#!/bin/zsh
# compile-icons.sh — compile Capsid's icons into an app's Resources folder.
# Usage: Scripts/compile-icons.sh <Resources folder> [partial Info.plist to write]
# (build-app.sh runs it on Capsid.app/Contents/Resources.)
#
# One actool call compiles Resources/AppIcon.icon as the app's icon and each
# document in Resources/AppIconVariants (but Clay, which is AppIcon) as an
# alternate app icon, so the folder gets AppIcon.icns and one Assets.car that
# holds all six as full icon stacks. Settings → General → App icon sets the
# chosen one as the Dock icon with NSImage: the catalog image named for the
# choice, 32 to 1024 px, with the system's own treatment (AppIconChoice). Each
# document's folder name is its icon's name. The partial Info.plist keeps
# CFBundleIconName and CFBundleIconFile at AppIcon (the app's own Info.plist is
# what ships; DESIGN.md, App icon).
#
# Failure-tolerant like the step it came from: if the combined call fails, it
# warns and compiles AppIcon alone (Capsid then keeps Clay); if that fails it
# warns again. It exits 0 either way. actool is given absolute paths only (its
# helper resolves relative ones against wherever another run started it).
set -euo pipefail
ROOT="${0:A:h:h}"
DEST="${1:?usage: compile-icons.sh <Resources folder> [partial Info.plist]}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ICON="$ROOT/Resources/AppIcon.icon"
VARIANTS="$ROOT/Resources/AppIconVariants"
[ -d "$ICON" ] || exit 0

mkdir -p "$DEST"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/capsid-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PARTIAL="${2:-$WORK/partial.plist}"
cp -R "$ICON" "$WORK/AppIcon.icon"

DOCS=("$WORK/AppIcon.icon")
ALTERNATES=()
for DOC in "$VARIANTS"/*.icon(N); do
    ID="${DOC:t:r}"
    [[ "$ID" == clay ]] && continue
    cp -R "$DOC" "$WORK/$ID.icon"
    DOCS+=("$WORK/$ID.icon")
    ALTERNATES+=(--alternate-app-icon "$ID")
done

COMMON=(--compile "$DEST" --app-icon AppIcon --output-partial-info-plist "$PARTIAL"
    --platform macosx --minimum-deployment-target 27.0 --target-device mac
    --output-format human-readable-text)

if [ ${#ALTERNATES} -gt 0 ]; then
    if xcrun actool "${DOCS[@]}" "${COMMON[@]}" "${ALTERNATES[@]}" --include-all-app-icons >/dev/null; then
        exit 0
    fi
    echo "warning: the alternate icons did not compile; compiling AppIcon alone, so Capsid keeps Clay" >&2
fi
xcrun actool "$WORK/AppIcon.icon" "${COMMON[@]}" >/dev/null || echo "warning: icon not compiled" >&2
exit 0
