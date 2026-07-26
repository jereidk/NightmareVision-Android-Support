package funkin.states.substates;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import funkin.objects.menu.TouchOptionList;
import funkin.states.options.Option;
import mobile.utils.MobileNavUtil;

/**
 * Gameplay Options screen opened from FreeplayState (keyboard G / mobile
 * button D) -- adjusts scroll type/speed, health gain/loss multipliers,
 * instakill, practice mode and botplay before a song even starts, all
 * stored in the same ClientPrefs.gameplaySettings map the pause menu's own
 * equivalent screen reads/writes.
 *
 * Rewritten onto the same TouchOptionList/Option machinery every other
 * options screen already uses (LanguagePickerSubState, OptionsState itself)
 * instead of a bespoke hand-rolled Alphabet-based column. That old layout
 * had no real touch handling of its own (D-pad/keyboard only, no tap
 * targets) and always spawned its own virtual pad regardless of nav mode,
 * while FreeplayState's own virtual pad stayed alive underneath it the
 * whole time (parent pads are only ever *hidden*, not destroyed, while a
 * substate's own pad is up -- see MusicBeatSubstate.addVirtualPad()'s
 * _hidParentPad chain) -- a lingering touch on that still-active hidden
 * pad's own button D could keep registering there and re-trigger this
 * screen's opening sound/logic. TouchOptionList already gates its own
 * touch handling on MobileNavUtil.allowPointerNav() and drives its D-pad
 * nav off the shared Controls (never a raw per-screen virtualPad.buttonX
 * poll), so there's no button-D-shaped hole here at all anymore.
 */
class GameplayChangersSubstate extends MusicBeatSubstate
{
	static final LIST_X:Float = 360;

	var list:TouchOptionList;
	var closeButton:FlxSprite;
	var scrollSpeedOption:Option;

	/**
	 * @param currentSongName Name of the song FreeplayState currently has
	 * selected. 'Defeat' already has its own built-in instakill mechanic
	 * (see FreeplayState's own 'Defeat' case, which opens MissCounterSubstate
	 * instead of loading it normally) -- the Instakill row is hidden there so
	 * it doesn't read as a second, redundant copy of the same behavior.
	 */
	public function new(?currentSongName:String)
	{
		super();

		final cutout = funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;

		var dim = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xE60A0A14);
		add(dim);

		var title = new FlxText(40 + cutout * 0.5, 50, 0, Lang.str('gc_title', 'Gameplay Changers'), 42);
		title.setFormat(Paths.font('AmaticSC-Bold.ttf'), 40, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.antialiasing = ClientPrefs.globalAntialiasing;
		add(title);

		closeButton = new FlxSprite(1100 + cutout, 50).loadGraphic(Paths.image('menu/common/menuBack'));
		closeButton.antialiasing = ClientPrefs.globalAntialiasing;
		add(closeButton);

		final listW = (1160 + cutout) - LIST_X;
		list = new TouchOptionList(LIST_X, 130, listW, 8);
		add(list);

		list.setOptions(buildOptions(currentSongName));

		#if mobile
		// Same convention as every other options screen (LanguagePickerSubState/
		// OptionsState/etc.): only show the virtual pad when the player's own
		// nav mode preference is 'Virtual Pad' -- the old version of this
		// screen always spawned one regardless of nav mode.
		if (ClientPrefs.navInputMode == 'Virtual Pad')
		{
			addVirtualPad(LEFT_FULL, A_B);
			addVirtualPadCamera();
		}
		#end
	}

