package funkin.states;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.addons.display.FlxBackdrop;
import flixel.input.keyboard.FlxKey;
import flixel.text.FlxText;
import flixel.text.FlxInputText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
#if mobile
import mobile.utils.MobileNavUtil;
#end

import openfl.display.BitmapData;
import openfl.geom.Rectangle;

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;
import funkin.data.*;
import funkin.data.CosmicubeData;
import funkin.data.GameFlags;
import funkin.objects.menu.AmongControls;
import funkin.utils.ProgressionUtil;
import funkin.utils.CoolUtil;
import funkin.states.options.*;
import funkin.states.*;
import funkin.states.substates.CreditsRollSubState;
import funkin.states.editors.MasterEditorMenu;

class MainMenuState extends MusicBeatState
{
	public static var fromTitle:Bool = false;
	
	var lockMovement:Bool = false;
	var mouseMode:Bool = #if mobile ClientPrefs.navInputMode == 'Touch' #else false #end;
	
	static var curMenuItem:Int = 0;
	static var lastSmallBtn:Int = 3;
	var menuButtons:Array<FlxSprite> = [];
	var menuLabels:Array<FlxText> = [];
	var menuLabelBaseSizes:Array<Int> = [];
	var menuLabelYOffsets:Array<Float> = [];
	var menuIcons:Array<FunkinSprite> = [];
	var menuIconOrigX:Array<Float> = [];
	var menuIconTweens:Array<FlxTween> = [];
	
	var redMenu:FlxSprite;
	var greenMenu:FlxSprite;
	var logo:FlxSprite;
	
	var starFG:FlxBackdrop;
	var starBG:FlxBackdrop;
	
	var panelIntroItems:Array<FlxSprite> = [];
	var introActive:Bool = false;
	var introTimer:Float = 0;
	
	var menuShinies:Array<FlxSprite> = [];

	static final BIG_LABEL_KEYS = ['storymode', 'freeplay', 'cosmi'];
	static final SMALL_LABEL_KEYS = ['options', 'awards'];
	static final ICON_PREFIXES = ['Red and Green instance 1', 'Cone instance 1', 'Polus instance 1', 'Gear instance 1', 'Trophy instance 1'];
	static final MENU_LABEL_MIN_SIZE:Int = 12;

	static final YT_CHANNEL_URL:String = 'https://youtube.com/@jere-idk?si=zqgS9D-dDx8IWmJ_';

	// ── Dev-panel code-entry gate ────────────────────────────────────────────
	// Previously an hscript overlay using a raw openfl.text.TextField, which
	// fought OpenFL's own FOCUS_IN timing gap (TextField.__enableInput() --
	// the thing that actually wires up typed characters and Enter, not just
	// keyboard visibility -- only runs from this_onFocusIn(), which requires
	// stage != null && stage.focus == this to BOTH already be true; neither
	// held at any of the field's trigger points) and, even once that was
	// worked around, still ran the event listeners through the hscript
	// interpreter. Ported to native + flixel.text.FlxInputText: its
	// FlxInputTextManager listens to the Stage's own TextEvent.TEXT_INPUT
	// directly (fires unconditionally, unlike a TextField's own internal
	// enable state) and to the Lime window's onKeyDown/onKeyUp signals, so
	// neither failure point exists here. It also lives in Flixel's normal
	// logical coordinate space, removing the raw-window-vs-logical-pixel
	// mismatch the old field's manual x/y positioning had to account for.
	static inline final DEV_CODE:String = 'cheatmenu';
	static inline final FNAF_CODE:String = 'backdoor';
	static inline final CODE_TRIGGER_SIZE:Int = 64;
	static inline final CODE_TRIGGER_MARGIN:Int = 12;
	// Warm near-black + the same red FreeplayCard/LoadingState already use as
	// their selection accent (0xFFFF4444) -- was a cold blue-purple "hacker
	// tool" palette that matched nothing else the game ever draws.
	static inline final DEV_COL_BG:Int = 0xFF1A1414;
	static inline final DEV_COL_ACCENT:Int = 0xFFFF4444;
	static inline final DEV_COL_DANGER:Int = 0xFF7F1D1D;
	static inline final DEV_COL_TEXT:Int = 0xFFFFFFFF;

	var devCodeTriggerBg:FlxSprite = null;
	var devCodeField:FlxInputText = null;
	var devCodeBoxOpen:Bool = false;
	// Tracks devCodeField.text so a real per-character change (typed OR
	// backspaced) can be told apart from this state's own programmatic
	// resets (fresh field on open, cleared on a wrong guess) -- matches
	// FNAFState's terminal, which plays the same 'type' sound per keystroke.
	var _lastDevCodeText:String = '';

	// ── Dev panel: full port from the former hscript overlay (assets/legacy/
	// scripts/states/MainMenuState.hx, now deleted) ─────────────────────────
	// Keeping the whole thing native is more consistent with the code-entry
	// gate above (one less interpreted-vs-compiled seam to reason about) and
	// keeps the panel's existence out of the asset folder entirely, where a
	// curious player poking through the APK/mod folder could stumble on it.

	// ── Panel state ─────────────────────────────────────────────────────────
	var devPanelOpen:Bool = false;
	var devPanelAll:Array<FlxSprite> = [];
	var devPanelBtns:Array<{x:Float, y:Float, w:Float, h:Float, idx:Int}> = [];
	var devPanelCooldown:Int = 0;
	var devPanelCam:FlxCamera = null; // dedicated top-most camera, always renders above game sprites

	// Panel body bounds, kept around so the touch handler can tell "missed a
	// button but still inside the panel" apart from "actually tapped outside
	// it" -- see updateDevPanel()'s close-on-tap check.
	var devPanelX:Float = 0;
	var devPanelY:Float = 0;
	var devPanelW:Float = 0;
	var devPanelH:Float = 0;

	// Virtual-pad row navigation (only active when ClientPrefs.navInputMode
	// == 'Virtual Pad' -- touch mode keeps tapping rows directly).
	var devPanelSelIdx:Int = 0;
	var devPanelSelector:FlxSprite = null;

	// Audio-synced "epic unlock" glow -- see openDevPanel()'s scheduling and
	// the DEV_UNLOCK_* timestamps below for where these numbers come from.
	var devPanelGlow:FlxSprite = null;
	var devPanelOpenGen:Int = 0;

	var devLblUnlock:FlxText = null;
	var devLblUnlockReq:FlxText = null;
	var devLblReset:FlxText = null;
	var devResetBtnSpr:FlxSprite = null;

	// Two-tap confirm guard for the destructive reset button.
	var devResetArmed:Bool = false;
	var devResetArmedUntil:Float = 0;

	// Panel palette (DEV_COL_BG/ACCENT/DANGER/TEXT already declared above,
	// shared with the code-entry field -- DEV_COL_BG matches the old
	// hscript's COL_BG_TOP, the panel's own darker body gets its own const).
	// Same warm-dark/red family as DEV_COL_BG/ACCENT above instead of the
	// old indigo/purple set, so the whole panel reads as one palette.
	static inline final DEV_PANEL_BG:Int = 0xFF120D0D;
	static inline final DEV_COL_SECTION:Int = 0xFF9C7A7A;
	static inline final DEV_COL_TOGGLE:Int = 0xFF332424;
	static inline final DEV_COL_TOGGLE_ON:Int = 0xFF2E7D32;
	static inline final DEV_COL_LOOT:Int = 0xFF9C6B1F;
	static inline final DEV_COL_MONEY:Int = 0xFF14532D;
	static inline final DEV_COL_DANGER_ARMED:Int = 0xFFFF4444;
	static inline final DEV_COL_CLOSE:Int = 0xFF241A1A;
	// Deliberately its own cool blue, apart from the warm gold/green/red
	// palette every other row uses -- makes the Editors entry read as
	// its own distinct category (a tool, not a cheat) at a glance.
	static inline final DEV_COL_TOOL:Int = 0xFF1E3A5F;

