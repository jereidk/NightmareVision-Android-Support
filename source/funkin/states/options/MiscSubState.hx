package funkin.states.options;

using StringTools;

class MiscSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'misc';
		rpcTitle = 'Miscellaneous Menu'; // for Discord Rich Presence
		
		var option:Option = new Option(Lang.str('opt_splashscreen', 'NMV Splash Screen'),
			Lang.str('opt_splashscreen_desc', "If unchecked, it will completely skip the splash screen upon the engine's boot up."), 'toggleSplashScreen', 'bool', true);
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_devmode', 'Dev Mode'), Lang.str('opt_devmode_desc', "If checked, traces & developer hotkeys will become available."), 'inDevMode', 'bool', true);
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_streamedsongfiles', 'Streamed Song files'),
			Lang.str('opt_streamedsongfiles_desc',
				'If checked, playable song files will be streamed via bytes instead of being loaded all at once. This heavily improves loading times, however it is EXTREMELY EXPERIMENTAL and prone to issues.'),
			'streamedMusic', 'bool', false);
		addOption(option);
		
		var pause:Option = new Option(Lang.str('opt_autopause', 'Auto-Pause Game'),
			Lang.str('opt_autopause_desc',
				'If checked, the game will automatically freeze when unselected, pausing all sounds and visuals. If unchecked, the game will continue as normal regardless of focus.'),
			'autoPause', 'bool', false);
		pause.onChange = () -> {
			FlxG.autoPause = ClientPrefs.autoPause;
		};
		addOption(pause);
		
		super();
	}
}
