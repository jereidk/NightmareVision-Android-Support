package mobile.backend;

#if android
/**
 * Haxe JNI bridge to JavaCrashHandler.java.
 *
 * Provides:
 *   install(path)             — installs the Java-level UncaughtExceptionHandler
 *   readPreviousNativeCrash() — reads Android ApplicationExitInfo for the last
 *                               session's abnormal exit (API 30+), null if none
 *
 * JNI method handles are created lazily on first use instead of at class-load
 * time, so a missing Java class or wrong signature fails gracefully rather than
 * crashing before any error handler is installed.
 */
class JavaCrashWrapper
{
	static var _install:Dynamic       = null;
	static var _readPrevCrash:Dynamic = null;
	static var _bound:Bool            = false;

	static function _ensureJni():Bool
	{
		if (_install != null) return true;
		try
		{
			_install       = JNI.createStaticMethod(
				"mobile/backend/java/JavaCrashHandler", "install",
				"(Ljava/lang/String;)V");
			_readPrevCrash = JNI.createStaticMethod(
				"mobile/backend/java/JavaCrashHandler", "readPreviousNativeCrash",
				"()Ljava/lang/String;");
			return true;
		}
		catch (e:Dynamic)
		{
			funkin.backend.Logger.log('JavaCrashWrapper: JNI init failed: $e', WARN);
			return false;
		}
	}

	public static function install(crashLogPath:String):Void
	{
		if (_bound) return;
		_bound = true;
		if (!_ensureJni()) return;
		try { _install([crashLogPath]); }
		catch (e:Dynamic) { funkin.backend.Logger.log('JavaCrashHandler.install failed: $e', WARN); }
	}

	/**
	 * Returns a localised summary string if the previous session exited
	 * abnormally (native crash, OOM, ANR …), or null for clean exits / API < 30.
	 */
	public static function readPreviousNativeCrash():Null<String>
	{
		if (!_ensureJni()) return null;
		try { return cast _readPrevCrash([]); }
		catch (_:Dynamic) { return null; }
	}
}
#end
