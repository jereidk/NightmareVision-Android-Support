package funkin.states.options;

import funkin.states.options.Option.OptionBadge;
import mobile.backend.LangFontPacks;
import mobile.backend.DLCManager;
import mobile.backend.DLCManager.DLCTaskState;

/**
 * Builds the "Language" category's option rows. buildTab() is the plain
 * 2-row list OptionsState's own Language tab shows (a "Choose your
 * language" button plus the Subtitles toggle); build() is the actual
 * alphabetized, tap-to-pick, A-Z-sectioned list of every installed
 * language, shown inside LanguagePickerSubState (opened by that button),
 * with per-row awareness of LangFontPacks (Korean/Japanese/Chinese need a
 * separate font-pack download -- see that file's own doc comment) via
 * Option.badgeProvider, so a downloadable-but-not-installed language shows
 * its size/download progress right on its own row instead of silently
 * downloading with zero UI feedback.
 */
class LanguageOptions
{
	/**
	 * Index of the current-language row within the array `build()` just
	 * returned, so LanguagePickerSubState can open pre-scrolled to your
	 * current language, same as it always has.
	 */
	public static var currentLanguageRowIndex(default, null):Int = -1;

	/**
	 * Current language's localization credits, formatted for display -- '' if
	 * it has none. Used to live as a 'label' row scrolling along with the
	 * rest of the A-Z list; now read directly by OptionsState.descriptionFor()
	 * to show in the desc box below the list instead, which isn't part of the
	 * list's own scroll (see that function's doc comment). Refreshed as a
	 * side effect of every build() call, same as currentLanguageRowIndex
	 * above -- in particular by refreshLanguageTabInPlace() right after a
	 * language switch, so this never goes stale.
	 */
	public static var currentCreditsText(default, null):String = '';

	/**
	 * The Language tab's own rows in OptionsState -- just two, same as
	 * every other tab's plain option list: a button that opens
	 * LanguagePickerSubState (the actual alphabetized picker, its own
	 * window/substate rather than crammed into this tab's own space), and
	 * the Subtitles toggle, back to being a normal row like it always was
	 * outside of the language tab's brief, since-reverted "booth" layout.
	 */
	public static function buildTab():Array<Option>
	{
		final opts:Array<Option> = [];

		final chooseOpt = new Option(Lang.str('opt_choose_language', 'Choose your language'),
			Lang.str('opt_choose_language_desc', 'Pick the app\'s display language from the full list.'), '', 'button');
		chooseOpt.callback = () -> {
			if (OptionsState.instance != null) OptionsState.instance.openSelectedSubstate('language');
		};
		// Live badge showing the currently active language, same mechanism
		// the per-language rows in build() below already use for download
		// status -- re-read every frame, so it self-corrects the instant a
		// switch is confirmed without this tab needing a rebuild.
		chooseOpt.badgeProvider = () -> ({text: Lang.current?.name ?? ClientPrefs.language, color: 0xFF22C55E} : OptionBadge);
		opts.push(chooseOpt);

		opts.push(new Option(Lang.str('opt_subtitles', 'Subtitles'), Lang.str('opt_subtitles_desc', 'Show subtitles for songs that have them.'),
			'subtitles', 'bool', true));

		return opts;
	}

	/**
	 * @param filter Case-insensitive substring match against each language's
	 * display name. Empty/null shows the full alphabetized list, same as
	 * before this param existed. While actively filtering, the A/B/C...
	 * section headers are skipped -- they're just noise once the list is
	 * already narrowed down to a handful of matches, and skipping them keeps
	 * the actual results in view without scrolling past unrelated rows first.
	 */
	public static function build(?filter:String):Array<Option>
	{
		final opts:Array<Option> = [];
		currentLanguageRowIndex = -1;

		final searching = filter != null && filter.length > 0;
		final needle = searching ? filter.toLowerCase() : '';

		final tc:String = Lang.current?.translationCredits ?? '';
		currentCreditsText = (tc.length > 0) ? Lang.str('opt_language_credits_label', 'Localization Credits: ') + tc : '';

		final codes = Lang.getAvailableLanguages();
		final displayNames = [for (code in codes) (Lang.loadLang(code)?.name ?? code)];
		final entries = [for (i in 0...codes.length) {code: codes[i], name: displayNames[i]}];
		entries.sort((a, b) -> a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0));

		// A/B/C... section headers -- same TouchOptionList 'label' row +
		// divider rule every other tab's list already uses for these.
		var lastLetter = '';
		var matchCount = 0;
		for (entry in entries)
		{
			if (searching && entry.name.toLowerCase().indexOf(needle) == -1) continue;
			matchCount++;

			if (!searching)
			{
				final letter = entry.name.substr(0, 1).toUpperCase();
				if (letter != lastLetter)
				{
					opts.push(new Option(letter, '', '', 'label'));
					lastLetter = letter;
				}
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
				// getInstalledDLCs() (behind isInstalled()) is now cached
				// (see DLCManager.hx) so this is cheap to call every frame
				// for every visible row -- it used to hit disk (list a
				// directory, open+parse every installed DLC's meta.json)
				// on every single one of those calls.
				opt.badgeProvider = () ->
				{
					if (LangFontPacks.isDownloading(entry.code)) return ({text: 'Downloading... ${DLCManager.taskProgress}%', color: 0xFFF59E0B} : OptionBadge);
					if (!LangFontPacks.isInstalled(entry.code)) return ({text: '• ${pack.sizeMb} MB', color: 0xFF38BDF8} : OptionBadge);
					// Downloaded but not yet the active language -- explicit
					// positive confirmation instead of silently showing no
					// badge at all, which read as "still hasn't finished
					// downloading" / "didn't notice it's there" rather than
					// "already got this one".
					return ({text: Lang.str('opt_language_downloaded', 'Downloaded'), color: 0xFF22C55E} : OptionBadge);
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
						// refreshLanguageTabInPlace() calls build() again, which
						// refreshes currentCreditsText as a side effect -- no
						// separate refresh call needed (unlike the old in-place
						// Option-mutation approach this replaced).
						if (OptionsState.instance != null) OptionsState.instance.refreshLanguageTabInPlace();
					}, null);
			};
			opts.push(opt);
		}

		if (searching && matchCount == 0)
			opts.push(new Option(Lang.str('opt_language_noresults', 'No languages match:') + ' "' + filter + '"', '', '', 'label'));

		return opts;
	}
}
