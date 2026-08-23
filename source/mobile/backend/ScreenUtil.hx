package mobile.backend;

import openfl.geom.Rectangle;

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * Reports device safe-area insets (notch / punch-hole cutouts) in HaxeFlixel
 * game coordinates. Always returns zeros on non-Android targets or devices
 * without a display cutout.
 *
 * Results are cached after the first call; call invalidate() on orientation
 * changes if needed.
 *
 * Follows FunkinCrew/Funkin pattern for cutout detection.
 */
class ScreenUtil
{
	static var _cached:Null<{top:Float, bottom:Float, left:Float, right:Float}> = null;

	#if android
	static var _getTop    = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetTop",    "()I");
	static var _getBottom = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetBottom", "()I");
	static var _getLeft   = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetLeft",   "()I");
	static var _getRight  = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getSafeInsetRight",  "()I");
	static var _getCutoutDimensions = JNI.createStaticMethod("mobile/backend/java/ScreenUtil", "getCutoutDimensions", "()[[F");
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
				top    = (_getTop()    : Int) * scaleH;
				bottom = (_getBottom() : Int) * scaleH;
				left   = (_getLeft()   : Int) * scaleW;
				right  = (_getRight()  : Int) * scaleW;
			}
		}
		catch (e:Dynamic) { Logger.log('ScreenUtil: Failed to get safe area insets: $e', WARN); }
		#end

		_cached = {top: top, bottom: bottom, left: left, right: right};
		return _cached;
	}

	/**
	 * Returns array of Rectangle objects representing display cutouts (notches).
	 * Follows FunkinCrew/Funkin pattern.
	 * @return Array of Rectangle, each representing a cutout's position and size.
	 */
	public static function getCutoutDimensions():Array<Rectangle>
	{
		var result:Array<Rectangle> = [];

		#if android
		try
		{
			var rawArray:Dynamic = _getCutoutDimensions();
			if (rawArray != null)
			{
				for (i in 0...Std.downcast(rawArray, Array).length)
				{
					var rectData:Array<Float> = rawArray[i];
					if (rectData != null && rectData.length >= 4)
					{
						// Scale to game coordinates
						var scaleX = flixel.FlxG.width / flixel.FlxG.stage.stageWidth;
						var scaleY = flixel.FlxG.height / flixel.FlxG.stage.stageHeight;
						result.push(new Rectangle(
							rectData[0] * scaleX,
							rectData[1] * scaleY,
							rectData[2] * scaleX,
							rectData[3] * scaleY
						));
					}
				}
			}
		}
		catch (e:Dynamic) { Logger.log('ScreenUtil: Failed to get cutout dimensions: $e', WARN); }
		#end

		return result;
	}

	/** Discard the cached result (e.g. on orientation change). */
	public static inline function invalidate():Void _cached = null;
}
