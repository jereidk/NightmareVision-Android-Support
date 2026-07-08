#!/usr/bin/env python3
"""patch-lime-sdlsurface-touch-normalize.py - Keep touch input aligned to the
real screen when the render-scale feature shrinks the surface buffer.

getNormalizedX/Y divide the raw touch coordinate by mWidth/mHeight -- which is
normally correct, since mWidth/mHeight track the surface's buffer size, and
(without render scale) that buffer fills the whole View.

But SDLActivity.setRenderBufferSize() (see
patch-lime-sdlactivity-renderscale.py) can now make the buffer SMALLER than
the View's actual on-screen size. Android always reports raw touch coordinates
in the View's real layout space regardless of the buffer size underneath it --
so once mWidth/mHeight shrink, dividing by them would push normalized
coordinates past 1.0 near the edges (e.g. a tap at physical x=1900 on a
1920-wide screen with a 960-wide buffer: 1900/959 ~= 1.98), scrambling every
touch target and note hitbox on screen.

Fix: normalize against getWidth()/getHeight() (the View's real layout size,
which setFixedSize() does NOT change) instead of mWidth/mHeight. This must
land in the SAME build as the render-scale patch, or render scale < 100% will
silently break all touch input.

Usage: patch-lime-sdlsurface-touch-normalize.py <path to SDLSurface.java>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "real layout size, not the SurfaceHolder buffer size"

if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

old = (
    "    private float getNormalizedX(float x)\n"
    "    {\n"
    "        if (mWidth <= 1) {\n"
    "            return 0.5f;\n"
    "        } else {\n"
    "            return (x / (mWidth - 1));\n"
    "        }\n"
    "    }\n"
    "\n"
    "    private float getNormalizedY(float y)\n"
    "    {\n"
    "        if (mHeight <= 1) {\n"
    "            return 0.5f;\n"
    "        } else {\n"
    "            return (y / (mHeight - 1));\n"
    "        }\n"
    "    }\n"
)
assert content.count(old) == 1, f"expected exactly 1 match for getNormalizedX/Y, found {content.count(old)} -- SDLSurface.java changed upstream"

new = (
    "    private float getNormalizedX(float x)\n"
    "    {\n"
    "        // Against the View's real layout size, not the SurfaceHolder buffer size\n"
    "        // (see SDLActivity.setRenderBufferSize) -- those can now differ (render\n"
    "        // scale < 100%), and Android always reports touch coordinates in the\n"
    "        // View's real on-screen space no matter how small the buffer is.\n"
    "        int viewWidth = getWidth();\n"
    "        if (viewWidth <= 1) {\n"
    "            return 0.5f;\n"
    "        } else {\n"
    "            return (x / (viewWidth - 1));\n"
    "        }\n"
    "    }\n"
    "\n"
    "    private float getNormalizedY(float y)\n"
    "    {\n"
    "        int viewHeight = getHeight();\n"
    "        if (viewHeight <= 1) {\n"
    "            return 0.5f;\n"
    "        } else {\n"
    "            return (y / (viewHeight - 1));\n"
    "        }\n"
    "    }\n"
)

content = content.replace(old, new, 1)

assert MARKER in content, "touch-normalization fix still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched SDLSurface.java: touch normalization now uses the View's real layout size, not the SurfaceHolder buffer size")
