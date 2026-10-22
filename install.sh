#!/bin/zsh
# install.sh — installs Capsid in /Applications from the latest GitHub release,
# or updates it: run it again for a new version.
#
#   curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh | zsh
#
# macOS only flags apps downloaded through a web browser, so Capsid installed
# this way opens without the "can't verify" prompt. You're trusting this
# script and the release it downloads, so read it first if you like: it's
# short.
#
# It asks GitHub which release is latest and downloads that tagged release, so
# the version it names is the one it installs. The download's signature is
# checked before anything is quit. The copy you have is moved aside, never
# deleted: it's removed only once the new one is running, and it's put back if
# the new one doesn't open.
#
# Capsid was called Bench until 0.6.0. The repository, the release's file
# (Bench.zip) and this script's address keep that name: an installed Bench
# finds its update there and runs this script to install it. A Bench already
# in Applications is quit and removed, because it has the same bundle id and
# the two must never sit side by side.
#
# BENCH_INSTALL_DIR installs somewhere else instead, without opening it (for
# testing this script). It keeps its name because Bench's updater clears it.
set -euo pipefail

DIR="${BENCH_INSTALL_DIR:-/Applications}"
RELEASES="https://github.com/samporter14/bench/releases"
API="https://api.github.com/repos/samporter14/bench/releases/latest"

if [[ "$(uname -m)" != arm64 ]]; then
    echo "Capsid needs a Mac with Apple silicon (M1 or later)." >&2
    exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 27 )); then
    echo "Capsid needs macOS 27 or later." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Ask GitHub for the latest release's tag, so the file comes from one named
# release. GitHub allows 60 unauthenticated API calls an hour per address, so
# this can fail; the latest-release link is the fallback. The tag is used only
# if it looks like a version, so nothing from the network can steer the address.
TAG=""
TAG_RE='^v?[0-9]{1,6}(\.[0-9]{1,6}){0,3}$'
if JSON="$(curl -fsSL --max-time 20 -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null)"; then
    TAG="$(printf '%s\n' "$JSON" \
        | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 \
        | sed 's/^"tag_name"[[:space:]]*:[[:space:]]*"\(.*\)"$/\1/' || true)"
fi
if [[ "$TAG" =~ $TAG_RE ]]; then
    echo "Downloading Capsid ${TAG#v}…"
    URL="$RELEASES/download/$TAG/Bench.zip"
else
    echo "Couldn't ask GitHub which release is latest; downloading the latest one directly."
    URL="$RELEASES/latest/download/Bench.zip"
fi
curl -fsSL "$URL" -o "$TMP/Bench.zip"
ditto -x -k "$TMP/Bench.zip" "$TMP"
# A release from 0.6.0 on holds Capsid.app. One from before (the latest until
# 0.6.0 is published) holds Bench.app, which is installed under its own name.
if [[ -d "$TMP/Capsid.app" ]]; then
    NAME=Capsid OTHER=Bench
elif [[ -d "$TMP/Bench.app" ]]; then
    NAME=Bench OTHER=Capsid
else
    echo "The download didn't contain Capsid.app. Try again later." >&2
    exit 1
fi
APP="$DIR/$NAME.app"
OLD="$DIR/$OTHER.app"
PREV="$APP.previous"

# Check the download before anything is quit or moved. curl doesn't set the
# quarantine flag, so one here means the file came another way.
if ! codesign --verify --deep --strict "$TMP/$NAME.app"; then
    echo "The download's signature didn't check out, so nothing was installed." >&2
    exit 1
fi
if xattr -p com.apple.quarantine "$TMP/$NAME.app" >/dev/null 2>&1; then
    echo "The download was quarantined, so nothing was installed. Download it again with this script rather than a browser." >&2
    exit 1
fi

