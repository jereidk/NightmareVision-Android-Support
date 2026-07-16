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
 * name) so picking one is a single tap/select instead of N cycles.
 */
class LanguagePickerSubState extends MusicBeatSubstate
{
	static final LIST_X:Float = 360;

	var list:TouchOptionList;
	var closeButton:FlxSprite;

	var onPicked:String->Void;
	var codes:Array<String>;
	var displayNames:Array<String>;

	public function new(codes:Array<String>, displayNames:Array<String>, onPicked:String->Void)
	{
		super();
		this.codes = codes;
		this.displayNames = displayNames;
		this.onPicked = onPicked;
	}

	override function create():Void
	{
		final cutout = funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;

		var dim = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xE60A0A14);
		add(dim);

		var title = new FlxText(40 + cutout * 0.5, 20, 0, Lang.str('opt_language_find', 'Find Your Language'), 42);
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

		final entries = [for (i in 0...codes.length) {code: codes[i], name: displayNames[i]}];
		entries.sort((a, b) -> a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0));

		// A/B/C... section headers (reuses TouchOptionList's existing 'label'
		// row + divider rule, same as every other tab's section breaks) so a
		// flat wall of 30+ names is actually scannable instead of just a long
		// uniform scroll.
		final opts:Array<Option> = [];
		var lastLetter = '';
		var currentIndex = -1;
		for (entry in entries)
		{
			final letter = entry.name.substr(0, 1).toUpperCase();
			if (letter != lastLetter)
			{
				opts.push(new Option(letter, '', '', 'label'));
				lastLetter = letter;
			}

			if (entry.code == ClientPrefs.language) currentIndex = opts.length;

			final opt = new Option(entry.name, '', '', 'button');
			opt.callback = () -> {
				// Already your language -- nothing to confirm, just close.
				if (entry.code == ClientPrefs.language)
				{
					close();
					return;
				}

				// A mis-tap here (31 small rows) instantly drops you into a
				// language you might not read, with no easy way back -- unlike
				// the arrow-cycle path, where a wrong tap is just one step to
				// undo. Confirm first, shown in whatever language is still
				// active (native Android dialog, so it works identically
				// whether nav mode is Touch or Virtual Pad).
				mobile.backend.utils.PopUp.showConfirm(Lang.str('opt_language_confirm_title', 'Change Language?'),
					Lang.str('opt_language_confirm_msg', 'Switch to this language?') + '\n\n' + entry.name,
					Lang.str('yes', 'Yes'), Lang.str('no', 'No'), () -> {
						onPicked(entry.code);
						close();
					}, null);
			};
			opts.push(opt);
		}

		// Land already scrolled to (and with) your current language selected
		// -- so re-opening this to double check what's active doesn't mean
		// scrolling past everything before it every time.
		list.setOptions(opts, currentIndex >= 0 ? currentIndex : null);

		#if mobile
		// Was unconditional -- every other options screen only shows the
		// virtual pad when the user's own nav mode preference is 'Virtual
		// Pad' (see MobileSettingsSubState/OptionsState/etc.); this one
		// popped it up regardless, so a 'Touch' user picked it up here too.
		if (ClientPrefs.navInputMode == 'Virtual Pad')
		{
			addVirtualPad(LEFT_FULL, B);
			addVirtualPadCamera();
		}
		#end

		super.create();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		list.keyboardEnabled = true;

		// Virtual Pad nav mode suppresses direct touch/mouse interaction on
		// every other options screen (see MobileSettingsSubState/OptionsState)
		// -- this button wasn't gated at all, so on a touchscreen device
		// (where taps ARE mouse events) an accidental tap near it while using
		// the pad would still instantly close the screen underneath it.
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
