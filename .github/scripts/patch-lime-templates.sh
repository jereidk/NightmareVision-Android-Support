#!/usr/bin/env bash
set -euo pipefail
# Patches Lime's Android template files BEFORE lime build runs.
# This ensures:
#   1. GameActivity.java template has extension imports
#   2. build.gradle includes source/mobile/backend/java as a source dir
#
# These patches are applied to the TEMPLATE files that Lime reads during
# update(). When lime build calls update(), it copies these patched 
# templates into the build dir.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

GA_TEMPLATE=".haxelib/lime/git/templates/android/template/app/src/main/java/org/haxe/lime/GameActivity.java"
BG_TEMPLATE=".haxelib/lime/git/templates/android/template/app/build.gradle"

echo "[PATCH LIME TEMPLATES]"

# ── 1. Patch GameActivity.java template ──
if [ -f "$GA_TEMPLATE" ]; then
    cp "$GA_TEMPLATE" "${GA_TEMPLATE}.bak"
    
    # Check if already patched
    if grep -q "mobile.backend.java" "$GA_TEMPLATE"; then
        echo -e "  ${GREEN}✓${NC} GameActivity.java template already patched"
    else
        # Add imports after the last existing import
        # Find the line number of the last "import" statement
        LAST_IMPORT_LINE=$(grep -n "^import " "$GA_TEMPLATE" | tail -1 | cut -d: -f1)
        
        python3 -c "
with open('$GA_TEMPLATE', 'r') as f:
    lines = f.readlines()

extra_imports = '''import mobile.backend.java.FileUtils;
import mobile.backend.java.AndroidUtils;
import mobile.backend.java.JavaCrashHandler;
import mobile.backend.java.ScreenUtil;
import mobile.backend.java.KizzyHelper;
'''

# Insert after last import line ($LAST_IMPORT_LINE)
lines.insert($LAST_IMPORT_LINE, extra_imports)

with open('$GA_TEMPLATE', 'w') as f:
    f.writelines(lines)
"
        echo -e "  ${GREEN}✓${NC} Added extension imports to GameActivity.java template"
    fi
else
    echo -e "  ${RED}✗${NC} GameActivity.java template not found: $GA_TEMPLATE"
fi

# ── 2. Patch build.gradle template to add extension source dir ──
if [ -f "$BG_TEMPLATE" ]; then
    cp "$BG_TEMPLATE" "${BG_TEMPLATE}.bak"
    
    if grep -q "srcDir.*mobile/backend" "$BG_TEMPLATE"; then
        echo -e "  ${GREEN}✓${NC} build.gradle template already patched"
    else
        # Add a sourceSets block inside the android {} block
        # after the defaultConfig {} block
        python3 << 'PYEOF'
with open('.haxelib/lime/git/templates/android/template/app/build.gradle', 'r') as f:
    content = f.read()

# Find the closing of defaultConfig block and add sourceSets after it
# Look for the pattern: defaultConfig { ... } followed by newline
# We'll add sourceSets after the defaultConfig closing brace
old = '''	}

	::if KEY_STORE::'''
new = '''	}

	sourceSets {
		main {
			java {
				srcDir '../../../../../../source/mobile/backend'
			}
		}
	}

	::if KEY_STORE::'''

if old in content:
    content = content.replace(old, new)
    print("Patched build.gradle with sourceSets block")
else:
    print("WARNING: Could not find injection point in build.gradle")

with open('.haxelib/lime/git/templates/android/template/app/build.gradle', 'w') as f:
    f.write(content)
PYEOF
        echo -e "  ${GREEN}✓${NC} Added sourceSets to build.gradle template"
    fi
else
    echo -e "  ${RED}✗${NC} build.gradle template not found: $BG_TEMPLATE"
fi

echo "[PATCH COMPLETE]"
