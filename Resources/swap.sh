#!/bin/zsh
# swap.sh — the last step of a Capsid update (App/UpdateInstall.swift,
# DESIGN.md "Update check → Installing natively"). Capsid has downloaded the
# new release and checked its signature and version. This script waits for
# that Capsid to quit, moves the installed copy aside, moves the new one into
# place and opens it. If the new copy doesn't start, the old one is put back
# and opened. The installed app is never deleted here: the old copy sits at
# <installed app>.previous until this script has written `installed` and
# the new Capsid, seeing that marker, removes it.
#
#   zsh swap.sh <pid> <installed app> <new app> <state dir>
#
# Capsid copies this script into the state dir and runs it from there, so the
# bundle it came from can be moved while it runs. The script keeps swap.log in
# the state dir and ends by writing one marker file there, `marker`:
# "installed <version>" or "failed: <reason>". The new Capsid reads it at its
# launch; a restored old Capsid shows the reason.
#
# Test hooks, which Capsid scrubs from the environment before running this:
#   CAPSID_SWAP_WAIT          seconds to wait for the old copy to quit, and for
#                             the new one to start (default 30 each)
#   CAPSID_SWAP_LAUNCH        an executable run with the app's path, instead
#                             of `open`
#   CAPSID_SWAP_RUNNING_FILE  "the new copy is running" means this file exists
set -u

if (( $# != 4 )); then
    print -u2 -r -- "usage: swap.sh <pid> <installed app> <new app> <state dir>"
    exit 2
fi
PID=$1
APP=$2
NEW=$3
STATE=$4
PREV="$APP.previous"
WAIT=${CAPSID_SWAP_WAIT:-30}

mkdir -p "$STATE"
log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$STATE/swap.log"; }
mark() { print -r -- "$1" > "$STATE/marker.tmp" && mv -f "$STATE/marker.tmp" "$STATE/marker"; }
fail() {
    log "failed: $1"
    mark "failed: $1"
    exit 1
}
launch() {
    if [[ -n "${CAPSID_SWAP_LAUNCH:-}" ]]; then
        "$CAPSID_SWAP_LAUNCH" "$1"
    else
        /usr/bin/open "$1"
    fi
}
# The new copy is running: a process whose executable is exactly the
# installed app's, compared as text (pgrep -f would read the path as a
# pattern over whole command lines).
running() {
    if [[ -n "${CAPSID_SWAP_RUNNING_FILE:-}" ]]; then
        [[ -e "$CAPSID_SWAP_RUNNING_FILE" ]]
        return
    fi
    local exe="$APP/Contents/MacOS/Capsid"
    [[ -n "$(ps -axo pid=,comm= | awk -v a="$exe" '{ sub(/^ *[0-9]+ /, ""); if ($0 == a) print "y" }')" ]]
}
version_of() { /usr/bin/defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null || print unknown; }

log "swap: pid $PID, $APP ← $NEW"
[[ -d "$NEW" ]] || fail "there is no new copy at $NEW"
[[ -d "$APP" ]] || fail "there is nothing to replace at $APP"

# 1. The old copy quits by itself (Capsid called terminate before starting
#    this); give it its time, and touch nothing while it runs.
for (( i = 0; i < WAIT * 4; i++ )); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.25
done
if kill -0 "$PID" 2>/dev/null; then
    fail "the running copy didn't quit"
fi

# 2. A leftover from an earlier update whose clean-up never ran goes into the
#    state dir, not the bin: it was a working Capsid once.
if [[ -e "$PREV" ]]; then
    mv "$PREV" "$STATE/stale-previous-$(date +%s).app" || fail "an earlier copy is in the way at $PREV"
    log "moved a stale $PREV into the state dir"
fi

# 3. The swap. The old copy is moved aside first, so there is always one
#    whole copy on disk; a move that fails puts it back.
if ! err=$(mv "$APP" "$PREV" 2>&1); then
    fail "couldn't move the old copy aside: $err"
fi
if ! err=$(mv "$NEW" "$APP" 2>&1); then
    # A partial copy can be at $APP only if the move crossed volumes; the old
    # copy is whole at $PREV.
    [[ -e "$APP" ]] && mv "$APP" "$STATE/partial-$(date +%s).app"
    mv "$PREV" "$APP" || fail "couldn't put the new copy in place ($err), and the old one couldn't be put back"
    launch "$APP"
    fail "couldn't put the new copy in place: $err"
fi
log "moved $NEW into place; the old copy is at $PREV"

# 4. Open the new copy and make sure it runs. A copy that dies on launch
#    can be seen for an instant, so it is looked at again two seconds later.
launch "$APP" || log "the launch command ended with status $?"
for (( i = 0; i < WAIT * 4; i++ )); do
    running && break
    sleep 0.25
done
if running; then
    sleep 2
fi
if running; then
    v=$(version_of "$APP")
    log "installed $v"
    mark "installed $v"
    exit 0
fi

# 5. It didn't start: keep it for a look, put the old copy back and open that.
mv "$APP" "$STATE/broken-$(date +%s).app" || fail "the new copy didn't open, and it couldn't be moved away"
mv "$PREV" "$APP" || fail "the new copy didn't open, and the old one couldn't be put back"
launch "$APP"
fail "the new copy didn't open"