	// Timestamps measured directly off assets/legacy/sounds/unlockSong.ogg
	// (ffmpeg -> raw PCM -> 20ms RMS/peak envelope + windowed-FFT peak
	// frequency, done offline): a quiet ~180ms lead-in, then a rising
	// arpeggio build (mostly A3/C#4/D4, RMS climbing 0.03 -> 0.3) from
	// 0.18s to 1.46s, then a ~360ms sustained peak -- the "epic" hit, RMS
	// 0.3-0.39 and peak clipping at 1.0, arpeggiating down through a bright
	// B6-A6-F#6-D6 chord -- from 1.46s to 1.82s, then a long reverb decay
	// tailing to silence by ~3.6s (full clip is 4.62s). The panel's own
	// content still appears immediately via the existing row cascade below
	// so it stays instantly usable -- this only times the extra glow/flash
	// payoff to land exactly on that climax instead of firing on open.
	static inline final DEV_UNLOCK_BUILD_START:Float = 0.18;
	static inline final DEV_UNLOCK_CLIMAX_START:Float = 1.46;
	// How long the burst itself takes to expand and fade once triggered --
	// deliberately a bit shorter than the climax's own 0.36s sustain (it
	// only needs to read as "the moment", not track the full decay tail).
	static inline final DEV_UNLOCK_BURST_DURATION:Float = 0.5;

	var ytRing:FlxSprite;
	var ytIcon:FlxSprite;
	var portCreditText:FlxText;

	// Same leak fix as TitleState/FreeplayState/PlayState: without this, every
	// dynamically-rendered bitmap this state creates (menu labels, the YouTube
	// credit text, etc.) outlives the state and accumulates on every single
	// MainMenuState visit, since this is the hub state revisited constantly.
	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	// Same fix as MusicBeatState's own _updateArgs: reused every frame instead
	// of allocating a fresh `[elapsed]` array literal on every single
	// scriptGroup.call('onUpdatePost', ...) below, which MainMenuState sits on
	// idling (menu music playing, tweens running) far longer than most states.
	final _updatePostArgs:Array<Dynamic> = [0.0];

	override function create()
	{
		#if android final _createT0 = haxe.Timer.stamp(); #end

		_bitmapSnapshotAtCreate = FunkinAssets.cache.snapshotBitmapKeys();

		Mods.currentModDirectory = null;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus");
		#end
		Lang.reloadLangFile();

		// Free previous state's assets before loading new ones. Must run before any
		// Paths.image/getSparrowAtlas calls so that shared assets (starFG, starBG, logo)
		// are revived from cache instead of reloaded, preventing double-allocation.
		// Timed directly (not profBegin/profEnd -- those only ever surface via
		// PlayState's [GAMEPLAY] line, which doesn't fire here) after a device
		// log showed a ~1s freeze landing on entry to this exact state,
		// particularly right after leaving FreeplayState (which can itself
		// dispose 80+ textures on the way out -- see AmongUIState.destroy()).
		#if android final _t0 = haxe.Timer.stamp(); #end
		FunkinAssets.cache.clearStoredMemory();
		FunkinAssets.cache.clearUnusedMemory();
		#if android
		final _clearMs = (haxe.Timer.stamp() - _t0) * 1000;
		if (_clearMs >= 5) Logger.log('[MainMenuState] create: clearStoredMemory+clearUnusedMemory took ${Std.int(_clearMs)}ms');
		#end

		persistentUpdate = persistentDraw = true;

		if (ClientPrefs.finaleState == ACTIVE) FunkinSound.playMusic(Paths.music('finaleMenu'), 0);
		else if (FlxG.sound.music == null) FunkinSound.playMusic(Paths.music('freakyMenu'), 0);

		initStateScript();

		starFG = new FlxBackdrop(Paths.image('menu/common/starFG'));
		add(starFG);

		starBG = new FlxBackdrop(Paths.image('menu/common/starBG'));
		add(starBG);

		logo = new FlxSprite(0, -5);
		logo.frames = Paths.getSparrowAtlas('logoBumpin');
		logo.animation.addByPrefix('bump', 'logo bumpin', 24, false);
		logo.antialiasing = true;
		logo.scale.set(0.5, 0.5);
		logo.updateHitbox();
		logo.screenCenter(X);
		logo.x += 20;

		add(logo);

		buildPanel();

		// Designed for the 1280-wide base canvas, hanging off the right edge.
		// 'expand' mode's extra width (see FunkinRatioScaleMode.gameCutoutSize)
		// only ever opens up to the right of that design (origin stays at 0,0),
		// so without this offset red stays pinned at its base-resolution X while
		// the screen grows around it, sliding it from "off the right edge" to
		// "in the middle". greenMenu sits off-screen to the LEFT, where expand
		// never reveals extra space, so it needs no such adjustment.
		var redTargetX:Float = 630 + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;
		var greenTargetX:Float = -225;

		redMenu = new FlxSprite(redTargetX, 70);
		redMenu.frames = Paths.getSparrowAtlas('menu/main/redmenu');
		redMenu.animation.addByPrefix('idle', 'idle', 24, false);
		redMenu.animation.addByPrefix('select', 'confirm', 24, false);
		redMenu.animation.play('idle');

		greenMenu = new FlxSprite(greenTargetX, 100);
		greenMenu.frames = Paths.getSparrowAtlas('menu/main/greenmenu');
		greenMenu.animation.addByPrefix('idle', 'idle', 24, false);
		greenMenu.animation.addByPrefix('select', 'confirm', 24, false);
		greenMenu.animation.play('idle');

		if (ClientPrefs.finaleState != ACTIVE)
		{
			add(redMenu);
			add(greenMenu);
		}

		var glow = new FlxSprite().loadGraphic(Paths.image(ClientPrefs.finaleState == ACTIVE ? 'menu/main/glowEVIL' : 'menu/main/glow'));
		glow.scale.set(1.1, 1.1);
		glow.updateHitbox();
		// Source image is exactly 1280x720 — on a device wide enough that
		// 'expand' screen fit grows FlxG.width past that, stretch to cover the
		// extra width instead of leaving an uncovered gap on either side.
		if (FlxG.width > glow.width)
		{
			glow.scale.x *= FlxG.width / glow.width;
			glow.updateHitbox();
		}
		glow.screenCenter();
		glow.blend = ADD;
		add(glow);

		var vignette = new FlxSprite().loadGraphic(Paths.image('menu/main/vignette'));
		vignette.scrollFactor.set();
		vignette.active = false;
		// Was never centered even at the base resolution (sat at (0,0) covering
		// only the left 1280px) — stretch and center so wide 'expand' screens
		// don't end up with the vignette darkening only one side of the screen.
		if (FlxG.width > vignette.width)
		{
			vignette.setGraphicSize(FlxG.width, Std.int(vignette.height));
			vignette.updateHitbox();
		}
		vignette.screenCenter();
		add(vignette);

		if (ClientPrefs.finaleState == ACTIVE)
		{
			for (icon in menuIcons)
				icon.visible = false;

			refreshMenuLabelLayout();
			menuLabels[0].color = 0xFFFF0000;

			menuButtons[0].animation.addByPrefix('idle', 'Big_buttonEVIL instance 1', 24, true);
			menuButtons[0].animation.play('idle');
			menuButtons[0].updateHitbox();
			menuButtons[0].screenCenter(X);
			menuButtons[0].y -= 15;
		}

		buildPortCredit();

		#if !mobile
		var bottomControls:AmongControls = new AmongControls([
			['arrow', 'select'],
			['enter', 'conf']
		], false);
		add(bottomControls);
		#end

		Conductor.bpm = 102;
		Conductor.bpmChangeMap.resize(0);

		FlxG.mouse.visible = MobileNavUtil.shouldShowMouse();

		super.create();

		if (fromTitle)
		{
			redMenu.x = FlxG.width + 120;
			greenMenu.x = -greenMenu.width - 120;
			FlxTween.tween(redMenu, {x: redTargetX}, 1.2, {ease: FlxEase.expoOut});
			FlxTween.tween(greenMenu, {x: greenTargetX}, 1.2, {ease: FlxEase.expoOut});
			playPanelIntro();
			fromTitle = false;
		}
		
		updateMenuSelection();
		
		var shinies:Int = ProgressionUtil.getShinies();
		for (i => shiny in menuShinies) shiny.visible = (i < shinies);
		
		scriptGroup.call('onCreatePost', []);

		#if mobile
		addVirtualPad(LEFT_FULL, A_B);
		addVirtualPadCamera();
		#end

		#if android
		createDevCodeTrigger();
		buildDevPanel();
		#end

		// This state just loaded ~40 new textures; forcing the GC pass here
		// (see FunkinCache.forceGcPass()'s own comment) bundles that decode
		// garbage into the loading transition instead of leaving it to
		// surface as a [LARGE-GC] stutter a second or two later while the
		// player is already looking at the menu.
		// forceGcPass() calls cpp.vm.Gc.compact() -- a FULL heap compaction,
		// not just a mark-sweep -- likely the single biggest contributor to
		// the ~1s freeze a device log showed on entry to this state; timed
		// directly for the same reason as the clearStoredMemory timing above.
		#if android final _t0b = haxe.Timer.stamp(); #end
		FunkinAssets.cache.forceGcPass();
		#if android
		final _gcMs = (haxe.Timer.stamp() - _t0b) * 1000;
		if (_gcMs >= 5) Logger.log('[MainMenuState] create: forceGcPass (System.gc + Gc.compact) took ${Std.int(_gcMs)}ms');
		final _createMs = (haxe.Timer.stamp() - _createT0) * 1000;
		if (_createMs >= 30) Logger.log('[MainMenuState] create: END, total ${Std.int(_createMs)}ms');
		#end
	}

