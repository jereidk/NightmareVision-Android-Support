package funkin.states.options;

import funkin.backend.MusicBeatSubstate;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.graphics.frames.FlxTileFrames;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.input.touch.FlxTouch;

import flixel.addons.display.FlxBackdrop;

import mobile.controls.MobileVirtualPad;
import mobile.backend.flixel.FlxButton;
import mobile.backend.flixel.input.FlxMobileInputID;
import mobile.utils.MobileNavUtil;
import funkin.data.ClientPrefs;
import funkin.Paths;

/**
 * Improved Virtual Pad customizer with:
 * - Collision detection between buttons (like Shadow Engine's bounds system)
 * - Drag all directional buttons with proper snapping
 * - Persistent save/load via ClientPrefs customPadPositions + customPadPositionsJson
 * - Visual layout preview
 * - Save & Exit / Reset buttons
 */
class VirtualPadCustomizerSubState extends MusicBeatSubstate
{
	static final DIR_NAMES = ['LEFT', 'DOWN', 'UP', 'RIGHT'];
	static final DIR_COLORS = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000];
	static final DIR_KEYS  = ['buttonLeft', 'buttonDown', 'buttonUp', 'buttonRight'];

	/** Minimum separation between button edges (prevents overlap). */
	static final MIN_GAP:Float = 6;

	/** Keyboard/gamepad nudge: single-press step, and px/sec while held. */
	static inline final NUDGE_STEP:Float = 8;
	static inline final NUDGE_SPEED:Float = 220;

	var dragButtons:Array<DragButton> = [];

	var saveBtn:FlxSprite;
	var resetBtn:FlxSprite;
	var statusText:FlxText;

	var dragIdx:Int = -1;
	var offsetX:Float = 0;
	var offsetY:Float = 0;

	/** Button bounding boxes for overlap check (invisible, used like Shadow Engine's TouchButton.bounds). */
	var _boundsList:Array<FlxRect> = [];

	// ── Keyboard / gamepad focus ─────────────────────────────────────────────
	// This whole screen was mouse/touch-only before -- a keyboard or gamepad
	// user could open and close it, but had no way to actually move a button,
	// unlike every other options screen in this app. 0-3 = the four direction
	// buttons, 4 = SAVE & EXIT, 5 = RESET; UP/DOWN cycles focus between them,
	// ACCEPT "grabs" a direction button (entering _kbMoveMode) the same way a
	// mouse-down does, and the arrow keys then nudge it -- ACCEPT again drops
	// it, mirroring mouse-up.
	static inline final KB_FOCUS_COUNT:Int = 6; // 4 buttons + save + reset
	var _kbFocus:Int = 0;
	var _kbMoveMode:Bool = false;
	var _kbHoldTime:Float = 0.0;
	var _defaultHint:String;

	override function create()
	{
		// ── Background (scrolling stars, matches OptionsState) ──
		var starsBG = new FlxBackdrop(Paths.image('menu/common/starBG'));
		starsBG.velocity.x = -4.5;
		add(starsBG);

		var starsFG = new FlxBackdrop(Paths.image('menu/common/starFG'));
		starsFG.velocity.x = -9;
		add(starsFG);

		// ── Header bar ──
		var topBar = new FlxSprite(0, 0);
		topBar.loadGraphic(Paths.image('menu/common/topBar'));
		topBar.setGraphicSize(FlxG.width, 90);
		topBar.updateHitbox();
		topBar.antialiasing = ClientPrefs.globalAntialiasing;
		add(topBar);

		// ── Title ──
		// Every other options screen routes its text through Lang.str() (which
		// falls back to the given English default until a translation exists,
		// same as any brand-new string added there) -- this whole screen had
		// been hardcoded English only, unlike its siblings.
		var title = new FlxText(0, 14, FlxG.width, Lang.str('vpadcustomizer_title', 'CUSTOMIZE VIRTUAL PAD'));
		title.setFormat(Paths.font('AmaticSC-Bold.ttf'), 50, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.antialiasing = ClientPrefs.globalAntialiasing;
		add(title);

		// ── Layout label ──
		var layoutName = ClientPrefs.virtualPadLayout;
		// '@' is this codebase's established placeholder token for Lang.str()
		// (see AwardsState.hx/MissCounterSubstate.hx/CosmicubeCard.hx), not '%s'.
		var layoutLabel = new FlxText(0, 62, FlxG.width, Lang.str('vpadcustomizer_layout', 'Current layout: @').replace('@', layoutName));
		layoutLabel.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(180, 200, 255), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		layoutLabel.antialiasing = ClientPrefs.globalAntialiasing;
		add(layoutLabel);

		// ── Status / hint (below header bar) ──
		_defaultHint = Lang.str('vpadcustomizer_hint', 'Drag the buttons to reposition · B / SAVE to confirm · RESET restores defaults');
		statusText = new FlxText(0, 148, FlxG.width, _defaultHint);
		statusText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(180, 180, 180), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.antialiasing = ClientPrefs.globalAntialiasing;
		add(statusText);

		// ── Load saved positions ──
		var savedPositions:Map<String, Array<Float>> = _loadPositionMap();

		// ── Create draggable buttons ──
		for (i in 0...4)
		{
			var key = DIR_KEYS[i];
			var pos:Array<Float>;

			// Check the JSON map first, then fall back to legacy customPadPositions, then defaults
			if (savedPositions.exists(key))
			{
				pos = savedPositions.get(key);
			}
			else
			{
				var legacy = ClientPrefs.customPadPositions[i];
				if (legacy[0] >= 0 && legacy[1] >= 0)
					pos = legacy;
				else
					pos = _defaultPos(i);
			}

			if (pos[0] < 0 || pos[1] < 0) pos = _defaultPos(i);

			var btn = new DragButton(pos[0], pos[1], DIR_NAMES[i].toLowerCase(), DIR_COLORS[i]);
			add(btn);
			dragButtons.push(btn);
			_boundsList.push(FlxRect.get(pos[0] - MIN_GAP, pos[1] - MIN_GAP, btn.width + MIN_GAP * 2, btn.height + MIN_GAP * 2));
		}

		// ── Save & Reset buttons (just below the header bar) ──
		saveBtn  = _makeButton(FlxG.width / 2 - 180, 95, Lang.str('vpadcustomizer_save', 'SAVE & EXIT'), 0xFF4488FF);
		resetBtn = _makeButton(FlxG.width / 2 + 20,  95, Lang.str('reset', 'RESET'), 0xFFCC4444);

		super.create();

		// Navigation pad — only when virtual pad is the nav input; Touch mode uses SAVE & EXIT.
		#if mobile
		if (ClientPrefs.navInputMode == 'Virtual Pad')
		{
			addVirtualPad(NONE, A_B);
			addVirtualPadCamera();
		}
		#end

		_updateKbFocusVisuals();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// ── Pointer state ──
		var pointerJustPressed  = FlxG.mouse.justPressed  || _anyTouchJustPressed();
		var pointerPressed      = FlxG.mouse.pressed      || _anyTouchPressed();
		var pointerJustReleased = FlxG.mouse.justReleased || _anyTouchJustReleased();
		var px = _getPointerX();
		var py = _getPointerY();

		// ── Start dragging ──
		if (pointerJustPressed && dragIdx < 0)
		{
			// Check save / reset buttons first
			if (_overlaps(saveBtn, px, py))
			{
				_saveAllPositions();
				ClientPrefs.flushSave();
				close();
				return;
			}
			else if (_overlaps(resetBtn, px, py))
			{
				_resetAllPositions();
				return;
			}

			// Check drag buttons
			for (i in 0...dragButtons.length)
			{
				var btn = dragButtons[i];
				if (px >= btn.x && px <= btn.x + btn.width &&
					py >= btn.y && py <= btn.y + btn.height)
				{
					dragIdx = i;
					offsetX = px - btn.x;
					offsetY = py - btn.y;
					btn.animation.play('pressed');
					break;
				}
			}
		}

		// ── During drag with collision snapping ──
		if (dragIdx >= 0 && pointerPressed)
		{
			var newX = px - offsetX;
			var newY = py - offsetY;

			// Clamp to screen
			newX = Math.max(0, Math.min(FlxG.width - dragButtons[dragIdx].width, newX));
			newY = Math.max(0, Math.min(FlxG.height - dragButtons[dragIdx].height, newY));

			// Collision check against other buttons (like Shadow Engine's bounds system)
			var snapped = _resolveCollision(dragIdx, newX, newY);
			dragButtons[dragIdx].x = snapped.x;
			dragButtons[dragIdx].y = snapped.y;
		}

		// ── Release ──
		if (dragIdx >= 0 && pointerJustReleased)
		{
			dragButtons[dragIdx].animation.play('idle');
			dragIdx = -1;
		}

		// ── Keyboard / gamepad focus & move ──
		// Skipped while an actual mouse/touch drag is in progress so the two
		// input paths never fight over the same button's position in the
		// same frame.
		if (dragIdx < 0)
		{
			if (_kbMoveMode)
			{
				final btn = dragButtons[_kbFocus];
				final held = controls.UI_LEFT || controls.UI_RIGHT || controls.UI_UP || controls.UI_DOWN;
				final justPressed = controls.UI_LEFT_P || controls.UI_RIGHT_P || controls.UI_UP_P || controls.UI_DOWN_P;

				if (held)
				{
					_kbHoldTime += elapsed;
					// First tap moves immediately by one step; holding then
					// repeats smoothly instead of waiting out the same
					// threshold on every individual nudge.
					if (justPressed || _kbHoldTime > 0.4)
					{
						final step = justPressed ? NUDGE_STEP : NUDGE_SPEED * elapsed;
						var dx = 0.0, dy = 0.0;
						if (controls.UI_LEFT)  dx -= step;
						if (controls.UI_RIGHT) dx += step;
						if (controls.UI_UP)    dy -= step;
						if (controls.UI_DOWN)  dy += step;

						var newX = Math.max(0, Math.min(FlxG.width  - btn.width,  btn.x + dx));
						var newY = Math.max(0, Math.min(FlxG.height - btn.height, btn.y + dy));
						// Same collision-snapping mouse dragging already uses,
						// so a keyboard nudge can't overlap another button either.
						var snapped = _resolveCollision(_kbFocus, newX, newY);
						btn.x = snapped.x;
						btn.y = snapped.y;
					}
				}
				else
				{
					_kbHoldTime = 0;
				}

				if (controls.ACCEPT)
				{
					_kbMoveMode = false;
					FunkinSound.play(Paths.sound('confirmMenu'));
					statusText.text = _defaultHint;
					_updateKbFocusVisuals();
				}
				else if (controls.BACK)
				{
					// Cancels the move, not the whole screen -- BACK while
					// actively repositioning a button means "let go of this",
					// not "save & exit" (see the global BACK handling below,
					// which this intentionally skips via return).
					_kbMoveMode = false;
					FunkinSound.play(Paths.sound('cancelMenu'));
					statusText.text = _defaultHint;
					_updateKbFocusVisuals();
					return;
				}
			}
			else
			{
				if (controls.UI_UP_P)
				{
					_kbFocus = (_kbFocus <= 0) ? KB_FOCUS_COUNT - 1 : _kbFocus - 1;
					FunkinSound.play(Paths.sound('hover'), 0.5);
					_updateKbFocusVisuals();
				}
				if (controls.UI_DOWN_P)
				{
					_kbFocus = (_kbFocus >= KB_FOCUS_COUNT - 1) ? 0 : _kbFocus + 1;
					FunkinSound.play(Paths.sound('hover'), 0.5);
					_updateKbFocusVisuals();
				}

				if (controls.ACCEPT)
				{
					if (_kbFocus < dragButtons.length)
					{
						_kbMoveMode = true;
						_kbHoldTime = 0;
						FunkinSound.play(Paths.sound('scrollMenu'));
						statusText.text = Lang.str('vpadcustomizer_moving', 'Moving @ -- arrow keys to nudge, ACCEPT to drop, BACK to cancel').replace('@', DIR_NAMES[_kbFocus]);
						_updateKbFocusVisuals();
					}
					else if (_kbFocus == dragButtons.length)
					{
						_saveAllPositions();
						ClientPrefs.flushSave();
						close();
						return;
					}
					else
					{
						_resetAllPositions();
					}
				}
			}
		}

		// ── BACK = save & exit ──
		if (controls.BACK)
		{
			_saveAllPositions();
			ClientPrefs.flushSave();
			close();
		}
	}

	/**
	 * Reflects _kbFocus/_kbMoveMode (and an active mouse drag) in each
	 * candidate's visual state -- drag buttons: 'idle' (unfocused) / 'hover'
	 * (keyboard-focused, not grabbed) / 'pressed' (grabbed, by keyboard move
	 * mode or an active mouse drag). Save/reset use a simple alpha brighten
	 * since they don't have their own frame states.
	 */
	function _updateKbFocusVisuals():Void
	{
		for (i in 0...dragButtons.length)
		{
			if (dragIdx == i || (_kbFocus == i && _kbMoveMode))
				dragButtons[i].animation.play('pressed');
			else if (_kbFocus == i)
				dragButtons[i].animation.play('hover');
			else
				dragButtons[i].animation.play('idle');
		}

		saveBtn.alpha  = (_kbFocus == dragButtons.length)     ? 1.0 : 0.75;
		resetBtn.alpha = (_kbFocus == dragButtons.length + 1) ? 1.0 : 0.75;
	}

	// ── Collision resolution (like Shadow Engine's TouchButton.bounds overlap) ──

	/**
	 * Resolve collision for the dragged button against all other buttons.
	 * Returns the closest non-overlapping position.
	 */
	function _resolveCollision(idx:Int, newX:Float, newY:Float):{x:Float, y:Float}
	{
		var bw = dragButtons[idx].width;
		var bh = dragButtons[idx].height;

		// Build current bounding rect for the dragged button
		var dragRect = FlxRect.get(newX - MIN_GAP, newY - MIN_GAP, bw + MIN_GAP * 2, bh + MIN_GAP * 2);

		var bestX = newX;
		var bestY = newY;
		var bestOverlap:Float = Math.POSITIVE_INFINITY;

		for (i in 0...dragButtons.length)
		{
			if (i == idx) continue;

			var other = _boundsList[i];
			if (other == null) continue;

			// Check if rects overlap
			if (dragRect.overlaps(other))
			{
				// Calculate overlap on each axis
				var overlapLeft   = (dragRect.x + dragRect.width)  - other.x;
				var overlapRight  = (other.x + other.width) - dragRect.x;
				var overlapTop    = (dragRect.y + dragRect.height) - other.y;
				var overlapBottom = (other.y + other.height) - dragRect.y;

				// Find the smallest overlap axis to resolve
				var minOverlapX = Math.min(overlapLeft, overlapRight);
				var minOverlapY = Math.min(overlapTop, overlapBottom);

				if (minOverlapX < minOverlapY)
				{
					// Resolve horizontally
					if (overlapLeft < overlapRight)
						bestX = other.x - bw - MIN_GAP;
					else
						bestX = other.x + other.width + MIN_GAP;
				}
				else
				{
					// Resolve vertically
					if (overlapTop < overlapBottom)
						bestY = other.y - bh - MIN_GAP;
					else
						bestY = other.y + other.height + MIN_GAP;
				}
			}
		}

		// Clamp to screen
		bestX = Math.max(0, Math.min(FlxG.width - bw, bestX));
		bestY = Math.max(0, Math.min(FlxG.height - bh, bestY));

		// Update the bounds rect for this button
		_boundsList[idx].x = bestX - MIN_GAP;
		_boundsList[idx].y = bestY - MIN_GAP;

		return {x: bestX, y: bestY};
	}

	// ── Persistence ──

	/**
	 * Load the position map from customPadPositionsJson.
	 * Returns a Map<String, Array<Float>> with all saved button positions.
	 */
	static function _loadPositionMap():Map<String, Array<Float>>
	{
		var map = new Map<String, Array<Float>>();
		if (ClientPrefs.customPadPositionsJson != null && ClientPrefs.customPadPositionsJson != "")
		{
			try
			{
				var parsed:Dynamic = haxe.Json.parse(ClientPrefs.customPadPositionsJson);
				if (parsed != null && Reflect.isObject(parsed))
				{
					for (field in Reflect.fields(parsed))
					{
						var arr:Array<Dynamic> = Reflect.field(parsed, field);
						if (arr != null && arr.length >= 2)
							map.set(field, [Std.int(arr[0]), Std.int(arr[1])]);
					}
				}
			}
			catch (e:Dynamic)
			{
				// Ignore parse errors - will use defaults
			}
		}
		return map;
	}

	/** Save ALL current button positions to both customPadPositionsJson and legacy customPadPositions. */
	function _saveAllPositions():Void
	{
		var jsonObj:Dynamic = {};
		for (i in 0...dragButtons.length)
		{
			var key = DIR_KEYS[i];
			var btn = dragButtons[i];
			Reflect.setField(jsonObj, key, [Std.int(btn.x), Std.int(btn.y)]);

			// Also update legacy array for backward compat
			ClientPrefs.customPadPositions[i] = [btn.x, btn.y];
		}
		ClientPrefs.customPadPositionsJson = haxe.Json.stringify(jsonObj);
		ClientPrefs.virtualPadLayout = 'Custom';
	}

	/** Reset all buttons to default positions. */
	function _resetAllPositions():Void
	{
		ClientPrefs.customPadPositionsJson = "";
		for (i in 0...4)
		{
			ClientPrefs.customPadPositions[i] = [-1, -1];
			var pos = _defaultPos(i);
			dragButtons[i].x = pos[0];
			dragButtons[i].y = pos[1];
			_boundsList[i].x = pos[0] - MIN_GAP;
			_boundsList[i].y = pos[1] - MIN_GAP;
		}
		statusText.text = Lang.str('vpadcustomizer_reset_done', 'Positions reset to defaults');
		statusText.color = FlxColor.fromRGB(255, 200, 100);
	}

	// ── Input helpers ──

	function _getPointerX():Float
	{
		#if mobile
		if (FlxG.touches.list.length > 0) return FlxG.touches.list[0].x;
		#end
		return FlxG.mouse.x;
	}

	function _getPointerY():Float
	{
		#if mobile
		if (FlxG.touches.list.length > 0) return FlxG.touches.list[0].y;
		#end
		return FlxG.mouse.y;
	}

	function _anyTouchJustPressed():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justPressed) return true;
		return false;
	}

	function _anyTouchPressed():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.pressed) return true;
		return false;
	}

	function _anyTouchJustReleased():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justReleased) return true;
		return false;
	}

	// ── UI helpers ──

	function _overlaps(spr:FlxSprite, mx:Float, my:Float):Bool
	{
		return mx >= spr.x && mx <= spr.x + spr.width && my >= spr.y && my <= spr.y + spr.height;
	}

	function _defaultPos(i:Int):Array<Float>
	{
		// Match MobileVirtualPad LEFT_FULL positions so defaults equal the actual game layout.
		var safe = mobile.backend.ScreenUtil.safeArea();
		var safeLeft = Std.int(safe.left);
		var baseY = FlxG.height - Std.int(safe.bottom);
		return switch (i)
		{
			case 0: [safeLeft,        baseY - 243]; // LEFT
			case 1: [safeLeft + 105,  baseY - 135]; // DOWN
			case 2: [safeLeft + 105,  baseY - 345]; // UP
			case 3: [safeLeft + 207,  baseY - 243]; // RIGHT
			default: [0, 0];
		};
	}

	function _makeButton(x:Float, y:Float, text:String, color:Int):FlxSprite
	{
		var spr = new FlxSprite(x, y);
		spr.loadGraphic(Paths.image('menu/freeplay/card'));
		spr.setGraphicSize(150, 36);
		spr.updateHitbox();
		spr.color = color;
		spr.antialiasing = ClientPrefs.globalAntialiasing;
		add(spr); // sprite first (background)
		var txt = new FlxText(x, y + 6, 150, text);
		txt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER);
		txt.antialiasing = ClientPrefs.globalAntialiasing;
		add(txt); // text after (foreground)
		return spr;
	}
}

/**
 * Draggable button using the real virtual pad PNG texture.
 * The graphic is a 3-frame horizontal sheet (idle | hover | pressed).
 */
class DragButton extends FlxSprite
{
	public function new(x:Float, y:Float, graphicName:String, color:Int)
	{
		super(x, y);
		var graphic = FlxG.bitmap.add('assets/mobile/virtualpad/$graphicName.png');
		frames = FlxTileFrames.fromGraphic(graphic, FlxPoint.weak(Std.int(graphic.width / 3), graphic.height));
		animation.add('idle',    [0], 1, false);
		// Middle frame of the sheet was never wired up before -- now used to
		// show keyboard/gamepad focus (selected but not yet grabbed), same
		// spritesheet mouse/touch dragging already used frame 2 ('pressed') for.
		animation.add('hover',   [1], 1, false);
		animation.add('pressed', [2], 1, false);
		animation.play('idle');
		this.color = color;
	}
}