# Only the copies being replaced are quit: processes whose executable is
# exactly Capsid's or Bench's in $DIR, compared as text. (pgrep -f would read
# the path as a pattern over whole command lines, so another copy could
# match.) Both take the signal as ⌘Q.
CAPSID_EXE="$DIR/Capsid.app/Contents/MacOS/Capsid"
BENCH_EXE="$DIR/Bench.app/Contents/MacOS/Bench"
target_pids() {
    ps -axo pid=,comm= | awk -v a="$CAPSID_EXE" -v b="$BENCH_EXE" \
        '{ pid = $1; sub(/^ *[0-9]+ /, ""); if ($0 == a || $0 == b) print pid }'
}
if [[ -n "$(target_pids)" ]]; then
    echo "Quitting the running copy…"
    kill -TERM $(target_pids) 2>/dev/null || true
    for _ in {1..20}; do
        [[ -z "$(target_pids)" ]] && break
        sleep 0.5
    done
    if [[ -n "$(target_pids)" ]]; then
        echo "Capsid (called Bench before 0.6.0) is still running. Quit it with ⌘Q, then run this again." >&2
        exit 1
    fi
fi

# Swap the new copy in. The copy you have is moved to $PREV, not deleted, so
# any failure from here on can put it back.
ERR=""
if [[ -e "$PREV" || -L "$PREV" ]]; then
    if ! ERR="$(mv "$PREV" "$TMP/leftover.app" 2>&1)"; then
        echo "Couldn't clear the leftover $PREV: $ERR. Nothing was changed." >&2
        exit 1
    fi
fi
if [[ -e "$APP" || -L "$APP" ]]; then
    if ! ERR="$(mv "$APP" "$PREV" 2>&1)"; then
        echo "Couldn't move the copy you have aside: $ERR. Nothing was changed." >&2
        exit 1
    fi
fi
if ! ERR="$(mv "$TMP/$NAME.app" "$APP" 2>&1)"; then
    if [[ -e "$APP" || -L "$APP" ]]; then
        mv "$APP" "$TMP/partial.app" 2>/dev/null || true
    fi
    if [[ ! -d "$PREV" ]]; then
        echo "Couldn't put the new copy in Applications: $ERR." >&2
    elif [[ ! -e "$APP" && ! -L "$APP" ]] && mv "$PREV" "$APP"; then
        echo "Couldn't put the new copy in Applications: $ERR. The copy you had is back where it was." >&2
    else
        echo "Couldn't put the new copy in Applications: $ERR. The copy you had is at $PREV." >&2
    fi
    exit 1
fi

# Whether a process is running exactly this copy's executable (see target_pids).
app_running() {
    ps -axo pid=,comm= | awk -v e="$APP/Contents/MacOS/$NAME" \
        '{ sub(/^ *[0-9]+ /, ""); if ($0 == e) found = 1 } END { exit !found }'
}
if [[ -z "${BENCH_INSTALL_DIR:-}" ]]; then
    open "$APP" || true
    RAN=0
    for _ in {1..120}; do
        if app_running; then
            # A copy that dies on launch can be seen for an instant. Look again.
            sleep 2
            if app_running; then RAN=1; fi
            break
        fi
        sleep 0.25
    done
    if (( ! RAN )); then
        # Quit whatever half started, so two copies never run at once.
        if [[ -n "$(target_pids)" ]]; then
            kill -TERM $(target_pids) 2>/dev/null || true
            sleep 2
        fi
        HAD=""
        if [[ -d "$PREV" ]]; then HAD="$PREV"; elif [[ -d "$OLD" ]]; then HAD="$OLD"; fi
        if [[ -z "$HAD" ]]; then
            echo "The new copy didn't open, and there was no earlier copy to put back. It's in $DIR if you want to try it." >&2
        elif ! mv "$APP" "$TMP/broken.app"; then
            echo "The new copy didn't open, and couldn't be moved out of the way. The copy you had is at $HAD." >&2
        else
            if [[ "$HAD" == "$PREV" ]]; then
                if mv "$PREV" "$APP"; then HAD="$APP"; fi
            fi
            open "$HAD" || true
            echo "The new copy didn't open, so the one you had is back." >&2
        fi
        exit 1
    fi
fi
# The new copy is in place, and running unless this is a test install. Only now
# does the copy it replaced go, and the one under the other name with it.
rm -rf "$PREV" "$OLD"
echo "Installed $NAME $(defaults read "$APP/Contents/Info" CFBundleShortVersionString) in $DIR."
