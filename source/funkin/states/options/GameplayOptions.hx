package funkin.states.options;

/** Builds the "Gameplay" category's option list. Pure data, see GraphicsOptions.hx. */
class GameplayOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		opts.push(new Option(Lang.str('opt_downscroll', 'Downscroll'),
			Lang.str('opt_downscroll_desc', 'If checked, notes go Down instead of Up, simple enough.'), 'downScroll', 'bool', false));

		// Was "it dcroll middle" -- garbled leftover placeholder text, not an actual description.
		opts.push(new Option(Lang.str('opt_middlescroll', 'Middlescroll'), Lang.str('opt_middlescroll_desc', "If checked, centers your notes instead of splitting them to the sides."), 'middleScroll', 'bool', false));

		opts.push(new Option(Lang.str('opt_ghosttapping', 'Ghost Tapping'),
			Lang.str('opt_ghosttapping_desc', "If checked, you won't get misses from pressing keys\nwhile there are no notes able to be hit."), 'ghostTapping', 'bool', true));

		opts.push(new Option(Lang.str('opt_disableresetbutton', 'Disable Reset Button'), Lang.str('opt_disableresetbutton_desc', "If checked, pressing Reset won't do anything."),
			'noReset', 'bool', false));

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
