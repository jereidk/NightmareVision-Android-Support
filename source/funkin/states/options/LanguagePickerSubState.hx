package funkin.states.options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import funkin.objects.menu.TouchOptionList;
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

	var list:TouchOptionList;
	var closeButton:FlxSprite;

	override function create():Void
	{
		final cutout = funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;

		var dim = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xE60A0A14);
		add(dim);

		var title = new FlxText(40 + cutout * 0.5, 20, 0, Lang.str('opt_choose_language', 'Choose your language'), 42);
		title.setFormat(Paths.font('AmaticSC-Bold.ttf'), 40, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.antialiasing = ClientPrefs.globalAntialiasing;
		add(title);

		closeButton = new FlxSprite(1100 + cutout, 20).loadGraphic(Paths.image('menu/common/menuBack'));
		closeButton.antialiasing = ClientPrefs.globalAntialiasing;
		add(closeButton);

		final listW = (1160 + cutout) - LIST_X;
		list = new TouchOptionList(LIST_X, 100, listW, 9);
		add(list);

		// Lands already scrolled to (and with) the current language
		// selected -- so opening this to double-check what's active doesn't
		// mean scrolling past everything before it every time.
		final opts = LanguageOptions.build();
		list.setOptions(opts, LanguageOptions.currentLanguageRowIndex >= 0 ? LanguageOptions.currentLanguageRowIndex : null);

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

	/** Rebuilds the list in place (fresh badges/current-language marker) right after a language switch, called from OptionsState.refreshLanguageTabInPlace(). */
	public function refreshInPlace():Void
	{
		list.setOptions(LanguageOptions.build(), list.curSelected);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		list.keyboardEnabled = true;

		// Virtual Pad nav mode suppresses direct touch/mouse interaction on
		// every other options screen (see MobileSettingsSubState/OptionsState)
		// -- gate this the same way, since on a touchscreen device (where
		// taps ARE mouse events) an accidental tap near it while using the
		// pad would otherwise still instantly close this screen.
		if (MobileNavUtil.allowPointerNav() && FlxG.mouse.justPressed && FlxG.mouse.overlaps(closeButton))
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
		}
	}
}
