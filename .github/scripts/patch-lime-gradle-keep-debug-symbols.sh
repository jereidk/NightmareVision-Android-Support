#!/bin/bash
# patch-lime-gradle-keep-debug-symbols.sh - Stops Gradle from stripping our
# own compiled library specifically, so it ships inside the APK with full
# debug info intact (assuming it was compiled with -g -- see
# -D HXCPP_DEBUG_LINK_AND_STRIP in the Compile step) instead of needing a
# separate native-debug-symbols.zip mechanism.
#
# Why this instead of relying on debugSymbolLevel alone
# (patch-lime-gradle-native-symbols.sh): debugSymbolLevel's own
# native-debug-symbols.zip came back containing only libc++_shared.so.dbg
# across two separate builds, never our own library -- inconclusive on
# whether that's because -g wasn't actually landing, or because that
# mechanism just doesn't reach a prebuilt .so Lime/HXCPP hands to Gradle
# already-built (as opposed to one Gradle compiles itself via CMake/ndk-build,
# which the mechanism is documented around). packagingOptions.jniLibs.
# keepDebugSymbols acts at Gradle's packaging step instead, which processes
# every native library uniformly regardless of where it came from -- same
# official Gradle API (see JniLibsPackaging in the Android Gradle Plugin DSL
# reference), just a different, more direct lever: keep this ONE library
# unstripped in the shipped output rather than exporting a stripped-vs-
# unstripped pair on the side.
#
# Only wired into the debug-symbols job -- a normal release build should
# stay small, this only makes sense for the one job that intentionally
# compiles with -g to chase down a crash.
set -euo pipefail

BUILD_GRADLE=".haxelib/lime/git/templates/android/template/app/build.gradle"
[ ! -f "$BUILD_GRADLE" ] && echo "Lime template not found" && exit 1

# Anchor on the exact, unique line immediately after the closing brace of
# the `android { ... }` block's buildTypes section (verified against the
# pinned Lime commit's source) -- if this ever stops matching (Lime
# template changed upstream), fail loudly instead of silently doing
# nothing or guessing at a different insertion point.
MARKER="android.applicationVariants.all { variant ->"
if ! grep -qF "$MARKER" "$BUILD_GRADLE"; then
	echo "ERROR: expected applicationVariants marker line not found in $BUILD_GRADLE -- Lime's template may have changed, refusing to patch blindly"
	exit 1
fi

python3 - "$BUILD_GRADLE" << 'PYTHON_EOF'
import sys
build_gradle = sys.argv[1]
with open(build_gradle) as f:
    c = f.read()

marker = "\tandroid.applicationVariants.all { variant ->"
count = c.count(marker)
if count != 1:
    print(f"ERROR: expected exactly 1 occurrence of the applicationVariants marker, found {count}")
    sys.exit(1)

packaging_block = (
    "\tpackagingOptions {\n"
    "\t\tjniLibs {\n"
    "\t\t\tkeepDebugSymbols += [\"**/libImpostorLegacy.so\"]\n"
    "\t\t}\n"
    "\t}\n\n"
)
c = c.replace(marker, packaging_block + marker, 1)

with open(build_gradle, 'w') as f:
    f.write(c)
print("Added packagingOptions.jniLibs.keepDebugSymbols for libImpostorLegacy.so")
PYTHON_EOF
