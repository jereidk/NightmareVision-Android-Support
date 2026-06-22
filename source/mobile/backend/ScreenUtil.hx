package mobile.backend;

/**
 * Reports device safe-area insets (notch / punch-hole cutouts) in HaxeFlixel
 * game coordinates. Always returns zeros on non-Android targets or devices
 * without a display cutout.
 *
 * Results are cached after the first call; call invalidate() on orientation
 * changes if needed.
 */
class ScreenUtil
{
	static var _cached:Null<{top:Float, bottom:Float, left:Float, right:Float}> = null;

	#if android
	static var _getTop    = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetTop",    "()I");
	static var _getBottom = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetBottom", "()I");
	static var _getLeft   = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetLeft",   "()I");
	static var _getRight  = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetRight",  "()I");
	#end

	/**
	 * Returns safe-area insets in game-coordinate pixels (0–720 vertical space).
	 * Cached after first call.
	 */
	public static function safeArea():{top:Float, bottom:Float, left:Float, right:Float}
	{
		if (_cached != null) return _cached;

		var top = 0.0, bottom = 0.0, left = 0.0, right = 0.0;

		#if android
		try
		{
			var stageH:Float = flixel.FlxG.stage.stageHeight;
			var stageW:Float = flixel.FlxG.stage.stageWidth;
			if (stageH > 0 && stageW > 0)
			{
				var scaleH = flixel.FlxG.height / stageH;
				var scaleW = flixel.FlxG.width  / stageW;
				top    = (_getTop([])    : Int) * scaleH;
				bottom = (_getBottom([]) : Int) * scaleH;
				left   = (_getLeft([])   : Int) * scaleW;
				right  = (_getRight([])  : Int) * scaleW;
			}
		}
		catch (_:Dynamic) {}
		#end

		_cached = {top: top, bottom: bottom, left: left, right: right};
		return _cached;
	}

	/** Discard the cached result (e.g. on orientation change). */
	public static inline function invalidate():Void _cached = null;
}
