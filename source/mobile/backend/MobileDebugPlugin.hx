package mobile.backend;

#if mobile
import funkin.backend.DebugDisplay;
import funkin.data.ClientPrefs;

/**
 * Registers a DebugDisplay plugin that shows mobile-specific runtime info
 * (input mode, nav mode, safe-area insets) in ADVANCED FPS overlay mode.
 */
class MobileDebugPlugin
{
	static var _registered:Bool = false;

	public static function register():Void
	{
		if (_registered) return;
		_registered = true;
		DebugDisplay.addPlugin(getInfo);
	}

	static function getInfo():String
	{
		var game = ClientPrefs.gameInputMode;
		if (game == 'Hitbox') game += ' (${ClientPrefs.hitboxLayout})';

		var safe = mobile.backend.ScreenUtil.safeArea();
		var safeStr = 'T:${Std.int(safe.top)} L:${Std.int(safe.left)} R:${Std.int(safe.right)} B:${Std.int(safe.bottom)}';

		return 'Input: $game | Nav: ${ClientPrefs.navInputMode}\nSafe[$safeStr]';
	}
}
#end
