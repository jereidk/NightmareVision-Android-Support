#!/usr/bin/env python3
"""patch-hxcpp-disable-align-alloc.py - Disable hxcpp's HXCPP_ALIGN_ALLOC.

include/hxcpp.h unconditionally does:

    #define HXCPP_ALIGN_ALLOC

with no #ifdef guard -- every build gets it, regardless of platform or GC
mode. This flag adds extra 8-byte alignment padding logic throughout
Immix.cpp's block/hole management and GC.h's inline allocation fast path
(ImmixAllocator::alloc(), the exact function symbolicated at the crash
address in TWO independently-investigated native_crash_trace.log SIGSEGVs
this project hit -- one in Ejected, one in Double Trouble, both landing in
this same inlined fast path via ground-truth objdump, not addr2line
guessing).

This project has already found and fixed ONE real, confirmed hxcpp GC bug
tied to this exact flag: HXCPP_GC_GENERATIONAL's MoveSurvivors() (Immix.cpp)
had a real hole-search bug interacting with HXCPP_ALIGN_ALLOC, twice
diagnosed as "root cause of silent mid-song crashes" and fixed by disabling
the generational collector -- see commits 78a922d6 and 425ad791. That fix
only stopped using the generational collector; HXCPP_ALIGN_ALLOC itself
stayed on unconditionally, still active in the plain (non-generational)
allocator this project actually ships with.

Given both since-observed native crashes symbolicate to this exact
alignment-padding code path, and FunkinCrew/hxcpp's own latest commit (per
425ad791's own research, 62 commits ahead of our pin) still has this same
flag unconditionally defined with the already-known-buggy interaction
still unresolved, this disables HXCPP_ALIGN_ALLOC entirely as a diagnostic
experiment -- every #ifdef HXCPP_ALIGN_ALLOC branch across Immix.cpp/GC.h
falls back to its plain (no extra padding) path uniformly, since they all
key off this same single macro.

Usage: patch-hxcpp-disable-align-alloc.py <path to hxcpp/include/hxcpp.h>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "// HXCPP_ALIGN_ALLOC disabled"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = "#define HXCPP_ALIGN_ALLOC\n"
NEW = (
    "// HXCPP_ALIGN_ALLOC disabled -- see patch-hxcpp-disable-align-alloc.py\n"
    "// for why (both native_crash_trace.log SIGSEGVs this project hit\n"
    "// symbolicate to the alignment-padding code this flag adds to\n"
    "// ImmixAllocator::alloc()'s inline fast path).\n"
    "// #define HXCPP_ALIGN_ALLOC\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for HXCPP_ALIGN_ALLOC define, found {count} -- hxcpp changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "disable marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched hxcpp.h: HXCPP_ALIGN_ALLOC disabled")
