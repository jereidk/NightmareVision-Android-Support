#!/usr/bin/env bash
set -euo pipefail
# Patches Lime's AndroidPlatform.hx to ensure extension .java files
# are properly copied into the Gradle source set.
# 
# The issue: update() calls removeDirectory(sourceSet/java) then
# recursiveCopy(javaPath, ...) but the try/catch silently swallows errors,
# and recursiveSmartCopyTemplate later overwrites GameActivity.java.
#
# This script injects a second javaPath pointing to source/mobile/backend/
# or simply ensures the copy happens correctly.

AP_HX=".haxelib/lime/git/tools/platforms/AndroidPlatform.hx"

echo "[PATCH ANDROID PLATFORM]"

if [ ! -f "$AP_HX" ]; then
    echo "  AndroidPlatform.hx not found at $AP_HX"
    exit 0
fi

cp "$AP_HX" "${AP_HX}.bak"

# Strategy: Find the line "for (javaPath in project.javaPaths)" and add
# source/mobile/backend/java to project.javaPaths BEFORE the loop.
# This ensures the extension .java files are copied.

python3 << 'PYEOF'
import re

with open('.haxelib/lime/git/tools/platforms/AndroidPlatform.hx', 'r') as f:
    content = f.read()

# Find: System.removeDirectory(sourceSet + "/java");
# After this block and before the for loop, inject code to add our java paths
old = '''		for (javaPath in project.javaPaths)'''
new = '''		// PATCH: ensure extension java files are copied
		var extJavaPath = "source/mobile/backend";
		if (FileSystem.exists(extJavaPath) && FileSystem.isDirectory(extJavaPath))
		{
			try
			{
				recursiveCopy(extJavaPath, sourceSet + "/java/mobile/backend", context, true);
			}
			catch (e:Dynamic)
			{
				Log.warn("Failed to copy extension java files from " + extJavaPath);
			}
		}
		for (javaPath in project.javaPaths)'''

content = content.replace(old, new)
print(f"Patched: injected extension copy before javaPaths loop")

with open('.haxelib/lime/git/tools/platforms/AndroidPlatform.hx', 'w') as f:
    f.write(content)
PYEOF

echo "  Patched $AP_HX"
echo "  Backed up to ${AP_HX}.bak"
