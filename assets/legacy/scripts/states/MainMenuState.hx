import funkin.data.ClientPrefs;
import funkin.data.FinaleState;
import funkin.data.CosmicubeData;
import funkin.data.GameFlags;
import funkin.utils.ProgressionUtil;
import funkin.states.TitleState;
import flixel.text.FlxText;
import flixel.FlxSprite;
import flixel.FlxCamera;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.sensors.Accelerometer;
import openfl.events.AccelerometerEvent;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.KeyboardEvent;

// ── Secret gesture: shake the device to open the panel ───────────────────────
// Deliberately NOT a tap/hold/touch gesture and NOT a typed code — the panel
// is undocumented in-game. Tune these if it feels too twitchy or too stubborn;
// values are in Gs (1.0 = standing still) since that's the unit OpenFL's
// Accelerometer reports in.
var accel:Accelerometer          = null;
var lastAccelMag:Float            = 1.0;
var shakeTimestamps:Array<Float>  = [];
var shakeCooldownUntil:Float      = 0;
var SHAKE_DELTA:Float             = 1.6;  // jolt size (Gs) to count as one shake peak
var SHAKE_PEAK_COOLDOWN:Float      = 0.22; // min gap between counted peaks
var SHAKE_COUNT_NEEDED:Int        = 4;    // peaks required
var SHAKE_WINDOW:Float            = 2.2;  // all peaks must land within this many seconds

// Ambient "charge" glow — a small, unlabeled dot that quietly brightens with
// each shake. Nothing explains what it is; only someone who already knows
// the gesture will recognize it building.
var chargeGlow:FlxSprite = null;

// ── Second access route: a typed code on the device keyboard ────────────────
// Unlike the shake, this one is meant to be findable — a small, deliberately
// styled corner button that opens a real text field (native Android keyboard
// pops up automatically once it gets focus). Change DEV_CODE to whatever you want.
var DEV_CODE:String = 'nightmare';

var CODE_TRIGGER_SIZE:Int   = 28;
var CODE_TRIGGER_MARGIN:Int = 12;

var codeTriggerBg:FlxSprite  = null;
var codeField:TextField      = null;
var codeBoxOpen:Bool         = false;

// ── Dev panel state ───────────────────────────────────────────────────────────
var panelOpen:Bool          = false;
var panelAll:Array<Dynamic> = [];   // every sprite/text belonging to the panel
var panelBtns:Array<Dynamic> = [];  // {x, y, w, h, idx} button hit-boxes
var panelCooldown:Int       = 0;
var panelCam:Dynamic        = null; // dedicated top-most camera, always renders above game sprites

var lblUnlock:FlxText    = null;
var lblUnlockReq:FlxText = null;
var lblReset:FlxText     = null;
var resetBtnSpr:FlxSprite = null;

// Two-tap confirm guard for the destructive reset button.
var resetArmed:Bool      = false;
var resetArmedUntil:Float = 0;

// Panel palette
var COL_BG:Int       = 0xFF0B0B18;
var COL_BG_TOP:Int   = 0xFF14142A;
var COL_ACCENT:Int   = 0xFF9D5CFF;
var COL_SECTION:Int  = 0xFF6B6B9E;
var COL_TOGGLE:Int   = 0xFF1E1B4B;
var COL_TOGGLE_ON:Int = 0xFF3730A5;
var COL_LOOT:Int     = 0xFF4C1D95;
var COL_MONEY:Int    = 0xFF14532D;
var COL_DANGER:Int   = 0xFF7F1D1D;
var COL_DANGER_ARMED:Int = 0xFFB91C1C;
var COL_CLOSE:Int    = 0xFF17171F;

