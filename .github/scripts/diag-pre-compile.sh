#!/usr/bin/env bash
set -euo pipefail
echo "============================================"
echo "PRE-COMPILE DIAGNOSTIC"
echo "============================================"

echo ""
echo "--- GameActivity.java template ---"
GA=".haxelib/lime/git/templates/android/template/app/src/main/java/org/haxe/lime/GameActivity.java"
if [ -f "$GA" ]; then
    echo "EXISTS: $GA"
    echo "  Size: $(wc -c < "$GA") bytes"
    echo "  First 5 lines:"
    head -5 "$GA"
    echo ""
    echo "  All import lines:"
    grep "^import" "$GA" || echo "  (none)"
    echo ""
    echo "  Lines with 'mobile':"
    grep "mobile" "$GA" || echo "  (none)"
else
    echo "MISSING: $GA"
fi

echo ""
echo "--- Extension .java files (source/) ---"
find source/ -name "*.java" 2>/dev/null | sort || echo "  (none)"

echo ""
echo "--- Extension .java files (build dir) ---"
for d in export/*/android/bin/app/src/main/java/; do
    if [ -d "$d" ]; then
        echo "  $d"
        find "$d" -name "*.java" | sort
    fi
done 2>/dev/null || echo "  (none)"

echo ""
echo "--- Lime git HEAD ---"
git -C .haxelib/lime/git log --oneline -1 2>/dev/null || echo "  (not a git repo)"
echo "  haxelib:"
haxelib list lime 2>/dev/null | head -3 || echo "  (unavailable)"

echo ""
echo "--- Project.xml android config ---"
grep -n '<java\|<android extension\|<source path' Project.xml | head -20 || echo "  (none)"

echo ""
echo "--- Disk ---"
df -h . 2>/dev/null || true
du -sh .haxelib/lime/git/templates/ 2>/dev/null || true

echo ""
echo "============================================"
echo "END DIAGNOSTIC"
echo "============================================"
