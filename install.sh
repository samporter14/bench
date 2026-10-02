#!/bin/zsh
# install.sh — installs Bench in /Applications from the latest GitHub release,
# or updates it: run it again for a new version.
#
#   curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh | zsh
#
# macOS only flags apps downloaded through a web browser, so Bench installed
# this way opens without the "can't verify" prompt. You're trusting this
# script and the release it downloads, so read it first if you like: it's
# short.
#
# BENCH_INSTALL_DIR installs somewhere else instead, without opening it (for
# testing this script).
set -euo pipefail

DIR="${BENCH_INSTALL_DIR:-/Applications}"
APP="$DIR/Bench.app"
URL="https://github.com/samporter14/bench/releases/latest/download/Bench.zip"

if [[ "$(uname -m)" != arm64 ]]; then
    echo "Bench needs a Mac with Apple silicon (M1 or later)." >&2
    exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 27 )); then
    echo "Bench needs macOS 27 or later." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading Bench…"
curl -fsSL "$URL" -o "$TMP/Bench.zip"
ditto -x -k "$TMP/Bench.zip" "$TMP"
if [[ ! -d "$TMP/Bench.app" ]]; then
    echo "The download didn't contain Bench.app. Try again later." >&2
    exit 1
fi

# Only the copy being replaced is quit: processes whose executable is
# exactly this copy's, compared as text. (pgrep -f would read the path as a
# pattern over whole command lines, so another copy could match.) Bench
# takes the signal as ⌘Q.
EXE="$APP/Contents/MacOS/Bench"
target_pids() {
    ps -axo pid=,comm= | awk -v exe="$EXE" '{ pid = $1; sub(/^ *[0-9]+ /, ""); if ($0 == exe) print pid }'
}
if [[ -n "$(target_pids)" ]]; then
    echo "Quitting the running Bench…"
    kill -TERM $(target_pids) 2>/dev/null || true
    for _ in {1..20}; do
        [[ -z "$(target_pids)" ]] && break
        sleep 0.5
    done
    if [[ -n "$(target_pids)" ]]; then
        echo "Bench is still running. Quit it with ⌘Q, then run this again." >&2
        exit 1
    fi
fi

rm -rf "$APP"
mv "$TMP/Bench.app" "$APP"
echo "Installed Bench $(defaults read "$APP/Contents/Info" CFBundleShortVersionString) in $DIR."
if [[ -z "${BENCH_INSTALL_DIR:-}" ]]; then
    open "$APP"
fi