// ─────────────────────────────────────────────────────────────────────────────
function onLoad()
{
	if (!ClientPrefs.inDevMode) return;

	// Quiet corner glow — the only visible trace of the whole system, and it
	// says nothing. Sits bottom-right, basically invisible until it charges.
	chargeGlow = new FlxSprite(FlxG.width - 16, FlxG.height - 16);
	chargeGlow.makeGraphic(6, 6, COL_ACCENT);
	chargeGlow.alpha = 0;
	chargeGlow.scrollFactor.set();
	add(chargeGlow);

	if (Accelerometer.isSupported)
	{
		accel = new Accelerometer();
		accel.addEventListener(AccelerometerEvent.UPDATE, onAccelUpdate);
	}

	// Small, visible corner button — top-right — for the code-entry route.
	// Understated but findable on purpose; the icon itself reads as a tiny
	// stylized keyboard so it doesn't need a text label to explain itself.
	codeTriggerBg = new FlxSprite(FlxG.width - CODE_TRIGGER_SIZE - CODE_TRIGGER_MARGIN, CODE_TRIGGER_MARGIN);
	codeTriggerBg.pixels = keyboardIcon(CODE_TRIGGER_SIZE, COL_BG_TOP, COL_ACCENT);
	codeTriggerBg.alpha = 0.75;
	codeTriggerBg.scrollFactor.set();
	add(codeTriggerBg);
}

// buildPanel() runs here — AFTER the compiled state finishes adding all menu
// sprites — so the panel overlay renders on top of everything (z-index fix).
function onCreatePost()
{
	if (!ClientPrefs.inDevMode) return;
	buildPanel();
}

function onDestroy()
{
	if (accel != null)
	{
		accel.removeEventListener(AccelerometerEvent.UPDATE, onAccelUpdate);
		accel = null;
	}
	closeCodeBox(false);
}

// ── Code-entry route ──────────────────────────────────────────────────────────
function toggleCodeBox()
{
	if (codeBoxOpen) closeCodeBox(false);
	else openCodeBox();
}

function openCodeBox()
{
	if (codeField != null) return;
	codeBoxOpen = true;
	pulseCodeTrigger(true);

	var format = new TextFormat(null, 20, 0xFFECE8FF);
	format.align = TextFormatAlign.CENTER;

	codeField = new TextField();
	codeField.type = TextFieldType.INPUT;
	codeField.width = 260;
	codeField.height = 40;
	codeField.background = true;
	codeField.backgroundColor = 0xFF14142A;
	codeField.border = true;
	codeField.borderColor = COL_ACCENT;
	codeField.defaultTextFormat = format;
	codeField.multiline = false;
	codeField.maxChars = 32;
	codeField.text = '';

	// Anchored to the raw window corner (not the logical Flixel resolution),
	// tucked just under the keyboard-icon button in the top-right. On a
	// device whose aspect ratio doesn't match, this may need nudging —
	// adjust these two offsets if it lands somewhere odd on-device.
	codeField.x = FlxG.stage.stageWidth - 272;
	codeField.y = 56;

	try
	{
		FlxG.game.parent.addChild(codeField);
		FlxG.stage.focus = codeField;
		codeField.setSelection(0, 0);
	}
	catch (e:Dynamic) { trace('code box: failed to attach text field — $e'); }

	codeField.addEventListener(KeyboardEvent.KEY_DOWN, onCodeFieldKey);
}

function pulseCodeTrigger(active:Bool)
{
	if (codeTriggerBg == null) return;
	FlxTween.cancelTweensOf(codeTriggerBg.scale);
	codeTriggerBg.alpha = active ? 1.0 : 0.75;
	codeTriggerBg.scale.set(active ? 1.15 : 1.0, active ? 1.15 : 1.0);
	FlxTween.tween(codeTriggerBg.scale, {x: 1.0, y: 1.0}, 0.25, {ease: FlxEase.quadOut});
}

function onCodeFieldKey(e:Dynamic)
{
	if (e.keyCode == 13) submitCode(); // Enter / Done on the soft keyboard
}

function submitCode()
{
	if (codeField == null) return;

	var typed = StringTools.trim(codeField.text).toLowerCase();
	if (typed == DEV_CODE)
	{
		closeCodeBox(true);
		openPanel();
	}
	else
	{
		codeField.text = '';
		codeField.backgroundColor = COL_DANGER;
		FlxG.sound.play(Paths.sound('error'), 0.6);
		haxe.Timer.delay(function() {
			if (codeField != null) codeField.backgroundColor = 0xFF14142A;
		}, 400);
	}
}

function closeCodeBox(success:Bool)
{
	codeBoxOpen = false;
	pulseCodeTrigger(false);

	if (codeField == null) return;

	codeField.removeEventListener(KeyboardEvent.KEY_DOWN, onCodeFieldKey);
	if (FlxG.stage.focus == codeField) FlxG.stage.focus = null;
	try { if (codeField.parent != null) codeField.parent.removeChild(codeField); }
	catch (e:Dynamic) {}
	codeField = null;

	if (!success) FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
}

