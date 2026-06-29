import funkin.data.ClientPrefs;
import funkin.data.FinaleState;
import funkin.data.CosmicubeData;
import funkin.states.TitleState;
import flixel.text.FlxText;
import flixel.FlxSprite;

// ── 2-finger hold progress bar ────────────────────────────────────────────────
var holdTime:Float  = 0;
var HOLD_TRIGGER:Float = 1.0;
var holdBar:FlxSprite  = null;
var holdFill:FlxSprite = null;

// ── Dev panel ─────────────────────────────────────────────────────────────────
var panelOpen:Bool = false;
var panelAll:Array<Dynamic>  = [];  // every sprite/text that belongs to the panel
var panelBtns:Array<Dynamic> = [];  // {x, y, w, h, idx} button hit-boxes
var panelCooldown:Int = 0;
var panelCam:Dynamic = null;          // dedicated top-most camera so panel always renders above game sprites
var panelWaitingForAllUp:Bool = false; // blocks input until hold-gesture fingers fully lift

var lblUnlock:FlxText    = null;
var lblUnlockReq:FlxText = null;

// ─────────────────────────────────────────────────────────────────────────────
function onLoad()
{
	if (!ClientPrefs.inDevMode) return;

	var debugText = new FlxText(0, 0, 1280,
		'content/scripts/states/MainMenuState.hx\n' +
		'Press 9 to go to credits roll sequence\n' +
		'Press Shift 7 to toggle Finale Endgame Sequence\n' +
		'Press 6 to Force unlock Cosmicube requirements\n' +
		'Press 5 to delete Cosmicube unlocks\n' +
		'Press 4 to toggle Force Unlock for freeplay and story mode\n' +
		'Press 3 to delete bought songs\n' +
		'Press 2 to be rich\n' +
		'Press 1 to be poor\n' +
		'[ Mobile: hold 2 fingers 1 s to open dev panel ]',
		12.5);
	debugText.alignment = 'right';
	add(debugText);

	// ── Hold-progress bar (drawn at bottom of screen) ────────────────────────
	holdBar = new FlxSprite(0, FlxG.height - 8);
	holdBar.makeGraphic(FlxG.width, 8, 0xFF1A1A2E);
	holdBar.visible = false;
	add(holdBar);

	holdFill = new FlxSprite(0, FlxG.height - 8);
	holdFill.makeGraphic(FlxG.width, 8, 0xFF7C3AED);
	holdFill.scale.x = 0;
	holdFill.origin.x = 0;
	holdFill.visible = false;
	add(holdFill);
}

// buildPanel() is called here — AFTER the compiled state finishes adding all menu sprites
// so the panel overlay renders on top of everything (z-index fix).
function onCreatePost()
{
	if (!ClientPrefs.inDevMode) return;
	buildPanel();
}

// ─────────────────────────────────────────────────────────────────────────────
function buildPanel()
{
	var PW:Int = 500;
	var PH:Int = 360;
	var px:Int = Std.int((FlxG.width  - PW) / 2);
	var py:Int = Std.int((FlxG.height - PH) / 2);
	var BW:Int = PW - 44;
	var BH:Int = 52;
	var BX:Int = px + 22;

	function reg(thing) { thing.visible = false; panelAll.push(thing); add(thing); }

	// Semi-transparent full-screen dim
	var overlay = new FlxSprite(0, 0);
	overlay.makeGraphic(FlxG.width, FlxG.height, 0xAA000000);
	reg(overlay);

	// Panel background
	var bg = new FlxSprite(px, py);
	bg.makeGraphic(PW, PH, 0xFF0F0F1E);
	reg(bg);

	// Accent bar at top of panel
	var accent = new FlxSprite(px, py);
	accent.makeGraphic(PW, 6, 0xFF7C3AED);
	reg(accent);

	// Title
	var title = new FlxText(px, py + 14, PW, 'DEV PANEL', 22);
	title.alignment = 'center';
	title.color = 0xFFDDD6FE;
	reg(title);

	// Divider
	var div = new FlxSprite(px + 20, py + 50);
	div.makeGraphic(PW - 40, 1, 0xFF2D2D5E);
	reg(div);

	// ── Helper: add one button row ────────────────────────────────────────────
	var rowY:Int = py + 64;

	function addRow(label:String, bgColor:Int, btnIdx:Int):FlxText
	{
		var spr = new FlxSprite(BX, rowY);
		spr.makeGraphic(BW, BH, bgColor);
		reg(spr);

		var lbl = new FlxText(BX, rowY + 15, BW, label, 16);
		lbl.alignment = 'center';
		lbl.color = 0xFFFFFFFF;
		reg(lbl);

		panelBtns.push({x: BX, y: rowY, w: BW, h: BH, idx: btnIdx});
		rowY += BH + 8;
		return lbl;
	}

	// Button rows — idx matches the switch in handleBtnTap()
	lblUnlock    = addRow(unlockLabel(),    0xFF1E1B4B, 0);
	lblUnlockReq = addRow(unlockReqLabel(), 0xFF1E1B4B, 1);
	                addRow('Give Max Money 💰',      0xFF14532D, 2);
	                addRow('Reset Money & Cube Unlocks', 0xFF7F1D1D, 3);
	                addRow('✕  Close',               0xFF1C1C1C, 4);
}