	var backpanel:FlxSprite;
	
	function buildPanel()
	{
		final ext:String = 'menu/main/';
		final r:Float = (1280 / 1920);
		
		backpanel = new FlxSprite(0, 350, Paths.image('${ext}tablet'));
		backpanel.scale.set(r, r);
		backpanel.updateHitbox();
		backpanel.screenCenter(X);
		add(backpanel);
		
		panelIntroItems.push(backpanel);
		
		var buttonY:Float = (backpanel.y + 28);
		for (i in 0...BIG_LABEL_KEYS.length)
		{
			var btn = new FlxSprite(0, buttonY);
			btn.frames = Paths.getSparrowAtlas('${ext}new buttons and stuff');
			btn.animation.addByPrefix('idle', 'Big button instance 1', 24, false);
			btn.animation.play('idle');
			btn.animation.pause();
			btn.scale.set(r, r);
			btn.updateHitbox();
			btn.screenCenter(X);
			add(btn);
			menuButtons.push(btn);
			panelIntroItems.push(btn);
			
			buttonY += (btn.height + 8);
			
			var lbl = new FlxText(btn.x + 16, 0, btn.width - 32, Lang.str(BIG_LABEL_KEYS[i]), 24);
			lbl.setFormat(Paths.font('vcr.ttf'), 28, 0xFF0F332F, RIGHT);
			lbl.y = Math.round(btn.y + (btn.height - lbl.height) * 0.5 + 4);
			add(lbl);
			menuLabels.push(lbl);
			menuLabelBaseSizes.push(28);
			menuLabelYOffsets.push(4);
			panelIntroItems.push(lbl);
		}
		
		for (i in 0...SMALL_LABEL_KEYS.length)
		{
			var btn = new FlxSprite(0, buttonY);
			btn.frames = Paths.getSparrowAtlas('${ext}new buttons and stuff');
			btn.animation.addByPrefix('idle', 'Small Button instance 1', 24, false);
			btn.animation.play('idle');
			btn.animation.pause();
			btn.scale.set(r, r);
			btn.updateHitbox();
			btn.x = Math.round(i == 0 ? backpanel.x + 28 : backpanel.x + backpanel.width - btn.width - 28);
			add(btn);
			menuButtons.push(btn);
			panelIntroItems.push(btn);
			
			var lbl = new FlxText(btn.x + 16, 0, btn.width - 32, Lang.str(SMALL_LABEL_KEYS[i]), 22);
			lbl.setFormat(Paths.font('vcr.ttf'), 18, 0xFF0F332F, RIGHT);
			lbl.y = Math.round(btn.y + (btn.height - lbl.height) * 0.5 + 3);
			add(lbl);
			menuLabels.push(lbl);
			menuLabelBaseSizes.push(18);
			menuLabelYOffsets.push(3);
			panelIntroItems.push(lbl);
		}
		
		final shinies:Int = 5;
		for (i in 0...shinies)
		{
			var shiny = new FlxSprite();
			shiny.frames = Paths.getSparrowAtlas('${ext}shiny');
			shiny.animation.addByPrefix('idle', 'Symbol 21 instance 1', 24, true);
			shiny.animation.play('idle');
			shiny.visible = false;
			shiny.scale.set(.75, .75);
			shiny.updateHitbox();
			shiny.setPosition(Math.round(FlxMath.remapToRange(i, 0, shinies - 1, backpanel.x + 28, backpanel.x + backpanel.width - shiny.width - 28)),
				Math.round(backpanel.y + backpanel.height - shiny.height - 28));
			add(shiny);
			menuShinies.push(shiny);
			panelIntroItems.push(shiny);
		}
		
		for (i in 0...menuButtons.length)
		{
			var btn = menuButtons[i];
			var icon = new FunkinSprite().loadAtlas('${ext}new buttons and stuff');
			icon.animation.addByPrefix('idle', ICON_PREFIXES[i], 24, false);
			icon.animation.play('idle');
			icon.scale.set(r, r);
			icon.updateHitbox();
			icon.x = btn.x + 10;
			icon.y = btn.y + (btn.height - icon.height) * 0.5;
			icon.origin.x = (btn.width * .5 - 10);
			icon.offset.x = (icon.origin.x * (1 - r));
			add(icon);
			menuIcons.push(icon);
			menuIconOrigX.push(icon.x);
			menuIconTweens.push(null);
			panelIntroItems.push(icon);
		}
		
		refreshMenuLabelLayout();
	}
	
	function refreshMenuLabelLayout()
	{
		for (i in 0...menuLabels.length)
			fitMenuLabel(i);
	}
	
	function fitMenuLabel(i:Int)
	{
		var btn = menuButtons[i];
		var lbl = menuLabels[i];
		var icon = menuIcons[i];
		
		var leftBound:Float = btn.x + 8;
		if (icon != null && icon.visible) leftBound = Math.max(leftBound, icon.x + icon.width + 8);
		var rightBound:Float = btn.x + btn.width - 8;
		
		lbl.x = Math.round(leftBound + 4);
		lbl.fieldWidth = Math.max(8, Math.round(rightBound - lbl.x - 4));
		
		var size:Int = menuLabelBaseSizes[i];
		lbl.setFormat(Paths.font('vcr.ttf'), size, lbl.color, RIGHT);
		lbl.textField.wordWrap = false;
		lbl.textField.multiline = false;
		
		while (size > MENU_LABEL_MIN_SIZE && lbl.textField != null && lbl.textField.textWidth > lbl.fieldWidth)
		{
			size--;
			lbl.setFormat(Paths.font('vcr.ttf'), size, lbl.color, RIGHT);
			lbl.textField.wordWrap = false;
			lbl.textField.multiline = false;
		}
		
		lbl.y = Math.round(btn.y + (btn.height - lbl.height) * 0.5 + menuLabelYOffsets[i]);
	}
	
	function playPanelIntro()
	{
		introActive = true;
		introTimer = 0.6;
		for (item in panelIntroItems)
		{
			var targetY = item.y;
			item.y += 220;
			FlxTween.tween(item, {y: targetY}, 1.2, {ease: FlxEase.expoOut});
		}
	}
	