// ── Shake detection ───────────────────────────────────────────────────────────
function onAccelUpdate(e:Dynamic)
{
	if (panelOpen) return;

	var mag = Math.sqrt(e.accelerationX * e.accelerationX + e.accelerationY * e.accelerationY + e.accelerationZ * e.accelerationZ);
	var delta = Math.abs(mag - lastAccelMag);
	lastAccelMag = mag;

	var now = haxe.Timer.stamp();
	if (delta < SHAKE_DELTA || now < shakeCooldownUntil) return;

	shakeCooldownUntil = now + SHAKE_PEAK_COOLDOWN;

	shakeTimestamps.push(now);
	while (shakeTimestamps.length > 0 && now - shakeTimestamps[0] > SHAKE_WINDOW)
		shakeTimestamps.shift();

	pulseCharge(shakeTimestamps.length / SHAKE_COUNT_NEEDED);

	if (shakeTimestamps.length >= SHAKE_COUNT_NEEDED)
	{
		shakeTimestamps = [];
		resetCharge();
		openPanel();
	}
}

function pulseCharge(progress:Float)
{
	if (chargeGlow == null) return;
	FlxTween.cancelTweensOf(chargeGlow);
	chargeGlow.alpha = Math.min(progress, 1.0);
	chargeGlow.scale.set(1 + progress, 1 + progress);
	FlxTween.tween(chargeGlow, {alpha: 0}, 0.7, {ease: FlxEase.quadOut});
}

function resetCharge()
{
	if (chargeGlow == null) return;
	FlxTween.cancelTweensOf(chargeGlow);
	chargeGlow.alpha = 0;
	chargeGlow.scale.set(1, 1);
}

// ── Rounded-rect bitmap helper (built once per panel, cheap to cache) ────────
function roundedRect(w:Int, h:Int, color:Int, radius:Int):BitmapData
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

// Same as roundedRect() but only rounds the TOP two corners, with a flat
// bottom edge — for strips meant to blend seamlessly into whatever sits
// beneath them (e.g. a top highlight band inside a larger rounded panel).
function roundedRectTop(w:Int, h:Int, color:Int, radius:Int):BitmapData
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

// Small stylized keyboard glyph, drawn procedurally (no font-glyph reliance,
// no risk of a Unicode symbol silently failing to render): a rounded body
// with a 4-column row of key-caps and a wide spacebar row underneath.
function keyboardIcon(size:Int, bgColor:Int, keyColor:Int):BitmapData
{
	var bmp = roundedRect(size, size, bgColor, Std.int(size * 0.22));

	var margin:Int  = Std.int(size * 0.16);
	var cols:Int    = 4;
	var gap:Int     = Std.int(size * 0.06);
	var usableW:Int = size - margin * 2;
	var keyW:Float  = (usableW - gap * (cols - 1)) / cols;
	var keyH:Int    = Std.int(size * 0.14);
	var rowY:Int    = Std.int(size * 0.28);

	for (col in 0...cols)
	{
		var kx = Std.int(margin + col * (keyW + gap));
		bmp.fillRect(new Rectangle(kx, rowY, keyW, keyH), keyColor);
	}

	var barY:Int = rowY + keyH + gap;
	bmp.fillRect(new Rectangle(margin, barY, usableW, keyH), keyColor);

	return bmp;
}

