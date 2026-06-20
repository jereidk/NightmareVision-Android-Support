package mobile.backend;

#if android
class JavaCrashHandler
{
	static var _install = JNI.createStaticMethod(
		"mobile/backend/java/JavaCrashHandler",
		"install",
		"(Ljava/lang/String;)V"
	);

	static var _readPreviousNativeCrash = JNI.createStaticMethod(
		"mobile/backend/java/JavaCrashHandler",
		"readPreviousNativeCrash",
		"()Ljava/lang/String;"
	);

	/**
	 * Install the Java-level uncaught exception handler.
	 * Call once at app startup, passing the path where crash.log should be written.
	 */
	public static function install(crashLogPath:String):Void
		_install([crashLogPath]);

	/**
	 * Read Android's ApplicationExitInfo (API 30+) for the previous session.
	 * Returns a human-readable description if the previous session ended in a
	 * crash, native signal, ANR or OOM; returns null otherwise.
	 */
	public static function readPreviousNativeCrash():Null<String>
		return _readPreviousNativeCrash([]);
}
#end
