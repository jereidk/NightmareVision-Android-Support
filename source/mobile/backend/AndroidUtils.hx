package mobile.backend;

#if android
class AndroidUtils
{
	static var _keepScreenOn = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "keepScreenOn", "(Z)V");
	static var _setFullscreen = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "setFullscreen", "(I)V");
	static var _getFullscreen = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "getFullscreen", "()I");
	static var _toggleFullscreen = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "toggleFullscreen", "()V");
	static var _scanFolder = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "scanFolder", "(Ljava/lang/String;)V");
	static var _openDataFolder = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "openDataFolder", "(Ljava/lang/String;)V");
	static var _setGameplayState = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "setGameplayState", "(Z)V");
	static var _getMaxRefreshRate = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "getMaxRefreshRate", "()F");
	static var _requestHighRefreshRate = JNI.createStaticMethod("mobile/backend/java/AndroidUtils", "requestHighRefreshRate", "()V");

	// JNI.createStaticMethod() defaults useArray to false, which returns the
	// method wrapped via Reflect.makeVarArgs -- meant to be called with plain
	// positional arguments (varargs collects them into the array the native
	// side expects). Calling it with a single Array argument instead (as
	// every method below used to) makes varargs collect THAT array into a
	// second, outer one, so the native JNI call received a nested array
	// instead of the flat one it needed. Harmless for zero-arg calls (nothing
	// to marshal either way), but for anything taking a real argument, the
	// param the native side extracted from that nested array was never the
	// value being passed -- e.g. openDataFolder(String) actually received
	// something so wrong the "folder doesn't exist" toast printed a single
	// "$" instead of the real path, since it was never really getting a
	// String parameter at all.
	public static inline function keepScreenOn(enable:Bool):Void _keepScreenOn(enable);

	/**
	 * Sets fullscreen/immersive mode.
	 * mode: 0=off (normal), 1=hide status bar, 2=full immersive (hide both bars)
	 */
	public static function setFullscreen(mode:Int):Void
	{
		try { _setFullscreen(mode); }
		catch (e:Dynamic) { trace("setFullscreen error: " + e); }
	}

	/**
	 * Gets current fullscreen mode.
	 * Returns: 0=off, 1=status bar only, 2=full immersive
	 */
	public static function getFullscreen():Int
	{
		try { return _getFullscreen(); }
		catch (e:Dynamic) { return 0; }
	}

	/**
	 * Toggles between fullscreen and normal mode.
	 */
	public static function toggleFullscreen():Void
	{
		try { _toggleFullscreen(); }
		catch (e:Dynamic) { trace("toggleFullscreen error: " + e); }
	}

	/**
	 * Scans a folder using Android's MediaScanner to make it visible in file managers.
	 * This uses MediaScannerConnection.scanFile to add the folder to the media store.
	 * Similar to FunkinCrew/Funkin's "Data Folder" and ShadowEngine's approach.
	 */
	public static function scanModFolder():Void
	{
		var folderPath = StorageSystem.getDirectory();
		try { _scanFolder(folderPath); }
		catch (e:Dynamic) { trace("scanModFolder error: " + e); }
	}

	/**
	 * Opens the data folder in the system file manager.
	 * Similar to FunkinCrew/Funkin's "Open Data Folder" option.
	 * Uses Android Intent to open the folder in the user's preferred file manager.
	 */
	public static function openDataFolder():Void
	{
		var folderPath = StorageSystem.getDirectory();
		try { _openDataFolder(folderPath); }
		catch (e:Dynamic) { trace("openDataFolder error: " + e); }
	}

	/**
	 * Signals Android's GameManager what state the app is in (API 33+ only).
	 * true  → MODE_GAMEPLAY_INTERACTING (active gameplay)
	 * false → MODE_NONE (menus, pause, loading)
	 * Silent no-op on API < 33 or if the call fails.
	 */
	public static inline function setGameplayState(inGameplay:Bool):Void
	{
		try { _setGameplayState(inGameplay); }
		catch (e:Dynamic) {}
	}

	/**
	 * The highest refresh rate (Hz) any display mode the screen supports offers.
	 * Android always reports 60 here unless requestHighRefreshRate() has been
	 * called (the OS defaults to 60Hz even on 90/120Hz-capable panels until an
	 * app explicitly opts in), so call that first if you want this to reflect
	 * what the hardware can actually do.
	 */
	public static function getMaxRefreshRate():Float
	{
		try { return _getMaxRefreshRate(); }
		catch (e:Dynamic) { return 60.0; }
	}

	/**
	 * Opts the window into its highest supported display refresh rate mode.
	 * Android defaults every app to 60Hz regardless of the panel's real
	 * capability until this is requested — call once, early at startup.
	 */
	public static function requestHighRefreshRate():Void
	{
		try { _requestHighRefreshRate(); }
		catch (e:Dynamic) {}
	}
}
#end
