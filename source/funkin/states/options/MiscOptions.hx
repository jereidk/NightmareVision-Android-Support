package funkin.states.options;

/** Builds the "Misc" category's option list. Pure data, see GraphicsOptions.hx. */
class MiscOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		opts.push(new Option(Lang.str('opt_splashscreen', 'NMV Splash Screen'),
			Lang.str('opt_splashscreen_desc', "If unchecked, it will completely skip the splash screen upon the engine's boot up."), 'toggleSplashScreen', 'bool', true));

		// defaultValue was 'true' (inherited from upstream) -- ClientPrefs.
		// inDevMode's own declared default is 'false', so Reset to Default
		// here actually TURNED ON dev mode (traces + developer hotkeys)
		// instead of resetting it off.
		opts.push(new Option(Lang.str('opt_devmode', 'Dev Mode'), Lang.str('opt_devmode_desc', "If checked, traces & developer hotkeys will become available."), 'inDevMode', 'bool', false));

		// Dev-only row: the list is rebuilt every time the Options menu opens,
		// so toggling Dev Mode above makes this appear/disappear on re-entry.
		if (ClientPrefs.inDevMode)
			opts.push(new Option(Lang.str('opt_showcase', 'Showcase'),
				Lang.str('opt_showcase_desc',
					'If checked, songs autoplay like Botplay, but the mobile controls stay visible and animate with the hits, and the HUD (score included) keeps updating live. For recording clean gameplay footage.'),
				'showcaseMode', 'bool', false));

		opts.push(new Option(Lang.str('opt_streamedsongfiles', 'Streamed Song files'),
			Lang.str('opt_streamedsongfiles_desc',
				'If checked, playable song files will be streamed via bytes instead of being loaded all at once. This heavily improves loading times, however it is EXTREMELY EXPERIMENTAL and prone to issues.'),
			'streamedMusic', 'bool', false));

		opts.push(new Option(Lang.str('opt_threadedpreload', 'Background Song Preload'),
			Lang.str('opt_threadedpreload_desc',
				'If checked, the loading screen decodes the next song\'s assets on a background thread while the bar animates. If unchecked, it just waits, and PlayState loads everything itself the plain, one-at-a-time way.'),
			'threadedPreload', 'bool', true));

		final pauseOption = new Option(Lang.str('opt_autopause', 'Auto-Pause Game'),
			Lang.str('opt_autopause_desc',
				'If checked, the game will automatically freeze when unselected, pausing all sounds and visuals. If unchecked, the game will continue as normal regardless of focus.'),
			'autoPause', 'bool', false);
		pauseOption.onChange = () -> FlxG.autoPause = ClientPrefs.autoPause;
		opts.push(pauseOption);

		// ClientPrefs.discordRPC's own set_discordRPC() already reactively
		// calls DiscordClient.check() to start/stop the presence the moment
		// this changes -- Reflect.setProperty (Option.setValue()) goes
		// through that setter, not a raw field write, so no onChange hook is
		// needed here.
		opts.push(new Option(Lang.str('opt_discordrpc', 'Discord Rich Presence'),
			#if android
			Lang.str('opt_discordrpc_desc_android',
				'If checked, your current song/menu is made available as a Discord status via a local MediaSession. Requires the free "Kizzy" app installed and configured separately -- this only makes the status available for it to pick up, it cannot detect whether Kizzy is actually installed.'),
			#else
			Lang.str('opt_discordrpc_desc', 'If checked, your current song/menu is shown as your Discord status.'),
			#end
			'discordRPC', 'bool', true));

		return opts;
	}
}
