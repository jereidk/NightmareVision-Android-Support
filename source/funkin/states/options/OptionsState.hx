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
 * Categories used to be a single vertical sidebar list, each opening its own
 * full sub-state -- that sidebar sat exactly where the Virtual Pad's
 * LEFT_FULL D-pad lives (see MobileVirtualPad.hx), so the pad ended up drawn
 * on top of the category labels for the (default!) Virtual Pad navigation
 * mode.
 *
 * Now split into two genuinely different things instead of one mixed list:
 *   - Tabs (Language/Gameplay/Graphics/Visuals and UI/Misc): a horizontal
 *     strip that swaps TouchOptionList's dataset live, no transition.
 *   - Action buttons (Adjust Delay/Mobile/DLC Manager/Credits): a small
 *     header row of real buttons that navigate straight to their own screen
 *     the moment you tap them -- their content (calibration UI, a live
 *     control preview, a download list, a credits roll) never fit "just a
 *     list of options" in the first place, so they don't pretend to be tabs
 *     of the same list anymore.
 */
class OptionsState extends MusicBeatState
{
	public static var onPlayState:Bool = false;

	static final TAB_BUILDERS:Map<String, Void->Array<Option>> = [
		'language' => LanguageOptions.build,
		'gameplay' => GameplayOptions.build,
		'graphics' => () -> GraphicsOptions.build(refreshSceneAntialiasing),
		'visualsui' => VisualsUIOptions.build,
		'misc' => MiscOptions.build,
	];

	var tabs:Array<String> = ['language', 'gameplay', 'graphics', 'visualsui', 'misc'];

	var actionButtons:Array<String> = [
		'adjustdelay',
		#if mobile
		'mobile',
		'dlc',
		#end
		'credits'
	];

	private static var curTab:Int = 0;
	private static var curButton:Int = 0;

	// 'tabs': LEFT/RIGHT cycle tabs, UP moves to 'buttons', DOWN/ACCEPT enters
	// the list. 'buttons': LEFT/RIGHT cycle action buttons, ACCEPT opens the
	// selected one, DOWN returns to 'tabs'. 'list': input goes to optionList;
	// BACK there steps back to 'tabs' instead of exiting the whole screen.
	var focus:String = 'tabs';

	var blockAllInput:Bool = false;
	var blockInput:Bool = false;
	var __openedOption:Null<String> = null;

	var optionsHeader:FlxText;
	var menuBackButton:FlxSprite;

	var tabBg:Array<FlxSprite> = [];
	var tabLabels:Array<FlxText> = [];

	var btnBg:Array<FlxSprite> = [];
	var btnLabels:Array<FlxText> = [];

	var optionList:TouchOptionList;
	var descText:FlxText;
	var descBg:FlxSprite;

	var resetIcon:FlxSprite;
	var resetLabel:FlxText;

	var mouseControlActive:Bool = true;
	var hoveredTab:Int = -1;
	var hoveredButton:Int = -1;
	var hoveredReset:Bool = false;

	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	static final HEADER_Y:Float = 20;
	static final BTN_H:Float = 46;
	static final TAB_Y:Float = 90;
	// Generous enough for a 2-line wrapped label at fitLabel()'s largest font
	// size in any language -- a long translated category name (e.g. "Visuals
	// and UI") needs the headroom.
	static final TAB_H:Float = 74;
	static final LIST_Y:Float = 182;
	static final LIST_MAX_VISIBLE:Int = 8;

	// Same left-edge clearance the Virtual Pad's LEFT_FULL layout needs
	// (buttons span roughly x:0-339, see MobileVirtualPad.hx) -- this is the
	// whole reason for this redesign, so keeping the list clear of it is the
	// one non-negotiable measurement here.
	static final LIST_X:Float = 360;

	// Strip reserved at the description box's right edge for the reset-to-
	// default button, so descText's word wrap never runs underneath it.
	static final RESET_W:Float = 110;

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

			// Same header panel MobileSettingsSubState/VirtualPadCustomizerSubState
			// already use for their own top bar -- ties this screen visually to the
			// sub-states it opens, instead of the title/buttons/tabs floating
			// directly over the starfield with nothing behind them.
			var topBar = new FlxSprite(0, 0).loadGraphic(Paths.image('menu/common/topBar'));
			topBar.antialiasing = ClientPrefs.globalAntialiasing;
			topBar.setGraphicSize(Std.int(FlxG.width), Std.int(LIST_Y - 10));
			topBar.updateHitbox();
			add(topBar);

