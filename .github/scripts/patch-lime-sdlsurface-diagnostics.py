#!/usr/bin/env python3
"""patch-lime-sdlsurface-diagnostics.py - Instruments SDLSurface.surfaceChanged()
so Haxe can tell whether that callback is firing at all on a given device, and
what width/height it's actually being called with.

Why this exists: RenderScale's own diagnostics (reading mSurface.mWidth /
mHeight from SDLActivity) showed a device where the buffer size read back as
0x0 on every single call, at every scale, even after a clean uninstall +
reinstall. mWidth/mHeight are only ever assigned inside surfaceChanged() --
a device-side value of exactly 0 (not the 1.0f the fields are initialized to)
is only possible if either surfaceChanged() has never fired at all (fields
stay untouched... but that would read as 1, not 0), or it fired at least
once with degenerate (0,0) dimensions. Neither can be told apart from the
outside without instrumenting the callback itself.

Adds:
  - static int sSurfaceChangedCallCount -- how many times it's fired, ever
  - static int sLastSurfaceChangedWidth / sLastSurfaceChangedHeight -- what
    the most recent call actually reported

Usage: patch-lime-sdlsurface-diagnostics.py <path to SDLSurface.java>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "sSurfaceChangedCallCount"

if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

field_anchor = "    protected float mWidth, mHeight;\n"
assert content.count(field_anchor) == 1, f"expected exactly 1 match for the mWidth/mHeight field anchor, found {content.count(field_anchor)}"

field_insertion = (
    "    protected float mWidth, mHeight;\n"
    "\n"
    "    // Diagnostics for RenderScale (see patch-lime-sdlsurface-diagnostics.py):\n"
    "    // lets Haxe-side code tell apart \"surfaceChanged() never fired\" from\n"
    "    // \"it fired but reported a degenerate size\", neither of which is visible\n"
    "    // from mWidth/mHeight alone.\n"
    "    protected static int sSurfaceChangedCallCount = 0;\n"
    "    protected static int sLastSurfaceChangedWidth = -1;\n"
    "    protected static int sLastSurfaceChangedHeight = -1;\n"
)

content = content.replace(field_anchor, field_insertion, 1)

call_anchor = (
    "        mWidth = width;\n"
    "        mHeight = height;\n"
)
assert content.count(call_anchor) == 1, f"expected exactly 1 match for the mWidth/mHeight assignment in surfaceChanged(), found {content.count(call_anchor)}"

call_insertion = (
    "        mWidth = width;\n"
    "        mHeight = height;\n"
    "        sSurfaceChangedCallCount++;\n"
    "        sLastSurfaceChangedWidth = width;\n"
    "        sLastSurfaceChangedHeight = height;\n"
)

content = content.replace(call_anchor, call_insertion, 1)

assert MARKER in content, "sSurfaceChangedCallCount still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched SDLSurface.java: surfaceChanged() now tracks call count + last reported size")
