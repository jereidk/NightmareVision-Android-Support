#!/bin/bash
# patch-lime-gradle-native-symbols.sh - Makes the release build emit a
# native-debug-symbols.zip (Play Console's own official mechanism, see
# https://developer.android.com/build/include-native-symbols) alongside the
# normal APK, so a future native_crash_trace.log's rel_pc offsets can be
# resolved to real function/file/line via addr2line/ndk-stack.
#
# Does NOT change what ships: AGP always strips the packaged .so in the APK
# regardless of this setting. debugSymbolLevel=FULL only makes it ALSO write
# an unstripped copy (full DWARF debug info + symbol table) to
# app/build/outputs/native-debug-symbols/release/native-debug-symbols.zip,
# which a later "Upload Artifact"-style step picks up separately.
set -euo pipefail

BUILD_GRADLE=".haxelib/lime/git/templates/android/template/app/build.gradle"
[ ! -f "$BUILD_GRADLE" ] && echo "Lime template not found" && exit 1

# Anchor on the exact, unique line Lime's own template ships in the release
# buildType (verified against the pinned Lime commit's source) -- if this
# ever stops matching (Lime template changed upstream), fail loudly instead
# of silently doing nothing or guessing at a different insertion point.
MARKER="proguardFiles getDefaultProguardFile('proguard-android-optimize.txt')"
if ! grep -qF "$MARKER" "$BUILD_GRADLE"; then
	echo "ERROR: expected release buildType marker line not found in $BUILD_GRADLE -- Lime's template may have changed, refusing to patch blindly"
	exit 1
fi

python3 - "$BUILD_GRADLE" << 'PYTHON_EOF'
import sys
build_gradle = sys.argv[1]
with open(build_gradle) as f:
    c = f.read()

marker = "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt')"
count = c.count(marker)
if count != 1:
    print(f"ERROR: expected exactly 1 occurrence of the release buildType marker, found {count}")
    sys.exit(1)

ndk_block = marker + "\n\t\t\tndk {\n\t\t\t\tdebugSymbolLevel = \"FULL\"\n\t\t\t}"
c = c.replace(marker, ndk_block, 1)

with open(build_gradle, 'w') as f:
    f.write(c)
print("Added ndk.debugSymbolLevel=FULL to the release buildType")
PYTHON_EOF
