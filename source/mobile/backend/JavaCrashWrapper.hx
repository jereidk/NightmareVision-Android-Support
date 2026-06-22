package mobile.backend;

#if android
/**
 * Haxe JNI bridge to JavaCrashHandler.java.
 *
 * Provides:
 *   install(path)           — installs the Java-level UncaughtExceptionHandler
 *   readPreviousNativeCrash() — reads Android ApplicationExitInfo for the last
 *                               session's abnormal exit (API 30+), null if none
 */
class JavaCrashWrapper
{
	static var _install         = JNI.createStaticMethod(
		"mobile/backend/java/JavaCrashHandler", "install", "(Ljava/lang/String;)V");

	static var _readPrevCrash   = JNI.createStaticMethod(
		"mobile/backend/java/JavaCrashHandler", "readPreviousNativeCrash", "()Ljava/lang/String;");

	static var _bound:Bool = false;

	public static function install(crashLogPath:String):Void
	{
		if (_bound) return;
		_bound = true;
		try { _install([crashLogPath]); }
		catch (e:Dynamic) { funkin.backend.Logger.log('JavaCrashHandler.install failed: $e', WARN); }
	}

	/**
	 * Returns a localised summary string if the previous session exited
	 * abnormally (native crash, OOM, ANR …), or null for clean exits / API < 30.
	 */
	public static function readPreviousNativeCrash():Null<String>
	{
		try { return cast _readPrevCrash([]); }
		catch (_:Dynamic) { return null; }
	}
}
#end
