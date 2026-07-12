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

Adds static methods to SDLActivity (same file as the `mSurface` reference
they need -- protected fields are only reachable from the same package):
  - setRenderBufferSize(width, height): shrink the buffer for render scale < 100%
  - resetRenderBufferSize(): SurfaceHolder.setSizeFromLayout() to go back to 1:1
  - getSurfaceBufferWidth/Height(): diagnostics, read SDLSurface.mWidth/mHeight
  - getSurfaceChangedCallCount/getLastSurfaceChanged{Width,Height}(): more
    diagnostics, read the counters patch-lime-sdlsurface-diagnostics.py adds
  - getSurfaceViewLayoutWidth/Height(): the View's own layout size, for comparison

IMPORTANT -- idempotency: this content has changed shape multiple times
across this project's development (methods added, a diagnostics bug fixed),
and a naive "if MARKER_STRING in content: skip" check is fooled by ANY of
those older versions sitting in a stale .haxelib/lime CI cache, since the
marker string (e.g. "setRenderBufferSize") is present in all of them --
that exact bug shipped an APK with a known-broken diagnostic method for two
builds in a row before it was caught by testing on a real device.

Instead of matching our own inserted content (which is exactly what keeps
changing), this replaces everything found between two STABLE anchors that
are part of the original, unpatched file and never change: the
mMotionListener/mHIDDeviceManager field pair, and the "This is what SDL
runs in" comment right after wherever our block ends up. Whatever's between
them -- nothing (pristine), or any past version of our block -- gets
replaced wholesale with the current block below, so this always converges
regardless of what a stale cache is carrying.

Usage: patch-lime-sdlactivity-renderscale.py <path to SDLActivity.java>
"""

import re
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

START_ANCHOR = (
    "    protected static SDLGenericMotionListener_API14 mMotionListener;\n"
    "    protected static HIDDeviceManager mHIDDeviceManager;\n"
)
END_ANCHOR = "    // This is what SDL runs in. It invokes SDL_main(), eventually\n"

assert content.count(START_ANCHOR) == 1, f"expected exactly 1 match for the start anchor, found {content.count(START_ANCHOR)}"
assert content.count(END_ANCHOR) == 1, f"expected exactly 1 match for the end anchor, found {content.count(END_ANCHOR)}"

block = (
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
    "    public static void setRenderBufferSize(final int width, final int height) {\n"
    "        if (mSingleton == null || mSurface == null) return;\n"
    "        // SurfaceHolder.setFixedSize() has to run on the main/UI thread --\n"
    "        // ViewRootImpl's relayout + surfaceChanged() dispatch is thread-bound\n"
    "        // to it, same as every other View/Window-touching call in this app\n"
    "        // (see AndroidUtils.java's runOnUiThread() wrapping on all of its own\n"
    "        // methods). Calling this from Haxe's own (SDL/game) thread let the\n"
    "        // method run and returned normally, but surfaceChanged() then never\n"
    "        // fired for it -- confirmed on-device via the diagnostics below,\n"
    "        // whose call counter never incremented across a dozen calls at\n"
    "        // different scales.\n"
    "        mSingleton.runOnUiThread(new Runnable() {\n"
    "            @Override\n"
    "            public void run() {\n"
    "                if (mSurface != null) mSurface.getHolder().setFixedSize(width, height);\n"
    "            }\n"
    "        });\n"
    "    }\n"
    "\n"
    "    /** Reverts a previous setRenderBufferSize() call back to native 1:1 rendering. */\n"
    "    public static void resetRenderBufferSize() {\n"
    "        if (mSingleton == null || mSurface == null) return;\n"
    "        mSingleton.runOnUiThread(new Runnable() {\n"
    "            @Override\n"
    "            public void run() {\n"
    "                if (mSurface != null) mSurface.getHolder().setSizeFromLayout();\n"
    "            }\n"
    "        });\n"
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
    "\n"
    "    /**\n"
    "     * Further diagnostics (see patch-lime-sdlsurface-diagnostics.py): whether\n"
    "     * surfaceChanged() has ever fired on this device, and what it last\n"
    "     * reported, since a 0x0 buffer reading alone can't tell apart \"never\n"
    "     * fired\" from \"fired with a degenerate size\". Also exposes the View's\n"
    "     * own layout size (getWidth/getHeight) for comparison -- that one is\n"
    "     * already known-good, since touch normalization depends on it.\n"
    "     */\n"
    "    public static int getSurfaceChangedCallCount() {\n"
    "        return mSurface != null ? SDLSurface.sSurfaceChangedCallCount : -1;\n"
    "    }\n"
    "\n"
    "    public static int getLastSurfaceChangedWidth() {\n"
    "        return mSurface != null ? SDLSurface.sLastSurfaceChangedWidth : -1;\n"
    "    }\n"
    "\n"
    "    public static int getLastSurfaceChangedHeight() {\n"
    "        return mSurface != null ? SDLSurface.sLastSurfaceChangedHeight : -1;\n"
    "    }\n"
    "\n"
    "    public static int getSurfaceViewLayoutWidth() {\n"
    "        return mSurface != null ? mSurface.getWidth() : -1;\n"
    "    }\n"
    "\n"
    "    public static int getSurfaceViewLayoutHeight() {\n"
    "        return mSurface != null ? mSurface.getHeight() : -1;\n"
    "    }\n"
    "\n"
)

start = content.index(START_ANCHOR) + len(START_ANCHOR)
end = content.index(END_ANCHOR)
gap = content[start:end]

if gap == block:
    print("Already patched with the current version, skipping.")
    sys.exit(0)

if gap.strip() == "":
    print("Pristine file, inserting RenderScale block.")
else:
    print("Found an older/different version of the RenderScale block -- replacing with the current version.")

content = content[:start] + block + content[end:]

assert "getSurfaceViewLayoutHeight" in content, "RenderScale block still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched SDLActivity.java: RenderScale block is now up to date")
