package funkin.states.options;

/**
 * Builds the "Gameplay" category's option list. Pure data, see GraphicsOptions.hx.
 *
 * Holds everything that changes what you're reacting to or how you interact
 * with it -- scroll direction, note visibility/appearance, hit rules, camera
 * feel, hitsounds. Previously split across this file and VisualsUIOptions.hx
 * with no clear line between them (e.g. Opponent Notes and Lane Underlay,
 * which change actual gameplay, used to live in "Visuals and UI" next to
 * Hide HUD); VisualsUIOptions.hx is now reserved for how the interface
 * itself looks (HUD layout, debug overlay, photosensitivity), not gameplay.
 */
class GameplayOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		opts.push(new Option(Lang.str('opt_category_scroll', 'Scroll').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_downscroll', 'Downscroll'),
			Lang.str('opt_downscroll_desc', 'If checked, notes go Down instead of Up, simple enough.'), 'downScroll', 'bool', false));

		// VSlice always shows both strumlines side by side at fixed positions
		// (see StrumNote.getCenteredXPos()) -- middleScroll's "collapse to the
		// middle, hide the opponent" behaviour has nothing to apply to there,
		// so the option is hidden entirely instead of showing a toggle that
		// silently does nothing (PlayState.hx also ignores the stored value
		// while VSlice is active, in case it was left on from Normal layout).
		if (ClientPrefs.noteLayout != 'VSlice')
		{
			// Was "it dcroll middle" -- garbled leftover placeholder text, not an actual description.
			opts.push(new Option(Lang.str('opt_middlescroll', 'Middlescroll'), Lang.str('opt_middlescroll_desc', "If checked, centers your notes instead of splitting them to the sides."), 'middleScroll', 'bool', false));
		}

		opts.push(new Option(Lang.str('opt_category_notes', 'Notes').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_opponentnotes', 'Opponent Notes'), Lang.str('opt_opponentnotes_desc', 'If unchecked, opponent notes get hidden.'), 'opponentStrums', 'bool', true));

		opts.push(new Option(Lang.str('opt_notesplashes', 'Note Splashes'), Lang.str('opt_notesplashes_desc', "If unchecked, hitting \"Sick!\" or \"Kutty!\" notes won't show particles."),
			'noteSplashes', 'bool', true));

		opts.push(new Option(Lang.str('opt_quants', 'Quants Enabled'), Lang.str('opt_quants_desc', 'Colors notes in-game based on their step value. Helpful for timing your note hits.'),
			'quants', 'bool', false));

		// NotesSubState/QuantNotesSubState had no menu entry point anywhere in
		// the codebase -- these two buttons are the only way to reach them.
		final noteColorsOption = new Option(Lang.str('opt_notecolors', 'Note Colors...'),
			Lang.str('opt_notecolors_desc', "Customize the hue, saturation, and brightness of each of the four notes."), '', 'button');
		noteColorsOption.callback = () -> {
			if (OptionsState.instance != null) OptionsState.instance.openSubState(new NotesSubState());
		};
		opts.push(noteColorsOption);

		final quantColorsOption = new Option(Lang.str('opt_quantcolors', 'Quant Colors...'),
			Lang.str('opt_quantcolors_desc', "Customize note colors per timing quantization. Only visible in-game while Quants Enabled is on."), '', 'button');
		quantColorsOption.callback = () -> {
			if (OptionsState.instance != null) OptionsState.instance.openSubState(new QuantNotesSubState());
		};
		opts.push(quantColorsOption);

		final laneUnderlayOption = new Option(Lang.str('opt_laneunderlay', 'Lane Underlay'), Lang.str('opt_laneunderlay_desc', 'Adds a semi-transparent background behind the notes.'),
			'laneUnderlayAlpha', 'percent', 0);
		laneUnderlayOption.scrollSpeed = 1.6;
		laneUnderlayOption.minValue = 0.0;
		laneUnderlayOption.maxValue = 1;
		laneUnderlayOption.changeValue = 0.1;
		laneUnderlayOption.decimals = 1;
		opts.push(laneUnderlayOption);

		// These 6 keys were called without the English fallback default every
		// other Option in this codebase provides -- Lang.str() renders
		// '<MISSING_key>' literally on screen if a key is ever missing from
		// both the current and fallback language files (see Lang.hx), so this
		// silently relied on english.json never losing these specific
		// entries instead of being self-contained like everything else.
		opts.push(new Option(Lang.str('opt_laneUnderlayStyle', 'Lane Underlay Style'), Lang.str('opt_laneUnderlayStyle_desc', 'Changes the appearance or layering of the lane underlay(s).'), 'laneUnderlayStyle', 'string', 'A', [
				Lang.str('choice_laneUnderlayStyle_a', 'Over Score Text'), Lang.str('choice_laneUnderlayStyle_b', 'Behind Score Text'), Lang.str('choice_laneUnderlayStyle_c', 'Behind Health Bar'), Lang.str('choice_laneUnderlayStyle_d', 'Fade')
			], ['A', 'B', 'C', 'D']));

		opts.push(new Option(Lang.str('opt_opponentLaneUnderlay', 'Opponent Lane Underlay'), Lang.str('opt_opponentLaneUnderlay_desc', "Shows the lane underlay behind the opponent's notes."), 'opponentLaneUnderlay', 'bool', true));

		opts.push(new Option(Lang.str('opt_category_rules', 'Rules').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_ghosttapping', 'Ghost Tapping'),
			Lang.str('opt_ghosttapping_desc', "If checked, you won't get misses from pressing keys\nwhile there are no notes able to be hit."), 'ghostTapping', 'bool', true));

		opts.push(new Option(Lang.str('opt_disableresetbutton', 'Disable Reset Button'), Lang.str('opt_disableresetbutton_desc', "If checked, pressing Reset won't do anything."),
			'noReset', 'bool', false));

		opts.push(new Option(Lang.str('opt_category_feel', 'Feel').toUpperCase(), '', '', 'label'));

		opts.push(new Option(Lang.str('opt_camerazooms', 'Camera Zooms'), Lang.str('opt_camerazooms_desc', "Allows camera to zoom in on a beat hit. Uncheck to disable."), 'camZooms',
			'bool', true));

		opts.push(new Option(Lang.str('opt_scoretextzoom', 'Score Text Zoom on Hit'),
			Lang.str('opt_scoretextzoom_desc', "If unchecked, disables the Score text zooming\neverytime you hit a note."), 'scoreZoom', 'bool', true));

		opts.push(new Option(Lang.str('opt_afterimages', 'Afterimages'), Lang.str('opt_afterimages_desc', "Characters will leave afterimages on double notes. Uncheck to disable."),
			'jumpGhosts', 'bool', true));

		opts.push(new Option(Lang.str('opt_category_audio', 'Audio').toUpperCase(), '', '', 'label'));

		// Was "stupdi ass description bro" -- placeholder joke text, not an actual description.
		final hitsoundOption = new Option(Lang.str('opt_hitsoundvolume', 'Hitsound Volume'), Lang.str('opt_hitsoundvolume_desc', 'Volume of the sound played when you hit a note.'), 'hitsoundVolume', 'percent', 0);
		hitsoundOption.scrollSpeed = 1.6;
		hitsoundOption.minValue = 0.0;
		hitsoundOption.maxValue = 1;
		hitsoundOption.changeValue = 0.1;
		hitsoundOption.decimals = 1;
		hitsoundOption.onChange = () -> FunkinSound.play(Paths.sound('hitsound'), ClientPrefs.hitsoundVolume);
		opts.push(hitsoundOption);

		return opts;
	}
}