			var optionsHeaderY:Float = 18 + (ClientPrefs.language == 'arabic' ? -10 : 0);
			optionsHeader = new FlxText(40 + cutout * 0.5, optionsHeaderY, 0, Lang.str('options'), 62);
			optionsHeader.setFormat(Paths.font('AmaticSC-Bold.ttf'), 42, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionsHeader.borderSize = 2;
			optionsHeader.antialiasing = ClientPrefs.globalAntialiasing;
			add(optionsHeader);

			menuBackButton = new FlxSprite(1100 + cutout, 20).loadGraphic(Paths.image('menu/common/menuBack'));
			menuBackButton.antialiasing = ClientPrefs.globalAntialiasing;
			add(menuBackButton);

			buildActionButtons(cutout);
			buildTabs(cutout);

			final listW = (1160 + cutout) - LIST_X;
			optionList = new TouchOptionList(LIST_X, LIST_Y, listW, LIST_MAX_VISIBLE);
			add(optionList);
			optionList.onSelect = onOptionSelected;
			optionList.onDatasetChanged = (opt) -> descText.text = opt.description;
			optionList.onChange = () -> scriptGroup.call('onOptionChanged', []);

			descBg = new FlxSprite(LIST_X - 6, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 6).makeGraphic(Std.int(listW + 12), 74, 0x88000000);
			add(descBg);

			descText = new FlxText(LIST_X + 8, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 12, listW - 16 - RESET_W, '');
			descText.setFormat(Paths.font('vcr.ttf'), 18, 0xFFB0B0B0, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			descText.borderSize = 1.2;
			descText.wordWrap = true;
			add(descText);

			buildResetButton();

			#if !mobile
			bottomControls = new AmongControls([
				['arrow', 'select'], // select
				['enter', 'conf'], // conf
				['esc', 'back'] // back
			], true);
			bottomControls.zIndex = 12;
			add(bottomControls);
			#end

			curButton = Std.int(Math.min(Math.max(curButton, 0), actionButtons.length - 1));
			changeTab(Std.int(Math.min(Math.max(curTab, 0), tabs.length - 1)));
		}

		super.create();

		scriptGroup.call('onCreatePost', []);

		#if mobile
		// A_B_C instead of A_B -- the extra C button is this screen's reset
		// shortcut for Virtual Pad nav mode (see the buttonC check in update()),
		// same convention CosmeticsSubstate already uses for its own reset button.
		addVirtualPad(LEFT_FULL, A_B_C);
		addVirtualPadCamera();
		#end
	}

