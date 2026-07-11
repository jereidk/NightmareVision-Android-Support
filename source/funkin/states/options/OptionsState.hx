package funkin.states.options;

import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;

import funkin.data.*;
import funkin.states.*;
import funkin.objects.*;
import funkin.objects.menu.AmongControls;
import funkin.objects.menu.TouchOptionList;

/**
 * Categories used to be a vertical sidebar list, each opening its own full
 * sub-state -- that sidebar sat exactly where the Virtual Pad's LEFT_FULL
 * D-pad lives (see MobileVirtualPad.hx), so the pad ended up drawn on top of
 * the category labels for the (default!) Virtual Pad navigation mode.
 *
 * Redesigned as a horizontal tab strip up top (clear of the pad entirely)
 * plus one TouchOptionList below it. The five simple, data-only categories
 * (Language/Gameplay/Graphics/Visuals and UI/Misc) swap the list's dataset
 * live when their tab is picked, no sub-state transition at all. The other
 * four (Adjust Delay, Mobile, DLC Manager, Credits) still navigate away like
 * before -- their content (calibration UI, a live control preview, a
 * download list, a credits roll) doesn't fit "just a list of options".
 */
class OptionsState extends MusicBeatState
{
	public static var onPlayState:Bool = false;

	static final INLINE_BUILDERS:Map<String, Void->Array<Option>> = [
		'language' => LanguageOptions.build,
		'gameplay' => GameplayOptions.build,
		'graphics' => () -> GraphicsOptions.build(refreshSceneAntialiasing),
		'visualsui' => VisualsUIOptions.build,
		'misc' => MiscOptions.build,
	];

	var options:Array<String> = [
		'adjustdelay',
		'language',
		'gameplay',
		'graphics',
		'visualsui',
		'misc',
		#if mobile
		'mobile',
		'dlc',
		#end
		'credits'
	];

	private static var curSelected:Int = 0;

	// 'tabs': LEFT/RIGHT cycle tabs, ACCEPT/DOWN either enters the list (inline
	// tabs) or navigates away (the other four). 'list': input goes to
	// optionList instead; BACK steps focus back to 'tabs' rather than
	// exiting the whole screen.
	var focusOnList:Bool = false;

	var blockAllInput:Bool = false;
	var blockInput:Bool = false;
	var __openedOption:Null<String> = null;

	var optionsHeader:FlxText;
	var menuBackButton:FlxSprite;

	var tabBg:Array<FlxSprite> = [];
	var tabLabels:Array<FlxText> = [];

	var optionList:TouchOptionList;
	var descText:FlxText;
	var descBg:FlxSprite;

	var mouseControlActive:Bool = true;
	var hoveredOption:Int = -1;

	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	static final TAB_Y:Float = 90;
	static final TAB_H:Float = 60;
	static final LIST_Y:Float = 168;
	static final LIST_MAX_VISIBLE:Int = 8;

	// Same left-edge clearance the Virtual Pad's LEFT_FULL layout needs
	// (buttons span roughly x:0-339, see MobileVirtualPad.hx) -- this is the
	// whole reason for this redesign, so keeping the list clear of it is the
	// one non-negotiable measurement here.
	static final LIST_X:Float = 360;

	var bottomControls:Null<AmongControls>;

	static var instance:OptionsState;

	public function openSelectedSubstate(label:String):Void
	{
		if (label == 'adjustdelay')
		{
			FlxG.switchState(funkin.states.options.NoteOffsetState.new);
			return;
		}

		blockInput = true;

		scriptGroup.call('onOptionsSubmenu', [label]);

		switch (label)
		{
			#if mobile
			case 'mobile':
				openSubState(new funkin.states.options.MobileSettingsSubState());
			case 'dlc':
				openSubState(new funkin.states.options.MobileDLCSubState());
			#end
			case 'credits':
				openSubState(new funkin.states.substates.CreditsRollSubState(true, resumeMenuMusic, resumeMenuMusic));
		}
		__openedOption = label;
	}

	function resumeMenuMusic():Void
	{
		FunkinSound.playMusic(Paths.music('freakyMenu'));
	}

