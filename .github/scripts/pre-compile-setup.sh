#!/usr/bin/env bash
set -uo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║         PRE-COMPILE: Copy Extensions + Full Diagnostic          ║
# ╚══════════════════════════════════════════════════════════════════╝

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

section() { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; }

###############################################################################
# PHASE 1: COPY EXTENSION .JAVA FILES INTO GRADLE SOURCE SET
###############################################################################
section "PHASE 1: Copy Extension Java Files"

SRC="source/mobile/backend/java"
COPIED=false

if [ ! -d "$SRC" ]; then
    fail "Extension source dir not found: $SRC"
else
    ok "Source dir exists: $SRC"
    for BUILD_DIR in export/debug/android/bin export/release/android/bin; do
        if [ -d "$BUILD_DIR" ]; then
            DEST="$BUILD_DIR/app/src/main/java/mobile/backend/java"
            mkdir -p "$DEST"
            cp -v "$SRC"/*.java "$DEST/" 2>&1 | while read line; do
                echo "  cp: $line"
            done
            COPIED=true
            ok "Copied to $DEST"
            break
        fi
    done
    if [ "$COPIED" = false ]; then
        warn "No build dir found (export/debug or export/release)"
    fi
fi

###############################################################################
# PHASE 2: GAMEACTIVITY.JAVA TEMPLATE
###############################################################################
section "PHASE 2: GameActivity.java Template"

GA=".haxelib/lime/git/templates/android/template/app/src/main/java/org/haxe/lime/GameActivity.java"

if [ -f "$GA" ]; then
    ok "Template exists: $GA"
    echo "  Size: $(wc -c < "$GA") bytes"
    echo "  SHA256: $(sha256sum "$GA" | cut -d' ' -f1)"

    # Check if extension imports are present
    MISSING_IMPORTS=()
    for cls in FileUtils AndroidUtils JavaCrashHandler ScreenUtil KizzyHelper; do
        if grep -q "mobile.backend.java.$cls" "$GA"; then
            ok "Import found: mobile.backend.java.$cls"
        else
            fail "Import MISSING: mobile.backend.java.$cls"
            MISSING_IMPORTS+=("$cls")
        fi
    done

    # Show all actual imports
    echo ""
    echo "  Current imports in GameActivity.java:"
    grep "^import" "$GA" | while read line; do
        echo "    $line"
    done

    # Show extension init lines (the foreach ANDROID_EXTENSIONS)
    echo ""
    echo "  Extension init lines:"
    grep -n "ANDROID_EXTENSIONS\|mobile\\\.\\|new.*()" "$GA" 2>/dev/null | head -20 || echo "    (none)"
else
    fail "TEMPLATE MISSING: $GA"
    # Try to find it elsewhere
    echo "  Searching for GameActivity.java..."
    find . -name "GameActivity.java" -path "*/lime/*" 2>/dev/null | head -10
fi

###############################################################################
# PHASE 3: EXTENSION .JAVA FILES — SOURCE & BUILD
###############################################################################
section "PHASE 3: Extension .java Files"

echo "--- source/ ---"
if [ -d source/mobile/backend/java ]; then
    for f in source/mobile/backend/java/*.java; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        sz=$(wc -c < "$f")
        pkg=$(head -1 "$f")
        ok "$name ($sz bytes) — $pkg"
    done
else
    fail "source/mobile/backend/java/ not found"
fi

echo ""
echo "--- build dir ---"
FOUND_BUILD=false
for d in export/*/android/bin/app/src/main/java/mobile/backend/java/; do
    if [ -d "$d" ]; then
        FOUND_BUILD=true
        ok "Build dir: $d"
        for f in "$d"/*.java; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            sz=$(wc -c < "$f")
            ok "  $name ($sz bytes)"
        done
    fi
done
if [ "$FOUND_BUILD" = false ]; then
    warn "No extension .java files in build dir"
    echo "  Listing all build java dirs:"
    find export/ -path "*/app/src/main/java" -type d 2>/dev/null | while read d; do
        echo "    $d"
        ls -la "$d/" 2>/dev/null | head -15
        # Check for mobile subdirs
        find "$d" -name "*.java" 2>/dev/null | head -20
    done
fi

###############################################################################
# PHASE 4: LIME VERSION & STATE
###############################################################################
section "PHASE 4: Lime Version & State"

echo "--- haxelib ---"
haxelib list lime 2>/dev/null || echo "  haxelib unavailable"

echo ""
echo "--- git HEAD ---"
if [ -d .haxelib/lime/git/.git ]; then
    LIMEDIR=".haxelib/lime/git"
    ok "Git repo: $LIMEDIR"
    echo "  HEAD commit:"
    git -C "$LIMEDIR" log --oneline -1 2>/dev/null || echo "   (error)"
    echo "  Branch:"
    git -C "$LIMEDIR" branch --show-current 2>/dev/null || echo "   (detached)"
    echo "  Remote:"
    git -C "$LIMEDIR" remote -v 2>/dev/null | head -2
else
    warn "Lime is not a git checkout"
fi

echo ""
echo "--- Lime build artifacts ---"
if [ -d .haxelib/lime/git/ndll ]; then
    echo "  ndll/ contents:"
    find .haxelib/lime/git/ndll -type f 2>/dev/null | while read f; do
        sz=$(wc -c < "$f" 2>/dev/null || echo "?")
        echo "    $(basename "$f") ($sz bytes)"
    done
