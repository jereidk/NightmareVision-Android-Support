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

IMPORTANT -- idempotency: same lesson as patch-lime-sdlactivity-renderscale.py
(a naive "if MARKER in content: skip" check shipped a stale, already-fixed
diagnostic to a real APK for two builds in a row because a CI cache had an
older version lying around). Both insertions here replace the gap between
STABLE anchors from the original, unpatched file -- content that's never
touched by us -- rather than trying to recognize our own past output, so
re-running this with edited content always converges on the version below.

Usage: patch-lime-sdlsurface-diagnostics.py <path to SDLSurface.java>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# --- Field declarations: insert the 3 static counters after mWidth/mHeight ---

FIELD_START_ANCHOR = "    protected float mWidth, mHeight;\n"
FIELD_END_ANCHOR = "    // Is SurfaceView ready for rendering\n"

assert content.count(FIELD_START_ANCHOR) == 1, f"expected exactly 1 match for the mWidth/mHeight field anchor, found {content.count(FIELD_START_ANCHOR)}"
assert content.count(FIELD_END_ANCHOR) == 1, f"expected exactly 1 match for the mIsSurfaceReady comment anchor, found {content.count(FIELD_END_ANCHOR)}"

field_block = (
    "\n"
    "    // Diagnostics for RenderScale (see patch-lime-sdlsurface-diagnostics.py):\n"
    "    // lets Haxe-side code tell apart \"surfaceChanged() never fired\" from\n"
    "    // \"it fired but reported a degenerate size\", neither of which is visible\n"
    "    // from mWidth/mHeight alone.\n"
    "    protected static int sSurfaceChangedCallCount = 0;\n"
    "    protected static int sLastSurfaceChangedWidth = -1;\n"
    "    protected static int sLastSurfaceChangedHeight = -1;\n"
    "\n"
)

field_start = content.index(FIELD_START_ANCHOR) + len(FIELD_START_ANCHOR)
field_end = content.index(FIELD_END_ANCHOR)
field_gap = content[field_start:field_end]

fields_already_current = field_gap == field_block

if not fields_already_current:
    content = content[:field_start] + field_block + content[field_end:]

# --- surfaceChanged(): track every call right after mWidth/mHeight are set ---

CALL_START_ANCHOR = (
    "        mWidth = width;\n"
    "        mHeight = height;\n"
)
CALL_END_ANCHOR = "        int nDeviceWidth = width;\n"

assert content.count(CALL_START_ANCHOR) == 1, f"expected exactly 1 match for the mWidth/mHeight assignment in surfaceChanged(), found {content.count(CALL_START_ANCHOR)}"
assert content.count(CALL_END_ANCHOR) == 1, f"expected exactly 1 match for the nDeviceWidth anchor, found {content.count(CALL_END_ANCHOR)}"

call_block = (
    "        sSurfaceChangedCallCount++;\n"
    "        sLastSurfaceChangedWidth = width;\n"
    "        sLastSurfaceChangedHeight = height;\n"
)

call_start = content.index(CALL_START_ANCHOR) + len(CALL_START_ANCHOR)
call_end = content.index(CALL_END_ANCHOR)
call_gap = content[call_start:call_end]

calls_already_current = call_gap == call_block

if fields_already_current and calls_already_current:
    print("Already patched with the current version, skipping.")
    sys.exit(0)

if not calls_already_current:
    content = content[:call_start] + call_block + content[call_end:]

assert "sSurfaceChangedCallCount" in content, "diagnostics fields still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched SDLSurface.java: surfaceChanged() now tracks call count + last reported size")
