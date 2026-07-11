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

		opts.push(new Option(Lang.str('opt_subtitles', 'Subtitles'), Lang.str('opt_subtitles_desc', "it ubtitle"), 'subtitles', 'bool', true));

		return opts;
	}
}
