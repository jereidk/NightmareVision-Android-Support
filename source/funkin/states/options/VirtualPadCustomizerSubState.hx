package funkin.states.options;

import funkin.backend.MusicBeatSubstate;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.input.touch.FlxTouch;

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

	var bg:FlxSprite;
	var dragButtons:Array<DragButton> = [];
	var collisionBounds:Array<FlxSprite> = [];

	var saveBtn:FlxSprite;
	var resetBtn:FlxSprite;
	var saveLabel:FlxText;
	var resetLabel:FlxText;
	var statusText:FlxText;

	var dragIdx:Int = -1;
	var offsetX:Float = 0;
	var offsetY:Float = 0;

	/** Button bounding boxes for overlap check (invisible, used like Shadow Engine's TouchButton.bounds). */
	var _boundsList:Array<FlxRect> = [];

	override function create()
	{
		// ── Background ──
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 0, 210));
		add(bg);

		// ── Title ──
		var title = new FlxText(0, 20, FlxG.width, 'CUSTOMIZE VIRTUAL PAD');
		title.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		add(title);

		// ── Layout label ──
		var layoutName = ClientPrefs.virtualPadLayout;
		var layoutLabel = new FlxText(0, 62, FlxG.width, 'Current layout: ' + layoutName);
		layoutLabel.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(180, 200, 255), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(layoutLabel);

		// ── Status / hint ──
		statusText = new FlxText(0, FlxG.height - 105, FlxG.width, 'Drag the buttons · B / SAVE to exit · RESET restores defaults');
		statusText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(180, 180, 180), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
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

			var btn = new DragButton(pos[0], pos[1], DIR_NAMES[i], DIR_COLORS[i]);
			add(btn);
			dragButtons.push(btn);
			collisionBounds.push(new FlxSprite(pos[0] - MIN_GAP, pos[1] - MIN_GAP));
			_boundsList.push(FlxRect.get(pos[0] - MIN_GAP, pos[1] - MIN_GAP, btn.width + MIN_GAP * 2, btn.height + MIN_GAP * 2));
		}

		// ── Save & Reset buttons ──
		saveBtn = _makeButton(FlxG.width / 2 - 180, FlxG.height - 50, 'SAVE & EXIT', 0xFF4488FF);
		resetBtn = _makeButton(FlxG.width / 2 + 20, FlxG.height - 50, 'RESET', 0xFFCC4444);
		add(saveBtn);
		add(resetBtn);

		super.create();

		// Navigation pad for BACK / ACCEPT — use NONE dpad + A_B so only accept/back are visible
		#if mobile
		addVirtualPad(NONE, A_B);
		addVirtualPadCamera();
		#end
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
			dragIdx = -1;
		}

		// ── BACK = save & exit ──
		if (controls.BACK)
		{
			_saveAllPositions();
			ClientPrefs.flushSave();
			close();
		}
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
						bestX = other.x + other.width + MIN_GAP - MIN_GAP * 2;
				}
				else
				{
					// Resolve vertically
					if (overlapTop < overlapBottom)
						bestY = other.y - bh - MIN_GAP;
					else
						bestY = other.y + other.height + MIN_GAP - MIN_GAP * 2;
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
		statusText.text = 'Positions reset to defaults';
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
		var safe = mobile.backend.ScreenUtil.safeArea();
		var safeLeft = Std.int(safe.left);
		var baseY = FlxG.height - Std.int(safe.bottom);
		return switch (i)
		{
			case 0: [safeLeft + 20, baseY - 220]; // LEFT
			case 1: [safeLeft + 140, baseY - 140]; // DOWN
			case 2: [safeLeft + 140, baseY - 300]; // UP
			case 3: [safeLeft + 260, baseY - 220]; // RIGHT
			default: [0, 0];
		};
	}

	function _makeButton(x:Float, y:Float, text:String, color:Int):FlxSprite
	{
		var spr = new FlxSprite(x, y).makeGraphic(150, 36, color);
		var txt = new FlxText(x, y + 6, 150, text);
		txt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER);
		add(txt);
		return spr;
	}
}

/**
 * Simple draggable button sprite for the customizer.
 * Shows a colored square with a direction label.
 */
class DragButton extends FlxSpriteGroup
{
	public var label:FlxText;
	public var bg:FlxSprite;

	public function new(x:Float, y:Float, text:String, color:Int)
	{
		super(x, y);

		bg = new FlxSprite().makeGraphic(80, 80, color);
		bg.alpha = 0.7;
		add(bg);

		label = new FlxText(0, 24, 80, text);
		label.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, CENTER);
		add(label);
	}
}
