package mobile.controls;

import flixel.FlxG;
import flixel.util.FlxDestroyUtil;
import openfl.display.BitmapData;
import mobile.backend.flixel.FlxButton;
import mobile.backend.flixel.input.TouchInputManager;
import mobile.backend.flixel.input.FlxMobileInputID;

enum HitboxLayout
{
	/** Four equal vertical columns spanning full screen height. */
	FOUR_LANES;
	/**
	 * 2×2 grid: left thumb covers LEFT (top-left) + DOWN (bottom-left),
	 * right thumb covers UP (top-right) + RIGHT (bottom-right).
	 */
	TWO_THUMB;
	/**
	 * Two circular D-Pad zones on each side of the screen.
	 * Uses 4 circular buttons arranged in a diamond pattern per thumb.
	 */
	DPAD;
}

/**
 * Hitbox — transparent tap zones that cover the screen.
 * @author StarNova (Cream.BR)
 */
class MobileHitbox extends TouchInputManager
{
	public var buttons:Array<FlxButton> = [];

	public var buttonLeft:FlxButton;
	public var buttonDown:FlxButton;
	public var buttonUp:FlxButton;
	public var buttonRight:FlxButton;

	private final alphaTarget:Float;

	private var _cachedGraphics:Map<Int, flixel.graphics.FlxGraphic> = new Map();

	public function new():Void
	{
		super();
		alphaTarget = funkin.data.ClientPrefs.hitboxAlpha;

		var safe = mobile.backend.ScreenUtil.safeArea();

		switch (layoutFromPrefs())
		{
			case TWO_THUMB:  buildTwoThumb(safe);
			case FOUR_LANES: buildFourLanes(safe);
			case DPAD:       buildDPad(safe);
		}

		scrollFactor.set();
		refreshMappedButtons();
	}

	// ─── Layout builders ───────────────────────────────────────────────────────

	function buildFourLanes(safe:{top:Float, bottom:Float, left:Float, right:Float}):Void
	{
		var safeTop    = Std.int(safe.top);
		var safeLeft   = Std.int(safe.left);
		var safeRight  = Std.int(safe.right);

		var totalW  = FlxG.width  - safeLeft - safeRight;
		var totalH  = FlxG.height - safeTop;
		var btnW:Int = Std.int(totalW / 4);

		var data = [
			{color: 0xFF00FF, ids: [FlxMobileInputID.hitboxLEFT,  FlxMobileInputID.noteLEFT]},
			{color: 0x00FFFF, ids: [FlxMobileInputID.hitboxDOWN,  FlxMobileInputID.noteDOWN]},
			{color: 0x00FF00, ids: [FlxMobileInputID.hitboxUP,    FlxMobileInputID.noteUP]},
			{color: 0xFF0000, ids: [FlxMobileInputID.hitboxRIGHT, FlxMobileInputID.noteRIGHT]}
		];

		for (i in 0...4)
		{
			var btn = createHint(safeLeft + i * btnW, safeTop, btnW, totalH, data[i].color, data[i].ids);
			add(btn);
			buttons.push(btn);
		}

		buttonLeft  = buttons[0];
		buttonDown  = buttons[1];
		buttonUp    = buttons[2];
		buttonRight = buttons[3];
	}

	function buildTwoThumb(safe:{top:Float, bottom:Float, left:Float, right:Float}):Void
	{
		var safeTop   = Std.int(safe.top);
		var safeLeft  = Std.int(safe.left);
		var safeRight = Std.int(safe.right);

		var totalW = FlxG.width  - safeLeft - safeRight;
		var totalH = FlxG.height - safeTop;
		var halfW:Int = Std.int(totalW / 2);
		var halfH:Int = Std.int(totalH / 2);

		// Top-left: LEFT  |  Top-right: UP
		// Bot-left: DOWN  |  Bot-right: RIGHT
		var positions = [
			{x: safeLeft,           y: safeTop,          w: halfW, h: halfH, color: 0xFF00FF, ids: [FlxMobileInputID.hitboxLEFT,  FlxMobileInputID.noteLEFT]},
			{x: safeLeft,           y: safeTop + halfH,  w: halfW, h: halfH, color: 0x00FFFF, ids: [FlxMobileInputID.hitboxDOWN,  FlxMobileInputID.noteDOWN]},
			{x: safeLeft + halfW,   y: safeTop,          w: halfW, h: halfH, color: 0x00FF00, ids: [FlxMobileInputID.hitboxUP,    FlxMobileInputID.noteUP]},
			{x: safeLeft + halfW,   y: safeTop + halfH,  w: halfW, h: halfH, color: 0xFF0000, ids: [FlxMobileInputID.hitboxRIGHT, FlxMobileInputID.noteRIGHT]}
		];

		for (p in positions)
		{
			var btn = createHint(p.x, p.y, p.w, p.h, p.color, p.ids);
			add(btn);
			buttons.push(btn);
		}

		buttonLeft  = buttons[0];
		buttonDown  = buttons[1];
		buttonUp    = buttons[2];
		buttonRight = buttons[3];
	}

