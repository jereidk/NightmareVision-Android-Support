package mobile.backend;

#if android
import lime.system.JNI;

// Discord RMobile by ArkoseLabs
class AndroidRPC {
	private static var _init:Dynamic = null;
	private static var _update:Dynamic = null;
	private static var _shutdown:Dynamic = null;

	public static function initialize() {
		if (_init == null)
			_init = JNI.createStaticMethod("mobile/backend/java/KizzyHelper", "initialize", "()V");

		try {
			_init();
		} catch(e:Dynamic) {
			trace("JNI Init Error: " + e);
		}
	}

	/**
	 * @param charIcon Character key (e.g. "bf", same as `Character.healthIcon`) to
	 *   show as album art, resolved through the same lookup `HealthIcon.changeIcon()`
	 *   uses -- so it matches mods/DLC icon overrides and falls back the same way.
	 *   `null` shows the app's own launcher icon instead (KizzyHelper's own fallback
	 *   when no album art bitmap could be loaded).
	 * @param isPlaying `false` reports `PlaybackState.STATE_PAUSED` -- Kizzy's own
	 *   Media RPC polls this MediaSession independently of when we last called
	 *   update(), so leaving it on STATE_PLAYING would keep showing "still playing"
	 *   in Discord indefinitely after the player actually paused.
	 * @param positionMs Current elapsed playback position in milliseconds --
	 *   only meaningful (and only shown by Kizzy at all) while isPlaying. See
	 *   KizzyHelper.updateStatus()'s own doc comment for why this needs to be
	 *   kept reasonably fresh via repeated calls, not just set once.
	 * @param durationMs Total song length in milliseconds. 0 (the default,
	 *   used by every non-gameplay caller) disables Kizzy's progress bar.
	 */
	public static function update(title:String, artist:String, ?charIcon:String, isPlaying:Bool = true, positionMs:Float = 0, durationMs:Float = 0) {
		if (_update == null) {
			// Java-side takes `int`, not `long` ("J") -- every other JNI call in
			// this codebase passes plain 32-bit ints/floats/strings/bools, and a
			// song position/duration in milliseconds comfortably fits an Int
			// (max ~24 days), so this stays on that same already-proven path
			// instead of introducing an untested 64-bit marshalling case.
			_update = JNI.createStaticMethod("mobile/backend/java/KizzyHelper", "updateStatus", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZII)V");
		}

		try {
			_update(title, artist, resolveIconPath(charIcon), isPlaying, Std.int(positionMs), Std.int(durationMs));
		} catch(e:Dynamic) {
			trace("JNI Update Error: " + e);
		}
	}

	public static function shutdown() {
		if (_shutdown == null)
			_shutdown = JNI.createStaticMethod("mobile/backend/java/KizzyHelper", "shutdown", "()V");

		try { _shutdown(); } catch(e:Dynamic) { trace("JNI Shutdown Error: " + e); }
	}

	/**
	 * Resolves a character key to a path KizzyHelper's Java side can actually open
	 * (an absolute file path, or a path relative to the APK's own bundled assets),
	 * using the exact same lookup chain as HealthIcon.changeIcon(): icons/<char> ->
	 * legacy icons/icon-<char> -> icons/icon-placeholder. Keeps this in sync with
	 * whatever the HUD actually shows for a character, including mod/DLC overrides,
	 * instead of guessing a filename shape here independently.
	 *
	 * funkin.Paths.getPath() returns one of two shapes:
	 *  - A mod/external-storage file, as a path relative to the app's own storage
	 *    root -- the same convention funkin.FunkinAssets.getBitmapData() already
	 *    prefixes with StorageSystem.getDirectory() before handing it to
	 *    BitmapData.fromFile() on Android. Needs the same prefix here so Java's
	 *    plain `new File(path)` can find it too.
	 *  - A bundled-APK path under Paths.CORE_DIRECTORY ("assets/..."). Left as-is:
	 *    KizzyHelper.updateStatus()'s own AssetManager fallback already strips a
	 *    leading "assets/" before calling AssetManager.open(), which is the path
	 *    shape it expects (relative to the APK's assets/ root, no prefix).
	 */
	static function resolveIconPath(?charIcon:String):Null<String> {
		if (charIcon == null) return null;

		var name:String = 'icons/' + charIcon;
		if (!funkin.Paths.fileExists('images/' + name + '.png', LOOSE)) name = 'icons/icon-' + charIcon;
		if (!funkin.Paths.fileExists('images/' + name + '.png', LOOSE)) name = 'icons/icon-placeholder';

		final path = funkin.Paths.getPath('images/' + name + '.png', null, LOOSE);

		return StringTools.startsWith(path, funkin.Paths.CORE_DIRECTORY + '/')
			? path
			: StorageSystem.getDirectory() + path;
	}
}
#end
