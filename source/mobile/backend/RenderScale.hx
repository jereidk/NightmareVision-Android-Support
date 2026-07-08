package mobile.backend;

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * True render-resolution scaling via Android's hardware surface scaler
 * (SurfaceHolder.setFixedSize), NOT DynamicResolution's frame-caching.
 *
 * Perfetto traces showed the game is GPU fill-rate bound -- the GPU is slow
 * to finish each frame, not slow to receive draw commands (RenderThread
 * itself was nearly idle). DynamicResolution mitigates that by skipping
 * every other render outright; this instead makes every render cheaper by
 * shrinking how many pixels the GPU has to fill, at effectively no extra
 * cost -- SurfaceFlinger already scales the buffer up to the View's real
 * on-screen size during composition, a hardware operation it performs every
 * frame regardless of whether we ask for a smaller buffer.
 *
 * Requires the SDLActivity/SDLSurface patches applied at build time (see
 * .github/scripts/patch-lime-sdlactivity-renderscale.py and
 * patch-lime-sdlsurface-touch-normalize.py) -- the second one is what keeps
 * touch input aligned to the screen once the buffer is smaller than the View.
 */
class RenderScale
{
	#if android
	static var _setBufferSize = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "setRenderBufferSize", "(II)V");
	static var _resetBufferSize = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "resetRenderBufferSize", "()V");
	#end

	public static var currentScale(default, null):Float = 1.0;

	/**
	 * Applies a render scale factor (e.g. 0.75 for 75%). 1.0 reverts to native
	 * 1:1 rendering. Safe to call repeatedly (e.g. on every settings change).
	 */
	public static function apply(scale:Float):Void
	{
		#if android
		try
		{
			if (scale >= 0.999)
			{
				_resetBufferSize([]);
				currentScale = 1.0;
				Logger.log('[RenderScale] Reset to native 1:1', NOTICE);
			}
			else
			{
				final w = Std.int(flixel.FlxG.stage.window.width * scale);
				final h = Std.int(flixel.FlxG.stage.window.height * scale);
				_setBufferSize([w, h]);
				currentScale = scale;
				Logger.log('[RenderScale] Set to ${Std.int(scale * 100)}% (${w}x${h})', NOTICE);
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScale] Failed to apply scale $scale: $e', WARN);
		}
		#end
	}
}