	/**
	 * Builds the DPad layout - two circular zones with 4 directional buttons each.
	 * Inspired by FunkinCrew's DoubleThumbDPad scheme.
	 * Left thumb zone covers LEFT+DOWN, Right thumb zone covers UP+RIGHT.
	 */
	function buildDPad(safe:{top:Float, bottom:Float, left:Float, right:Float}):Void
	{
		var safeTop   = Std.int(safe.top);
		var safeLeft  = Std.int(safe.left);
		var safeRight = Std.int(safe.right);

		var hintSize:Int = 75;
		var outlineThickness:Int = 5;
		var zoneRadius:Int = 115;

		// Angles in radians: LEFT=π, DOWN=π/2, UP=1.5π, RIGHT=0
		// Arranged in diamond pattern per thumb zone
		var hintsAngles:Array<Float> = [Math.PI, Math.PI / 2, Math.PI * 1.5, 0];

		// Colors per direction
		var hintsColors:Array<FlxColor> = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000];

		// IDs per direction (LEFT, DOWN, UP, RIGHT)
		var hintsIDs:Array<Array<FlxMobileInputID>> = [
			[FlxMobileInputID.hitboxLEFT,  FlxMobileInputID.noteLEFT],
			[FlxMobileInputID.hitboxDOWN,  FlxMobileInputID.noteDOWN],
			[FlxMobileInputID.hitboxUP,    FlxMobileInputID.noteUP],
			[FlxMobileInputID.hitboxRIGHT, FlxMobileInputID.noteRIGHT]
		];

		// Two thumb zones: 0=left side, 1=right side
		for (thumb in 0...2)
		{
			for (i in 0...4)
			{
				// Calculate base X position (left zone starts at safeLeft, right zone starts near right edge)
				var baseX:Float = (thumb == 0) ? safeLeft + hintSize * 2 : FlxG.width - safeRight - hintSize * 4;
				var xOffset:Float = Math.cos(hintsAngles[i]) * zoneRadius;
				var x:Float = baseX + xOffset;

				// Y position centered in screen height, adjusted by safe area
				var baseY:Float = FlxG.height - safeTop - hintSize * 3.75;
				var yOffset:Float = Math.sin(hintsAngles[i]) * zoneRadius;
				var y:Float = baseY + yOffset;

				// Create circular button
				var btn = createHintCircle(x, y, hintSize, hintsColors[i], hintsIDs[i]);
				add(btn);
				buttons.push(btn);
			}
		}

