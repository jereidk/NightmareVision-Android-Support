#!/bin/bash
# extract-dwarf-symbols.sh <unstripped .so> <output .sym file>
#
# Runs Mozilla's dump_syms (https://github.com/mozilla/dump_syms) against an
# unstripped libApplicationMain*.so (built with -D HXCPP_DEBUG_LINK -- see
# the arm64-debugsymbols job's own doc comment for why that flag, not
# Gradle's debugSymbolLevel, is the only reliable source of our own
# library's debug info) to produce a Breakpad-format symbol file:
# https://chromium.googlesource.com/breakpad/breakpad/+/master/docs/symbol_files.md
#
# FUNC records carry a real address+size, so on-device resolution against
# this file is exact-range matching, not the nearest-preceding-symbol
# approximation the previous nm-based extract-symbol-table.sh (now removed)
# had to fall back to -- and the following bare line records give real
# file:line, which nm's flat symbol table never could.
#
# Deliberately NOT passing --inlines: measured in CI (the MeasureSymSize
# job) at ~7.3MB gzip-compressed per ABI without it vs ~22.3MB with it
# (789k INLINE records, since hxcpp-generated C++ inlines very
# aggressively) -- the extra inlining-chain precision wasn't needed to
# find either native crash this project's own function-name-only resolver
# already solved, so it isn't worth roughly tripling the embedded asset
# size for.
#
# Downloads a pinned dump_syms release into a shared cache dir so calling
# this twice in the same job (once per ABI, see the fat Android job) only
# downloads it once.
set -euo pipefail

SO_PATH="$1"
OUT_PATH="$2"

if [ ! -f "$SO_PATH" ]; then
	echo "ERROR: $SO_PATH not found"
	exit 1
fi

DUMP_SYMS_VERSION="v2.3.7"
CACHE_DIR="${RUNNER_TEMP:-/tmp}/dump_syms_cache"
DUMP_SYMS_BIN="$CACHE_DIR/dump_syms"

if [ ! -x "$DUMP_SYMS_BIN" ]; then
	mkdir -p "$CACHE_DIR"
	curl -sSL -o "$CACHE_DIR/dump_syms.tar.xz" \
		"https://github.com/mozilla/dump_syms/releases/download/${DUMP_SYMS_VERSION}/dump_syms-x86_64-unknown-linux-gnu.tar.xz"
	tar -xJf "$CACHE_DIR/dump_syms.tar.xz" -C "$CACHE_DIR"

	FOUND_BIN=$(find "$CACHE_DIR" -maxdepth 3 -type f -iname "dump_syms")
	if [ -z "$FOUND_BIN" ]; then
		echo "ERROR: dump_syms binary not found inside the downloaded release archive"
		exit 1
	fi
	cp "$FOUND_BIN" "$DUMP_SYMS_BIN"
	chmod +x "$DUMP_SYMS_BIN"
fi

mkdir -p "$(dirname "$OUT_PATH")"
"$DUMP_SYMS_BIN" -o "$OUT_PATH" "$SO_PATH"

COUNT=$(grep -c '^FUNC ' "$OUT_PATH" || true)
echo "Wrote $COUNT FUNC records ($(wc -l < "$OUT_PATH") lines total) to $OUT_PATH"
if [ "$COUNT" -eq 0 ]; then
	echo "ERROR: zero FUNC records extracted -- $SO_PATH may not actually have debug info (HXCPP_DEBUG_LINK not applied?)"
	exit 1
fi
