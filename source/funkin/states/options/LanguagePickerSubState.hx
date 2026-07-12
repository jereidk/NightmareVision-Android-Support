package funkin.states.options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import funkin.objects.menu.TouchOptionList;

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

		final opts:Array<Option> = [];
		for (entry in entries)
		{
			final opt = new Option(entry.name, '', '', 'button');
			opt.callback = () -> {
				onPicked(entry.code);
				close();
			};
			opts.push(opt);
		}
		list.setOptions(opts);

		#if mobile
		addVirtualPad(LEFT_FULL, B);
		addVirtualPadCamera();
		#end

		super.create();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		list.keyboardEnabled = true;

		if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(closeButton))
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
