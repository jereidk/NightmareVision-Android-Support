package mobile.backend;

#if android
class AndroidUtils
{
	static var _keepScreenOn = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "keepScreenOn", "(Z)V");
	static var _vibrate = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "vibrate", "(I)V");

	public static inline function keepScreenOn(enable:Bool):Void _keepScreenOn([enable]);

	public static inline function vibrate(ms:Int = 12):Void _vibrate([ms]);
}
#end