	/**
	 * Small YouTube-styled icon + "Android Port By Jere" credit, centered at
	 * the bottom of the menu (replaces the old left-aligned port/version text).
	 * Tapping the icon opens the channel in the browser.
	 */
	function buildPortCredit():Void
	{
		final iconSize:Int = 44;
		final iconX:Float  = 18;
		final iconY:Float  = 16;
		final ringColor:Int = 0xFF6CFF7A;

		// Ring sits a touch larger than the avatar and behind it, like a
		// colored profile-picture border.
		ytRing = new FlxSprite(iconX - 3, iconY - 3).loadGraphic(_ringBitmap(iconSize + 6, ringColor, 3));
		ytRing.scrollFactor.set();
		add(ytRing);

		ytIcon = new FlxSprite(iconX, iconY).loadGraphic(_circleMask(Paths.image('menu/main/ytChannelIcon').bitmap, iconSize));
		ytIcon.scrollFactor.set();
		add(ytIcon);

		portCreditText = new FlxText(iconX + iconSize + 12, iconY + (iconSize - 22) * 0.5, 300, 'Android Port By Jere', 18);
		portCreditText.alignment = 'left';
		portCreditText.setFormat(Paths.font('vcr.ttf', false), 18, ringColor, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		portCreditText.borderSize = 1.5;
		portCreditText.scrollFactor.set();
		add(portCreditText);

		// Gentle breathing pulse so the corner credit feels a little alive.
		FlxTween.tween(ytIcon, {"scale.x": 1.08, "scale.y": 1.08}, 1.1,
			{ease: FlxEase.quadInOut, type: PINGPONG});
		FlxTween.tween(ytRing, {"scale.x": 1.08, "scale.y": 1.08}, 1.1,
			{ease: FlxEase.quadInOut, type: PINGPONG});
	}

	/**
	 * Scales `source` to fit an size×size square and clips it to a circle
	 * (per-pixel alpha cutoff outside the radius) — same procedural masking
	 * approach used elsewhere this session, applied to a real image instead
	 * of a solid fill.
	 */
	function _circleMask(source:BitmapData, size:Int):BitmapData
	{
		var scaled = new BitmapData(size, size, true, 0x00000000);
		var matrix = new openfl.geom.Matrix();
		matrix.scale(size / source.width, size / source.height);
		scaled.draw(source, matrix, null, null, null, true);

		final radius:Float = size * 0.5;
		final cx:Float = radius, cy:Float = radius;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				final dx = px - cx, dy = py - cy;
				if (dx * dx + dy * dy > radius * radius) scaled.setPixel32(px, py, 0x00000000);
			}
		}

