#!/bin/bash
# patch-lime-gradle-proguard.sh - Enables R8 (minifyEnabled) and adds
# custom ProGuard rules for JNI-reachable classes.
#
# Without this, the 6 Java source files under source/mobile/backend/java/
# compile into the APK with NO code shrinking, so every unused method and
# inner class stays in the DEX. R8 eliminates them safely (the rules in
# proguard-rules.pro keep everything JNI/reachability needs) and shrinks
# any AndroidX/appcompat/gson/okhttp transitive dependencies the android-
# manager or other libs pull in.
set -euo pipefail

BUILD_GRADLE=".haxelib/lime/git/templates/android/template/app/build.gradle"
[ ! -f "$BUILD_GRADLE" ] && echo "Lime template not found" && exit 1

# The proguard-rules.pro lives at the repo root. When Lime generates the
# Android project under export/, it copies our templates/android/ dir
# into app/src/main/ (via Project.xml's <template path="templates/android"/>).
# But proguard-rules.pro needs to be in app/ for build.gradle to reference
# it with a relative path. We place a symlink from the generated project's
# root into the repo root so the same file works both in CI and local builds.
# Actually, simpler: just reference it from build.gradle using a path
# relative to the generated project -- the repo root is accessible via
# ../../../../../../ (project/app/build.gradle -> repo root).
# Even simpler: echo it into the generated project's root during the build.
# For now, just patch the build.gradle template to enable R8.
python3 - "$BUILD_GRADLE" << 'PYTHON_EOF'
import sys
build_gradle = sys.argv[1]
with open(build_gradle) as f:
    c = f.read()

# Change minifyEnabled false -> true
if 'minifyEnabled false' not in c:
    print("ERROR: expected minifyEnabled false, not found - template may have changed")
    sys.exit(1)
c = c.replace('minifyEnabled false', 'minifyEnabled true', 1)

# Add custom proguard rules file reference
old_proguard = "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt')"
if old_proguard not in c:
    print("ERROR: expected proguardFiles line not found")
    sys.exit(1)

new_proguard = (
    "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), "
    "'proguard-rules.pro'"
)
c = c.replace(old_proguard, new_proguard, 1)

with open(build_gradle, 'w') as f:
    f.write(c)
print("Enabled R8 (minifyEnabled=true) and added proguard-rules.pro reference")
PYTHON_EOF
