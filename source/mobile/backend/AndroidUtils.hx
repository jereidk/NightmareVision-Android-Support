package mobile.backend;

#if android
class AndroidUtils
{
	static var _keepScreenOn = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "keepScreenOn", "(Z)V");
	static var _vibrate = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "vibrate", "(I)V");

	public static inline function keepScreenOn(enable:Bool):Void _keepScreenOn([enable]);

	static var _vibrateWorks:Bool = true;

	public static function vibrate(ms:Int = 12):Void
	{
		if (!_vibrateWorks) return;
		try { _vibrate([ms]); }
		catch (e:Dynamic) {
			trace("Vibrate error: " + e);
			_vibrateWorks = false;
		}
	}
}
#end
