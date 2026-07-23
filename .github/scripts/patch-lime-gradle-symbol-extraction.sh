#!/bin/bash
# patch-lime-gradle-symbol-extraction.sh - Adds a Gradle task that extracts
# the native symbol table from the already-placed (pre-Gradle) unstripped
# libApplicationMain.so under src/main/jniLibs and writes it straight into
# src/main/assets/data/, wired to run before whichever merge*Assets task
# packages assets into the APK.
#
# Why this is possible in a single "lime build android" pass: Lime's own
# AndroidPlatform.build() (tools/platforms/AndroidPlatform.hx) compiles the
# native .so and copies it to bin/app/src/main/jniLibs/<abi>/libApplicationMain.so
# BEFORE it ever invokes Gradle (that copy happens synchronously in the same
# function, well before the trailing AndroidHelper.build() call that runs
# `./gradlew assembleRelease`). So by the time Gradle's task graph starts,
# the unstripped .so this needs to read is already sitting on disk -- no
# second full Lime invocation is needed just to make an asset available
# before Gradle packages it, unlike the previous "Compile (repackage with
# symbol tables)" double-compile step this replaces.
#
# Requires the SYMBOL_EXTRACT_SCRIPT env var to be set to this repo's own
# .github/scripts/extract-dwarf-symbols.sh, as an ABSOLUTE path -- the
# generated Android project lives several directories deep under export/,
# so a relative path from build.gradle wouldn't reliably resolve. Silently
# skipped (not an error) if unset, e.g. a local/non-CI build.
set -euo pipefail

BUILD_GRADLE=".haxelib/lime/git/templates/android/template/app/build.gradle"
[ ! -f "$BUILD_GRADLE" ] && echo "Lime template not found" && exit 1

MARKER="extractNativeSymbols"
if grep -qF "$MARKER" "$BUILD_GRADLE"; then
	echo "Already patched, skipping."
	exit 0
fi

cat >> "$BUILD_GRADLE" << 'GRADLE_EOF'

// --- BEGIN: on-device native symbol table extraction (see
// patch-lime-gradle-symbol-extraction.sh for why this is safe to hook here
// instead of needing a second full "lime build android" pass) ---
task extractNativeSymbols {
	doLast {
		def scriptPath = System.getenv('SYMBOL_EXTRACT_SCRIPT')
		if (scriptPath == null || scriptPath.isEmpty()) {
			println "extractNativeSymbols: SYMBOL_EXTRACT_SCRIPT env var not set, skipping"
			return
		}

		def jniLibsDir = file('src/main/jniLibs')
		if (!jniLibsDir.exists()) return

		def abiMap = ['arm64-v8a': 'arm64', 'armeabi-v7a': 'armv7']
		abiMap.each { abiDir, suffix ->
			def soFile = new File(jniLibsDir, "${abiDir}/libApplicationMain.so")
			if (soFile.exists()) {
				def outFile = file("src/main/assets/data/symbols-${suffix}.sym")
				outFile.parentFile.mkdirs()
				exec {
					commandLine 'bash', scriptPath, soFile.absolutePath, outFile.absolutePath
				}
			}
		}
	}
}

tasks.whenTaskAdded { task ->
	if (task.name.startsWith("merge") && task.name.endsWith("Assets")) {
		task.dependsOn extractNativeSymbols
	}
}
// --- END: on-device native symbol table extraction ---
GRADLE_EOF

echo "Added extractNativeSymbols task to build.gradle template"
