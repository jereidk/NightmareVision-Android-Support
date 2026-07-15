package funkin.states.options;

import mobile.backend.LangFontPacks;
import mobile.backend.DLCManager;
import mobile.backend.DLCManager.DLCTaskState;

/**
 * Builds the "Language" category's option list -- and, since this tab
 * already has its own dedicated screen area in OptionsState, IS the
 * language browser itself (no separate substate/window). Absorbs what used
 * to be LanguagePickerSubState's alphabetized, tap-to-pick, A-Z-sectioned
 * list directly into this tab's own Array<Option>, plus per-row awareness
 * of LangFontPacks (Korean/Japanese/Chinese need a separate font-pack
 * download -- see that file's own doc comment) via Option.badgeProvider,
 * so a downloadable-but-not-installed language shows its size/download
 * progress right on its own row instead of silently downloading with zero
 * UI feedback.
 */
class LanguageOptions
{
	/**
	 * Index of the current-language row within the array `build()` just
	 * returned, so OptionsState.changeTab() can reproduce the old picker's
	 * "opens pre-scrolled to your current language" behaviour on a genuine
	 * tab switch. NOT used by OptionsState.refreshOptionFonts() (that one
	 * must keep using optionList.curSelected) -- see that function's own
	 * comment for why.
	 */
	public static var currentLanguageRowIndex(default, null):Int = -1;

	public static function build():Array<Option>
	{
		final opts:Array<Option> = [];
		currentLanguageRowIndex = -1;

		// Subtitles + credits at the top -- with 30+ language rows now
		// inline below, leaving them at the bottom (where the old 4-row
		// list had them) would bury a frequently-toggled, unrelated setting
		// behind a full scroll of the alphabet.
		opts.push(new Option(Lang.str('opt_subtitles', 'Subtitles'),
			Lang.str('opt_subtitles_desc', "Show subtitles for songs that have them."), 'subtitles', 'bool', true));

		final creditsOption = new Option('', '', '', 'label');
		opts.push(creditsOption);

		function refreshCredits()
		{
			final tc:String = Lang.current?.translationCredits ?? '';
			creditsOption.name = (tc.length > 0) ? 'Localization Credits: $tc' : '';
		}
		refreshCredits();

		final codes = Lang.getAvailableLanguages();
		final displayNames = [for (code in codes) (Lang.loadLang(code)?.name ?? code)];
		final entries = [for (i in 0...codes.length) {code: codes[i], name: displayNames[i]}];
		entries.sort((a, b) -> a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0));

		// A/B/C... section headers -- same TouchOptionList 'label' row +
		// divider rule every other tab's list already uses for these.
		var lastLetter = '';
		for (entry in entries)
		{
			final letter = entry.name.substr(0, 1).toUpperCase();
			if (letter != lastLetter)
			{
				opts.push(new Option(letter, '', '', 'label'));
				lastLetter = letter;
			}

			if (entry.code == ClientPrefs.language) currentLanguageRowIndex = opts.length;

			final opt = new Option(entry.name, '', '', 'button');
			final pack = LangFontPacks.getPack(entry.code);

			if (entry.code == ClientPrefs.language)
			{
				opt.badgeProvider = () -> ({text: Lang.str('opt_language_current', 'Current'), color: 0xFF22C55E} : OptionBadge);
			}
			else if (pack != null)
			{
				// Re-checked live every call (not snapshotted here at build
				// time) so this self-corrects the moment a download
				// finishes or starts, without the tab needing a rebuild.
				opt.badgeProvider = () ->
				{
					if (LangFontPacks.isDownloading(entry.code)) return ({text: 'Downloading... ${DLCManager.taskProgress}%', color: 0xFFF59E0B} : OptionBadge);
					if (!LangFontPacks.isInstalled(entry.code)) return ({text: '• ${pack.sizeMb} MB', color: 0xFF38BDF8} : OptionBadge);
					return null;
				};
			}

			opt.callback = () -> {
				// Already your language -- nothing to confirm, nothing to do.
				if (entry.code == ClientPrefs.language) return;

				// A mis-tap here (30+ small rows) instantly drops you into a
				// language you might not read, with no easy way back --
				// unlike the old arrow-cycle path, where a wrong tap was
				// just one step to undo. Confirm first, shown in whatever
				// language is still active (native Android dialog, so it
				// works identically whether nav mode is Touch or Virtual Pad).
				mobile.backend.utils.PopUp.showConfirm(Lang.str('opt_language_confirm_title', 'Change Language?'),
					Lang.str('opt_language_confirm_msg', 'Switch to this language?') + '\n\n' + entry.name,
					Lang.str('yes', 'Yes'), Lang.str('no', 'No'), () -> {
						ClientPrefs.language = entry.code;
						Lang.reloadLangFile(); // also kicks LangFontPacks.ensureDownloaded() internally, unchanged
						refreshCredits();
						if (OptionsState.instance != null) OptionsState.instance.refreshLanguageTabInPlace();
					}, null);
			};
			opts.push(opt);
		}

		return opts;
	}
}
