package funkin.states.options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.text.FlxInputText;
import flixel.util.FlxColor;

import funkin.objects.menu.TouchOptionList;
import funkin.states.options.OptionsTheme;
import mobile.utils.MobileNavUtil;

/**
 * Cycling the Language option one arrow-tap at a time gets painful once
 * there are 30+ translations installed -- this shows every available
 * language as its own tappable/scrollable row (alphabetical by display
 * name, same LanguageOptions.build() the tab itself used to embed directly)
 * so picking one is a single tap/select instead of N cycles.
 *
 * Opened from OptionsState's Language tab via its "Choose your language"
 * button (see LanguageOptions.buildTab()) -- this used to exist as exactly
 * this kind of separate window, got merged directly into the tab for a
 * while (fighting that tab's own tab-picker focus states for space in the
 * process), and is back to being its own substate again.
 */
class LanguagePickerSubState extends MusicBeatSubstate
{
	static final LIST_X:Float = 360;
	static final SEARCH_Y:Float = 76;
	static final SEARCH_H:Float = 44;
	static final LIST_Y:Float = SEARCH_Y + SEARCH_H + 10;
	static final LIST_MAX_VISIBLE:Int = 7;

	var list:TouchOptionList;
	var closeButton:FlxSprite;
	var searchField:FlxInputText;
	var searchClear:FlxText;
	var searchText:String = '';
	var creditsText:FlxText;

	override function create():Void
	{
		final cutout = funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;
		final listW = (1160 + cutout) - LIST_X;

		var dim = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xE60A0A14);
		add(dim);

		var title = new FlxText(40 + cutout * 0.5, 20, 0, Lang.str('opt_choose_language', 'Choose your language'), 42);
		title.setFormat(Paths.font('AmaticSC-Bold.ttf'), 40, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.antialiasing = ClientPrefs.globalAntialiasing;
		add(title);

		// Touch-only close 'X' -- its tap check below is already gated to
		// non-Virtual-Pad nav (B already closes this screen there), so skip
		// creating it entirely under Virtual Pad, same convention as every
		// other AmongUIState-style back button this session.
		#if mobile
		if (ClientPrefs.navInputMode != 'Virtual Pad')
		#end
		{
			closeButton = new FlxSprite(1100 + cutout, 20).loadGraphic(Paths.image('menu/common/menuBack'));
			closeButton.antialiasing = ClientPrefs.globalAntialiasing;
			add(closeButton);
		}

		// Search + credits footer: both existed on the old tab-embedded
		// version of this screen (before it got merged into, then reverted
		// out of, OptionsState's own Language tab) -- ported here rather than
		// dropped, since a 30+ language list is exactly where a search filter
		// and "who translated this" credits actually matter.
		searchField = new FlxInputText(LIST_X, SEARCH_Y, Std.int(listW - 56), '', 20, OptionsTheme.TEXT_HOVER, 0xFF2A2A3A);
		searchField.font = Paths.font('vcr.ttf');
		searchField.fieldBorderThickness = 2;
		searchField.fieldBorderColor = OptionsTheme.PINK_DIM;
		searchField.fieldHeight = SEARCH_H - 8;
		searchField.multiline = false;
		searchField.maxChars = 40;
		searchField.scrollFactor.set();
		add(searchField);

		searchField.onTextChange.add((text, _) -> {
			searchText = text;
			refreshResults();
		});

		// Tap to clear -- plain text glyph instead of a new icon asset, same
		// low-risk approach MobileSettingsSubState's '< BACK' button uses.
		// Touch-only, same reasoning as closeButton above -- Virtual Pad has
		// no keyboard-driven way to reach this field either.
		#if mobile
		if (ClientPrefs.navInputMode != 'Virtual Pad')
		#end
		{
			searchClear = new FlxText(LIST_X + listW - 46, SEARCH_Y, 40, 'X');
			searchClear.setFormat(Paths.font('vcr.ttf'), 20, OptionsTheme.PINK, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			searchClear.borderSize = 1.5;
			searchClear.y += Math.round((SEARCH_H - searchClear.height) * .5);
			searchClear.antialiasing = ClientPrefs.globalAntialiasing;
			searchClear.visible = false;
			add(searchClear);
		}

		list = new TouchOptionList(LIST_X, LIST_Y, listW, LIST_MAX_VISIBLE);
		add(list);

		// Lands already scrolled to (and with) the current language
		// selected -- so opening this to double-check what's active doesn't
		// mean scrolling past everything before it every time.
		final opts = LanguageOptions.build();
		list.setOptions(opts, LanguageOptions.currentLanguageRowIndex >= 0 ? LanguageOptions.currentLanguageRowIndex : null);

		// Constant footer for the whole screen, not tied to whichever row is
		// selected -- refreshed every frame in update() from
		// LanguageOptions.currentCreditsText (a side effect of build()/
		// refreshResults() above), same as it worked on the old tab version.
		creditsText = new FlxText(LIST_X, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 8, listW, '');
		creditsText.setFormat(Paths.font('vcr.ttf'), 16, 0xFF9A9AB0, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		creditsText.borderSize = 1;
		add(creditsText);

		#if mobile
		// Same convention as every other options screen (MobileSettingsSubState/
		// OptionsState/etc.): only show the virtual pad when the player's own
		// nav mode preference is 'Virtual Pad'.
		if (ClientPrefs.navInputMode == 'Virtual Pad')
		{
			addVirtualPad(LEFT_FULL, A_B);
			addVirtualPadCamera();
		}
		#end

		super.create();
	}

	function refreshResults():Void
	{
		final opts = LanguageOptions.build(searchText);
		list.setOptions(opts, searchText.length == 0 && LanguageOptions.currentLanguageRowIndex >= 0 ? LanguageOptions.currentLanguageRowIndex : null);
	}

	/** Rebuilds the list in place (fresh badges/current-language marker) right after a language switch, called from OptionsState.refreshLanguageTabInPlace(). */
	public function refreshInPlace():Void
	{
		list.setOptions(LanguageOptions.build(searchText), list.curSelected);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		list.keyboardEnabled = true;

		if (creditsText.text != LanguageOptions.currentCreditsText) creditsText.text = LanguageOptions.currentCreditsText;

		final pointerNavAllowed = MobileNavUtil.allowPointerNav();

		if (searchClear != null)
			searchClear.visible = pointerNavAllowed && searchField.hasFocus && searchText.length > 0;

		// Virtual Pad nav mode suppresses direct touch/mouse interaction on
		// every other options screen (see MobileSettingsSubState/OptionsState)
		// -- gate this the same way, since on a touchscreen device (where
		// taps ARE mouse events) an accidental tap near it while using the
		// pad would otherwise still instantly close this screen.
		if (closeButton != null && pointerNavAllowed && FlxG.mouse.justPressed && FlxG.mouse.overlaps(closeButton))
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		// Only the clear button needs handling here -- FlxInputText already
		// manages its own click-to-focus and click-away-to-unfocus.
		if (searchClear != null && pointerNavAllowed && searchClear.visible && FlxG.mouse.justPressed && FlxG.mouse.overlaps(searchClear))
		{
			searchField.text = '';
			searchText = '';
			refreshResults();
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
		}
	}
}