	override function create()
	{
		instance = this;

		_bitmapSnapshotAtCreate = FunkinAssets.cache.snapshotBitmapKeys();

		FunkinAssets.cache.clearStoredMemory();
		FunkinAssets.cache.clearUnusedMemory();

		DiscordClient.changePresence("Options Menu");

		initStateScript();
		persistentUpdate = true;

		if (isHardcodedState())
		{
			var starsBG = new FlxBackdrop(Paths.image('menu/common/starBG'));
			starsBG.scrollFactor.set();
			starsBG.velocity.x = -4.5;
			starsBG.zIndex = -2;
			add(starsBG);

			var starsFG = new FlxBackdrop(Paths.image('menu/common/starFG'));
			starsFG.scrollFactor.set();
			starsFG.velocity.x = -9;
			starsFG.zIndex = -1;
			add(starsFG);

			final cutout = funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;

			var dim = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xAA0A0A14);
			add(dim);

			var optionsHeaderY:Float = 18 + (ClientPrefs.language == 'arabic' ? -10 : 0);
			optionsHeader = new FlxText(40 + cutout * 0.5, optionsHeaderY, 0, Lang.str('options'), 62);
			optionsHeader.setFormat(Paths.font('AmaticSC-Bold.ttf'), 42, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionsHeader.borderSize = 2;
			optionsHeader.antialiasing = ClientPrefs.globalAntialiasing;
			add(optionsHeader);

			menuBackButton = new FlxSprite(1100 + cutout, 20).loadGraphic(Paths.image('menu/common/menuBack'));
			menuBackButton.antialiasing = ClientPrefs.globalAntialiasing;
			add(menuBackButton);

			buildTabs(cutout);

			final listW = (1160 + cutout) - LIST_X;
			optionList = new TouchOptionList(LIST_X, LIST_Y, listW, LIST_MAX_VISIBLE);
			add(optionList);
			optionList.onSelect = onOptionSelected;
			optionList.onChange = () -> scriptGroup.call('onOptionChanged', []);

			descBg = new FlxSprite(LIST_X - 6, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 6).makeGraphic(Std.int(listW + 12), 74, 0x88000000);
			add(descBg);

			descText = new FlxText(LIST_X + 8, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 12, listW - 16, '');
			descText.setFormat(Paths.font('vcr.ttf'), 18, 0xFFB0B0B0, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			descText.borderSize = 1.2;
			descText.wordWrap = true;
			add(descText);

			#if !mobile
			bottomControls = new AmongControls([
				['arrow', 'select'], // select
				['enter', 'conf'], // conf
				['esc', 'back'] // back
			], true);
			bottomControls.zIndex = 12;
			add(bottomControls);
			#end

			changeSelection();
		}

		super.create();

		scriptGroup.call('onCreatePost', []);

		#if mobile
		addVirtualPad(LEFT_FULL, A_B);
		addVirtualPadCamera();
		#end
	}

	function buildTabs(cutout:Float):Void
	{
		final totalW = (1160 + cutout) - 40;
		final tabW = totalW / options.length;

		for (i in 0...options.length)
		{
			final tx = 40 + cutout * 0.5 + tabW * i;

			final bg = new FlxSprite(tx, TAB_Y).makeGraphic(Std.int(tabW - 4), Std.int(TAB_H), 0xFF2A2A3A);
			add(bg);
			tabBg.push(bg);

			final lbl = new FlxText(tx + 4, TAB_Y, tabW - 12, Lang.str('opt_category_' + options[i]));
			lbl.setFormat(Paths.font('vcr.ttf'), 17, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.globalAntialiasing;
			lbl.wordWrap = true;
			lbl.ID = i;
			fitTabLabel(lbl, tabW);
			add(lbl);
			tabLabels.push(lbl);
		}
	}

	function fitTabLabel(txt:FlxText, tabW:Float):Void
	{
		var size = 17;
		while (size > 10 && txt.textField.numLines > 2)
		{
			size--;
			txt.setFormat(Paths.font('vcr.ttf'), size, txt.color, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.borderSize = 1.5;
		}
		txt.y = TAB_Y + Math.max(0, (TAB_H - txt.height) * 0.5);
	}

	function onOptionSelected(opt:Option):Void
	{
		focusOnList = true;
		descText.text = opt.description;
	}

	static function refreshSceneAntialiasing():Void
	{
		if (instance == null) return;
		for (spr in instance.members)
		{
			if (spr != null && (spr is FlxSprite) && !(spr is FlxText))
			{
				(cast spr : FlxSprite).antialiasing = ClientPrefs.globalAntialiasing;
			}
		}
		FlxSprite.defaultAntialiasing = ClientPrefs.globalAntialiasing;
	}

	override function closeSubState()
	{
		if (subState is funkin.backend.BaseTransitionState)
		{
			super.closeSubState();
			return;
		}

		__openedOption = null;
		blockInput = false;
		refreshOptionFonts();

		super.closeSubState();
	}

	override function destroy():Void
	{
		ClientPrefs.flush();
		ClientPrefs.reloadControls();
		super.destroy();

		if (instance == this) instance = null;

		if (_bitmapSnapshotAtCreate != null)
		{
			FunkinAssets.cache.disposeNewSince(_bitmapSnapshotAtCreate);
			_bitmapSnapshotAtCreate = null;
		}
	}

	function refreshOptionFonts():Void
	{
		optionsHeader.text = Lang.str('options');
		optionsHeader.font = Paths.font('AmaticSC-Bold.ttf');

		#if !mobile
		@:privateAccess bottomControls?.refreshBar();
		#end

		for (lbl in tabLabels)
		{
			lbl.text = Lang.str('opt_category_' + options[lbl.ID]);
			fitTabLabel(lbl, tabBg[lbl.ID].width + 4);
		}

		scriptGroup.call('onRefreshLang', []);
		refreshOptionVisuals();

		if (isInlineCategory(options[curSelected])) showCategory(options[curSelected]);
	}

	inline function isInlineCategory(label:String):Bool
		return INLINE_BUILDERS.exists(label);

	function showCategory(label:String):Void
	{
		final builder = INLINE_BUILDERS.get(label);
		optionList.visible = descBg.visible = descText.visible = (builder != null);
		if (builder == null) return;

		optionList.setOptions(builder());
	}

	function refreshOptionVisuals():Void
	{
		if (blockAllInput) return;
		for (i in 0...tabBg.length)
		{
			tabBg[i].color = (i == curSelected) ? 0xFF4A4A6A : (i == hoveredOption ? 0xFF35354A : 0xFF2A2A3A);
			tabLabels[i].color = (i == curSelected) ? 0xFFFFE066 : FlxColor.WHITE;
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (!isHardcodedState()) return;

		optionList.keyboardEnabled = focusOnList && !blockInput && !blockAllInput;

		hoveredOption = -1;

		if ((FlxG.mouse.justMoved || FlxG.mouse.justPressed) && ClientPrefs.navInputMode != 'Virtual Pad')
		{
			mouseControlActive = true;
		}
		if (controls.UI_UP_P || controls.UI_DOWN_P || controls.ACCEPT || controls.BACK)
		{
			mouseControlActive = false;
		}

		if (subState != null && subState is funkin.states.substates.CreditsRollSubState) mouseControlActive = false;

		if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(menuBackButton) && !blockAllInput)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			exitToParent();
			return;
		}

		if (mouseControlActive && !blockAllInput && !blockInput)
		{
			for (i in 0...tabBg.length)
			{
				if (!FlxG.mouse.overlaps(tabBg[i])) continue;
				hoveredOption = i;
				if (FlxG.mouse.justPressed)
				{
					if (i != curSelected)
					{
						curSelected = i;
						changeSelection(0, true);
					}
					activateSelectedTab();
				}
				break;
			}
		}

		refreshOptionVisuals();

		if (!blockInput && !blockAllInput && !focusOnList)
		{
			if (controls.UI_LEFT_P) changeSelection(-1);
			if (controls.UI_RIGHT_P) changeSelection(1);

			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				exitToParent();
			}

			if (controls.ACCEPT || controls.UI_DOWN_P) activateSelectedTab();
		}
		else if (!blockInput && !blockAllInput && focusOnList)
		{
			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				focusOnList = false;
			}
		}
	}

	function exitToParent():Void
	{
		if (onPlayState)
		{
			FlxG.switchState(PlayState.new);
			FlxG.sound.music.volume = 0;
			onPlayState = false;
		}
		else FlxG.switchState(MainMenuState.new);
	}

	function activateSelectedTab():Void
	{
		final label = options[curSelected];
		if (isInlineCategory(label))
		{
			focusOnList = true;
			return;
		}

		if (blockInput) return;

		openSelectedSubstate(label);
	}

	function changeSelection(change:Int = 0, ?fromMouse:Bool = false):Void
	{
		curSelected += change;
		if (curSelected < 0) curSelected = options.length - 1;
		if (curSelected >= options.length) curSelected = 0;
		focusOnList = false;
		refreshOptionVisuals();
		showCategory(options[curSelected]);

		var snd = fromMouse ? 'scrollMenu' : 'hover';
		FlxG.sound.play(Paths.sound(snd), fromMouse ? 1 : 0.5);
	}
}
