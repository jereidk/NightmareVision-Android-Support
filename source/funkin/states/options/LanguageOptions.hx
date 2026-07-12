package funkin.states.options;

/**
 * Builds the "Language" category's option list. The old per-screen version
 * had to override the display text at runtime (Lang.current.name) because
 * Lang.getAvailableLanguages() returns raw locale codes ('english', 'spanish'),
 * not pretty names -- this resolves each language's own self-declared name
 * once up front instead, via the same 'string' Option convention every other
 * choice list already uses (options = what's shown, storedValues = what's
 * saved), so no special-casing is needed in TouchOptionList at all.
 */
class LanguageOptions
{
	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];

		final codes = Lang.getAvailableLanguages();
		final displayNames = [for (code in codes) (Lang.loadLang(code)?.name ?? code)];

		final langOption = new Option(Lang.str('opt_language', 'Language'),
			Lang.str('opt_language_desc', 'Choose your language! Note: All languages besides English (United States) are community translated!'), 'language', 'string', 'english',
			displayNames, codes);
		opts.push(langOption);

		// Cycling one arrow-tap at a time through 30+ languages is painful --
		// this opens a scrollable, alphabetical, tap-to-pick list instead.
		final findLangOption = new Option(Lang.str('opt_language_find', 'Find Your Language...'),
			Lang.str('opt_language_find_desc', "Browse every installed language and pick yours directly, instead of cycling through them one by one."), '', 'button');
		findLangOption.callback = () -> {
			if (OptionsState.instance != null)
			{
				// 'mobile'/'dlc'/'credits' all open via openSelectedSubstate(), which
				// sets blockInput = true so OptionsState's own tab/button/reset-icon
				// mouse handling in update() goes quiet while that substate covers
				// the screen. This bypasses openSelectedSubstate() (it needs its own
				// constructor args), so it never set that flag -- OptionsState kept
				// running underneath (persistentUpdate = true) with its tab row
				// still fully clickable, and the picker's own list sits in roughly
				// the same screen area, so a tap meant for a language row could
				// silently change the hidden tab underneath instead.
				OptionsState.instance.blockInput = true;
				OptionsState.instance.openSubState(new LanguagePickerSubState(codes, displayNames, (pickedCode) -> {
					langOption.curOption = codes.indexOf(pickedCode);
					langOption.setValue(pickedCode);
					langOption.change();
				}));
			}
		};
		opts.push(findLangOption);

		final creditsOption = new Option('', '', '', 'label');
		opts.push(creditsOption);

		function refreshCredits()
		{
			final tc:String = Lang.current?.translationCredits ?? '';
			creditsOption.name = (tc.length > 0) ? 'Localization Credits: $tc' : '';
		}

		langOption.onChange = () -> {
			Lang.reloadLangFile();
			refreshCredits();
		};
		refreshCredits();

		// Was "it ubtitle" -- garbled leftover placeholder text, not an actual description.
		opts.push(new Option(Lang.str('opt_subtitles', 'Subtitles'), Lang.str('opt_subtitles_desc', "Show subtitles for songs that have them."), 'subtitles', 'bool', true));

		return opts;
	}
}
