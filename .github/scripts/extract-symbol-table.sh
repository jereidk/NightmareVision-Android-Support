#!/bin/bash
# extract-symbol-table.sh <unstripped .so> <output text file>
#
# Extracts a compact "address -> demangled function name" table from an
# unstripped libApplicationMain*.so (built with -D HXCPP_DEBUG_LINK, see the
# arm64-debugsymbols job's own doc comment for why that flag -- not Gradle's
# debugSymbolLevel -- is the only reliable source of our own library's debug
# info). Bundled into the APK as a plain asset so the app itself can resolve
# a native_crash_trace.log's rel_pc offsets to function names on next launch,
# without needing the full ~500MB unstripped .so or a separate CI symbolicate
# step.
#
# Format: one line per defined function (text/code) symbol, sorted ascending
# by address, "<16-hex-digit address> <demangled name>". No size field --
# resolution at runtime is nearest-preceding-symbol (binary search for the
# largest address <= the target rel_pc), the same approximation addr2line
# itself falls back to between exact symbol boundaries.
#
# Demangling is done as a separate pass AFTER address/type extraction (nm's
# own -C demangles inline, but a demangled C++ name routinely contains
# spaces -- e.g. "hx::ObjectPtr<Foo>::ObjectPtr(hx::ObjectPtr<Foo> const&)"
# -- which would corrupt naive whitespace-based field splitting on nm's
# posix output. Mangled names (the raw _Z... form) never contain spaces, so
# splitting happens on those first and only the trailing "name" column is
# ever allowed to contain spaces.
set -euo pipefail

SO_PATH="$1"
OUT_PATH="$2"

if [ ! -f "$SO_PATH" ]; then
	echo "ERROR: $SO_PATH not found"
	exit 1
fi

NM_BIN="nm"
CXXFILT_BIN="c++filt"
if [ -n "${ANDROID_NDK_LATEST_HOME:-}" ]; then
	NM_CANDIDATE="$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
	[ -f "$NM_CANDIDATE" ] && NM_BIN="$NM_CANDIDATE"
	CXXFILT_CANDIDATE="$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-cxxfilt"
	[ -f "$CXXFILT_CANDIDATE" ] && CXXFILT_BIN="$CXXFILT_CANDIDATE"
fi

mkdir -p "$(dirname "$OUT_PATH")"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# posix format: "name type address size" (address/size in hex, no 0x prefix,
# variable width). Type 'T'/'t' = defined symbol in the text (code) section.
# Mangled names have no spaces, so plain awk field splitting is safe here.
# Re-pad the address to 16 hex digits ourselves (don't rely on nm's own
# output width) so a later plain lexicographic sort is also a correct
# numeric sort.
"$NM_BIN" --defined-only -f posix "$SO_PATH" \
	| awk '($2 == "T" || $2 == "t") { addr = $3; while (length(addr) < 16) addr = "0" addr; print addr, $1 }' \
	| sort -k1,1 \
	> "$WORKDIR/addr_mangled.txt"

# Demangle just the name column, one call for the whole batch (preserves
# line order 1:1) instead of shelling out per symbol.
awk '{print $2}' "$WORKDIR/addr_mangled.txt" | "$CXXFILT_BIN" > "$WORKDIR/demangled_names.txt"
awk '{print $1}' "$WORKDIR/addr_mangled.txt" > "$WORKDIR/addrs.txt"

paste -d' ' "$WORKDIR/addrs.txt" "$WORKDIR/demangled_names.txt" > "$OUT_PATH"

COUNT=$(wc -l < "$OUT_PATH")
echo "Wrote $COUNT function symbols to $OUT_PATH"
if [ "$COUNT" -eq 0 ]; then
	echo "ERROR: zero symbols extracted -- $SO_PATH may not actually have debug info (HXCPP_DEBUG_LINK not applied?)"
	exit 1
fi
