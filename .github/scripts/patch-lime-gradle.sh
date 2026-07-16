#!/bin/bash
# patch-lime-gradle.sh - Patches Lime's build.gradle to filter APKs by ABI
# Usage: ./patch-lime-gradle.sh <arch> (arm64, armv7, all)

set -euo pipefail

ARCH="${1:-}"
[ -z "$ARCH" ] && echo "Usage: $0 <arm64|armv7|all>" && exit 1

BUILD_GRADLE=".haxelib/lime/git/templates/android/template/app/build.gradle"
[ ! -f "$BUILD_GRADLE" ] && echo "Lime template not found" && exit 1

# .haxelib/lime is now one cache shared across all three jobs (fat/arm64/
# arm32) -- this file gets mutated IN PLACE further down (sed/python write
# it back), so whichever job last patched-and-saved the cache leaves that
# same filter baked into what every other job restores afterwards. Reset
# to Lime's own committed version FIRST, before the arch case below (which
# for "fat"/"all" exits early applying no filter of its own) -- otherwise
# "fat" would silently keep whatever a prior arm64/armv7 run's patch left
# behind, which is exactly what happened: this reset used to run after
# that early exit, so it never actually executed for the fat job at all.
git -C .haxelib/lime/git checkout -- templates/android/template/app/build.gradle 2>/dev/null || true

case "$ARCH" in
    arm64)  ABI_FILTER="arm64-v8a";;
    armv7)  ABI_FILTER="armeabi-v7a";;
    all|fat) echo "No filter for universal APK (template reset to unfiltered)"; exit 0;;
    *)      echo "Unknown arch: $ARCH"; exit 1;;
esac

echo "[INFO] Found: $BUILD_GRADLE"

# Remove old splits block (AGP 8.0 incompatible)
sed -i '/splits {/,/^[[:space:]]*}/d' "$BUILD_GRADLE" 2>/dev/null || true

# Apply patch
python3 - "$BUILD_GRADLE" "$ABI_FILTER" << 'PYTHON_EOF'
import sys, re
build_gradle, abi = sys.argv[1], sys.argv[2]
with open(build_gradle) as f: c = f.read()
c = re.sub(r'\n\s*ndk\s*\{[^}]*\}', '', c)
c = re.sub(r'\n\s*ndkAbiFilters[^\n]+', '', c)
ndk = '\n            ndk { abiFilters "%s" }' % abi
m = re.search(r'(defaultConfig\s*\{[^}]*\})', c, re.DOTALL)
if m:
    dc = m.group(1).rstrip()
    if dc.endswith('}'): dc = dc[:-1] + ndk + '\n        }'
    c = c.replace(m.group(1), dc)
    print(f"Added ndk.abiFilters '{abi}' to defaultConfig")
with open(build_gradle, 'w') as f: f.write(c)
PYTHON_EOF

# ── Inject extension java source dir ──
# GameActivity.java imports mobile.backend.java.* classes that javac
# cannot find unless they are in Gradle's source set. Lime normally
# copies extension .java files into the build dir via recursiveCopy
# during update(), but that try/catch swallows errors silently on
# some runners. Adding srcDir makes Gradle find them directly.
echo "[INFO] Adding extension java sourceSets..."
python3 - "$BUILD_GRADLE" << 'EXTEOF'
import sys
bg = sys.argv[1]
with open(bg) as f:
    c = f.read()
# Template line ends defaultConfig block with a tab-indented
# closing brace, blank line, then the ::if KEY_STORE:: guard.
# Inject sourceSets right between them.
needle = '\t}\n\n\t::if KEY_STORE::'
replacement = (
    '\t}\n\n'
    '\tsourceSets {\n'
    '\t\tmain {\n'
    '\t\t\tjava {\n'
    '\t\t\t\tsrcDir \'../../../../../../../source/mobile/backend/java\'\n'
    '\t\t\t}\n'
    '\t\t}\n'
    '\t}\n\n'
    '\t::if KEY_STORE::'
)
if needle in c:
    c = c.replace(needle, replacement)
    print('[INFO] Added extension java sourceSet')
else:
    print('[WARN] Could not find injection point')
with open(bg, 'w') as f:
    f.write(c)
EXTEOF

echo "[INFO] Done! ABI filter: $ABI_FILTER"