		return scaled;
	}

	/** Thin colored ring (annulus), used as a border behind the circular avatar. */
	function _ringBitmap(size:Int, color:Int, thickness:Float):BitmapData
	{
		var bmp = new BitmapData(size, size, true, 0x00000000);
		final outerR:Float = size * 0.5;
		final innerR:Float = outerR - thickness;
		final cx:Float = outerR, cy:Float = outerR;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				final dx = px - cx, dy = py - cy;
				final dist = Math.sqrt(dx * dx + dy * dy);
				if (dist <= outerR && dist >= innerR) bmp.setPixel32(px, py, color);
			}
		}

		return bmp;
	}

	function updateMenuSelection()
	{
		var isFinale = ClientPrefs.finaleState == ACTIVE;
		for (i in 0...menuButtons.length)
		{
			if (isFinale && i == 0)
			{
				menuLabels[0].color = (curMenuItem == 0) ? FlxColor.WHITE : 0xFFFF0000;
			}
			else
			{
				menuButtons[i].animation.curAnim.curFrame = (i == curMenuItem) ? 1 : 0;
			}
			if (menuIconTweens[i] != null)
			{
				menuIconTweens[i].cancel();
				menuIconTweens[i] = null;
			}
			
			if (i < 3)
			{
				if (menuIconTweens[i] != null) menuIconTweens[i].cancel();
				
				menuIconTweens[i] = FlxTween.tween(menuIcons[i].spriteOffset, {x: (i == curMenuItem ? 15 : 0)}, 0.15, {ease: FlxEase.quadOut});
			}
		}
	}
	
	override function beatHit()
	{
		super.beatHit();
		
		if (redMenu?.animation.name != 'select') redMenu.animation.play('idle', true);
		if (greenMenu?.animation.name != 'select') greenMenu.animation.play('idle', true);
	}
	
	function select()
	{
		if (lockMovement) return;
		lockMovement = true;
		
		redMenu.animation.play('select');
		greenMenu.animation.play('select');
		
		for (item in [menuButtons[curMenuItem], menuLabels[curMenuItem], menuIcons[curMenuItem]])
		{
			item.scale.scale(.9);
			FlxTween.tween(item.scale, {x: item.scale.x * 1.05, y: item.scale.y * 1.05}, .2, {ease: FlxEase.circOut});
		}
		
		FlxG.sound.play(Paths.sound('confirmMenu'));
		
		FlxTween.tween(starFG, {y: starFG.y + 2000}, 1.8, {ease: FlxEase.sineIn, startDelay: .6});
		FlxTween.tween(starBG, {y: starBG.y + 1500}, 1.8, {ease: FlxEase.sineIn, startDelay: .6});
		FlxTween.tween(redMenu, {y: redMenu.y + 750}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		FlxTween.tween(greenMenu, {y: greenMenu.y + 750}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		FlxTween.tween(logo, {y: logo.y + 1000}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		for (item in panelIntroItems)
			FlxTween.tween(item, {y: item.y + 1000}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		FlxTimer.wait(1, switchToSelection);
	}
	
	function switchToSelection()
	{
		switch (curMenuItem)
		{
			case 0:
				FlxG.switchState(new StoryMenuState());
			case 1:
				FlxG.switchState(new FreeplayState());
			case 2:
				FlxG.switchState(new CosmicubeSelectState());
			case 3:
				FlxG.switchState(new OptionsState());
			case 4:
				FlxG.switchState(new AwardsState());
		}
	}
	
	override function update(elapsed:Float)
	{
		if (FlxG.sound.music != null)
		{
			if (FlxG.sound.music.volume < 0.8) FlxG.sound.music.volume += 0.5 * elapsed;
			Conductor.songPosition = FlxG.sound.music.time;
		}
		
		starBG.x -= 4.5 * elapsed;
		starFG.x -= 9 * elapsed;

		if (!devCodeBoxOpen && !devPanelOpen && ytIcon != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(ytIcon))
		{
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
			CoolUtil.browserLoad(YT_CHANNEL_URL);
		}

		if (!devCodeBoxOpen && !devPanelOpen && FlxG.keys.justPressed.SEVEN) FlxG.switchState(new MasterEditorMenu());

		#if !mobile
		// Desktop: allow switching between keyboard and mouse
		if (FlxG.keys.firstJustPressed() != FlxKey.NONE) mouseMode = false;
		if (FlxG.mouse.justMoved) mouseMode = true;
		#end

		if (introActive)
		{
			introTimer -= elapsed;
			if (introTimer <= 0) introActive = false;
		}

		// The code-entry field and the dev panel each own input focus while
		// they're open -- menu navigation, mouse selection, and ACCEPT must
		// not fire underneath them. For the code field, a physical/soft-
		// keyboard Enter used to double as both "submit the code" and
		// "controls.ACCEPT the highlighted menu item" on the same frame. For
		// the panel, UI_UP_P/UI_DOWN_P/ACCEPT now drive its own row
		// navigation (see updateDevPanel()) -- without this gate they'd ALSO
		// move curMenuItem and select() the highlighted main-menu button
		// underneath it, which is exactly the kind of "closes/exits as if
		// nothing happened" behavior reported for the panel. controls.BACK
		// still works in both cases, closing the code box / panel instead of
		// leaking through to the normal "back to TitleState" handling below.
		if (devCodeBoxOpen)
		{
			#if android
			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				closeDevCodeBox();
			}
			#end
		}
		else if (devPanelOpen)
		{
			// Actual row navigation handled in updateDevPanel(), called after
			// this -- this branch only exists so the main-menu block below is
			// skipped while the panel owns input.
		}
		else
		{
			if (!lockMovement && !introActive && mouseMode)
			{
				for (i in 0...menuButtons.length)
				{
					if (FlxG.mouse.overlaps(menuButtons[i]))
					{
						if (curMenuItem != i)
						{
							curMenuItem = i;
							updateMenuSelection();
						}
						if (FlxG.mouse.justPressed) select();
						break;
					}
				}
			}

			if (!lockMovement && !introActive)
			{
				var moved = false;
				if (controls.UI_UP_P)
				{
					final prev = curMenuItem;
					if (curMenuItem >= 3)
					{
						lastSmallBtn = curMenuItem;
						curMenuItem = 2;
					}
					else if (curMenuItem > 0) curMenuItem--;

					moved = curMenuItem != prev;
				}
				else if (controls.UI_DOWN_P)
				{
					final prev = curMenuItem;

					if (curMenuItem == 2) curMenuItem = lastSmallBtn;
					else if (curMenuItem < 2) curMenuItem++;

					moved = curMenuItem != prev;
				}
				else if (controls.UI_LEFT_P && curMenuItem == 4)
				{
					curMenuItem = 3;
					moved = true;
				}
				else if (controls.UI_RIGHT_P && curMenuItem == 3)
				{
					curMenuItem = 4;
					moved = true;
				}
				if (moved)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
					updateMenuSelection();
				}
				if (controls.ACCEPT) select();
				#if android
				if (controls.BACK)
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					FlxG.switchState(TitleState.new);
				}
				#end
			}
		}

		super.update(elapsed);

		_updatePostArgs[0] = elapsed;
		scriptGroup.call('onUpdatePost', _updatePostArgs);

		#if android
		updateDevCodeGate();
		#end

		updateDevPanel();
	}

	override function destroy()
	{
		super.destroy();

		if (_bitmapSnapshotAtCreate != null)
		{
			FunkinAssets.cache.disposeNewSinceIfDestructive(_bitmapSnapshotAtCreate);
			_bitmapSnapshotAtCreate = null;
		}

		// super.destroy() above already destroyed these (both were added via
		// add()) -- just drop the stale references.
		devCodeTriggerBg = null;
		devCodeField = null;
		devPanelSelector = null;
		devPanelGlow = null;
	}

	// ── Dev-panel code-entry gate ────────────────────────────────────────────

	function createDevCodeTrigger():Void
	{
		devCodeTriggerBg = new FlxSprite(FlxG.width - CODE_TRIGGER_SIZE - CODE_TRIGGER_MARGIN, CODE_TRIGGER_MARGIN);
		devCodeTriggerBg.loadGraphic(cachedDevShape('devpanel_keyboardicon', () -> devKeyboardIcon(CODE_TRIGGER_SIZE, DEV_COL_BG, DEV_COL_ACCENT)));
		devCodeTriggerBg.alpha = 0.75;
		devCodeTriggerBg.scrollFactor.set();
		add(devCodeTriggerBg);
	}

	function updateDevCodeGate():Void
	{
		// The trigger icon sits under the dev panel's dim overlay once it's
		// open (visually), but touches aren't blocked by what's drawn on top
		// -- skip entirely so a tap landing on that same screen region can't
		// reopen the code box while the panel is already up.
		if (devPanelOpen) return;

		// Only the trigger toggles the box -- deliberately no "tap elsewhere
		// closes it" check, since the field itself would count as "elsewhere".
		if (!devCodeBoxOpen)
		{
			var touches = FlxG.touches.list;
			if (touches != null)
			{
				for (touch in touches)
				{
					if (!touch.justReleased) continue;
					final x0 = FlxG.width - CODE_TRIGGER_SIZE - CODE_TRIGGER_MARGIN - 6;
					final x1 = FlxG.width - CODE_TRIGGER_MARGIN + 6;
					final y0 = CODE_TRIGGER_MARGIN - 6;
					final y1 = CODE_TRIGGER_MARGIN + CODE_TRIGGER_SIZE + 6;
					if (touch.x >= x0 && touch.x <= x1 && touch.y >= y0 && touch.y <= y1) toggleDevCodeBox();
					break;
				}
			}
			return;
		}

		// Auto-submit the moment the typed text matches either code -- no need to press Enter.
		if (devCodeField != null)
		{
			if (devCodeField.text != _lastDevCodeText)
			{
				_lastDevCodeText = devCodeField.text;
				FlxG.sound.play(Paths.sound('type'));
			}

			final typed = StringTools.trim(devCodeField.text).toLowerCase();
			if (typed == DEV_CODE || typed == FNAF_CODE) submitDevCode();
		}
	}

	function toggleDevCodeBox():Void
	{
		if (devCodeBoxOpen) closeDevCodeBox();
		else openDevCodeBox();
	}

	function openDevCodeBox():Void
	{
		if (devCodeField != null) return;
		devCodeBoxOpen = true;
		pulseDevCodeTrigger(true);

		// Typing a code needs the keyboard, not the D-pad -- hide the pad so
		// it doesn't sit there visually reactable while its presses are
		// actually being blocked (see update()'s devCodeBoxOpen gate).
		#if mobile
		if (virtualPad != null) virtualPad.visible = false;
		#end

		devCodeField = new FlxInputText(FlxG.width - 272, CODE_TRIGGER_MARGIN + CODE_TRIGGER_SIZE + 8, 260, '', 20, DEV_COL_TEXT, DEV_COL_BG);
		devCodeField.font = Paths.font('vcr.ttf');
		devCodeField.fieldBorderThickness = 2;
		devCodeField.fieldBorderColor = DEV_COL_ACCENT;
		devCodeField.alignment = FlxTextAlign.CENTER;
		devCodeField.multiline = false;
		devCodeField.maxChars = 10;
		devCodeField.scrollFactor.set();
		add(devCodeField);
		_lastDevCodeText = '';

		devCodeField.onEnter.add(_ -> submitDevCode());
		devCodeField.startFocus();
	}

	function pulseDevCodeTrigger(active:Bool):Void
	{
		if (devCodeTriggerBg == null) return;
		FlxTween.cancelTweensOf(devCodeTriggerBg.scale);
		devCodeTriggerBg.alpha = active ? 1.0 : 0.75;
		devCodeTriggerBg.scale.set(active ? 1.15 : 1.0, active ? 1.15 : 1.0);
		FlxTween.tween(devCodeTriggerBg.scale, {x: 1.0, y: 1.0}, 0.25, {ease: FlxEase.quadOut});
	}

	function submitDevCode():Void
	{
		if (devCodeField == null) return;

		final typed = StringTools.trim(devCodeField.text).toLowerCase();
		if (typed == DEV_CODE)
		{
			closeDevCodeBox();
			openDevPanel();
		}
		else if (typed == FNAF_CODE)
		{
			closeDevCodeBox();
			FlxG.switchState(new FNAFState());
		}
		else
		{
			// Leave the typed text in place -- wiping it here used to give the
			// illusion the field had been cleared, but _lastDevCodeText stayed
			// stale until the next keystroke, so the "cleared" text would pop
			// back and pile on top of whatever got typed next. A red flash is
			// enough to signal "wrong code"; the player can see and correct
			// what they actually typed instead.
			devCodeField.backgroundColor = DEV_COL_DANGER;
			// 'error' isn't a real key under assets/legacy/sounds -- the only
			// error.ogg in the project lives under assets/embeds/sounds/ui/,
			// a different lookup path Paths.sound() doesn't check, so this
			// silently fell back to Flixel's beep. 'locked' is the sound this
			// codebase already uses everywhere else for "denied" (locked
			// songs/cosmetics in FreeplayState, StoryMenuState,
			// CosmicubeSubState) and it actually resolves.
			FlxG.sound.play(Paths.sound('locked'), 0.6);
			haxe.Timer.delay(() -> {
				if (devCodeField != null) devCodeField.backgroundColor = DEV_COL_BG;
			}, 400);
		}
	}

	function closeDevCodeBox():Void
	{
		devCodeBoxOpen = false;
		pulseDevCodeTrigger(false);

		#if mobile
		if (virtualPad != null) virtualPad.visible = true;
		#end

		if (devCodeField == null) return;
		remove(devCodeField, true);
		devCodeField.destroy();
		devCodeField = null;
	}

	function devRoundedRect(w:Int, h:Int, color:Int, radius:Int):BitmapData
	{
		var bmp = new BitmapData(w, h, true, 0x00000000);
		var r = radius;

		for (px in 0...w)
		{
			for (py in 0...h)
			{
				var inside = true;

				if (px < r && py < r)
				{
					var dx = r - px, dy = r - py;
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px >= w - r && py < r)
				{
					var dx = px - (w - r - 1), dy = r - py;
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px < r && py >= h - r)
				{
					var dx = r - px, dy = py - (h - r - 1);
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px >= w - r && py >= h - r)
				{
					var dx = px - (w - r - 1), dy = py - (h - r - 1);
					if (dx * dx + dy * dy > r * r) inside = false;
				}

				if (inside) bmp.setPixel32(px, py, color);
			}
		}

		return bmp;
	}

	function devKeyboardIcon(size:Int, bgColor:Int, keyColor:Int):BitmapData
	{
		var bmp = devRoundedRect(size, size, bgColor, Std.int(size * 0.22));

		var margin:Int = Std.int(size * 0.16);
		var cols:Int = 4;
		var gap:Int = Std.int(size * 0.06);
		var usableW:Int = size - margin * 2;
		var keyW:Float = (usableW - gap * (cols - 1)) / cols;
		var keyH:Int = Std.int(size * 0.14);
		var rowY:Int = Std.int(size * 0.28);

		for (col in 0...cols)
		{
			var kx = Std.int(margin + col * (keyW + gap));
			bmp.fillRect(new Rectangle(kx, rowY, keyW, keyH), keyColor);
		}

		var barY:Int = rowY + keyH + gap;
		bmp.fillRect(new Rectangle(margin, barY, usableW, keyH), keyColor);

		return bmp;
	}

	// Same caching approach as FunkinCache/MobileVirtualPad button textures:
	// this per-pixel loop only ever runs once for the lifetime of the app.
	function cachedDevShape(key:String, builder:Void->BitmapData):Dynamic
	{
		var existing = FunkinAssets.cache.currentTrackedGraphics.get(key);
		if (existing != null) return existing;

		var graphic = FunkinAssets.cache.cacheBitmap(key, builder());
		FunkinAssets.cache.currentTrackedGraphics.addPermanentKey(key);
		return graphic;
	}

	function devRoundedRectTop(w:Int, h:Int, color:Int, radius:Int):BitmapData
	{
		var bmp = new BitmapData(w, h, true, 0x00000000);
		var r = radius;

		for (px in 0...w)
		{
			for (py in 0...h)
			{
				var inside = true;

				if (px < r && py < r)
				{
					var dx = r - px, dy = r - py;
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px >= w - r && py < r)
				{
					var dx = px - (w - r - 1), dy = r - py;
					if (dx * dx + dy * dy > r * r) inside = false;
				}

				if (inside) bmp.setPixel32(px, py, color);
			}
		}

		return bmp;
	}

	// Soft radial glow -- full alpha at the center, smoothly falling off to
	// fully transparent at the edge (squared falloff, so it stays bright
	// through the middle instead of looking like a flat-topped circle).
	// Used for the dev panel's audio-synced "epic unlock" burst below.
	function devGlowBlob(size:Int, color:Int):BitmapData
	{
		var bmp = new BitmapData(size, size, true, 0x00000000);
		var cx = size / 2;
		var cy = size / 2;
		var maxDist = size / 2;
		var r = (color >> 16) & 0xFF;
		var g = (color >> 8) & 0xFF;
		var b = color & 0xFF;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				var dx = px - cx;
				var dy = py - cy;
				var dist = Math.sqrt(dx * dx + dy * dy) / maxDist;
				if (dist > 1) continue;

				var a = 1 - dist;
				a *= a;
				var alpha = Std.int(a * 255);
				bmp.setPixel32(px, py, (alpha << 24) | (r << 16) | (g << 8) | b);
			}
		}

		return bmp;
	}

	// ── Dev panel content ────────────────────────────────────────────────────

	function buildDevPanel():Void
	{
		var PW:Int = 560;
		// Was 560 -- already a touch short for the six rows it had (the Close
		// row's own bottom edge landed ~32px past the panel background before
		// this), and the new TOOLS section below adds a full section label +
		// row (~88px) on top of that. Grown to fit both with a little margin
		// to spare instead of compounding the existing overflow.
		var PH:Int = 700;
		var px:Int = Std.int((FlxG.width - PW) / 2);
		var py:Int = Std.int((FlxG.height - PH) / 2);
		var BW:Int = PW - 48;
		var BH:Int = 48;
		var BX:Int = px + 24;

		devPanelX = px;
		devPanelY = py;
		devPanelW = PW;
		devPanelH = PH;

		function reg(thing:FlxSprite):Void
		{
			thing.visible = false;
			devPanelAll.push(thing);
			add(thing);
		}

		// Full-screen dim behind the panel.
		var overlay = new FlxSprite(0, 0);
		overlay.makeGraphic(FlxG.width, FlxG.height, 0xBF000000);
		reg(overlay);

		// Panel body -- proper rounded corners instead of a flat rectangle.
		var bg = new FlxSprite(px, py);
		bg.loadGraphic(cachedDevShape('devpanel_bg', () -> devRoundedRect(PW, PH, DEV_PANEL_BG, 22)));
		reg(bg);

		// Subtle top highlight band (fake gradient: a lighter strip along the
		// top, flat-bottomed so it blends into the panel body beneath it).
		var topBand = new FlxSprite(px, py);
		topBand.loadGraphic(cachedDevShape('devpanel_topband', () -> devRoundedRectTop(PW, 90, DEV_COL_BG, 22)));
		topBand.alpha = 0.9;
		reg(topBand);

		// Accent bar.
		var accent = new FlxSprite(px + 22, py + 18);
		accent.makeGraphic(6, 46, DEV_COL_ACCENT);
		reg(accent);

		// Title -- same AmaticSC-Bold + white + black outline treatment
		// OptionsState uses for its own header, instead of the plain
		// unformatted default font every other FlxText in here used to fall
		// back to.
		var title = new FlxText(px + 40, py + 16, PW - 80, 'DEVELOPER PANEL', 32);
		title.setFormat(Paths.font('AmaticSC-Bold.ttf'), 32, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		reg(title);

		var subtitle = new FlxText(px + 42, py + 50, PW - 80, 'you shouldn\'t be here', 14);
		subtitle.setFormat(Paths.font('vcr.ttf'), 14, DEV_COL_SECTION, LEFT, OUTLINE, FlxColor.BLACK);
		reg(subtitle);

		var rowY:Int = py + 104;

		function sectionLabel(text:String):Void
		{
			var lbl = new FlxText(BX, rowY, BW, text, 14);
			lbl.setFormat(Paths.font('vcr.ttf'), 14, DEV_COL_SECTION, LEFT, OUTLINE, FlxColor.BLACK);
			reg(lbl);
			rowY += 24;
		}

		function addRow(label:String, bgColor:Int, btnIdx:Int, cacheKey:String):FlxText
		{
			var spr = new FlxSprite(BX, rowY);
			spr.loadGraphic(cachedDevShape(cacheKey, () -> devRoundedRect(BW, BH, bgColor, 10)));
			reg(spr);

			var lbl = new FlxText(BX, rowY + 13, BW, label, 18);
			lbl.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
			reg(lbl);

			devPanelBtns.push({x: BX, y: rowY, w: BW, h: BH, idx: btnIdx});
			rowY += BH + 10;
			return lbl;
		}

		sectionLabel('PROGRESSION');
		devLblUnlock = addRow(devUnlockLabel(), ClientPrefs.forceUnlock ? DEV_COL_TOGGLE_ON : DEV_COL_TOGGLE, 0,
			ClientPrefs.forceUnlock ? 'devpanel_toggle_on' : 'devpanel_toggle_off');
		devLblUnlockReq = addRow(devUnlockReqLabel(), ClientPrefs.forceUnlockReq ? DEV_COL_TOGGLE_ON : DEV_COL_TOGGLE, 1,
			ClientPrefs.forceUnlockReq ? 'devpanel_toggle_on' : 'devpanel_toggle_off');
		addRow('Unlock All Cosmetics', DEV_COL_LOOT, 2, 'devpanel_loot');
		addRow('Grant All Achievements', DEV_COL_LOOT, 3, 'devpanel_loot');

		rowY += 6;
		sectionLabel('ECONOMY');
		addRow('Grant 1,000,000 Beans', DEV_COL_MONEY, 4, 'devpanel_money');

		rowY += 6;
		sectionLabel('TOOLS');
		addRow('Editors', DEV_COL_TOOL, 7, 'devpanel_tool');

		rowY += 6;
		sectionLabel('DANGER ZONE');
		devResetBtnSpr = null;
		devLblReset = addRow('!  Reset Money & Cosmetics', DEV_COL_DANGER, 5, 'devpanel_danger');
		// grab the sprite behind the label we just added (last-1 in devPanelAll before the label)
		devResetBtnSpr = devPanelAll[devPanelAll.length - 2];

		rowY += 8;
		addRow('X  Close', DEV_COL_CLOSE, 6, 'devpanel_close');

		// Row highlight for virtual-pad navigation -- added after every row so
		// it draws on top of them, but kept out of devPanelAll/reg() since its
		// own visibility is driven by nav mode (see updateDevPanelSelector()),
		// not the panel open/close cascade every other sprite here uses.
		devPanelSelector = new FlxSprite(BX, devPanelBtns[0].y);
		devPanelSelector.loadGraphic(cachedDevShape('devpanel_selector', () -> devRoundedRect(BW, BH, DEV_COL_ACCENT, 10)));
		devPanelSelector.alpha = 0.35;
		devPanelSelector.visible = false;
		devPanelSelector.scrollFactor.set();
		add(devPanelSelector);

		// Audio-synced glow, centered on the panel and generously sized so it
		// bleeds out past the edges into the dim overlay -- see
		// DEV_UNLOCK_* above and openDevPanel()'s scheduling for the timing.
		// ADD blend so it reads as light washing over the panel instead of
		// covering the text (same trick this state's own background glow
		// uses above, in create()).
		var glowSize = Std.int(PW * 1.3);
		devPanelGlow = new FlxSprite(px + PW / 2 - glowSize / 2, py + PH / 2 - glowSize / 2);
		devPanelGlow.loadGraphic(cachedDevShape('devpanel_glow', () -> devGlowBlob(glowSize, DEV_COL_ACCENT)));
		devPanelGlow.alpha = 0;
		devPanelGlow.visible = false;
		devPanelGlow.blend = ADD;
		devPanelGlow.scrollFactor.set();
		add(devPanelGlow);
	}

	function updateDevPanelSelector():Void
	{
		if (devPanelSelector == null || devPanelBtns.length == 0) return;
		final btn = devPanelBtns[devPanelSelIdx];
		devPanelSelector.x = btn.x;
		devPanelSelector.y = btn.y;
		devPanelSelector.visible = devPanelOpen && ClientPrefs.navInputMode == 'Virtual Pad';
	}

	// No leading check/cross/warning glyphs -- vcr.ttf has no glyph for any of
	// them (confirmed via fonttools cmap), so they rendered as blank boxes on
	// a real device. The ON/OFF text already says which state it's in.
	function devUnlockLabel():String
		return (ClientPrefs.forceUnlock ? 'Unlock Everything  ON' : 'Unlock Everything  OFF');

	function devUnlockReqLabel():String
		return (ClientPrefs.forceUnlockReq ? 'Bypass Requirements  ON' : 'Bypass Requirements  OFF');

	function devResetLabel():String
		return (devResetArmed ? '!  TAP AGAIN TO CONFIRM' : '!  Reset Money & Cosmetics');

	function openDevPanel():Void
	{
		devPanelOpen = true;
		devPanelCooldown = 5;
		devResetArmed = false;

		if (devLblUnlock != null) devLblUnlock.text = devUnlockLabel();
		if (devLblUnlockReq != null) devLblUnlockReq.text = devUnlockReqLabel();
		if (devLblReset != null) devLblReset.text = devResetLabel();

		// Dedicated camera added last = renders on top of everything: game
		// sprites, virtual pad, HUD, all of it. `false` here is load-bearing:
		// FlxG.cameras.add()'s DefaultDrawTarget defaults to true, which would
		// make devPanelCam a default render target for every sprite in this
		// state that doesn't set its own `.cameras` -- i.e. the whole rest of
		// the main menu (background, buttons, star layers, the virtual pad's
		// underlying sprites don't count since those explicitly pin to
		// virtualPadCam, but plenty of others don't) would get silently
		// redrawn a second time on top of everything through this camera,
		// permanently burying the virtual pad under a duplicate opaque
		// background even after the panel itself closes. Every panel sprite
		// (and the selector below) is already explicitly pinned to
		// devPanelCam, so it doesn't need to be a default target at all.
		if (devPanelCam == null)
		{
			devPanelCam = new FlxCamera();
			devPanelCam.bgColor = 0x00000000;
			FlxG.cameras.add(devPanelCam, false);
			for (thing in devPanelAll) thing.cameras = [devPanelCam];
			if (devPanelSelector != null) devPanelSelector.cameras = [devPanelCam];
			if (devPanelGlow != null) devPanelGlow.cameras = [devPanelCam];
		}

		// Layered with unlockSong (the same fanfare the "Grant every
		// achievement" dev button and real content unlocks elsewhere use) so
		// getting into the cheat menu itself feels like an unlock, not just
		// another panel opening.
		FlxG.sound.play(Paths.sound('panelAppear'), 0.6);
		FlxG.sound.play(Paths.sound('unlockSong'), 0.9);

		// Cascading fade/slide-in entrance.
		var i = 0;
		for (thing in devPanelAll)
		{
			thing.visible = true;
			var startY = thing.y;
			thing.y = startY + 18;
			thing.alpha = 0;

			var delay = Math.min(i * 0.012, 0.18);
			FlxTween.tween(thing, {y: startY, alpha: 1}, 0.28, {ease: FlxEase.quintOut, startDelay: delay});
			i++;
		}

		devPanelSelIdx = 0;
		updateDevPanelSelector();

		// Schedule the audio-synced glow: a slow charge-up alpha ramp across
		// the sound's own build-up, then the big payoff timed to land right
		// on the climax (see the DEV_UNLOCK_* comment above and
		// triggerDevPanelUnlockBurst() below). devPanelOpenGen guards both
		// against the panel having since been closed and against it having
		// been closed AND reopened before this fires -- either way, a stale
		// callback from a previous open should not flash/shake the current
		// one (or an empty screen).
		devPanelOpenGen++;
		final myGen = devPanelOpenGen;

		if (devPanelGlow != null)
		{
			FlxTween.cancelTweensOf(devPanelGlow);
			FlxTween.cancelTweensOf(devPanelGlow.scale);
			devPanelGlow.scale.set(1, 1);
			devPanelGlow.alpha = 0;
			devPanelGlow.visible = true;
			FlxTween.tween(devPanelGlow, {alpha: 0.3}, DEV_UNLOCK_CLIMAX_START - DEV_UNLOCK_BUILD_START,
				{ease: FlxEase.sineIn, startDelay: DEV_UNLOCK_BUILD_START});
		}

		haxe.Timer.delay(() -> triggerDevPanelUnlockBurst(myGen), Std.int(DEV_UNLOCK_CLIMAX_START * 1000));
	}

	// The "epic" payoff -- fired via the timer openDevPanel() schedules,
	// timed to land exactly on unlockSong.ogg's sustained peak (see the
	// DEV_UNLOCK_* comment above openDevPanel()). Camera flash/shake are
	// gated behind ClientPrefs.flashing, same convention as
	// StoryMenuState.lockAnim()/FreeplayState's own lock-shake; the glow
	// burst itself isn't a flashing-lights effect (just a shape scaling and
	// fading), so it still plays either way, only dimmer without the flash.
	function triggerDevPanelUnlockBurst(gen:Int):Void
	{
		if (!devPanelOpen || gen != devPanelOpenGen || devPanelGlow == null) return;

		FlxTween.cancelTweensOf(devPanelGlow);
		FlxTween.cancelTweensOf(devPanelGlow.scale);
		devPanelGlow.visible = true;
		devPanelGlow.scale.set(1, 1);
		devPanelGlow.alpha = ClientPrefs.flashing ? 0.9 : 0.5;
		FlxTween.tween(devPanelGlow.scale, {x: 2.2, y: 2.2}, DEV_UNLOCK_BURST_DURATION, {ease: FlxEase.quadOut});
		FlxTween.tween(devPanelGlow, {alpha: 0}, DEV_UNLOCK_BURST_DURATION,
			{ease: FlxEase.quadOut, onComplete: function(_) devPanelGlow.visible = false});

		if (ClientPrefs.flashing && devPanelCam != null)
		{
			devPanelCam.flash(FlxColor.WHITE, 0.4);
			devPanelCam.shake(0.006, 0.2);
		}
	}

	function closeDevPanel():Void
	{
		devPanelOpen = false;
		devResetArmed = false;
		FlxG.sound.play(Paths.sound('panelDisappear'), 0.5);
		for (thing in devPanelAll)
		{
			FlxTween.cancelTweensOf(thing);
			thing.visible = false;
			thing.alpha = 1;
		}
		if (devPanelSelector != null) devPanelSelector.visible = false;
		if (devPanelGlow != null)
		{
			FlxTween.cancelTweensOf(devPanelGlow);
			FlxTween.cancelTweensOf(devPanelGlow.scale);
			devPanelGlow.visible = false;
			devPanelGlow.alpha = 0;
		}
	}

	function handleDevBtnTap(idx:Int):Void
	{
		switch (idx)
		{
			case 0: // Force Unlock toggle
				ClientPrefs.forceUnlock = !ClientPrefs.forceUnlock;
				ClientPrefs.doubletrouble = ClientPrefs.forceUnlock;
				ClientPrefs.flush();
				if (devLblUnlock != null) devLblUnlock.text = devUnlockLabel();
				FlxG.sound.play(Paths.sound('select'), 0.6);

			case 1: // Force Unlock Req toggle
				ClientPrefs.forceUnlockReq = !ClientPrefs.forceUnlockReq;
				ClientPrefs.flush();
				if (devLblUnlockReq != null) devLblUnlockReq.text = devUnlockReqLabel();
				FlxG.sound.play(Paths.sound('select'), 0.6);

			case 2: // Unlock all cosmicube cosmetics
				ClientPrefs.cosmicubeUnlocks = ProgressionUtil.allImpostorItems.copy();
				ClientPrefs.flush();
				FlxG.sound.play(Paths.sound('cosmicubePop'), 0.8);

			case 3: // Grant every achievement
				for (award in GameFlags.getAwards())
					GameFlags.giveAchievement(award.id);
				FlxG.sound.play(Paths.sound('unlockSong'), 0.8);

			case 4: // Grant money
				CosmicubeData.currentMoney += 1000000;
				ClientPrefs.flush();
				FlxG.sound.play(Paths.sound('getbeans'), 0.8);

			case 5: // Reset money + cube unlocks -- two-tap confirm to avoid fat-finger data loss
				if (!devResetArmed)
				{
					devResetArmed = true;
					devResetArmedUntil = haxe.Timer.stamp() + 3.0;
					if (devLblReset != null) devLblReset.text = devResetLabel();
					if (devResetBtnSpr != null)
					{
						var bw = Std.int(devResetBtnSpr.width), bh = Std.int(devResetBtnSpr.height);
						devResetBtnSpr.loadGraphic(cachedDevShape('devpanel_danger_armed', () -> devRoundedRect(bw, bh, DEV_COL_DANGER_ARMED, 10)));
					}
					// 'warn' isn't a real key under assets/legacy/sounds (same
					// gap as 'error' below -- see submitDevCode()'s comment).
					// 'cancelMenu' is already this file's go-to "heads up"
					// blip for the code-entry field's own BACK handling.
					FlxG.sound.play(Paths.sound('cancelMenu'), 0.7);
				}
				else
				{
					CosmicubeData.currentMoney = 0;
					ClientPrefs.cosmicubeUnlocks.resize(0);
					ClientPrefs.flush();
					// Same broken 'error' key -- 'kill' is what
					// MissCounterSubstate already uses for its own "you just
					// confirmed a destructive reset" menu action, so it's a
					// proven fit here too.
					FlxG.sound.play(Paths.sound('kill'), 0.7);
					closeDevPanel();
				}

			case 6: // Close
				closeDevPanel();

			case 7: // Editors -- full MasterEditorMenu hub, not just the chart editor directly
				closeDevPanel();
				FlxG.switchState(new MasterEditorMenu());
		}
	}

	function updateDevPanel():Void
	{
		// ── Desktop keyboard shortcuts (dev convenience on PC/editor) ──────
		if (FlxG.keys.pressed.SHIFT && FlxG.keys.justPressed.SEVEN)
		{
			ClientPrefs.finaleState = (ClientPrefs.finaleState == FinaleState.ACTIVE
				? FinaleState.INACTIVE : FinaleState.ACTIVE);
			ClientPrefs.flush();
			TitleState.initialized = false;
			FlxG.resetGame();
		}
		if (FlxG.keys.justPressed.NINE)
		{
			persistentUpdate = persistentDraw = false;
			openSubState(new CreditsRollSubState(true,
				() -> persistentUpdate = persistentDraw = true,
				() -> persistentUpdate = persistentDraw = true));
		}
		if (FlxG.keys.justPressed.SIX)
		{
			ClientPrefs.forceUnlockReq = !ClientPrefs.forceUnlockReq;
			ClientPrefs.flush();
			trace(ClientPrefs.forceUnlockReq ? 'FORCE UNLOCK REQ ON' : 'FORCE UNLOCK REQ OFF');
		}
		if (FlxG.keys.justPressed.FIVE)
		{
			ClientPrefs.cosmicubeUnlocks.resize(0);
			ClientPrefs.flush();
			trace('Cosmicube progress reset');
		}
		if (FlxG.keys.justPressed.FOUR)
		{
			ClientPrefs.forceUnlock = !ClientPrefs.forceUnlock;
			ClientPrefs.doubletrouble = ClientPrefs.forceUnlock;
			ClientPrefs.flush();
			trace(ClientPrefs.forceUnlock ? 'FORCE UNLOCK ON' : 'FORCE UNLOCK OFF');
		}
		if (FlxG.keys.justPressed.THREE)
		{
			ClientPrefs.unlockedSongs = [];
			ClientPrefs.flush();
			trace('WIPED SONG DATA');
		}
		if (FlxG.keys.justPressed.TWO)
		{
			CosmicubeData.currentMoney += 1000000;
			ClientPrefs.flush();
			trace('FREE MONEY');
		}
		if (FlxG.keys.justPressed.ONE)
		{
			CosmicubeData.currentMoney = 0;
			ClientPrefs.flush();
			trace('no money :(');
		}

		// ── Panel interaction (only reachable via the shake gesture or the
		// code-entry gate) ──────────────────────────────────────────────────
		if (!devPanelOpen) return;

		if (devPanelCooldown > 0) { devPanelCooldown--; return; }

		// Auto-revert the destructive-reset arm state if the player doesn't
		// confirm within the window.
		if (devResetArmed && haxe.Timer.stamp() > devResetArmedUntil)
		{
			devResetArmed = false;
			if (devLblReset != null) devLblReset.text = devResetLabel();
			if (devResetBtnSpr != null)
			{
				var bw = Std.int(devResetBtnSpr.width), bh = Std.int(devResetBtnSpr.height);
				devResetBtnSpr.loadGraphic(cachedDevShape('devpanel_danger', () -> devRoundedRect(bw, bh, DEV_COL_DANGER, 10)));
			}
		}

		if (ClientPrefs.navInputMode == 'Virtual Pad')
		{
			// Same D-pad-moves-a-highlighted-row + Action-confirms pattern
			// CosmeticsSubstate's grid uses -- the panel reuses this state's
			// own virtualPad (still visible while the panel is open) instead
			// of spawning a second one.
			if (controls.UI_UP_P)
			{
				devPanelSelIdx = (devPanelSelIdx > 0) ? devPanelSelIdx - 1 : devPanelBtns.length - 1;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
				updateDevPanelSelector();
			}
			else if (controls.UI_DOWN_P)
			{
				devPanelSelIdx = (devPanelSelIdx + 1) % devPanelBtns.length;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
				updateDevPanelSelector();
			}
			if (controls.ACCEPT) handleDevBtnTap(devPanelBtns[devPanelSelIdx].idx);
			if (controls.BACK) closeDevPanel();
		}
		else
		{
			var touches = FlxG.touches.list;
			if (touches != null)
			{
				for (touch in touches)
				{
					if (!touch.justReleased) continue;
					var tapped = false;
					for (btn in devPanelBtns)
					{
						if (touch.x >= btn.x && touch.x <= btn.x + btn.w &&
						    touch.y >= btn.y && touch.y <= btn.y + btn.h)
						{
							handleDevBtnTap(btn.idx);
							tapped = true;
							break;
						}
					}
					// Only close on a tap that lands fully outside the panel
					// body -- a near-miss between two rows (still inside the
					// panel) used to close the whole thing on any stray touch,
					// which felt like a hair trigger for something you have
					// to enter a secret code to even open.
					if (!tapped && !devPanelContains(touch.x, touch.y)) closeDevPanel();
					break;
				}
			}
		}
	}

	function devPanelContains(x:Float, y:Float):Bool
	{
		return x >= devPanelX && x <= devPanelX + devPanelW && y >= devPanelY && y <= devPanelY + devPanelH;
	}
}