	function buildOptions(currentSongName:Null<String>):Array<Option>
	{
		final opts:Array<Option> = [];

		final scrollTypeOpt = new Option(Lang.str('gc_scrolltype', 'Scroll Type'),
			Lang.str('gc_scrolltype_desc', 'Multiplicative scales with the song\'s BPM; Constant is the same speed for every song.'), '', 'string',
			'multiplicative', ['Multiplicative', 'Constant'], ['multiplicative', 'constant'], () -> ClientPrefs.gameplaySettings.get('scrolltype'),
			v -> ClientPrefs.gameplaySettings.set('scrolltype', v));
		opts.push(scrollTypeOpt);

		scrollSpeedOption = new Option(Lang.str('gc_scrollspeed', 'Scroll Speed'), Lang.str('gc_scrollspeed_desc', 'How fast notes scroll down the highway.'),
			'', 'float', 1.0, null, null, () -> ClientPrefs.gameplaySettings.get('scrollspeed'), v -> ClientPrefs.gameplaySettings.set('scrollspeed', v));
		scrollSpeedOption.scrollSpeed = 1.5;
		scrollSpeedOption.minValue = 0.5;
		scrollSpeedOption.changeValue = 0.1;
		_applyScrollTypeToSpeed(scrollTypeOpt.getValue());
		opts.push(scrollSpeedOption);

		// Scroll Speed's own max/display format depend on Scroll Type -- same
		// interdependency the old GameplayOption-based version had. Mutating
		// the row's fields directly is enough: TouchOptionList re-reads
		// displayFormat/maxValue fresh every frame, no rebuild needed.
		scrollTypeOpt.onChange = () -> _applyScrollTypeToSpeed(scrollTypeOpt.getValue());

		final healthGainOpt = new Option(Lang.str('gc_healthgain', 'Health Gain Multiplier'),
			Lang.str('gc_healthgain_desc', 'Multiplies how much health a hit note gives back.'), '', 'float', 1.0, null, null,
			() -> ClientPrefs.gameplaySettings.get('healthgain'), v -> ClientPrefs.gameplaySettings.set('healthgain', v));
		healthGainOpt.scrollSpeed = 2.5;
		healthGainOpt.minValue = 0;
		healthGainOpt.maxValue = 5;
		healthGainOpt.changeValue = 0.1;
		healthGainOpt.displayFormat = '%vX';
		opts.push(healthGainOpt);

		final healthLossOpt = new Option(Lang.str('gc_healthloss', 'Health Loss Multiplier'),
			Lang.str('gc_healthloss_desc', 'Multiplies how much health a missed note takes away.'), '', 'float', 1.0, null, null,
			() -> ClientPrefs.gameplaySettings.get('healthloss'), v -> ClientPrefs.gameplaySettings.set('healthloss', v));
		healthLossOpt.scrollSpeed = 2.5;
		healthLossOpt.minValue = 0.5;
		healthLossOpt.maxValue = 5;
		healthLossOpt.changeValue = 0.1;
		healthLossOpt.displayFormat = '%vX';
		opts.push(healthLossOpt);

		if (currentSongName != 'Defeat')
		{
			opts.push(new Option(Lang.str('gc_instakill', 'Instakill on Miss'), Lang.str('gc_instakill_desc', 'Any missed note ends the song immediately.'),
				'', 'bool', false, null, null, () -> ClientPrefs.gameplaySettings.get('instakill'), v -> ClientPrefs.gameplaySettings.set('instakill', v)));
		}

		// Showcase (dev-only) forces botplay on and drives the HUD itself, so
		// hide the Practice/Botplay toggles while it's enabled -- they'd only
		// let the player fight that mode. Gated on the pref combo (not a live
		// PlayState) since this substate also opens from FreeplayState.
		if (!(ClientPrefs.inDevMode && ClientPrefs.showcaseMode))
		{
			opts.push(new Option(Lang.str('gc_practice', 'Practice Mode'), Lang.str('gc_practice_desc', 'Play without misses or losses counting against you.'),
				'', 'bool', false, null, null, () -> ClientPrefs.gameplaySettings.get('practice'), v -> ClientPrefs.gameplaySettings.set('practice', v)));

			opts.push(new Option(Lang.str('gc_botplay', 'Botplay'), Lang.str('gc_botplay_desc', 'Watch the song play itself.'), '', 'bool', false, null, null,
				() -> ClientPrefs.gameplaySettings.get('botplay'), v -> ClientPrefs.gameplaySettings.set('botplay', v)));
		}

		final resetOpt = new Option(Lang.str('gc_reset', 'Reset to Default'), '', '', 'button');
		resetOpt.callback = () -> list.resetAllToDefault();
		opts.push(resetOpt);

		return opts;
	}

	function _applyScrollTypeToSpeed(scrollType:String):Void
	{
		if (scrollType == 'constant')
		{
			scrollSpeedOption.displayFormat = '%v';
			scrollSpeedOption.maxValue = 6;
		}
		else
		{
			scrollSpeedOption.displayFormat = '%vX';
			scrollSpeedOption.maxValue = 3;
			if ((scrollSpeedOption.getValue() : Float) > 3) scrollSpeedOption.setValue(3.0);
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		list.keyboardEnabled = true;

		// Same nav-mode gate as LanguagePickerSubState's own close button --
		// on a touchscreen device (where taps ARE mouse events), an accidental
		// tap near it while using the Virtual Pad would otherwise still
		// instantly close this screen.
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

	override function destroy():Void
	{
		ClientPrefs.flush();
		super.destroy();
	}
}
