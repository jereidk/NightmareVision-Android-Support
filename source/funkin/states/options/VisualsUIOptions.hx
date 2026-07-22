package funkin.states.options;

/**
 * Builds the "Visuals and UI" category's option list -- purely how the
 * on-screen interface itself looks (HUD elements, the debug overlay,
 * photosensitivity), not gameplay-affecting note visuals. Those (Opponent
 * Notes, Note Splashes, Lane Underlay, Quants, etc.) moved to
 * GameplayOptions.hx's NOTES section -- they change what you're reacting to,
 * not just how the screen looks, so they belong with Downscroll/Ghost
 * Tapping rather than next to Hide HUD.
 *
 * The old per-screen version needed a hand-built "split underlay" hack to
 * visually separate the NOTES section, plus overrides on
 * selectOption()/changeSelection() to skip over the label row --
 * TouchOptionList treats 'label' options as non-selectable section headers
 * natively, so none of that survives here.
 */
class VisualsUIOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		opts.push(new Option(Lang.str('opt_category_hud', 'HUD').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_hidehud', 'Hide HUD'), Lang.str('opt_hidehud_desc', 'If checked, hides most HUD elements.'), 'hideHud', 'bool', false));

		// defaultValue was 'Time Left' (inherited from upstream) --
		// ClientPrefs.timeBarType's own declared default is 'Song Name', so
		// Reset to Default here switched the Time Bar to a different display
		// than what a fresh install/reset actually starts with.
		opts.push(new Option(Lang.str('opt_timebar', 'Time Bar:'), Lang.str('opt_timebar_desc', "What should the Time Bar display?"), 'timeBarType', 'string', 'Song Name',
			[Lang.str('choice_timebar_timeleft',
				'Time Left'), Lang.str('choice_timebar_timeelapsed', 'Time Elapsed'), Lang.str('choice_timebar_songname', 'Song Name'), Lang.str('choice_generic_disabled', 'Disabled')],
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']));

		opts.push(new Option(Lang.str('opt_hudrankdisplay', 'HUD Rank Display:'), Lang.str('opt_hudrankdisplay_desc', "What should be displayed on the HUD?"), 'hudRankDisplay', 'string',
			'Both', [Lang.str('choice_scoredisplay_both', 'Both'), Lang.str('choice_scoredisplay_accuracy', 'Accuracy'), Lang.str('choice_scoredisplay_rank', 'Rank')], ['Both', 'Accuracy', 'Rank']));

		// 'Enabled DX' is a real third value -- assets/legacy/scripts/utils.hx
		// checks for it explicitly (tints the rating popup graphic and combo
		// digits to match the score text's color, on top of the base
		// 'Enabled' coloring) but it was never exposed as a pickable choice
		// here, in this port OR upstream. Confirmed upstream has the exact
		// same 2-choice option next to the exact same 3-value check in its
		// own utils.hx, so this wasn't a porting regression -- just an old
		// mode that lost its menu entry at some point and was never wired
		// back up. Adding the third choice here restores it without
		// touching storedValues' existing 'Enabled'/'Disabled' strings, so
		// anyone with either already saved keeps working exactly as before.
		opts.push(new Option(Lang.str('opt_coloredui', 'Colored UI:'),
			Lang.str('opt_coloredui_desc', "Colors UI elements based on the opponent's icon color.\nDX also tints the rating popup and combo digits to match.\n(Some colors might be hard to read.)"), 'colorText', 'string', 'Enabled',
			[Lang.str('choice_generic_enabled', 'Enabled'), Lang.str('choice_coloredui_enableddx', 'Enabled (DX)'), Lang.str('choice_generic_disabled', 'Disabled')], ['Enabled', 'Enabled DX', 'Disabled']));

		opts.push(new Option(Lang.str('opt_category_display', 'Display').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_debugdisplaytype', 'Debug Display Type'),
			Lang.str('opt_debugdisplaytype_desc',
				'Handles what type of information to display in the top left of your screen.\nSimple shows FPS & Memory. Advanced adds debug info.\nDisabled hides it entirely.'),
			'fpsDisplayType', 'string', 'Simple',
			[Lang.str('choice_debug_simple', 'Simple'), Lang.str('choice_debug_advanced', 'Advanced'), Lang.str('choice_debug_memory', 'Memory'), Lang.str('choice_generic_disabled', 'Disabled')],
			['Simple', 'Advanced', 'Memory', 'Disabled']));

		opts.push(new Option(Lang.str('opt_fpsrgb', 'Animate FPS Color (RGB)'),
			Lang.str('opt_fpsrgb_desc', 'Cycles the FPS counter color through the rainbow.\nWorks with both Simple and Advanced display modes.'),
			'fpsRGB', 'bool', false));

		opts.push(new Option(Lang.str('opt_category_accessibility', 'Accessibility').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_photosensitivemode', 'Photosensitive Mode'),
			Lang.str('opt_photosensitivemode_desc', "If checked, flashing lights and other imagery that may affect photosensitive individuals will be disabled."), 'photosensitive', 'bool', true));

		return opts;
	}
}
