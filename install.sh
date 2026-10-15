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
URL="https://github.com/samporter14/bench/releases/latest/download/Bench.zip"

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
echo "Downloading Capsid…"
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

rm -rf "$APP"
mv "$TMP/$NAME.app" "$APP"
# The copy under the other name goes only once this one is in place.
rm -rf "$OLD"
echo "Installed $NAME $(defaults read "$APP/Contents/Info" CFBundleShortVersionString) in $DIR."
if [[ -z "${BENCH_INSTALL_DIR:-}" ]]; then
    open "$APP"
fi
