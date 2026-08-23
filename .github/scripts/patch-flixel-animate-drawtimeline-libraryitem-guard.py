#!/usr/bin/env python3
"""patch-flixel-animate-drawtimeline-libraryitem-guard.py - Guard and log
SymbolInstance._drawTimeline()'s libraryItem.timeline dereference.

animate.internal.elements.SymbolInstance._drawTimeline() unconditionally
dereferences libraryItem.timeline:

    function _drawTimeline(camera, index, frameIndex, parentMatrix, ?command) {
        _mat.copyFrom(matrix);
        _mat.concat(parentMatrix);
        libraryItem.timeline.currentFrame = getFrameIndex(index, frameIndex);
        libraryItem.timeline.draw(camera, _mat, command);
    }

This is the confirmed crash site for a recurring Double Trouble native
SIGSEGV: a symbolicated native_crash_trace.log resolved the crash to this
exact function (inlined into the calling closure in FilterRenderer's
bakeFilters(), which is why it originally looked like the crash was in
filter-baking code -- it isn't; that's just the caller). The constructor
already accounts for libraryItem legitimately being null (`if (libraryItem
== null) visible = false;`), so a null/invalid libraryItem or a
libraryItem with no timeline reaching draw() anyway is a real, reachable
state, not just a theoretical one.

This guard doesn't claim to fix the underlying cause (we don't have
definitive proof yet of WHICH caller hands this instance a bad
libraryItem -- doubletrouble.hx's 'red placeholder' cross-retry Frame
injection is the leading suspect in our own repo, but unproven). It logs
(plain trace(), captured into game.log) the symbol name and which part
was null whenever this fires, so the next occurrence tells us exactly
which symbol is involved instead of just the same opaque SIGSEGV -- that's
the missing piece for actually root-causing this instead of guessing
further.

Usage: patch-flixel-animate-drawtimeline-libraryitem-guard.py <path to animate/internal/elements/SymbolInstance.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "_drawTimeline() guard fired"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = (
    "\tfunction _drawTimeline(camera:FlxCamera, index:Int, frameIndex:Int, parentMatrix:FlxMatrix, ?command:AnimateDrawCommand):Void\n"
    "\t{\n"
    "\t\t_mat.copyFrom(matrix);\n"
    "\t\t_mat.concat(parentMatrix);\n"
    "\t\tlibraryItem.timeline.currentFrame = getFrameIndex(index, frameIndex);\n"
    "\t\tlibraryItem.timeline.draw(camera, _mat, command);\n"
    "\t}\n"
)
NEW = (
    "\tfunction _drawTimeline(camera:FlxCamera, index:Int, frameIndex:Int, parentMatrix:FlxMatrix, ?command:AnimateDrawCommand):Void\n"
    "\t{\n"
    "\t\t// Guarded and logged so a null/invalid libraryItem (or a libraryItem\n"
    "\t\t// with no timeline) is a traceable no-op instead of a null pointer\n"
    "\t\t// dereference with no catchable exception -- confirmed as the exact\n"
    "\t\t// crash site for a recurring Double Trouble SIGSEGV via a\n"
    "\t\t// symbolicated native_crash_trace.log (this function gets inlined\n"
    "\t\t// into the calling closure in FilterRenderer.bakeFilters(), which is\n"
    "\t\t// why the crash originally looked like a filter-baking bug -- it\n"
    "\t\t// isn't, that's just the caller). We don't yet know for certain which\n"
    "\t\t// caller hands this instance a bad libraryItem, so this logs the\n"
    "\t\t// symbol name and which part was null every time it fires, instead of\n"
    "\t\t// silently guarding it away -- that's the missing detail to actually\n"
    "\t\t// root-cause this on the next occurrence.\n"
    "\t\tif (libraryItem == null || libraryItem.timeline == null)\n"
    "\t\t{\n"
    "\t\t\ttrace(\"SymbolInstance._drawTimeline() guard fired: \" + (libraryItem == null ? \"libraryItem is null\" : \"libraryItem.timeline is null\") + \" (symbolName='\" + symbolName + \"'). Would have crashed dereferencing libraryItem.timeline -- worth tracking down which caller handed this instance a bad libraryItem.\");\n"
    "\t\t\treturn;\n"
    "\t\t}\n"
    "\n"
    "\t\t_mat.copyFrom(matrix);\n"
    "\t\t_mat.concat(parentMatrix);\n"
    "\t\tlibraryItem.timeline.currentFrame = getFrameIndex(index, frameIndex);\n"
    "\t\tlibraryItem.timeline.draw(camera, _mat, command);\n"
    "\t}\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for SymbolInstance._drawTimeline(), found {count} -- flixel-animate changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "guard marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched SymbolInstance.hx: _drawTimeline() now guards and logs a null/invalid libraryItem instead of crashing")
