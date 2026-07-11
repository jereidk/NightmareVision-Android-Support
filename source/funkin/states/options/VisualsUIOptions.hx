package funkin.states.options;

/**
 * Builds the "Visuals and UI" category's option list. The old per-screen
 * version needed a hand-built "split underlay" hack to visually separate the
 * NOTES section, plus overrides on selectOption()/changeSelection() to skip
 * over the label row -- TouchOptionList treats 'label' options as
 * non-selectable section headers natively, so none of that survives here.
 */
class VisualsUIOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		opts.push(new Option(Lang.str('opt_hidehud', 'Hide HUD'), Lang.str('opt_hidehud_desc', 'If checked, hides most HUD elements.'), 'hideHud', 'bool', false));

		opts.push(new Option(Lang.str('opt_timebar', 'Time Bar:'), Lang.str('opt_timebar_desc', "What should the Time Bar display?"), 'timeBarType', 'string', 'Time Left',
			[Lang.str('choice_timebar_timeleft',
				'Time Left'), Lang.str('choice_timebar_timeelapsed', 'Time Elapsed'), Lang.str('choice_timebar_songname', 'Song Name'), Lang.str('choice_generic_disabled', 'Disabled')],
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']));

		opts.push(new Option(Lang.str('opt_hudrankdisplay', 'HUD Rank Display:'), Lang.str('opt_hudrankdisplay_desc', "What should be displayed on the HUD?"), 'hudRankDisplay', 'string',
			'Both', [Lang.str('choice_scoredisplay_both', 'Both'), Lang.str('choice_scoredisplay_accuracy', 'Accuracy'), Lang.str('choice_scoredisplay_rank', 'Rank')], ['Both', 'Accuracy', 'Rank']));

		opts.push(new Option(Lang.str('opt_coloredui', 'Colored UI:'),
			Lang.str('opt_coloredui_desc', "Colors UI elements based on the opponent's icon color.\n(Some colors might be hard to read.)"), 'colorText', 'string', 'Enabled',
			[Lang.str('choice_generic_enabled', 'Enabled'), Lang.str('choice_generic_disabled', 'Disabled')], ['Enabled', 'Disabled']));

		opts.push(new Option(Lang.str('opt_photosensitivemode', 'Photosensitive Mode'),
			Lang.str('opt_photosensitivemode_desc', "If checked, flashing lights and other imagery that may affect photosensitive individuals will be disabled."), 'photosensitive', 'bool', true));

		opts.push(new Option(Lang.str('opt_camerazooms', 'Camera Zooms'), Lang.str('opt_camerazooms_desc', "Allows camera to zoom in on a beat hit. Uncheck to disable."), 'camZooms',
			'bool', true));

		opts.push(new Option(Lang.str('opt_scoretextzoom', 'Score Text Zoom on Hit'),
			Lang.str('opt_scoretextzoom_desc', "If unchecked, disables the Score text zooming\neverytime you hit a note."), 'scoreZoom', 'bool', true));

		opts.push(new Option(Lang.str('opt_afterimages', 'Afterimages'), Lang.str('opt_afterimages_desc', "Characters will leave afterimages on double notes. Uncheck to disable."),
			'jumpGhosts', 'bool', true));

		opts.push(new Option(Lang.str('opt_category_notes', 'NOTES').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_quants', 'Quants Enabled'), Lang.str('opt_quants_desc', 'Colors notes in-game based on their step value. Helpful for timing your note hits.'),
			'quants', 'bool', false));

		opts.push(new Option(Lang.str('opt_notesplashes', 'Note Splashes'), Lang.str('opt_notesplashes_desc', "If unchecked, hitting \"Sick!\" or \"Kutty!\" notes won't show particles."),
			'noteSplashes', 'bool', true));

		opts.push(new Option(Lang.str('opt_opponentnotes', 'Opponent Notes'), Lang.str('opt_opponentnotes_desc', 'If unchecked, opponent notes get hidden.'), 'opponentStrums', 'bool', true));

		final laneUnderlayOption = new Option(Lang.str('opt_laneunderlay', 'Lane Underlay'), Lang.str('opt_laneunderlay_desc', 'Adds a semi-transparent background behind the notes.'),
			'laneUnderlayAlpha', 'percent', 0);
		laneUnderlayOption.scrollSpeed = 1.6;
		laneUnderlayOption.minValue = 0.0;
		laneUnderlayOption.maxValue = 1;
		laneUnderlayOption.changeValue = 0.1;
		laneUnderlayOption.decimals = 1;
		opts.push(laneUnderlayOption);

		opts.push(new Option(Lang.str('opt_laneUnderlayStyle'), Lang.str('opt_laneUnderlayStyle_desc'), 'laneUnderlayStyle', 'string', 'A', [
				Lang.str('choice_laneUnderlayStyle_a'), Lang.str('choice_laneUnderlayStyle_b'), Lang.str('choice_laneUnderlayStyle_c'), Lang.str('choice_laneUnderlayStyle_d')
			], ['A', 'B', 'C', 'D']));

		opts.push(new Option(Lang.str('opt_opponentLaneUnderlay'), Lang.str('opt_opponentLaneUnderlay_desc'), 'opponentLaneUnderlay', 'bool', true));

		return opts;
	}
}