// ─────────────────────────────────────────────────────────────────────────────
function buildPanel()
{
	var PW:Int = 560;
	var PH:Int = 560;
	var px:Int = Std.int((FlxG.width  - PW) / 2);
	var py:Int = Std.int((FlxG.height - PH) / 2);
	var BW:Int = PW - 48;
	var BH:Int = 48;
	var BX:Int = px + 24;

	function reg(thing) { thing.visible = false; panelAll.push(thing); add(thing); }

	// Full-screen dim behind the panel.
	var overlay = new FlxSprite(0, 0);
	overlay.makeGraphic(FlxG.width, FlxG.height, 0xBF000000);
	reg(overlay);

	// Panel body — proper rounded corners instead of a flat rectangle.
	var bgBmp = roundedRect(PW, PH, COL_BG, 22);
	var bg = new FlxSprite(px, py);
	bg.pixels = bgBmp;
	reg(bg);

	// Subtle top highlight band (fake gradient: a lighter strip along the top,
	// flat-bottomed so it blends into the panel body beneath it).
	var topBmp = roundedRectTop(PW, 90, COL_BG_TOP, 22);
	var topBand = new FlxSprite(px, py);
	topBand.pixels = topBmp;
	topBand.alpha = 0.9;
	reg(topBand);

	// Accent bar.
	var accent = new FlxSprite(px + 22, py + 18);
	accent.makeGraphic(6, 46, COL_ACCENT);
	reg(accent);

	// Title.
	var title = new FlxText(px + 40, py + 20, PW - 80, 'DEVELOPER PANEL', 24);
	title.color = 0xFFECE8FF;
	reg(title);

	var subtitle = new FlxText(px + 40, py + 48, PW - 80, 'you shouldn\'t be here', 12);
	subtitle.color = 0xFF6B6B9E;
	reg(subtitle);

	var rowY:Int = py + 104;

	function sectionLabel(text:String)
	{
		var lbl = new FlxText(BX, rowY, BW, text, 13);
		lbl.color = COL_SECTION;
		reg(lbl);
		rowY += 24;
	}

	function addRow(label:String, bgColor:Int, btnIdx:Int):FlxText
	{
		var sprBmp = roundedRect(BW, BH, bgColor, 10);
		var spr = new FlxSprite(BX, rowY);
		spr.pixels = sprBmp;
		reg(spr);

		var lbl = new FlxText(BX, rowY + 14, BW, label, 16);
		lbl.alignment = 'center';
		lbl.color = 0xFFFFFFFF;
		reg(lbl);

		panelBtns.push({x: BX, y: rowY, w: BW, h: BH, idx: btnIdx});
		rowY += BH + 10;
		return lbl;
	}

	sectionLabel('PROGRESSION');
	lblUnlock    = addRow(unlockLabel(),    ClientPrefs.forceUnlock    ? COL_TOGGLE_ON : COL_TOGGLE, 0);
	lblUnlockReq = addRow(unlockReqLabel(), ClientPrefs.forceUnlockReq ? COL_TOGGLE_ON : COL_TOGGLE, 1);
	                addRow('◆  Unlock All Cosmetics',   COL_LOOT,  2);
	                addRow('★  Grant All Achievements', COL_LOOT,  3);

	rowY += 6;
	sectionLabel('ECONOMY');
	                addRow('Grant 1,000,000 Beans', COL_MONEY, 4);

	rowY += 6;
	sectionLabel('DANGER ZONE');
	resetBtnSpr = null;
	lblReset = addRow('⚠  Reset Money & Cosmetics', COL_DANGER, 5);
	// grab the sprite behind the label we just added (last-1 in panelAll before the label)
	resetBtnSpr = panelAll[panelAll.length - 2];

	rowY += 8;
	addRow('✕  Close', COL_CLOSE, 6);
}

// ─────────────────────────────────────────────────────────────────────────────
function unlockLabel():String
	return (ClientPrefs.forceUnlock    ? '✓  Unlock Everything  ON'  : '✗  Unlock Everything  OFF');

function unlockReqLabel():String
	return (ClientPrefs.forceUnlockReq ? '✓  Bypass Requirements  ON' : '✗  Bypass Requirements  OFF');

function resetLabel():String
	return (resetArmed ? '⚠  TAP AGAIN TO CONFIRM' : '⚠  Reset Money & Cosmetics');

function openPanel()
{
	panelOpen = true;
	panelCooldown = 5;
	resetArmed = false;

	if (lblUnlock    != null) lblUnlock.text    = unlockLabel();
	if (lblUnlockReq != null) lblUnlockReq.text = unlockReqLabel();
	if (lblReset     != null) lblReset.text     = resetLabel();

	// Dedicated camera added last = renders on top of everything: game
	// sprites, virtual pad, HUD, all of it.
	if (panelCam == null)
	{
		panelCam = new FlxCamera();
		panelCam.bgColor = 0x00000000;
		FlxG.cameras.add(panelCam);
		for (thing in panelAll) thing.cameras = [panelCam];
	}

	FlxG.sound.play(Paths.sound('panelAppear'), 0.6);

	// Cascading fade/slide-in entrance.
	var i = 0;
	for (thing in panelAll)
	{
		thing.visible = true;
		var startY = thing.y;
		thing.y = startY + 18;
		thing.alpha = 0;

		var delay = Math.min(i * 0.012, 0.18);
		FlxTween.tween(thing, {y: startY, alpha: 1}, 0.28, {ease: FlxEase.quintOut, startDelay: delay});
		i++;
	}
}