// ─────────────────────────────────────────────────────────────────────────────
function unlockLabel():String
	return (ClientPrefs.forceUnlock    ? '✓  Force Unlock  ON'  : '✗  Force Unlock  OFF');

function unlockReqLabel():String
	return (ClientPrefs.forceUnlockReq ? '✓  Force Unlock Req  ON' : '✗  Force Unlock Req  OFF');

function openPanel()
{
	panelOpen = true;
	panelCooldown = 5;
	panelWaitingForAllUp = true; // block input until hold-gesture fingers fully lift

	if (lblUnlock    != null) lblUnlock.text    = unlockLabel();
	if (lblUnlockReq != null) lblUnlockReq.text = unlockReqLabel();

	// Assign panel sprites to a dedicated camera added last in the list.
	// Being last = renders on top of everything: game sprites, virtual pad, etc.
	if (panelCam == null)
	{
		panelCam = new FlxCamera();
		panelCam.bgColor = 0x00000000;
		FlxG.cameras.add(panelCam);
		for (thing in panelAll) thing.cameras = [panelCam];
	}

	for (thing in panelAll) thing.visible = true;
}

function closePanel()
{
	panelOpen = false;
	for (thing in panelAll) thing.visible = false;
}

function handleBtnTap(idx:Int)
{
	switch (idx)
	{
		case 0: // Force Unlock toggle
			ClientPrefs.forceUnlock = !ClientPrefs.forceUnlock;
			ClientPrefs.doubletrouble = ClientPrefs.forceUnlock;
			ClientPrefs.flush();
			if (lblUnlock != null) lblUnlock.text = unlockLabel();

		case 1: // Force Unlock Req toggle
			ClientPrefs.forceUnlockReq = !ClientPrefs.forceUnlockReq;
			ClientPrefs.flush();
			if (lblUnlockReq != null) lblUnlockReq.text = unlockReqLabel();

		case 2: // Max money
			CosmicubeData.currentMoney = 2_147_483_647;
			ClientPrefs.flush();

		case 3: // Reset money + cube unlocks
			CosmicubeData.currentMoney = 0;
			ClientPrefs.cosmicubeUnlocks.resize(0);
			ClientPrefs.flush();
			closePanel();

		case 4: // Close
			closePanel();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
function onUpdate()
{
	if (!ClientPrefs.inDevMode) return;

	// ── Desktop keyboard shortcuts (unchanged) ────────────────────────────────
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
		openSubState(new funkin.states.substates.CreditsRollSubState(true,
			function() persistentUpdate = persistentDraw = true,
			function() persistentUpdate = persistentDraw = true));
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

	// ── Mobile: 2-finger hold gesture ────────────────────────────────────────
	var touches = FlxG.touches.list;
	if (touches == null || touches.length == 0)
	{
		resetHold();
		if (panelWaitingForAllUp) panelWaitingForAllUp = false; // all fingers lifted, ready for new input
		return;
	}

	// If panel is open, check for button taps on release
	if (panelOpen)
	{
		if (panelCooldown > 0) { panelCooldown--; return; }

		// Don't process taps until hold-gesture fingers have fully lifted
		if (panelWaitingForAllUp) return;

		for (touch in touches)
		{
			if (!touch.justReleased) continue;
			var tapped = false;
			for (btn in panelBtns)
			{
				if (touch.x >= btn.x && touch.x <= btn.x + btn.w &&
				    touch.y >= btn.y && touch.y <= btn.y + btn.h)
				{
					handleBtnTap(btn.idx);
					tapped = true;
					break;
				}
			}
			if (!tapped) closePanel(); // tap outside panel → dismiss
			break;
		}
		return;
	}

	// Count how many fingers are currently held down
	var fingers:Int = 0;
	for (t in touches) if (t.pressed) fingers++;

	if (fingers >= 2)
	{
		holdTime += FlxG.elapsed;

		if (holdBar  != null) holdBar.visible  = true;
		if (holdFill != null)
		{
			holdFill.visible = true;
			holdFill.scale.x = Math.min(holdTime / HOLD_TRIGGER, 1.0);
		}

		if (holdTime >= HOLD_TRIGGER)
		{
			resetHold();
			openPanel();
		}
	}
	else
	{
		resetHold();
	}
}

function resetHold()
{
	holdTime = 0;
	if (holdBar  != null) holdBar.visible  = false;
	if (holdFill != null) { holdFill.visible = false; holdFill.scale.x = 0; }
}
