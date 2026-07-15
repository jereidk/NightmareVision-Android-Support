#!/bin/bash
# =============================================================================
# Build Android APK, working around Lime bug where extension .java files
# are not placed in the Gradle source set.
#
# Phase 1: Run "lime build android" (HAXE + C++ compile + Gradle).
#           The Gradle step will fail; that's expected.
# Phase 2: Copy our extension .java files into the generated Gradle tree.
# Phase 3: Add import statements to GameActivity.java.
# Phase 4: Run Gradle directly to finish.
# =============================================================================
set -euo pipefail

BUILD_MODE="${1:-release}"
BUILD_FLAGS="${2:-}"

MODE_FLAG=""
MODE_DIR="release"
if [ "$BUILD_MODE" = "debug" ]; then
    MODE_FLAG="-debug"
    MODE_DIR="debug"
fi

BUILD_DIR="export/$MODE_DIR/android"
GRADLE_DIR="$BUILD_DIR/bin"
JAVA_TARGET="$GRADLE_DIR/app/src/main/java/mobile/backend/java"
GA_TARGET="$GRADLE_DIR/app/src/main/java/org/haxe/lime/GameActivity.java"

echo "=== Phase 1: Run Lime build (Java part expected to fail) ==="
set +e
# Convert space-separated flags to -D flag1 -D flag2 ...
D_FLAGS=""
if [ -n "$BUILD_FLAGS" ]; then
    for flag in $BUILD_FLAGS; do
        D_FLAGS="$D_FLAGS -D $flag"
    done
fi
haxelib run lime build android $MODE_FLAG $D_FLAGS
LIME_RC=$?
set -e

if [ $LIME_RC -eq 0 ]; then
    echo "Lime build succeeded on first try!"
    exit 0
fi

echo "Lime exited with code $LIME_RC (expected)."

echo ""
echo "=== Phase 2: Copy Java extension classes ==="
SRC="source/mobile/backend/java"
if [ ! -d "$SRC" ]; then
    echo "ERROR: $SRC not found"
    exit 1
fi

mkdir -p "$JAVA_TARGET"
for f in AndroidUtils FileUtils JavaCrashHandler ScreenUtil KizzyHelper ModFolderDocumentsProvider; do
    if [ -f "$SRC/$f.java" ]; then
        cp "$SRC/$f.java" "$JAVA_TARGET/$f.java"
        echo "  Copied $f.java"
    fi
done

echo ""
echo "=== Phase 3: Patch GameActivity.java ==="
if [ -f "$GA_TARGET" ]; then
    if ! grep -q "import mobile.backend.java" "$GA_TARGET"; then
        IMPORTS="import mobile.backend.java.FileUtils;
import mobile.backend.java.AndroidUtils;
import mobile.backend.java.JavaCrashHandler;
import mobile.backend.java.ScreenUtil;
import mobile.backend.java.KizzyHelper;"
        sed -i "/^import java.util.List;$/a\\
\\
$IMPORTS" "$GA_TARGET"
        echo "  Added extension imports to GameActivity.java"
    else
        echo "  GameActivity.java already has imports"
    fi
else
    echo "  WARNING: $GA_TARGET not found"
fi

echo ""
echo "=== Phase 4: Run Gradle assembleRelease ==="
cd "$GRADLE_DIR"
chmod +x gradlew 2>/dev/null || true
./gradlew assembleRelease
