#!/usr/bin/env python3
"""patch-lime-sdlactivity-renderscale.py - Expose Android's hardware surface
scaler (SurfaceHolder.setFixedSize) to Haxe for a real "Render Scale" option.

Perfetto traces on-device showed the game is GPU fill-rate bound (the
"GPU completion" thread's waitForever alone -- CPU blocked waiting on the GPU
to finish a frame -- outweighed RenderThread's own work by ~400x). DRS
(mobile/backend/DynamicResolution.hx) mitigates this by skipping every other
render entirely, but doesn't reduce the cost of the renders it does do.

SurfaceHolder.setFixedSize(width, height) tells the SurfaceView's buffer
producer to use a smaller buffer than the View's on-screen layout size;
SurfaceFlinger scales it up to fill the view during composition, a hardware
operation it already performs every frame regardless -- unlike a hand-rolled
FBO + blit-shader downscale, this costs no extra GPU rendering time at all.
This is the Java-level equivalent of the NDK's ANativeWindow_setBuffersGeometry.

Adds two static methods to SDLActivity (same file as the `mSurface` reference
they need -- protected fields are only reachable from the same package):
  - setRenderBufferSize(width, height): shrink the buffer for render scale < 100%
  - resetRenderBufferSize(): SurfaceHolder.setSizeFromLayout() to go back to 1:1

Usage: patch-lime-sdlactivity-renderscale.py <path to SDLActivity.java>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "setRenderBufferSize"

if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

anchor = (
    "    protected static SDLGenericMotionListener_API14 mMotionListener;\n"
    "    protected static HIDDeviceManager mHIDDeviceManager;\n"
)
assert content.count(anchor) == 1, f"expected exactly 1 match for the field-declaration anchor, found {content.count(anchor)}"

insertion = (
    "\n"
    "    /**\n"
    "     * Render-scale support: shrinks the SurfaceView's backing buffer to the\n"
    "     * given pixel size while its on-screen layout bounds stay full-size --\n"
    "     * SurfaceFlinger scales the smaller buffer up during composition (the\n"
    "     * Android hardware scaler) at near-zero extra GPU cost, unlike rendering\n"
    "     * to an offscreen texture and blitting it ourselves.\n"
    "     *\n"
    "     * NOTE: touch coordinates are normalized in SDLSurface.getNormalizedX/Y\n"
    "     * against the View's real layout size (getWidth()/getHeight()), NOT this\n"
    "     * buffer size -- that's deliberate, so this call can never desync touch\n"
    "     * input from the screen. Do not \"simplify\" that back to mWidth/mHeight.\n"
    "     */\n"
    "    public static void setRenderBufferSize(int width, int height) {\n"
    "        if (mSurface != null) mSurface.getHolder().setFixedSize(width, height);\n"
    "    }\n"
    "\n"
    "    /** Reverts a previous setRenderBufferSize() call back to native 1:1 rendering. */\n"
    "    public static void resetRenderBufferSize() {\n"
    "        if (mSurface != null) mSurface.getHolder().setSizeFromLayout();\n"
    "    }\n"
    "\n"
    "    /**\n"
    "     * Diagnostics for setRenderBufferSize(): reads back what the OS actually\n"
    "     * has for the surface's buffer right now, so Haxe-side logging can tell\n"
    "     * apart \"the OS never shrank the buffer\" from \"the buffer shrank but\n"
    "     * rendering ignored it\". Returns -1 if there's no surface yet.\n"
    "     *\n"
    "     * Deliberately reads SDLSurface.mWidth/mHeight (set inside its own\n"
    "     * surfaceChanged(), which fires reliably for every real buffer change)\n"
    "     * instead of SurfaceHolder.getSurfaceFrame() -- that Rect is only ever\n"
    "     * updated by SurfaceView's own View.draw() cycle, which a GL game like\n"
    "     * this one bypasses entirely by rendering straight to the Surface on\n"
    "     * its own thread, so getSurfaceFrame() would just stay (0,0,0,0) forever.\n"
    "     */\n"
    "    public static int getSurfaceBufferWidth() {\n"
    "        return mSurface != null ? (int) mSurface.mWidth : -1;\n"
    "    }\n"
    "\n"
    "    public static int getSurfaceBufferHeight() {\n"
    "        return mSurface != null ? (int) mSurface.mHeight : -1;\n"
    "    }\n"
)

content = content.replace(anchor, anchor + insertion, 1)

assert MARKER in content, "setRenderBufferSize still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched SDLActivity.java: added setRenderBufferSize()/resetRenderBufferSize()")
