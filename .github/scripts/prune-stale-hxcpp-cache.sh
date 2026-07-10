#!/bin/bash
# prune-stale-hxcpp-cache.sh - Deletes old Actions cache entries for a given
# key prefix, keeping only the single most recently created one as a
# same-run fallback.
#
# The hxcpp compile/build-artifact caches are keyed by a hash of the game's
# source tree, so *any* commit touching source produces a brand-new cache key
# that never matches an old one exactly -- restore-keys lets the job seed
# from the closest old entry, but actions/cache always saves a fresh full
# copy afterwards regardless, so the old entry is never replaced, only ever
# added to. Left unchecked this silently grows the repo's total Actions cache
# usage until GitHub starts evicting *other*, unrelated caches (which is what
# broke the hxpkg install step -- see commit 15913508).
#
# Runs right after the cache-restore step (before Compile), so it only ever
# deletes caches that are already generations old -- the one just restored
# this run is always the "most recent" and is deliberately kept, in case this
# run's own compile fails before a new cache gets saved.
#
# Best-effort: any failure here (missing permissions, rate limit, API hiccup)
# is logged and swallowed, never fails the build -- this is pure cache
# housekeeping, not something a compile should ever depend on.
#
# Usage: prune-stale-hxcpp-cache.sh <key-prefix> <ref>
# Requires: GH_TOKEN with actions:write, run from inside the checked-out repo,
# and GITHUB_REPOSITORY set (always true on an Actions runner).

set -uo pipefail

PREFIX="${1:?Usage: $0 <key-prefix> <ref>}"
REF="${2:?Usage: $0 <key-prefix> <ref>}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

echo "[prune-cache] Looking for caches matching prefix '$PREFIX' on ref '$REF' in $REPO"

# $REPO is spelled out literally in the path (not the {owner}/{repo}
# template) on purpose, and NOT via a -R flag -- gh api doesn't actually
# have one ("unknown shorthand flag: 'R' in -R", confirmed from a real
# run's log; -R is a global gh flag but apparently isn't wired into this
# subcommand's own parser). This repo also has a submodule
# (content/NMV-Base-Game, a DIFFERENT owner/repo) checked out alongside
# it, and gh api's automatic {owner}/{repo} template resolves from
# whatever git context it finds in the working tree -- with two .git
# trees present it was silently resolving to the wrong repo and 404ing on
# every run, which meant this script never pruned anything and stale
# caches just piled up until GitHub's own eviction kicked in. Spelling
# $REPO out directly sidesteps that detection entirely.
IDS=$(gh api "/repos/$REPO/actions/caches" \
    -f "key=$PREFIX" -f "ref=$REF" -f "per_page=100" \
    --jq '.actions_caches | sort_by(.created_at) | reverse | .[1:] | .[].id' 2>&1)
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
    echo "[prune-cache] Failed to list caches (non-fatal, skipping prune). Output was:"
    echo "$IDS"
    exit 0
fi

if [ -z "$IDS" ]; then
    echo "[prune-cache] Nothing to prune (0 or 1 matching caches)."
    exit 0
fi

COUNT=0
while IFS= read -r ID; do
    [ -z "$ID" ] && continue
    if gh api -X DELETE "/repos/$REPO/actions/caches/$ID" >/dev/null 2>&1; then
        echo "[prune-cache] Deleted stale cache id=$ID"
        COUNT=$((COUNT + 1))
    else
        echo "[prune-cache] Failed to delete cache id=$ID (continuing)"
    fi
done <<< "$IDS"

echo "[prune-cache] Done. Pruned $COUNT stale cache(s), kept the newest as fallback."
