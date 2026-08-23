#!/usr/bin/env python3
"""patch-flixel-animate-bakefilters-stale-read.py - Use the already-validated
filters parameter instead of a fresh (and possibly stale/null) re-read.

animate.internal.FilterRenderer.bakeFilters()'s only caller,
MovieClipInstance._bakeFilters(), already checks its own filters parameter
for null/empty before calling this function -- but bakeFilters() itself
completely ignores that parameter and re-reads movieclip._filters instead:

    public static function bakeFilters(movieclip:MovieClipInstance, frameIndex:Int, filters:Array<BitmapFilter>):AtlasInstance
    {
        return _bakeFilters(movieclip._filters, movieclip.getBounds(frameIndex, null, null, false), movieclip._filterQuality, (cam, mat) ->
        ...

Confirmed live via a symbolicated native_crash_trace.log (file:line +
on-device resolution, SIGSEGV / null pointer dereference): the crash lands
in the closure passed to _bakeFilters(), specifically at
expandFilterBounds(bounds.copyTo(FlxRect.get()), filters) -- a `for (filter
in filters)` over a null array is exactly a null pointer dereference on
cpp, with no catchable Haxe exception. The only way `filters` (the
captured closure parameter, itself a snapshot of movieclip._filters taken
right here) can be null at that point is if movieclip._filters and this
re-read observed different values -- movieclip.getBounds(...), evaluated
as a sibling argument in the very same call, is the only thing in this
expression that could run before that field read.

Fixing this doesn't require pinning down the exact evaluation-order
mechanics: the caller ALREADY validated `filters` is non-null/non-empty
immediately before calling this function, so simply using that parameter
(currently unused!) instead of re-reading movieclip._filters removes the
stale-read window entirely, with zero behavior change in the normal
(non-racing) case since every current caller always passes
movieclip._filters as this exact parameter.

Usage: patch-flixel-animate-bakefilters-stale-read.py <path to FilterRenderer.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "return _bakeFilters(filters, movieclip.getBounds(frameIndex, null, null, false)"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = (
    "\tpublic static function bakeFilters(movieclip:MovieClipInstance, frameIndex:Int, filters:Array<BitmapFilter>):AtlasInstance\n"
    "\t{\n"
    "\t\treturn _bakeFilters(movieclip._filters, movieclip.getBounds(frameIndex, null, null, false), movieclip._filterQuality, (cam, mat) ->\n"
    "\t\t{\n"
    "\t\t\tmovieclip._drawTimeline(cam, frameIndex, 0, mat);\n"
    "\t\t});\n"
    "\t}\n"
)
NEW = (
    "\tpublic static function bakeFilters(movieclip:MovieClipInstance, frameIndex:Int, filters:Array<BitmapFilter>):AtlasInstance\n"
    "\t{\n"
    "\t\t// Use the already-validated `filters` parameter, not a fresh\n"
    "\t\t// movieclip._filters re-read -- the only caller already checked\n"
    "\t\t// filters != null/length > 0 right before this call, and re-reading\n"
    "\t\t// the mutable field here (interleaved with the movieclip.getBounds()\n"
    "\t\t// call on the same line) risks observing a stale/null value that\n"
    "\t\t// then null-derefs inside expandFilterBounds()'s `for (filter in\n"
    "\t\t// filters)` -- a real SIGSEGV confirmed via a symbolicated crash\n"
    "\t\t// trace. Every caller already passes movieclip._filters as this\n"
    "\t\t// exact parameter, so this is a no-op change outside that race.\n"
    "\t\treturn _bakeFilters(filters, movieclip.getBounds(frameIndex, null, null, false), movieclip._filterQuality, (cam, mat) ->\n"
    "\t\t{\n"
    "\t\t\tmovieclip._drawTimeline(cam, frameIndex, 0, mat);\n"
    "\t\t});\n"
    "\t}\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for FilterRenderer.bakeFilters(), found {count} -- flixel-animate changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "fix marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched FilterRenderer.hx: bakeFilters() now uses its validated filters parameter instead of a fresh movieclip._filters re-read")
