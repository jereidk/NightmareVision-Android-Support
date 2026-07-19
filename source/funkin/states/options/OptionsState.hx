package funkin.states.options;

import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText;
import flixel.text.FlxInputText;
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
import funkin.objects.menu.NineSlice;

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
		'language' => () -> LanguageOptions.build(),
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
		'credits',
		// The physical-key/gamepad rebinding screen. Kept last and labeled
		// "Keybinds" (opt_category_controls) so it doesn't read as, or sit next
		// to, "Mobile" (the touch-controls screen) -- upstream had it first and
		// simply called it "Controls", which on a touch device is ambiguous.
		'controls'
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

	// Only actually shown/usable on the 'language' tab (see update()) -- Touch
	// nav mode only, since there's no D-pad-driven way to type. FlxInputText
	// (same widget MainMenuState's dev-code entry already uses) owns its own
	// background/border/caret/click-to-focus/click-away-to-unfocus and drives
	// the OS on-screen keyboard through FlxInputTextManager -- see that
	// class's own history comment for why a hand-rolled TextField/manual
	// Lime-window-listener approach was tried and dropped there.
	var languageSearchField:FlxInputText;
	var languageSearchClear:FlxText;
	var languageSearchText:String = '';

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

	// Design canvas is a fixed 1280x720 (Project.xml's <window>) no matter the
	// device's real resolution/DPI -- FunkinRatioScaleMode handles actual device
	// scaling separately, this screen (like upstream's) always lays out against
	// this fixed logical size.
	static final CANVAS_H:Float = 720;

	// One shared vertical gap between every stacked row (header -> tabs ->
	// list) instead of the two different hand-picked gaps (24, then 18) that
	// used to be baked silently into TAB_Y/LIST_Y as opaque absolute numbers.
	static final SECTION_GAP:Float = 16;

	// Unchanged from before -- matches optionsHeader/menuBackButton's own
	// hardcoded y (18/20 respectively, set independently below in create())
	// so action buttons' cards still start flush with that row instead of
	// introducing a few px of new misalignment against them.
	static final HEADER_Y:Float = 20;
	static final BTN_H:Float = 38;
	// fitLabel() now also shrinks a label further if its rendered height
	// alone exceeds its box (see fitLabel()'s own comment) rather than only
	// watching line count, so this no longer has to stay this generous just
	// to guarantee a 2-line label in some language never spills past it.
	static final TAB_H:Float = 60;
	static final TAB_Y:Float = HEADER_Y + BTN_H + SECTION_GAP;

	// Reserved on every tab (not just Language) so the list's own y0/
	// maxVisible stay one single derived value shared by all 5 tabs instead
	// of needing a different layout per tab -- costs one fewer visible row
	// everywhere else, in exchange for never having to resize/reposition the
	// shared TouchOptionList instance when switching to/from Language.
	// Content only actually appears here on the Language tab (see
	// buildLanguageSearch()/refreshVisuals()).
	static final SEARCH_H:Float = 44;
	static final LIST_Y:Float = TAB_Y + TAB_H + SECTION_GAP + SEARCH_H + SECTION_GAP;

	// Gap between the last visible option row and the description box below
	// it, and that box's own fixed height -- named here so LIST_MAX_VISIBLE's
	// math (and the couple of places that used to repeat "6"/"74" inline)
	// stay readable instead of scattering the same two magic numbers around.
	static final DESC_GAP:Float = 6;
	static final DESC_H:Float = 74;

	// menu/freeplay/card.png's own corner radius measures ~16-17px (scanned
	// its alpha channel) -- 20 gives NineSlice.build() a couple px of buffer
	// so the corner curve is always fully inside the unscaled slice.
	static final CARD_MARGIN:Int = 20;

	// However many ROW_H-tall rows actually fit between the list's top and
	// the canvas bottom, after reserving room for the description box below
	// them and one more SECTION_GAP of bottom clearance -- derived instead of
	// a hand-picked "8" that would silently go stale (too tall, or leaving
	// unused space) the moment ROW_H/TAB_H/BTN_H/SECTION_GAP above change.
	static final LIST_MAX_VISIBLE:Int = Std.int((CANVAS_H - LIST_Y - DESC_GAP - DESC_H - SECTION_GAP) / TouchOptionList.ROW_H);

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

		// ControlsSubState has no starfield of its own -- just a 50%-alpha
		// dim -- so it actually relies on this state's own background
		// staying drawn underneath it to look fully opaque; leave
		// persistentDraw at its default (true) for that case and any other
		// substate opened from here. MobileSettingsSubState is the one
		// exception: it now draws its own full starBG/starFG/dim stack (see
		// that file), so this state's copy underneath is pure redundant
		// render -- skip it while that substate is open.
		persistentDraw = true;

		switch (label)
		{
			case 'controls':
				final gamepad = FlxG.gamepads.getFirstActiveGamepad();
				openSubState(new funkin.states.options.ControlsSubState(gamepad != null ? Gamepad(gamepad.id) : Keys));
			#if mobile
			case 'mobile':
				persistentDraw = false;
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

			// The tab row (and its backing panel) spans the same left/right
			// bounds as the title/close-button row above it -- optionsHeader.x
			// on the left, menuBackButton's right edge on the right -- read off
			// those two widgets instead of repeating "40 + cutout * 0.5" and
			// "1160 + cutout" as separate hand-typed magic numbers in three
			// different places (tabsPanelBg's own math and buildTabs() used to
			// each hardcode this independently; nothing enforced they'd stay in
			// sync if either widget's position/size ever changed).
			final tabsAreaStart = optionsHeader.x;
			final tabsAreaEnd = menuBackButton.x + menuBackButton.width;

			// Action buttons sit on the SAME row as the title and the close
			// button, so their span has to be read off those two widgets' actual
			// rendered bounds too -- this used to be a hardcoded "340" left edge
			// that assumed the (untranslated, unshrunk) title never got wider
			// than ~276px. A longer translation of "Options" -- or, as of the
			// Controls button just added, five buttons squeezed into the same
			// row -- had no guarantee of actually clearing the title text.
			buildActionButtons(optionsHeader.x + optionsHeader.width + 24, menuBackButton.x - 10);

			// Same thingy.png-derived gradient as artPanelBg below (the "options"
			// panel), cropped to a short strip instead -- unifies tabs with the
			// rest of this screen's thingy-restructured look instead of the tab
			// pills floating directly over the dim/starfield with nothing behind
			// their own row, the way action buttons above (still on topBar/the
			// header row, not this) and everything below already have.
			final tabsPanelX = tabsAreaStart - 8;
			final tabsPanelW = (tabsAreaEnd - tabsAreaStart) + 16;
			var tabsPanelBg = new FlxSprite(tabsPanelX, TAB_Y - 8).loadGraphic(Paths.image('menu/options/tabsPanel'));
			tabsPanelBg.antialiasing = ClientPrefs.globalAntialiasing;
			tabsPanelBg.setGraphicSize(Std.int(tabsPanelW), Std.int(TAB_H + 16));
			tabsPanelBg.updateHitbox();
			add(tabsPanelBg);

			buildTabs(tabsAreaStart, tabsAreaEnd);

			buildLanguageSearch(tabsAreaStart, tabsAreaEnd);

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
			final panelH = LIST_MAX_VISIBLE * TouchOptionList.ROW_H + DESC_GAP + DESC_H;

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

			descBg = new FlxSprite(LIST_X - 6, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + DESC_GAP);
			// 9-sliced instead of a plain stretch -- at this box's actual size
			// (~11:1, vs. the source card's own ~5:1) a naive setGraphicSize()
			// squashed the rounded corner/border noticeably flatter here than
			// on the narrower tab/button cards using the exact same bitmap.
			descBg.loadGraphic(NineSlice.build('menu/freeplay/card', CARD_MARGIN, listW + 12, DESC_H), false, 0, 0, true);
			descBg.updateHitbox();
			descBg.antialiasing = ClientPrefs.globalAntialiasing;
			descBg.color = 0xFF1A1A2E;
			descBg.alpha = 0.9;
			add(descBg);

			descText = new FlxText(LIST_X + 8, LIST_Y + LIST_MAX_VISIBLE * TouchOptionList.ROW_H + DESC_GAP + 6, listW - 16 - RESET_W, '');
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
	 * Evenly distributes `count` equal-width cards across [areaStart, areaEnd]
	 * with `gap` between neighbors -- the one spacing algorithm buildTabs()
	 * and buildActionButtons() both use, instead of each row hand-rolling its
	 * own slightly different math (the tabs used to fake their gap by just
	 * shrinking the card 4px inside its slot; action buttons already did a
	 * real gap-based split). Same algorithm for both means the two stacked
	 * rows actually line up card-edge-to-card-edge instead of drifting.
	 */
	static inline function rowCardWidth(areaStart:Float, areaEnd:Float, count:Int, gap:Float):Float
		return (areaEnd - areaStart - gap * (count - 1)) / count;

	/**
	 * Small pill buttons in the header, between the title and the close
	 * button -- tapping one navigates straight to its screen, no selection
	 * step. Only reachable by keyboard/D-pad via the 'buttons' focus state
	 * (UP from the tab row), since there's no separate touch affordance for
	 * "select without opening" that would make sense for these.
	 */
	function buildActionButtons(areaStart:Float, areaEnd:Float):Void
	{
		final gap = 10.0;
		final btnW = rowCardWidth(areaStart, areaEnd, actionButtons.length, gap);

		for (i in 0...actionButtons.length)
		{
			final bx = areaStart + (btnW + gap) * i;

			// Real card sprite instead of a flat makeGraphic() rect -- same
			// rounded panel MobileSettingsSubState uses, so both options
			// screens share one UI language instead of each inventing its own
			// flat rectangles. 9-sliced (see NineSlice's own doc comment) so
			// the corner radius/border stay the same actual size here as on
			// every other card using this bitmap, instead of a plain stretch
			// squashing or stretching them to whatever this row's aspect
			// ratio happens to be.
			final bg = new FlxSprite(bx, HEADER_Y);
			bg.loadGraphic(NineSlice.build('menu/freeplay/card', CARD_MARGIN, btnW, BTN_H), false, 0, 0, true);
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

	function buildTabs(areaStart:Float, areaEnd:Float):Void
	{
		final gap = 4.0;
		final tabW = rowCardWidth(areaStart, areaEnd, tabs.length, gap);

		for (i in 0...tabs.length)
		{
			final tx = areaStart + (tabW + gap) * i;

			// Real card sprite instead of a flat makeGraphic() rect -- see
			// buildActionButtons() above for why.
			final bg = new FlxSprite(tx, TAB_Y);
			bg.loadGraphic(NineSlice.build('menu/freeplay/card', CARD_MARGIN, tabW, TAB_H), false, 0, 0, true);
			bg.updateHitbox();
			bg.antialiasing = ClientPrefs.globalAntialiasing;
			bg.color = 0xFF2A2A3A;
			add(bg);
			tabBg.push(bg);

			// Same 4px label inset on both sides as buildActionButtons() uses
			// (bx + 4, width - 8) -- tabW here is already the card's own width
			// (rowCardWidth already subtracted the gap), unlike the old tabW
			// that meant "card + gutter" and needed a bigger, differently-sized
			// inset (tabW - 12) to land in the same visual spot.
			final lbl = new FlxText(tx + 4, TAB_Y, tabW - 8, '');
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

	/**
	 * The Language tab's search bar -- built once here like every other
	 * tab's chrome, its own .visible/.active toggled in update() (Touch nav
	 * mode + the language tab only -- Virtual Pad users have no way to type,
	 * same reasoning as the tap-to-reset icon being Touch-only).
	 *
	 * FlxInputText (same widget MainMenuState's dev-code entry already
	 * uses) instead of a hand-rolled solution: that class's own history
	 * comment explains why a raw openfl.text.TextField didn't work (its
	 * __enableInput() only wires up typed input from a FOCUS_IN callback
	 * that needs stage.focus == the field already true, which never held at
	 * any point this could trigger it from), and driving lime.ui.Window's
	 * onTextInput/textInputEnabled by hand runs into the same class of
	 * focus-timing risk without FlxInputTextManager's already-solved
	 * click-to-focus/click-away-to-unfocus/keyboard-rect handling.
	 */
	function buildLanguageSearch(areaStart:Float, areaEnd:Float):Void
	{
		final y = TAB_Y + TAB_H + SECTION_GAP;
		final w = areaEnd - areaStart;

		languageSearchField = new FlxInputText(areaStart, y, Std.int(w - 56), '', 20, OptionsTheme.TEXT_HOVER, 0xFF2A2A3A);
		languageSearchField.font = Paths.font('vcr.ttf');
		languageSearchField.fieldBorderThickness = 2;
		languageSearchField.fieldBorderColor = OptionsTheme.PINK_DIM;
		languageSearchField.fieldHeight = SEARCH_H - 8;
		languageSearchField.multiline = false;
		languageSearchField.maxChars = 40;
		languageSearchField.scrollFactor.set();
		add(languageSearchField);

		languageSearchField.onTextChange.add((text, _) -> {
			languageSearchText = text;
			refreshLanguageResults();
		});

		// Tap to clear -- plain text glyph instead of a new icon asset, same
		// low-risk approach MobileSettingsSubState's '<  BACK' button uses.
		// Not part of FlxInputText itself, so this stays a separate sprite.
		languageSearchClear = new FlxText(areaEnd - 46, y, 40, 'X');
		languageSearchClear.setFormat(Paths.font('vcr.ttf'), 20, OptionsTheme.PINK, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		languageSearchClear.borderSize = 1.5;
		languageSearchClear.y += Math.round((SEARCH_H - languageSearchClear.height) * .5);
		languageSearchClear.antialiasing = ClientPrefs.globalAntialiasing;
		languageSearchClear.visible = false;
		add(languageSearchClear);
	}

	/** Rebuilds the language tab's own rows from the current search text -- separate from refreshLanguageTabInPlace() (language-switch confirm), which must NOT re-apply the filter/reset scroll the way a real search edit should. */
	function refreshLanguageResults():Void
	{
		optionList.setOptions(LanguageOptions.build(languageSearchText));
	}

	function refreshTabText():Void
	{
		for (lbl in tabLabels)
		{
			lbl.text = Lang.str('opt_category_' + tabs[lbl.ID]);
			fitLabel(lbl, tabBg[lbl.ID].width - 8, TAB_H, TAB_Y, 17);
		}
	}

	/**
	 * Shrinks `txt` until it both wraps to at most 2 lines AND its actual
	 * rendered height clears `boxH` -- the old version only watched line
	 * count, so a 2-line label could still be taller than a given boxH and
	 * spill past its card's edges without ever triggering a further
	 * reduction. Watching real height too means TAB_H/BTN_H above can be
	 * sized for how much text actually needs to show, instead of having to
	 * stay permanently oversized "just in case" a longer translation shows up.
	 */
	function fitLabel(txt:FlxText, fieldW:Float, boxH:Float, boxY:Float, maxSize:Int):Void
	{
		var size = maxSize;
		txt.fieldWidth = fieldW;
		txt.wordWrap = true;
		while (size > 9 && (txt.textField.numLines > 2 || txt.height > boxH))
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
		// languageSearchField needs no manual cleanup here -- FlxInputText's
		// own destroy() (called via super.destroy() below, since it was
		// add()ed like everything else on this screen) already calls
		// endFocus() (closing the OS keyboard if it was still open) and
		// unregisters itself from FlxInputTextManager.
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
		// Same reasoning for the Language tab's own search text below --
		// closing e.g. Credits and coming straight back to a filtered list
		// shouldn't silently drop the filter the search box is still showing.
		final rebuiltOpts = (tabs[curTab] == 'language') ? LanguageOptions.build(languageSearchText) : TAB_BUILDERS.get(tabs[curTab])();
		optionList.setOptions(rebuiltOpts, optionList.curSelected);
	}

	function refreshVisuals():Void
	{
		if (blockAllInput) return;

		// Slow breathing glow on whichever card is currently selected -- a
		// plain FlxTween(PINGPONG) (the idiom MainMenuState's own breathing
		// pulse uses) doesn't fit here since selection moves between cards
		// dynamically; nothing else in this loop touches .alpha (the entrance
		// drop-in tweens only ever animate .y), so driving it here every frame
		// alongside the rest of the selection-state refresh can't fight
		// anything else for ownership of it.
		final glow = 0.85 + 0.15 * Math.sin(FlxG.game.ticks * 0.004);

		for (i in 0...tabBg.length)
		{
			final isSel = (i == curTab) && (focus != 'buttons');
			// Gold = "selected in a list", the same language TouchOptionList's
			// row highlight already uses below -- tabs filter that list, so
			// they share its meaning instead of the unrelated blue-purple this
			// screen used to invent on its own (see OptionsTheme's doc comment).
			tabBg[i].color = isSel ? 0xFF4A4020 : (i == hoveredTab ? 0xFF35354A : 0xFF2A2A3A);
			tabBg[i].alpha = isSel ? glow : 1;
			// 3 states like upstream's category list: gold selected, white
			// hovered-but-not-selected, dim gray otherwise -- was just a 2-state
			// white/gold before, with no way to tell "moused over" from "neither".
			tabLabels[i].color = isSel ? OptionsTheme.GOLD : (i == hoveredTab ? OptionsTheme.TEXT_HOVER : OptionsTheme.TEXT_IDLE);
		}
		for (i in 0...btnBg.length)
		{
			final isSel = (i == curButton) && (focus == 'buttons');
			// Pink = "standalone interactive accent" (MobileSettingsSubState's
			// own COLOR_ACCENT, TouchOptionList's arrows/scrollbar) -- action
			// buttons jump to a whole different screen instead of filtering the
			// list below, so a different hue from the tabs' gold is the one cue
			// that actually tells the two apart at a glance instead of both
			// reading as the same kind of button.
			btnBg[i].color = isSel ? 0xFF4F2A3A : (i == hoveredButton ? 0xFF45455F : 0xFF35354F);
			btnBg[i].alpha = isSel ? glow : 1;
			btnLabels[i].color = isSel ? OptionsTheme.PINK : (i == hoveredButton ? OptionsTheme.TEXT_HOVER : OptionsTheme.TEXT_IDLE);
		}
		resetIcon.alpha = hoveredReset ? 1 : 0.8;
		resetLabel.color = hoveredReset ? OptionsTheme.PINK : FlxColor.WHITE;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (!isHardcodedState()) return;

		// OptionsState keeps updating under any open substate (persistentUpdate
		// = true), so its own list/handlers must not process input while one is
		// up. openSelectedSubstate() sets blockInput for the submenus it opens,
		// but Note Colors / Quant Colors are opened directly via
		// openSubState() from VisualsUIOptions and bypass it -- their D-pad and
		// OptionsState's list navigation were both firing on every press, which
		// is why those two screens read as "extremely buggy". Treating any open
		// (non-transition) substate as blockInput closes that gap uniformly;
		// closeSubState() already clears blockInput on the way out.
		if (subState != null && !(subState is funkin.backend.BaseTransitionState)) blockInput = true;

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

		// Mobile-only (see buildLanguageSearch()'s own doc comment for why) --
		// desktop already has a real physical keyboard driving Controls'
		// normal navigation, and typing search text there risks colliding
		// with whatever's bound to those same keys, so this stays a touch-
		// specific affordance rather than a universal one.
		final searchVisible = #if mobile (pointerNavAllowed && tabs[curTab] == 'language') #else false #end;
		languageSearchField.visible = languageSearchField.active = searchVisible;
		languageSearchClear.visible = searchVisible && languageSearchField.hasFocus && languageSearchText.length > 0;
		if (!searchVisible) languageSearchField.endFocus();

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
				if (FlxG.mouse.justPressed)
				{
					if (i != curTab) changeTab(i);
					else if (focus != 'tabs')
					{
						// Clicking the tab that's already active (e.g. while
						// focus is 'list') just returns focus to the tab row,
						// same as BACK already does from 'list' -- doesn't call
						// changeTab() since that resets the list's scroll/
						// selection, which a same-tab click has no reason to
						// discard.
						focus = 'tabs';
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					}
				}
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

			// Only the clear button needs handling here -- FlxInputText already
			// manages its own click-to-focus and click-away-to-unfocus (see
			// buildLanguageSearch()'s doc comment).
			if (searchVisible && languageSearchClear.visible && FlxG.mouse.justPressed && FlxG.mouse.overlaps(languageSearchClear))
			{
				languageSearchField.text = '';
				languageSearchText = '';
				refreshLanguageResults();
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

		// Fresh search every visit to (or away from) the Language tab --
		// also dismisses the keyboard if it was still open from before.
		languageSearchField.endFocus();
		languageSearchField.text = '';
		languageSearchText = '';

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