function closePanel()
{
	panelOpen = false;
	resetArmed = false;
	FlxG.sound.play(Paths.sound('panelDisappear'), 0.5);
	for (thing in panelAll)
	{
		FlxTween.cancelTweensOf(thing);
		thing.visible = false;
		thing.alpha = 1;
	}
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
			FlxG.sound.play(Paths.sound('select'), 0.6);

		case 1: // Force Unlock Req toggle
			ClientPrefs.forceUnlockReq = !ClientPrefs.forceUnlockReq;
			ClientPrefs.flush();
			if (lblUnlockReq != null) lblUnlockReq.text = unlockReqLabel();
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

		case 5: // Reset money + cube unlocks — two-tap confirm to avoid fat-finger data loss
			if (!resetArmed)
			{
				resetArmed = true;
				resetArmedUntil = haxe.Timer.stamp() + 3.0;
				if (lblReset != null) lblReset.text = resetLabel();
				if (resetBtnSpr != null)
				{
					var armedBmp = roundedRect(Std.int(resetBtnSpr.width), Std.int(resetBtnSpr.height), COL_DANGER_ARMED, 10);
					resetBtnSpr.pixels = armedBmp;
				}
				FlxG.sound.play(Paths.sound('warn'), 0.7);
			}
			else
			{
				CosmicubeData.currentMoney = 0;
				ClientPrefs.cosmicubeUnlocks.resize(0);
				ClientPrefs.flush();
				FlxG.sound.play(Paths.sound('error'), 0.7);
				closePanel();
			}

		case 6: // Close
			closePanel();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
function onUpdate()
{
	if (!ClientPrefs.inDevMode) return;

	// ── Desktop keyboard shortcuts (unchanged — dev convenience on PC/editor) ──
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

	// ── Code-entry trigger (only live while the panel itself isn't open) ────
	// Note: only the trigger toggles the box. We deliberately don't try to
	// detect "tapped outside the field" here — the raw TextField lives in
	// real window pixels while FlxG.touches reports logical game coordinates,
	// so the two don't line up and a naive "anything else closes it" check
	// would fire the moment you tap the field itself to type.
	if (!panelOpen)
	{
		var touches = FlxG.touches.list;
		if (touches != null)
		{
			for (touch in touches)
			{
				if (!touch.justReleased) continue;
				var triggerX0 = FlxG.width - CODE_TRIGGER_SIZE - CODE_TRIGGER_MARGIN - 6;
				var triggerX1 = FlxG.width - CODE_TRIGGER_MARGIN + 6;
				var triggerY0 = CODE_TRIGGER_MARGIN - 6;
				var triggerY1 = CODE_TRIGGER_MARGIN + CODE_TRIGGER_SIZE + 6;
				if (touch.x >= triggerX0 && touch.x <= triggerX1 && touch.y >= triggerY0 && touch.y <= triggerY1)
					toggleCodeBox();
				break;
			}
		}
	}

	// ── Panel interaction (only reachable via the shake gesture or code) ────
	if (!panelOpen) return;

	// The panel opened while the code box was still up — tidy it away.
	if (codeBoxOpen) closeCodeBox(true);

	if (panelCooldown > 0) { panelCooldown--; return; }

	// Auto-revert the destructive-reset arm state if the player doesn't
	// confirm within the window.
	if (resetArmed && haxe.Timer.stamp() > resetArmedUntil)
	{
		resetArmed = false;
		if (lblReset != null) lblReset.text = resetLabel();
		if (resetBtnSpr != null)
		{
			var idleBmp = roundedRect(Std.int(resetBtnSpr.width), Std.int(resetBtnSpr.height), COL_DANGER, 10);
			resetBtnSpr.pixels = idleBmp;
		}
	}

	var touches = FlxG.touches.list;
	if (touches != null)
	{
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
			if (!tapped) closePanel();
			break;
		}
	}
}
