#!/bin/zsh
# sync-shared.sh — refresh Sources/Bench/Shared and the icon from a checkout
# of the Science Status droplet, which is where the scenes and ScienceCore
# are written. Bench keeps copies so it builds on its own.
#
# Usage: Scripts/sync-shared.sh [path/to/droplets/science-status]
# (default: ../droplets/science-status, next to this repo)
set -euo pipefail
ROOT="${0:A:h:h}"
DROPLET="${1:-$ROOT/../droplets/science-status}"
SRC="$DROPLET/Sources/ScienceStatus"
[[ -d "$SRC" ]] || { echo "No droplet sources at $SRC" >&2; exit 1; }

SHARED="$ROOT/Sources/Bench/Shared"
# Bench's own versions, not overwritten: they find the database through the
# daemon's reported data folder and the live org (Bench 0.1.2), which the
# droplet doesn't yet.
KEEP=(Core/CLIStatus.swift Core/SQLiteSource.swift)
count=0
# Every file Bench already shares, from its place in the droplet.
for file in "$SHARED"/*.swift; do
    cp "$SRC/${file:t}" "$file"; count=$((count + 1))
done
for file in "$SHARED"/Core/*.swift; do
    if (( ${KEEP[(Ie)Core/${file:t}]} )); then echo "kept Bench's own Core/${file:t}"; continue; fi
    cp "$SRC/ScienceCore/${file:t}" "$file"; count=$((count + 1))
done
# Files the droplet has that Bench doesn't share, listed but not copied:
# some are the droplet's own (its Droppy entry point, the menu bar item), so
# a new scene file is added by hand, once it builds here.
for file in "$SRC"/*.swift; do
    [[ -e "$SHARED/${file:t}" ]] || echo "not shared: ${file:t}"
done
rm -rf "$ROOT/Resources/AppIcon.icon"
cp -R "$DROPLET/ScienceStatus.icon" "$ROOT/Resources/AppIcon.icon"
echo "Synced $count files and the icon from $DROPLET"
