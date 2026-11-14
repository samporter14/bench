#!/bin/zsh
# sign-app.sh — sign an app bundle inside-out. Usage: Scripts/sign-app.sh <Capsid.app>
#
# Every nested piece is signed before the bundle that holds it, and the app
# last, so each signature seals pieces that are already signed. --deep is never
# used to sign (it skips entitlements and signs things in the wrong order); it's
# only for verifying. Today Capsid is a single executable with nothing nested,
# so this signs only the app, but a framework, dylib, helper, XPC service or
# extension added later is picked up without changing this script. A nested
# bundle with an entitlements file is signed with it: <bundle name>.entitlements
# next to this repository's Resources/Info.plist (e.g. Resources/CapsidWidget.entitlements).
#
# The identity, in order:
#   1. CAPSID_SIGN_IDENTITY, if set: a certificate name or SHA-1, or "-" for
#      ad-hoc. Set it to a "Developer ID Application: …" identity to sign for
#      notarization later (add CAPSID_SIGN_OPTIONS="--options runtime --timestamp"
#      then, with whatever entitlements hardened runtime needs).
#   2. "Solanum Code Signing", when this Mac has it (a self-signed certificate
#      in the login keychain). The signature then names the certificate rather
#      than this exact build, so macOS keeps the permissions it granted
#      (microphone, browser control) across updates, and Capsid's own updater
#      (App/UpdateInstall.swift) accepts the next release: it requires the
#      download to meet the running copy's designated requirement.
#   3. Ad-hoc ("-"), as anyone building from source gets. An ad-hoc copy's
#      designated requirement is its exact build (a cdhash), so it can't update
#      itself natively and macOS asks for its permissions again after each
#      update.
#
# No hardened runtime by default: there's no Developer ID or notarization to
# need it, and without entitlements it would block the microphone and Apple
# Events (browser control).
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP/Contents" ]]; then
    echo "usage: ${0:t} <Capsid.app>" >&2
    exit 2
fi
APP="${APP:A}"
ROOT="${0:A:h:h}"

if [[ -n "${CAPSID_SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$CAPSID_SIGN_IDENTITY"
else
    IDENTITY=$(security find-certificate -c "Solanum Code Signing" -Z 2>/dev/null | awk '/SHA-1/ {print $3; exit}' || true)
    IDENTITY="${IDENTITY:--}"
fi
# Extra codesign options, split on spaces (e.g. "--options runtime --timestamp").
OPTIONS=(${=CAPSID_SIGN_OPTIONS:-})
[[ "$IDENTITY" == "-" ]] && OPTIONS+=(--timestamp=none)

sign() {
    local target="$1" entitlements="$ROOT/Resources/${1:t:r}.entitlements"
    local args=(--force --sign "$IDENTITY" "${OPTIONS[@]}")
    [[ -f "$entitlements" ]] && args+=(--entitlements "$entitlements")
    codesign "${args[@]}" "$target" >/dev/null
}

# Nested code, deepest first: bundles (frameworks, helpers, XPC services,
# extensions, login items) and loose Mach-O files (dylibs, tools). Sorting by
# path depth, deepest first, signs whatever is inside a bundle before it.
MAIN="$APP/Contents/MacOS/$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
typeset -a nested
for item in "$APP"/Contents/**/*(.N) "$APP"/Contents/**/*.(framework|app|xpc|appex|bundle|systemextension)(/N); do
    [[ "$item" == "$MAIN" ]] && continue
    if [[ -d "$item" ]]; then
        nested+=("$item")
    elif [[ "$item" != */_CodeSignature/* && "$item" != */Contents/Resources/* ]] \
        && file -b "$item" | grep -q '^Mach-O'; then
        nested+=("$item")
    fi
done
# A bundle's own main executable is signed with the bundle, not on its own.
for item in ${(f)"$(for n in $nested; do print -r -- "${#${n//[^\/]/}} $n"; done | sort -rn | cut -d' ' -f2-)"}; do
    [[ -z "$item" ]] && continue
    if [[ -f "$item" && "$item" == */Contents/MacOS/* ]]; then
        holder="${item%/Contents/MacOS/*}"
        (( ${nested[(Ie)$holder]} )) && continue
    fi
    sign "$item"
done

sign "$APP"
if [[ "$IDENTITY" == "-" ]]; then
    echo "Signed $APP ad-hoc"
else
    echo "Signed $APP with $(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/ {print $2; exit}')"
fi
