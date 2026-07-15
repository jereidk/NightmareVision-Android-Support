package funkin.states.options;

import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;

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

	// Shown in place of optionList/descBg/descText while still choosing a
	// section (focus != 'list') -- see the panel-building block in create()
	// and the visibility toggle in update() for the rest of this.
	var artPanelBg:FlxSprite;
	var artImage:FlxSprite;
	var titleText:FlxText;
	var versionText:FlxText;

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

	public static var instance:OptionsState;

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

			// Upstream's glossy header-strip texture (cropped from thingy.png at
			// its native 64px height -- no vertical stretch, so the diagonal
			// highlight streaks keep their real proportions) behind the title/
			// close-button/action-buttons row, instead of the generic topBar
			// every other mobile screen uses. Tabs get their own matching strip
			// below (see tabsPanelBg, right before buildTabs()) rather than one
			// bar stretched to cover both rows -- stretching thingy's short
			// strip that tall looked crude.
			var topBar = new FlxSprite(0, 0).loadGraphic(Paths.image('menu/options/headerStrip'));
			topBar.antialiasing = ClientPrefs.globalAntialiasing;
			topBar.setGraphicSize(Std.int(FlxG.width), 64);
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

			// Same thingy.png-derived gradient as artPanelBg below (the "options"
			// panel), cropped to a short strip instead -- unifies tabs with the
			// rest of this screen's thingy-restructured look instead of the tab
			// pills floating directly over the dim/starfield with nothing behind
			// their own row, the way action buttons above (still on topBar/the
			// header row, not this) and everything below already have.
			final tabsPanelX = 40 + cutout * 0.5 - 8;
			final tabsPanelW = ((1160 + cutout) - 40) + 16;
			var tabsPanelBg = new FlxSprite(tabsPanelX, TAB_Y - 8).loadGraphic(Paths.image('menu/options/tabsPanel'));
			tabsPanelBg.antialiasing = ClientPrefs.globalAntialiasing;
			tabsPanelBg.setGraphicSize(Std.int(tabsPanelW), Std.int(TAB_H + 16));
			tabsPanelBg.updateHitbox();
			add(tabsPanelBg);

			buildTabs(cutout);

			final listW = (1160 + cutout) - LIST_X;

			// Shared backdrop for the whole options column below the tabs --
			// upstream's thingy.png-derived gradient (same source as
			// tabsPanelBg above), built and added before optionList/descBg/the
			// art+title+version below so all of them draw on TOP of it. Always
			// visible regardless of focus: it's the one constant "window" this
			// area sits in, only its CONTENT (option list vs. hero art) swaps
			// between "choosing a section" and "editing its options" -- see the
			// focus-based toggle in update().
			final panelX = LIST_X - 6;
			final panelY = LIST_Y - 6;
			final panelH = LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 6 + 74;

			artPanelBg = new FlxSprite(panelX, panelY).loadGraphic(Paths.image('menu/options/artPanel'));
			artPanelBg.setGraphicSize(Std.int(listW + 12), Std.int(panelH));
			artPanelBg.updateHitbox();
			artPanelBg.antialiasing = ClientPrefs.globalAntialiasing;
			add(artPanelBg);

			optionList = new TouchOptionList(LIST_X, LIST_Y, listW, LIST_MAX_VISIBLE);
			add(optionList);
			optionList.onSelect = onOptionSelected;
			optionList.onDatasetChanged = (opt) -> descText.text = opt.description;
			optionList.onChange = () -> scriptGroup.call('onOptionChanged', []);

			descBg = new FlxSprite(LIST_X - 6, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 6);
			descBg.loadGraphic(Paths.image('menu/freeplay/card'));
			descBg.setGraphicSize(Std.int(listW + 12), 74);
			descBg.updateHitbox();
			descBg.antialiasing = ClientPrefs.globalAntialiasing;
			descBg.color = 0xFF1A1A2E;
			descBg.alpha = 0.9;
			add(descBg);

			descText = new FlxText(LIST_X + 8, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + 12, listW - 16 - RESET_W, '');
			descText.setFormat(Paths.font('vcr.ttf'), 18, 0xFFB0B0B0, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			descText.borderSize = 1.2;
			descText.wordWrap = true;
			add(descText);

			// Upstream's OptionsState only ever showed this hero-art/title/version
			// panel on its own dedicated category-picker screen, swapped out
			// entirely once a category opened its own full substate over it. This
			// tab-based redesign has no separate picker screen to swap away from,
			// so this content takes over the option list's own footprint instead
			// (on the SAME artPanelBg backdrop built above) -- see the
			// focus-based toggle in update() for when each one shows. Built
			// before buildResetButton() so the reset icon/label -- which stay
			// visible/functional regardless of focus, see the RESET keybind
			// handling below -- always render on top of whichever content is
			// currently showing on the panel.
			titleText = new FlxText(panelX, panelY + 16, listW + 12, 'VS IMPOSTOR: LEGACY');
			titleText.setFormat(Paths.font('AmaticSC-Bold.ttf'), 36, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			titleText.borderSize = 2;
			titleText.antialiasing = ClientPrefs.globalAntialiasing;
			add(titleText);

			artImage = new FlxSprite().loadGraphic(Paths.image('menu/options/art'));
			// Capped at 520 (not just "however wide the panel is minus a margin")
			// -- title/gap/art/gap/version all have to fit within panelH, and a
			// width scaled straight off the panel's own (quite generous) width
			// left the art tall enough to push version past the panel's bottom.
			artImage.setGraphicSize(Std.int(Math.min(listW + 12 - 80, 520)));
			artImage.updateHitbox();
			artImage.antialiasing = ClientPrefs.globalAntialiasing;
			artImage.setPosition(panelX + (listW + 12 - artImage.width) * 0.5, titleText.y + titleText.height + 16);
			add(artImage);

			versionText = new FlxText(panelX, artImage.y + artImage.height + 12, listW + 12, Main.LEGACY_VERSION);
			versionText.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			versionText.borderSize = 1.5;
			versionText.antialiasing = ClientPrefs.globalAntialiasing;
			add(versionText);

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

			// Real card sprite instead of a flat makeGraphic() rect -- same
			// rounded panel MobileSettingsSubState uses, so both options
			// screens share one UI language instead of each inventing its own
			// flat rectangles.
			final bg = new FlxSprite(bx, HEADER_Y);
			bg.loadGraphic(Paths.image('menu/freeplay/card'));
			bg.setGraphicSize(Std.int(btnW), Std.int(BTN_H));
			bg.updateHitbox();
			bg.antialiasing = ClientPrefs.globalAntialiasing;
			bg.color = 0xFF35354F;
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

			// Staggered drop-in for the card, same cascade style as
			// MobileSettingsSubState's option rows. The label is animated
			// separately below, AFTER refreshActionButtonText() -- fitLabel()
			// sets lbl.y synchronously, which would otherwise cancel this
			// offset before the tween ever got to run.
			final bgTargetY = bg.y;
			bg.y = bgTargetY - 24;
			FlxTween.tween(bg, {y: bgTargetY}, 0.3, {ease: FlxEase.quintOut, startDelay: i * 0.05});
		}
		refreshActionButtonText();

		for (i in 0...btnLabels.length)
		{
			final lbl = btnLabels[i];
			final targetY = lbl.y;
			lbl.y = targetY - 24;
			FlxTween.tween(lbl, {y: targetY}, 0.3, {ease: FlxEase.quintOut, startDelay: i * 0.05});
		}
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

			// Real card sprite instead of a flat makeGraphic() rect -- see
			// buildActionButtons() above for why.
			final bg = new FlxSprite(tx, TAB_Y);
			bg.loadGraphic(Paths.image('menu/freeplay/card'));
			bg.setGraphicSize(Std.int(tabW - 4), Std.int(TAB_H));
			bg.updateHitbox();
			bg.antialiasing = ClientPrefs.globalAntialiasing;
			bg.color = 0xFF2A2A3A;
			add(bg);
			tabBg.push(bg);

			final lbl = new FlxText(tx + 4, TAB_Y, tabW - 12, '');
			lbl.setFormat(Paths.font('vcr.ttf'), 17, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.globalAntialiasing;
			lbl.wordWrap = true;
			lbl.ID = i;
			add(lbl);
			tabLabels.push(lbl);

			// Staggered drop-in for the card, same two-phase split as
			// buildActionButtons() below -- the label's tween moved into its
			// own loop, AFTER refreshTabText() sets its text and runs
			// fitLabel(). refreshTabText() previously wasn't a shared function
			// (this loop and refreshOptionFonts() each hand-duplicated the same
			// "set text + fitLabel" logic, unlike the action buttons, which
			// already shared refreshActionButtonText() between the two) --
			// extracting it removes that duplication and, as a side effect,
			// requires the same fitLabel()-runs-before-the-tween-captures-y
			// ordering buildActionButtons() already needs.
			final bgTargetY = bg.y;
			bg.y = bgTargetY - 24;
			FlxTween.tween(bg, {y: bgTargetY}, 0.3, {ease: FlxEase.quintOut, startDelay: i * 0.05});
		}
		refreshTabText();

		for (i in 0...tabLabels.length)
		{
			final lbl = tabLabels[i];
			final targetY = lbl.y;
			lbl.y = targetY - 24;
			FlxTween.tween(lbl, {y: targetY}, 0.3, {ease: FlxEase.quintOut, startDelay: i * 0.05});
		}
	}

	function refreshTabText():Void
	{
		for (lbl in tabLabels)
		{
			lbl.text = Lang.str('opt_category_' + tabs[lbl.ID]);
			fitLabel(lbl, tabBg[lbl.ID].width - 8, TAB_H, TAB_Y, 17);
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

		refreshTabText();
		refreshActionButtonText();
		resetLabel.text = Lang.str('reset', 'RESET');

		scriptGroup.call('onRefreshLang', []);
		refreshVisuals();
		// This runs after ANY substate closes (Mobile/DLC/Credits), not
		// just on a real tab switch (changeTab(), which SHOULD
		// reset scroll/selection for a genuinely different category) -- without
		// preserving curSelected here, returning from e.g. Credits threw the
		// player back to the top of whatever tab they were on, discarding
		// their scroll position for no reason related to what actually changed.
		// setOptions()'s initialIndex param already exists for exactly this
		// "keep the thing you already have" case (see its own doc comment).
		optionList.setOptions(TAB_BUILDERS.get(tabs[curTab])(), optionList.curSelected);
	}

	function refreshVisuals():Void
	{
		if (blockAllInput) return;
		for (i in 0...tabBg.length)
		{
			final isSel = (i == curTab) && (focus != 'buttons');
			tabBg[i].color = isSel ? 0xFF4A4A6A : (i == hoveredTab ? 0xFF35354A : 0xFF2A2A3A);
			// 3 states like upstream's category list: gold selected, white
			// hovered-but-not-selected, dim gray otherwise -- was just a 2-state
			// white/gold before, with no way to tell "moused over" from "neither".
			tabLabels[i].color = isSel ? 0xFFFFE066 : (i == hoveredTab ? FlxColor.WHITE : 0xFFC9C9C9);
		}
		for (i in 0...btnBg.length)
		{
			final isSel = (i == curButton) && (focus == 'buttons');
			btnBg[i].color = isSel ? 0xFF5A5A7A : (i == hoveredButton ? 0xFF45455F : 0xFF35354F);
			btnLabels[i].color = isSel ? 0xFFFFE066 : (i == hoveredButton ? FlxColor.WHITE : 0xFFC9C9C9);
		}
		resetIcon.alpha = hoveredReset ? 1 : 0.8;
		resetLabel.color = hoveredReset ? 0xFFFFE066 : FlxColor.WHITE;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (!isHardcodedState()) return;

		optionList.keyboardEnabled = (focus == 'list') && !blockInput && !blockAllInput;

		// Swap the option list for the hero art/title/version while still
		// choosing a section -- active=false (not just visible=false) so a tap
		// landing on the now-hidden list doesn't still register on one of its
		// rows. artPanelBg itself is NOT part of this toggle: it's the shared
		// backdrop for both the list and the art (same as tabsPanelBg is for
		// the tab row), so it stays visible either way -- only its CONTENT
		// (list rows vs. hero art) swaps on top of it.
		final showList = (focus == 'list');
		optionList.visible = optionList.active = showList;
		descBg.visible = descText.visible = showList;
		artImage.visible = titleText.visible = versionText.visible = !showList;

		hoveredTab = -1;
		hoveredButton = -1;
		hoveredReset = false;

		// Virtual Pad nav mode suppresses every direct touch/mouse interaction
		// on screen (tabs, action buttons, reset, the close button) -- only the
		// virtual pad's own buttons should respond, same contract TouchOptionList
		// already follows for its rows via this same helper.
		final pointerNavAllowed = mobile.utils.MobileNavUtil.allowPointerNav();

		// The tap-to-reset icon is a Touch-mode-only affordance (Virtual Pad
		// mode resets via the pad's own C button instead, see below) -- hide it
		// rather than leave a dead, untappable icon sitting in the corner.
		resetIcon.visible = resetLabel.visible = pointerNavAllowed;

		// The navInputMode check only makes sense on mobile (Virtual Pad users
		// shouldn't have a stray touch re-enable mouse hover) -- on desktop
		// there's no screen to ever change navInputMode away from its default
		// ('Virtual Pad'), so gating this on it there meant mouseControlActive
		// could never flip back to true once any keyboard/gamepad press
		// cleared it below: a keyboard-then-mouse desktop user would lose all
		// mouse interaction with the tabs/buttons/reset icon for the rest of
		// that visit to this screen. CosmeticsSubstate's equivalent mouseMode
		// field already gets this right by only checking navInputMode #if mobile.
		if ((FlxG.mouse.justMoved || FlxG.mouse.justPressed) #if mobile && ClientPrefs.navInputMode != 'Virtual Pad' #end)
		{
			mouseControlActive = true;
		}
		if (controls.UI_UP_P || controls.UI_DOWN_P || controls.ACCEPT || controls.BACK)
		{
			mouseControlActive = false;
		}

		if (subState != null && subState is funkin.states.substates.CreditsRollSubState) mouseControlActive = false;

		// Was missing !blockInput, unlike every other interactive element below
		// (tabs, action buttons, reset icon) -- OptionsState keeps updating
		// underneath any open substate (persistentUpdate = true), so this
		// stayed clickable the whole time Mobile Settings/DLC/Credits/the
		// Language Picker covered the screen. A tap meant for that substate
		// landing on this exact spot would exitToParent(), switching away
		// from the entire Options screen (and destroying whatever substate
		// was open) with no visible cause.
		if (pointerNavAllowed && FlxG.mouse.justPressed && FlxG.mouse.overlaps(menuBackButton) && !blockAllInput && !blockInput)
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
					// changeTab() sets focus = 'tabs' itself on a tab click, but this
					// never set focus = 'buttons' -- so a mouse click here left curButton
					// pointing at this button while focus stayed wherever it was before
					// (e.g. 'list'), so refreshVisuals() wouldn't highlight this button as
					// selected once the substate closed, and keyboard/gamepad input would
					// go back to the tab list instead of this button row.
					curButton = i;
					focus = 'buttons';
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

		// controls.RESET (keyboard/gamepad) already resets while focus == 'list'
		// (see TouchOptionList.handleInput(), which only runs there since
		// optionList.keyboardEnabled is false otherwise) -- but the touch reset
		// icon above and the Virtual Pad's C button both work from ANY focus on
		// this screen, since resetAllToDefault() always acts on the current
		// tab's options regardless of which row/area is selected. Extend the
		// keybind the same way for 'tabs'/'buttons' focus; 'list' is excluded
		// here so this doesn't double-fire alongside TouchOptionList's own check.
		if (!blockAllInput && !blockInput && focus != 'list' && controls.RESET) optionList.resetAllToDefault();

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
					if (controls.UI_LEFT_P)
					{
						curButton = (curButton <= 0 ? actionButtons.length - 1 : curButton - 1);
						// changeTab() plays this same 'hover' cue on every tab change --
						// cycling the button row is the same kind of horizontal selection
						// move and had no audio feedback at all before this.
						FlxG.sound.play(Paths.sound('hover'), 0.5);
						_pulseButton(curButton);
					}
					if (controls.UI_RIGHT_P)
					{
						curButton = (curButton >= actionButtons.length - 1 ? 0 : curButton + 1);
						FlxG.sound.play(Paths.sound('hover'), 0.5);
						_pulseButton(curButton);
					}
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
		// A genuine tab switch starts fresh (top of the list) for every tab
		// except 'language' -- that one opens pre-scrolled to your current
		// language, same as the old LanguagePickerSubState used to.
		// refreshOptionFonts() below deliberately does NOT do this (see its
		// own comment) -- only a real category change should jump here.
		optionList.setOptions(TAB_BUILDERS.get(tabs[curTab])(), tabs[curTab] == 'language' ? LanguageOptions.currentLanguageRowIndex : null);

		FlxG.sound.play(Paths.sound('hover'), 0.5);
		_pulseTab(curTab);
	}

	/**
	 * Rebuilds the 'language' tab's rows in place (fresh badges/credits
	 * right after a language switch) while preserving scroll position, same
	 * idea as refreshOptionFonts() but scoped to just this one tab instead
	 * of running the full substate-close refresh. Guarded to the language
	 * tab specifically: PopUp.showConfirm's callback is async (fires later,
	 * not blocking), so the user could navigate to a different tab before
	 * confirming a language switch -- without this guard, a delayed
	 * callback landing after that would silently overwrite whatever tab is
	 * actually on screen by then.
	 */
	public function refreshLanguageTabInPlace():Void
	{
		if (tabs[curTab] != 'language') return;
		optionList.setOptions(TAB_BUILDERS.get('language')(), optionList.curSelected);
	}

	/**
	 * Small scale punch on a tab/button card when it becomes selected --
	 * same feedback pattern as MobileSettingsSubState's _pulseSelection(),
	 * so both options screens share the same bit of bounce instead of tabs
	 * just snapping to their new color.
	 */
	function _pulseCard(spr:FlxSprite):Void
	{
		if (spr == null) return;
		FlxTween.cancelTweensOf(spr.scale);
		spr.origin.set(spr.width / 2, spr.height / 2);
		spr.scale.set(1, 1);
		FlxTween.tween(spr.scale, {x: 1.05, y: 1.12}, 0.08, {
			ease: FlxEase.quadOut,
			onComplete: (_) -> FlxTween.tween(spr.scale, {x: 1, y: 1}, 0.14, {ease: FlxEase.quadIn})
		});
	}

	inline function _pulseTab(index:Int):Void
		_pulseCard((index >= 0 && index < tabBg.length) ? tabBg[index] : null);

	inline function _pulseButton(index:Int):Void
		_pulseCard((index >= 0 && index < btnBg.length) ? btnBg[index] : null);
}
