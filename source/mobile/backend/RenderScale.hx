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
	static var _getBufferWidth = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getSurfaceBufferWidth", "()I");
	static var _getBufferHeight = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getSurfaceBufferHeight", "()I");
	static var _getSurfaceChangedCallCount = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getSurfaceChangedCallCount", "()I");
	static var _getLastSurfaceChangedWidth = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getLastSurfaceChangedWidth", "()I");
	static var _getLastSurfaceChangedHeight = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getLastSurfaceChangedHeight", "()I");
	static var _getSurfaceViewLayoutWidth = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getSurfaceViewLayoutWidth", "()I");
	static var _getSurfaceViewLayoutHeight = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getSurfaceViewLayoutHeight", "()I");
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
				_resetBufferSize();
				currentScale = 1.0;
				Logger.log('[RenderScale] Reset to native 1:1', NOTICE);
			}
			else
			{
				final w = Std.int(flixel.FlxG.stage.window.width * scale);
				final h = Std.int(flixel.FlxG.stage.window.height * scale);
				_setBufferSize(w, h);
				currentScale = scale;
				Logger.log('[RenderScale] Set to ${Std.int(scale * 100)}% (${w}x${h})', NOTICE);
			}

			// Diagnostics: setFixedSize() only takes effect once the next
			// surfaceChanged() callback fires (async), and it resizes the surface
			// BUFFER -- not necessarily what Flixel/OpenFL think the resolution is.
			// Log both readings twice: immediately (expected to still show the OLD
			// buffer size, proving the async gap is real) and after a delay
			// (expected to show the NEW size if the OS + engine both reacted).
			logDiagnostics('immediate');
			haxe.Timer.delay(() -> logDiagnostics('+500ms'), 500);
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScale] Failed to apply scale $scale: $e', WARN);
		}
		#end
	}

	#if android
	static function logDiagnostics(when:String):Void
	{
		try
		{
			final bufW = (_getBufferWidth() : Int);
			final bufH = (_getBufferHeight() : Int);
			final callCount = (_getSurfaceChangedCallCount() : Int);
			final lastW = (_getLastSurfaceChangedWidth() : Int);
			final lastH = (_getLastSurfaceChangedHeight() : Int);
			final layoutW = (_getSurfaceViewLayoutWidth() : Int);
			final layoutH = (_getSurfaceViewLayoutHeight() : Int);
			Logger.log('[RenderScale][$when] surfaceBuffer=${bufW}x${bufH} '
				+ 'surfaceChangedCalls=$callCount lastReported=${lastW}x${lastH} '
				+ 'viewLayout=${layoutW}x${layoutH} '
				+ 'FlxG=${flixel.FlxG.width}x${flixel.FlxG.height} '
				+ 'stage=${flixel.FlxG.stage.stageWidth}x${flixel.FlxG.stage.stageHeight} '
				+ 'window=${flixel.FlxG.stage.window.width}x${flixel.FlxG.stage.window.height}', NOTICE);
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScale][$when] Failed to read diagnostics: $e', WARN);
		}
	}
	#end
}