else
    warn "  No ndll/ in Lime"
fi

echo ""
echo "--- Lime template dir ---"
if [ -d .haxelib/lime/git/templates/android/template ]; then
    ok "Template dir exists"
    echo "  Size: $(du -sh .haxelib/lime/git/templates/ 2>/dev/null | cut -f1)"
    echo "  Java files in template:"
    find .haxelib/lime/git/templates/android/template -name "*.java" | while read f; do
        echo "    $f"
    done
fi

###############################################################################
# PHASE 5: PROJECT.XML CONFIG
###############################################################################
section "PHASE 5: Project.xml Android Config"

echo "--- <java> paths ---"
grep -n '<java ' Project.xml | while read line; do
    echo "  $line"
done

echo ""
echo "--- <android extension> ---"
grep -n '<android extension' Project.xml | while read line; do
    echo "  $line"
done

echo ""
echo "--- <source path> ---"
grep -n '<source path' Project.xml 2>/dev/null | head -10 | while read line; do || true
    echo "  $line"
done

echo ""
echo "--- <haxelib> ---"
grep -n '<haxelib' Project.xml 2>/dev/null | head -10 | while read line; do
    echo "  $line"
done

###############################################################################
# PHASE 6: ENVIRONMENT
###############################################################################
section "PHASE 6: Environment"

echo "--- Android SDK/NDK ---"
echo "  ANDROID_SDK:      ${ANDROID_SDK:-not set}"
echo "  ANDROID_NDK_ROOT: ${ANDROID_NDK_ROOT:-not set}"
echo "  JAVA_HOME:        ${JAVA_HOME:-not set}"

echo ""
echo "--- Haxe ---"
haxe --version 2>/dev/null || echo "  haxe unavailable"
haxelib version 2>/dev/null || echo "  haxelib unavailable"

echo ""
echo "--- Disk ---"
df -h . 2>/dev/null | head -3
echo ""
echo "  Workspace size:"
du -sh . 2>/dev/null || true
echo "  .haxelib size:"
du -sh .haxelib 2>/dev/null || true

###############################################################################
# PHASE 7: BUILD DIR STRUCTURE
###############################################################################
section "PHASE 7: Build Directory Structure"

for BUILD_DIR in export/debug export/release; do
    if [ -d "$BUILD_DIR" ]; then
        ok "Build dir: $BUILD_DIR"
        echo "  android/bin exists: $([ -d "$BUILD_DIR/android/bin" ] && echo YES || echo NO)"
        if [ -d "$BUILD_DIR/android/bin/app/src/main/java" ]; then
            echo "  java dir contents:"
            find "$BUILD_DIR/android/bin/app/src/main/java" -maxdepth 3 -type f -o -type d | sort | while read p; do
                if [ -d "$p" ]; then
                    echo "    $p/"
                else
                    echo "    $p"
                fi
            done
        fi
        echo ""
        echo "  build.gradle exists: $([ -f "$BUILD_DIR/android/bin/app/build.gradle" ] && echo YES || echo NO)"
        echo "  settings.gradle exists: $([ -f "$BUILD_DIR/android/bin/settings.gradle" ] && echo YES || echo NO)"
        echo "  gradle.properties exists: $([ -f "$BUILD_DIR/android/bin/gradle.properties" ] && echo YES || echo NO)"
    fi
done

echo ""
echo "--- Gradle JDK ---"
java -version 2>&1 || echo "  java unavailable"
javac -version 2>&1 || echo "  javac unavailable"

###############################################################################
# PHASE 8: GRADLE BUILD.GRADLE (ABI SPLITS)
###############################################################################
section "PHASE 8: Gradle build.gradle ABI Splits"

for BUILD_DIR in export/debug export/release; do
    BG="$BUILD_DIR/android/bin/app/build.gradle"
    if [ -f "$BG" ]; then
        ok "$BG exists"
        echo "  ndk { abiFilters lines:"
        grep -n "abiFilter\|ndk\|splits\|include.*arm" "$BG" | head -10 | while read line; do
            echo "    $line"
        done
    fi
done

###############################################################################
# SUMMARY
###############################################################################
section "SUMMARY"

ERRORS=0
# Check critical path
if [ -f "$GA" ]; then
    IMPORT_COUNT=$(grep -c "mobile.backend.java" "$GA" 2>/dev/null || echo 0)
    if [ "$IMPORT_COUNT" -ge 5 ]; then
        ok "GameActivity.java has all 5 extension imports"
    else
        fail "GameActivity.java has only $IMPORT_COUNT/5 extension imports"
        ERRORS=$((ERRORS + 1))
    fi
else
    fail "GameActivity.java template not found"
    ERRORS=$((ERRORS + 1))
fi

if [ "$COPIED" = true ]; then
    ok "Extension .java files copied to build dir"
else
    warn "Extension .java files NOT copied (no build dir yet)"
fi

if [ $ERRORS -gt 0 ]; then
    echo -e "\n${RED}⚠ $ERRORS critical issue(s) detected — compile will likely fail${NC}"
else
    echo -e "\n${GREEN}All checks passed${NC}"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "END PRE-COMPILE SETUP"
echo "════════════════════════════════════════════════════════════════"
