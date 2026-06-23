package mobile.backend;

#if android
class AndroidUtils
{
	static var _keepScreenOn = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "keepScreenOn", "(Z)V");
	static var _vibrate = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "vibrate", "(I)V");
	static var _setFullscreen = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "setFullscreen", "(I)V");
	static var _getFullscreen = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "getFullscreen", "()I");
	static var _toggleFullscreen = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "toggleFullscreen", "()V");

	public static inline function keepScreenOn(enable:Bool):Void _keepScreenOn([enable]);

	public static function vibrate(ms:Int = 12):Void
	{
		try { _vibrate([ms]); }
		catch (e:Dynamic) { trace("Vibrate error: " + e); }
	}

	/**
	 * Sets fullscreen/immersive mode.
	 * mode: 0=off (normal), 1=hide status bar, 2=full immersive (hide both bars)
	 */
	public static function setFullscreen(mode:Int):Void
	{
		try { _setFullscreen([mode]); }
		catch (e:Dynamic) { trace("setFullscreen error: " + e); }
	}

	/**
	 * Gets current fullscreen mode.
	 * Returns: 0=off, 1=status bar only, 2=full immersive
	 */
	public static function getFullscreen():Int
	{
		try { return _getFullscreen([]); }
		catch (e:Dynamic) { return 0; }
	}

	/**
	 * Toggles between fullscreen and normal mode.
	 */
	public static function toggleFullscreen():Void
	{
		try { _toggleFullscreen([]); }
		catch (e:Dynamic) { trace("toggleFullscreen error: " + e); }
	}
}
#end
