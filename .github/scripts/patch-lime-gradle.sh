#!/bin/bash
# patch-lime-gradle.sh - Patches Lime's build.gradle to filter APKs by ABI
# Usage: ./patch-lime-gradle.sh <arch> (arm64, armv7, all)

set -euo pipefail

ARCH="${1:-}"
[ -z "$ARCH" ] && echo "Usage: $0 <arm64|armv7|all>" && exit 1

case "$ARCH" in
    arm64)  ABI_FILTER="arm64-v8a";;
    armv7)  ABI_FILTER="armeabi-v7a";;
    all|fat) echo "No filter for universal APK"; exit 0;;
    *)      echo "Unknown arch: $ARCH"; exit 1;;
esac

BUILD_GRADLE=".haxelib/lime/git/templates/android/template/app/build.gradle"
[ ! -f "$BUILD_GRADLE" ] && echo "Lime template not found" && exit 1

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

echo "[INFO] Done! ABI filter: $ABI_FILTER"
