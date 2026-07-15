#!/bin/bash
# Patch Lime's GameActivity.java template with import statements for
# our custom extension classes.
#
# This MUST run AFTER any step that might re-clone .haxelib/lime
# (Rebuild Linux Lime ndll, Rebuild Android Lime so) and BEFORE the
# Compile step (haxelib run lime build android).
#
# When this script is called, the Lime template should already exist
# at .haxelib/lime/git/templates/android/template/app/src/main/java/
# org/haxe/lime/GameActivity.java

set -euo pipefail

TEMPLATES=(
    ".haxelib/lime/git/templates/android/template/app/src/main/java/org/haxe/lime/GameActivity.java"
)

FOUND=0
for tmpl in "${TEMPLATES[@]}"; do
    if [ -f "$tmpl" ]; then
        FOUND=1
        if grep -q "import mobile.backend.java" "$tmpl"; then
            echo "[INFO] $tmpl already has extension imports."
        else
            echo "[INFO] Adding extension imports to $tmpl..."
            IMPORTS="import mobile.backend.java.FileUtils;
import mobile.backend.java.AndroidUtils;
import mobile.backend.java.JavaCrashHandler;
import mobile.backend.java.ScreenUtil;
import mobile.backend.java.KizzyHelper;"
            sed -i "/^import java.util.List;$/a\\
\\
$IMPORTS" "$tmpl"
            echo "[INFO] Patched."
        fi
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "[WARN] GameActivity.java template not found in any expected location."
    echo "[WARN] Searched: ${TEMPLATES[*]}"
fi