	/**
	 * Small pill buttons in the header, between the title and the close
	 * button -- tapping one navigates straight to its screen, no selection
	 * step. Only reachable by keyboard/D-pad via the 'buttons' focus state
	 * (UP from the tab row), since there's no separate touch affordance for
	 * "select without opening" that would make sense for these.
	 */
	function buildActionButtons(cutout:Float):Void
	{
		final areaStart = 340 + cutout * 0.5;
		final areaEnd = 1090 + cutout;
		final gap = 10.0;
		final btnW = (areaEnd - areaStart - gap * (actionButtons.length - 1)) / actionButtons.length;

		for (i in 0...actionButtons.length)
		{
			final bx = areaStart + (btnW + gap) * i;

			final bg = new FlxSprite(bx, HEADER_Y).makeGraphic(Std.int(btnW), Std.int(BTN_H), 0xFF35354F);
			add(bg);
			btnBg.push(bg);

			final lbl = new FlxText(bx + 4, HEADER_Y, btnW - 8, '');
			lbl.setFormat(Paths.font('vcr.ttf'), 15, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.3;
			lbl.antialiasing = ClientPrefs.globalAntialiasing;
			lbl.wordWrap = true;
			lbl.ID = i;
			add(lbl);
			btnLabels.push(lbl);
		}
		refreshActionButtonText();
	}

	function refreshActionButtonText():Void
	{
		for (lbl in btnLabels)
		{
			lbl.text = Lang.str('opt_category_' + actionButtons[lbl.ID]);
			fitLabel(lbl, btnBg[lbl.ID].width - 8, BTN_H, HEADER_Y, 15);
		}
	}

	function buildTabs(cutout:Float):Void
	{
		final totalW = (1160 + cutout) - 40;
		final tabW = totalW / tabs.length;

		for (i in 0...tabs.length)
		{
			final tx = 40 + cutout * 0.5 + tabW * i;

			final bg = new FlxSprite(tx, TAB_Y).makeGraphic(Std.int(tabW - 4), Std.int(TAB_H), 0xFF2A2A3A);
			add(bg);
			tabBg.push(bg);

			final lbl = new FlxText(tx + 4, TAB_Y, tabW - 12, Lang.str('opt_category_' + tabs[i]));
			lbl.setFormat(Paths.font('vcr.ttf'), 17, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.globalAntialiasing;
			lbl.wordWrap = true;
			lbl.ID = i;
			fitLabel(lbl, tabW - 12, TAB_H, TAB_Y, 17);
			add(lbl);
			tabLabels.push(lbl);
		}
	}

	function fitLabel(txt:FlxText, fieldW:Float, boxH:Float, boxY:Float, maxSize:Int):Void
	{
		var size = maxSize;
		txt.fieldWidth = fieldW;
		txt.wordWrap = true;
		while (size > 9 && txt.textField.numLines > 2)
		{
			size--;
			txt.setFormat(Paths.font('vcr.ttf'), size, txt.color, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.borderSize = 1.3;
		}
		txt.y = boxY + Math.max(0, (boxH - txt.height) * 0.5);
	}

	/**
	 * Touch-first equivalent of the RESET keybind (funkin.input.Controls.RESET,
	 * keyboard/gamepad only) -- resets the currently active tab's options to
	 * their defaults. Reuses menu/common/reset, the same icon CosmeticsSubstate
	 * already uses for its own reset button.
	 */
	function buildResetButton():Void
	{
		final iconH = 34.0;
		final iconScale = iconH / 175; // reset.png is a 165x175 source image
		final iconW = 165 * iconScale;
		final stripX = descBg.x + descBg.width - RESET_W;
		final contentH = iconH + 2 + 18;
		final topY = descBg.y + (descBg.height - contentH) * 0.5;

		resetIcon = new FlxSprite(stripX + (RESET_W - iconW) * 0.5, topY).loadGraphic(Paths.image('menu/common/reset'));
		resetIcon.antialiasing = ClientPrefs.globalAntialiasing;
		resetIcon.setGraphicSize(0, Std.int(iconH));
		resetIcon.updateHitbox();
		add(resetIcon);

		resetLabel = new FlxText(stripX, topY + iconH + 2, RESET_W, Lang.str('reset', 'RESET'));
		resetLabel.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		resetLabel.borderSize = 1.2;
		resetLabel.antialiasing = ClientPrefs.globalAntialiasing;
		add(resetLabel);
	}

	function onOptionSelected(opt:Option):Void
	{
		focus = 'list';
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
		// optionList's row sprites (e.g. the bool checkbox icon) live inside its
		// own group, one level below instance.members, so the loop above never
		// reaches them.
		if (instance.optionList != null)
		{
			for (spr in instance.optionList.members)
				if (spr != null && !(spr is FlxText)) spr.antialiasing = ClientPrefs.globalAntialiasing;
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
			lbl.text = Lang.str('opt_category_' + tabs[lbl.ID]);
			fitLabel(lbl, tabBg[lbl.ID].width - 8, TAB_H, TAB_Y, 17);
		}
		refreshActionButtonText();
		resetLabel.text = Lang.str('reset', 'RESET');

		scriptGroup.call('onRefreshLang', []);
		refreshVisuals();
		optionList.setOptions(TAB_BUILDERS.get(tabs[curTab])());
	}

	function refreshVisuals():Void
	{
		if (blockAllInput) return;
		for (i in 0...tabBg.length)
		{
			final isSel = (i == curTab) && (focus != 'buttons');
			tabBg[i].color = isSel ? 0xFF4A4A6A : (i == hoveredTab ? 0xFF35354A : 0xFF2A2A3A);
			tabLabels[i].color = isSel ? 0xFFFFE066 : FlxColor.WHITE;
		}
		for (i in 0...btnBg.length)
		{
			final isSel = (i == curButton) && (focus == 'buttons');
			btnBg[i].color = isSel ? 0xFF5A5A7A : (i == hoveredButton ? 0xFF45455F : 0xFF35354F);
			btnLabels[i].color = isSel ? 0xFFFFE066 : FlxColor.WHITE;
		}
		resetIcon.alpha = hoveredReset ? 1 : 0.8;
		resetLabel.color = hoveredReset ? 0xFFFFE066 : FlxColor.WHITE;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (!isHardcodedState()) return;

		optionList.keyboardEnabled = (focus == 'list') && !blockInput && !blockAllInput;

		hoveredTab = -1;
		hoveredButton = -1;
		hoveredReset = false;

		// Virtual Pad nav mode suppresses every direct touch/mouse interaction
		// on screen (tabs, action buttons, reset, the close button) -- only the
		// virtual pad's own buttons should respond, same contract TouchOptionList
		// already follows for its rows via this same helper.
		final pointerNavAllowed = mobile.utils.MobileNavUtil.allowPointerNav();

		if ((FlxG.mouse.justMoved || FlxG.mouse.justPressed) && ClientPrefs.navInputMode != 'Virtual Pad')
		{
			mouseControlActive = true;
		}
		if (controls.UI_UP_P || controls.UI_DOWN_P || controls.ACCEPT || controls.BACK)
		{
			mouseControlActive = false;
		}

		if (subState != null && subState is funkin.states.substates.CreditsRollSubState) mouseControlActive = false;

		if (pointerNavAllowed && FlxG.mouse.justPressed && FlxG.mouse.overlaps(menuBackButton) && !blockAllInput)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			exitToParent();
			return;
		}

		if (mouseControlActive && pointerNavAllowed && !blockAllInput && !blockInput)
		{
			for (i in 0...tabBg.length)
			{
				if (!FlxG.mouse.overlaps(tabBg[i])) continue;
				hoveredTab = i;
				if (FlxG.mouse.justPressed && i != curTab) changeTab(i);
				break;
			}

			for (i in 0...btnBg.length)
			{
				if (!FlxG.mouse.overlaps(btnBg[i])) continue;
				hoveredButton = i;
				if (FlxG.mouse.justPressed)
				{
					curButton = i;
					openSelectedSubstate(actionButtons[i]);
				}
				break;
			}

			if (FlxG.mouse.overlaps(resetIcon))
			{
				hoveredReset = true;
				if (FlxG.mouse.justPressed) optionList.resetAllToDefault();
			}
		}

		// Virtual Pad nav mode has no mouse/touch overlap to tap resetIcon with
		// (see MobileNavUtil.allowPointerNav()) -- its own dedicated C button is
		// the equivalent affordance instead, same convention CosmeticsSubstate
		// already uses for its own reset button.
		#if mobile
		if (!blockAllInput && !blockInput && virtualPad?.buttonC?.justPressed == true) optionList.resetAllToDefault();
		#end

		refreshVisuals();

		switch (focus)
		{
			case 'tabs':
				if (!blockInput && !blockAllInput)
				{
					if (controls.UI_LEFT_P) changeTab(curTab <= 0 ? tabs.length - 1 : curTab - 1);
					if (controls.UI_RIGHT_P) changeTab(curTab >= tabs.length - 1 ? 0 : curTab + 1);
					if (controls.UI_UP_P) focus = 'buttons';
					if (controls.ACCEPT || controls.UI_DOWN_P) focus = 'list';

					if (controls.BACK)
					{
						FlxG.sound.play(Paths.sound('cancelMenu'));
						exitToParent();
					}
				}
			case 'buttons':
				if (!blockInput && !blockAllInput)
				{
					if (controls.UI_LEFT_P) curButton = (curButton <= 0 ? actionButtons.length - 1 : curButton - 1);
					if (controls.UI_RIGHT_P) curButton = (curButton >= actionButtons.length - 1 ? 0 : curButton + 1);
					if (controls.UI_DOWN_P) focus = 'tabs';
					if (controls.ACCEPT) openSelectedSubstate(actionButtons[curButton]);

					if (controls.BACK)
					{
						FlxG.sound.play(Paths.sound('cancelMenu'));
						exitToParent();
					}
				}
			case 'list':
				if (!blockInput && !blockAllInput && controls.BACK)
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					focus = 'tabs';
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

	function changeTab(index:Int):Void
	{
		curTab = index;
		focus = 'tabs';
		refreshVisuals();
		optionList.setOptions(TAB_BUILDERS.get(tabs[curTab])());

		FlxG.sound.play(Paths.sound('hover'), 0.5);
	}
}
