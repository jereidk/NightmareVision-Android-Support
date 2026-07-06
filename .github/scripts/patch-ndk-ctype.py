#!/usr/bin/env python3
"""
Patch libc++'s __posix_l_fallback.h so it stops redefining ctype _l
functions that modern bionic (the NDK's libc) already defines unconditionally.

Root cause: bionic's ctype.h (aosp-mirror/platform_bionic) unconditionally
defines isalnum_l/isalpha_l/isblank_l/iscntrl_l/isdigit_l/isgraph_l/
islower_l/isprint_l/ispunct_l/isspace_l/isupper_l/isxdigit_l/tolower_l/
toupper_l via the __BIONIC_CTYPE_INLINE macro (no API-level gating).
libc++'s __posix_l_fallback.h - a legacy shim originally written for libcs
without _l support - also unconditionally defines whichever of those same
names it ships (currently 6: isdigit_l, islower_l, isupper_l, isxdigit_l,
tolower_l, toupper_l). Any translation unit that includes both headers
(e.g. lime's Font.cpp, compiled with -std=c++23 against NDK 28+) then fails
with "redefinition of ... isdigit_l" and friends.

This script wraps only the functions that collide with bionic's list in
`#ifndef __ANDROID__ ... #endif`, leaving everything else in the file
(wide-char functions, strcoll_l/strxfrm_l/strftime_l, the include guard)
untouched. It is idempotent: a sentinel comment marks already-patched files.
"""
import os
import re
import sys

SENTINEL = "__ANDROID_CTYPE_L_FIX__"

# All _l ctype names bionic's ctype.h defines unconditionally. Only whichever
# of these actually appear in a given NDK's __posix_l_fallback.h get wrapped;
# this list is intentionally over-inclusive so the script keeps working if a
# future NDK/libc++ revision ships a different subset.
BIONIC_L_NAMES = {
    "isalnum_l", "isalpha_l", "isblank_l", "iscntrl_l", "isdigit_l",
    "isgraph_l", "islower_l", "isprint_l", "ispunct_l", "isspace_l",
    "isupper_l", "isxdigit_l", "tolower_l", "toupper_l",
}

PATTERN = re.compile(
    r"inline\s+\S+(?:\s+\w+)?\s+(?P<name>\w+_l)\s*\([^)]*\)\s*\{[^{}]*\}",
    re.DOTALL,
)


def find_fallback_headers(ndk_root):
    search_root = os.path.join(ndk_root, "toolchains", "llvm", "prebuilt")
    if not os.path.isdir(search_root):
        search_root = ndk_root
    matches = []
    for dirpath, _dirnames, filenames in os.walk(search_root):
        if "__posix_l_fallback.h" in filenames:
            matches.append(os.path.join(dirpath, "__posix_l_fallback.h"))
    return matches


def patch_file(path):
    with open(path, "r") as f:
        src = f.read()

    if SENTINEL in src:
        print(f"  Already patched, skipping: {path}")
        return True

    patched_names = []

    def wrap(match):
        name = match.group("name")
        if name not in BIONIC_L_NAMES:
            return match.group(0)
        patched_names.append(name)
        return (
            "#ifndef __ANDROID__  // " + SENTINEL + "\n"
            + match.group(0)
            + "\n#endif  // " + SENTINEL
        )

    new_src = PATTERN.sub(wrap, src)

    if not patched_names:
        print(f"  WARNING: no colliding _l functions found in {path}, leaving untouched")
        return True

    with open(path, "w") as f:
        f.write(new_src)

    print(f"  Patched {path}: {sorted(patched_names)}")
    return True


def main():
    ndk_root = os.environ.get("ANDROID_NDK_LATEST_HOME") or (sys.argv[1] if len(sys.argv) > 1 else None)
    if not ndk_root:
        print("ERROR: ANDROID_NDK_LATEST_HOME not set and no path argument given", file=sys.stderr)
        return 1

    headers = find_fallback_headers(ndk_root)
    if not headers:
        print(f"ERROR: __posix_l_fallback.h not found under {ndk_root}", file=sys.stderr)
        return 1

    ok = True
    for header in headers:
        if not patch_file(header):
            ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
