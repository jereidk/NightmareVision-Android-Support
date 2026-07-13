package mobile.backend;

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * True render-resolution scaling driven entirely through OpenFL's own
 * backbuffer pipeline, NOT DynamicResolution's frame-caching.
 *
 * Perfetto traces showed the game is GPU fill-rate bound -- the GPU is slow
 * to finish each frame, not slow to receive draw commands. DynamicResolution
 * mitigates that by skipping every other render outright; this instead makes
 * every render cheaper by shrinking how many pixels the GPU has to fill.
 *
 * This used to reach into the Android Surface directly (SurfaceHolder's
 * hardware buffer scaler, via JNI). That bypassed OpenFL/Lime's own resize
 * pipeline entirely, so Stage.__resize() -- the one place that recomputes
 * both Context3D's backbuffer AND OpenGLRenderer's glViewport/projection --
 * never re-ran, leaving the GPU viewport pointed at the old, full-native
 * size while the real buffer underneath had shrunk. That mismatch is what
 * produced the "flea in the corner with black borders" result instead of a
 * clean downscale.
 *
 * window.scale is the SAME lever OpenFL already uses for HiDPI (rendering
 * MORE physical pixels than the logical stage size, on displays with a
 * device pixel ratio above 1). Scaling it below 1 asks for the opposite:
 * fewer physical pixels than the logical size. Stage.stageWidth/stageHeight
 * (and therefore FlxG's logical resolution and all touch/mouse mapping,
 * which normalizes against the View's real on-screen size, not the
 * backbuffer) stay untouched, since window.width cancels window.scale out
 * of that calculation -- only the physical backbuffer/viewport shrink.
 * Re-running Stage.__resize() then lets OpenFL's own already-correct,
 * already-shipping code do the rest: reconfigure Context3D's backbuffer and
 * recompute the renderer's glViewport/projection to match, exactly as it
 * would for a genuine HiDPI display.
 */
class RenderScale
{
	public static var currentScale(default, null):Float = 1.0;

	// The device's real window.scale (DPI factor), captured once the first
	// time apply() runs. Every later call multiplies this baseline by the
	// requested render scale rather than compounding onto whatever the
	// previous call already left window.scale at.
	static var _baseWindowScale:Float = 0;

	/**
	 * Applies a render scale factor (e.g. 0.75 for 75%). 1.0 reverts to native
	 * 1:1 rendering. Safe to call repeatedly (e.g. on every settings change).
	 */
	public static function apply(scale:Float):Void
	{
		#if android
		try
		{
			final stage = flixel.FlxG.stage;
			final window = stage.window;

			if (_baseWindowScale <= 0)
			{
				_baseWindowScale = window.scale;
			}

			@:privateAccess window.__scale = _baseWindowScale * scale;
			@:privateAccess stage.__resize();

			currentScale = scale;
			Logger.log('[RenderScale] Set to ${Std.int(scale * 100)}% '
				+ '(window.scale=${window.scale}, stage=${stage.stageWidth}x${stage.stageHeight}, '
				+ 'FlxG=${flixel.FlxG.width}x${flixel.FlxG.height})', NOTICE);
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScale] Failed to apply scale $scale: $e', WARN);
		}
		#end
	}
}
