package funkin.states.options;

#if mobile
import mobile.utils.MobileNavUtil;
#end

/**
 * Builds the "Misc" category's option list. Pure data, see GraphicsOptions.hx.
 *
 * streamedMusic/threadedPreload used to live here despite being loading-time
 * performance settings -- moved to GraphicsOptions.hx, next to the rest of
 * the performance-related options (see that file's own comment on why
 * they're not folded into the Performance Preset system).
 */
class MiscOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		opts.push(new Option(Lang.str('opt_splashscreen', 'NMV Splash Screen'),
			Lang.str('opt_splashscreen_desc', "If unchecked, it will completely skip the splash screen upon the engine's boot up."), 'toggleSplashScreen', 'bool', true));

		opts.push(new Option(Lang.str('opt_showcursor', 'Show Cursor'),
			#if mobile
			Lang.str('opt_showcursor_desc',
				'Shows or hides the mouse cursor on screen.
On mobile this also controls whether Touch navigation is available -- if the cursor is hidden, only Virtual Pad buttons respond.'),
			#else
			Lang.str('opt_showcursor_desc', 'Shows or hides the mouse cursor on screen.'),
			#end
			'showCursor', 'bool', true));
		opts[opts.length - 1].onChange = () -> {
			FlxG.mouse.visible = MobileNavUtil.shouldShowMouse();
		};

		#if mobile
		opts.push(new Option(Lang.str('opt_hidepausebtn', 'Hide Pause Button'),
			Lang.str('opt_hidepausebtn_desc', 'If checked, hides the floating pause button during songs. You can still pause with the Android back button.'),
			'hidePauseButton', 'bool', false));
		#end

		opts.push(new Option(Lang.str('opt_category_companion', 'Companion').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_shimeji', 'Desktop Companion'),
			Lang.str('opt_shimeji_desc',
				"If checked, your currently equipped pet wanders around the screen and reacts when tapped, everywhere except during an actual song.\nEquip a pet first from the Locker -- this has nothing to show without one."),
			'shimejiEnabled', 'bool', false));

		opts.push(new Option(Lang.str('opt_category_developer', 'Developer').toUpperCase(), '', '', 'label'));

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