		// Assign button references (left zone: 0=LEFT, 1=DOWN; right zone: 2=UP, 3=RIGHT)
		buttonLeft  = buttons[0];
		buttonDown  = buttons[1];
		buttonUp    = buttons[2];
		buttonRight = buttons[3];
	}

	/**
	 * Creates a circular hint button with outline effect.
	 */
	private function createHintCircle(X:Float, Y:Float, radius:Int, Color:FlxColor, IDs:Array<FlxMobileInputID>):FlxButton
	{
		var hint:FlxButton = new FlxButton(X, Y, IDs);
		var diameter:Int = radius * 2;

		// Create circular bitmap with gradient effect
		var graphicKey:Int = Color + radius * 1000;
		var bgGraphic:flixel.graphics.FlxGraphic = _cachedGraphics.get(graphicKey);

		if (bgGraphic == null)
		{
			var bitmap:BitmapData = new BitmapData(diameter, diameter, true, 0x00000000);

			// Draw filled circle with the color
			for (px in 0...diameter)
			{
				for (py in 0...diameter)
				{
					var dx:Float = px - radius;
					var dy:Float = py - radius;
					var dist:Float = Math.sqrt(dx * dx + dy * dy);

					if (dist <= radius - 2)
					{
						// Inside circle - fill with semi-transparent color
						bitmap.setPixel32(px, py, (Color & 0x00FFFFFF) | 0x88000000);
					}
					else if (dist <= radius)
					{
						// Edge - draw brighter outline
						bitmap.setPixel32(px, py, Color | 0xCC000000);
					}
				}
			}

			bgGraphic = FlxG.bitmap.add(bitmap, false, "hitbox_circle_" + graphicKey);
			_cachedGraphics.set(graphicKey, bgGraphic);
		}

		hint.loadGraphic(bgGraphic);
		hint.solid = hint.moves = false;
		hint.immovable = true;
		hint.scrollFactor.set();
		hint.alpha = 0.00001;

		// Adjust hitbox to be circular (FlxButton uses rectangular collision by default)
		hint.width = diameter;
		hint.height = diameter;
		hint.centerOffsets();

		var hintTween:FlxTween = null;

		hint.onDown.callback = function()
		{
			if (hintTween != null) hintTween.cancel();
			hintTween = FlxTween.tween(hint, {alpha: alphaTarget}, 0.075, {
				ease: FlxEase.circInOut,
				onComplete: function(_) { hintTween = null; }
			});
		};

		hint.onUp.callback = function()
		{
			if (hintTween != null) hintTween.cancel();
			hintTween = FlxTween.tween(hint, {alpha: 0.00001}, 0.15, {
				ease: FlxEase.circInOut,
				onComplete: function(_) { hintTween = null; }
			});
		};

		hint.onOut.callback = hint.onUp.callback;

		#if FLX_DEBUG
		hint.ignoreDrawDebug = true;
		#end

		return hint;
	}

	// ─── Helpers ───────────────────────────────────────────────────────────────

	static function layoutFromPrefs():HitboxLayout
	{
		return switch (funkin.data.ClientPrefs.hitboxLayout)
		{
			case 'Two Thumb': TWO_THUMB;
			case 'DPad':      DPAD;
			default:          FOUR_LANES;
		};
	}

	private function createHint(X:Float, Y:Float, Width:Int, Height:Int, Color:FlxColor, IDs:Array<FlxMobileInputID>):FlxButton
	{
		var hint:FlxButton = new FlxButton(X, Y, IDs);

		var graphicKey:Int = Color + Width * 31 + Height;
		var bgGraphic:flixel.graphics.FlxGraphic = _cachedGraphics.get(graphicKey);

		if (bgGraphic == null)
		{
			var bitmap:BitmapData = new BitmapData(Width, Height, true, (Color & 0x00FFFFFF) | 0x88000000);
			bgGraphic = FlxG.bitmap.add(bitmap, false, "hitbox_" + graphicKey);
			_cachedGraphics.set(graphicKey, bgGraphic);
		}

		hint.loadGraphic(bgGraphic);
		hint.solid = hint.moves = false;
		hint.immovable = true;
		hint.scrollFactor.set();
		hint.alpha = 0.00001;

		var hintTween:FlxTween = null;

		hint.onDown.callback = function()
		{
			if (hintTween != null) hintTween.cancel();
			hintTween = FlxTween.tween(hint, {alpha: alphaTarget}, 0.075, {
				ease: FlxEase.circInOut,
				onComplete: function(_) { hintTween = null; }
			});
		};

		hint.onUp.callback = function()
		{
			if (hintTween != null) hintTween.cancel();
			hintTween = FlxTween.tween(hint, {alpha: 0.00001}, 0.15, {
				ease: FlxEase.circInOut,
				onComplete: function(_) { hintTween = null; }
			});
		};

		hint.onOut.callback = hint.onUp.callback;

		#if FLX_DEBUG
		hint.ignoreDrawDebug = true;
		#end

		return hint;
	}

	override function destroy():Void
	{
		super.destroy();
		for (btn in buttons)
			FlxDestroyUtil.destroy(btn);

		for (key in _cachedGraphics.keys())
		{
			var graphic = _cachedGraphics.get(key);
			FlxG.bitmap.remove(graphic);
			graphic.destroy();
		}
		_cachedGraphics.clear();
	}
}
