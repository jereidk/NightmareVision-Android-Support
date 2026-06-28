package mobile.controls;

import flixel.FlxG;
import flixel.util.FlxDestroyUtil;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import openfl.display.BitmapData;
import mobile.backend.flixel.FlxButton;
import mobile.backend.flixel.input.TouchInputManager;
import mobile.backend.flixel.input.FlxMobileInputID;
import funkin.Paths;
import funkin.data.ClientPrefs;

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
	/**
	 * Uses note-style arrow sprites as hitbox buttons.
	 * Arrows are displayed at the bottom of the screen.
	 */
	ARROWS;
	/**
	 * Two zones with triangular hitbox buttons.
	 * Left zone covers LEFT+DOWN, Right zone covers UP+RIGHT.
	 */
	TRIANGLE;
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

	public function new(?forcedLayout:HitboxLayout):Void
	{
		super();
		alphaTarget = funkin.data.ClientPrefs.hitboxAlpha;

		var safe = mobile.backend.ScreenUtil.safeArea();

		switch (forcedLayout ?? layoutFromPrefs())
		{
			case TWO_THUMB:  buildTwoThumb(safe);
			case FOUR_LANES: buildFourLanes(safe);
			case DPAD:       buildDPad(safe);
			case ARROWS:     buildArrows(safe);
			case TRIANGLE:   buildTriangle(safe);
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
			{color: getArrowColor(0), ids: [FlxMobileInputID.hitboxLEFT,  FlxMobileInputID.noteLEFT]},
			{color: getArrowColor(1), ids: [FlxMobileInputID.hitboxDOWN,  FlxMobileInputID.noteDOWN]},
			{color: getArrowColor(2), ids: [FlxMobileInputID.hitboxUP,    FlxMobileInputID.noteUP]},
			{color: getArrowColor(3), ids: [FlxMobileInputID.hitboxRIGHT, FlxMobileInputID.noteRIGHT]}
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
			{x: safeLeft,           y: safeTop,          w: halfW, h: halfH, color: getArrowColor(0), ids: [FlxMobileInputID.hitboxLEFT,  FlxMobileInputID.noteLEFT]},
			{x: safeLeft,           y: safeTop + halfH,  w: halfW, h: halfH, color: getArrowColor(1), ids: [FlxMobileInputID.hitboxDOWN,  FlxMobileInputID.noteDOWN]},
			{x: safeLeft + halfW,   y: safeTop,          w: halfW, h: halfH, color: getArrowColor(2), ids: [FlxMobileInputID.hitboxUP,    FlxMobileInputID.noteUP]},
			{x: safeLeft + halfW,   y: safeTop + halfH,  w: halfW, h: halfH, color: getArrowColor(3), ids: [FlxMobileInputID.hitboxRIGHT, FlxMobileInputID.noteRIGHT]}
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

		// Colors per direction using HSV from ClientPrefs
		var hintsColors:Array<FlxColor> = [
			getArrowColor(0),  // LEFT
			getArrowColor(1),  // DOWN
			getArrowColor(2),  // UP
			getArrowColor(3)   // RIGHT
		];

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
	 * Builds the Arrows layout - uses note-style arrow sprites as hitbox buttons.
	 * Inspired by FunkinCrew's Arrows scheme.
	 * Arrows are positioned at the bottom of the screen, centered.
	 */
	function buildArrows(safe:{top:Float, bottom:Float, left:Float, right:Float}):Void
	{
		var safeTop    = Std.int(safe.top);
		var safeLeft   = Std.int(safe.left);
		var safeRight  = Std.int(safe.right);

		// Arrow dimensions matching NOTE_assets atlas
		var hintWidth:Int = 157;
		var hintHeight:Int = 154;
		var noteSpacing:Int = 80;

		// Calculate X position to center arrows
		var totalWidth:Float = (hintWidth + noteSpacing) * 4 - noteSpacing;
		var xPos:Float = (FlxG.width - totalWidth) / 2;

		// Y position at bottom, above safe area
		var yPos:Float = FlxG.height - safeTop - hintHeight * 2 - 24;

		// Arrow directions in order: LEFT, DOWN, UP, RIGHT
		var arrowNames:Array<String> = ['left', 'down', 'up', 'right'];
		var arrowIDs:Array<Array<FlxMobileInputID>> = [
			[FlxMobileInputID.hitboxLEFT,  FlxMobileInputID.noteLEFT],
			[FlxMobileInputID.hitboxDOWN,  FlxMobileInputID.noteDOWN],
			[FlxMobileInputID.hitboxUP,    FlxMobileInputID.noteUP],
			[FlxMobileInputID.hitboxRIGHT, FlxMobileInputID.noteRIGHT]
		];

		for (i in 0...4)
		{
			var btn = createArrowHint(xPos + i * (hintWidth + noteSpacing), yPos, hintWidth, hintHeight, arrowNames[i], arrowIDs[i]);
			add(btn);
			buttons.push(btn);
		}

		buttonLeft  = buttons[0];
		buttonDown  = buttons[1];
		buttonUp    = buttons[2];
		buttonRight = buttons[3];
	}

	/**
	 * Builds the Triangle layout - two zones with triangular buttons.
	 * Inspired by FunkinCrew's DoubleThumbTriangle scheme.
	 * Left zone covers LEFT+DOWN, Right zone covers UP+RIGHT.
	 */
	function buildTriangle(safe:{top:Float, bottom:Float, left:Float, right:Float}):Void
	{
		var safeTop   = Std.int(safe.top);
		var safeLeft  = Std.int(safe.left);
		var safeRight = Std.int(safe.right);

		var screenHalf:Int = Std.int(FlxG.width / 2);

		// Colors per direction using HSV from ClientPrefs: 0=LEFT, 1=DOWN, 2=UP, 3=RIGHT
		var hintsColors:Array<FlxColor> = [
			getArrowColor(0),  // LEFT
			getArrowColor(1),  // DOWN
			getArrowColor(2),  // UP
			getArrowColor(3)   // RIGHT
		];

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
			var xOffset:Float = (thumb == 1) ? screenHalf : safeLeft;

			// LEFT triangle (full height, left side of zone)
			var leftW:Int = Std.int(FlxG.width / 4);
			var btnLeft = createHintTriangle(xOffset, safeTop, leftW, FlxG.height - safeTop, hintsColors[0], hintsIDs[0], 'left');
			add(btnLeft);
			buttons.push(btnLeft);

			// DOWN triangle (bottom half, left portion of zone)
			var downW:Int = Std.int(FlxG.width / 2);
			var downH:Int = Std.int((FlxG.height - safeTop) / 2);
			var btnDown = createHintTriangle(xOffset, safeTop + downH, downW, downH, hintsColors[1], hintsIDs[1], 'down');
			add(btnDown);
			buttons.push(btnDown);

			// UP triangle (top half, right portion of zone)
			var upW:Int = Std.int(FlxG.width / 2);
			var upH:Int = Std.int((FlxG.height - safeTop) / 2);
			var btnUp = createHintTriangle(xOffset, safeTop, upW, upH, hintsColors[2], hintsIDs[2], 'up');
			add(btnUp);
			buttons.push(btnUp);

			// RIGHT triangle (full height, right side of zone)
			var rightW:Int = Std.int(FlxG.width / 4);
			var btnRight = createHintTriangle(xOffset + rightW, safeTop, rightW, FlxG.height - safeTop, hintsColors[3], hintsIDs[3], 'right');
			add(btnRight);
			buttons.push(btnRight);
		}

		// Assign button references (left zone: 0=LEFT, 1=DOWN; right zone: 2=UP, 3=RIGHT)
		buttonLeft  = buttons[0];
		buttonDown  = buttons[1];
		buttonUp    = buttons[2];
		buttonRight = buttons[3];
	}

	/**
	 * Creates a button with arrow sprite animation.
	 * Uses the NOTE_assets atlas with 'static' and 'pressed' animations.
	 */
	private function createArrowHint(X:Float, Y:Float, Width:Int, Height:Int, direction:String, IDs:Array<FlxMobileInputID>):FlxButton
	{
		var hint:FlxButton = new FlxButton(X, Y, IDs);

		// Load arrow sprites from NOTE_assets atlas
		hint.frames = Paths.getSparrowAtlas('NOTE_assets');

		// Add animations if not already present
		if (!hint.animation.exists('static'))
		{
			hint.animation.addByPrefix('static', 'arrow${direction}0000', 24, false);
		}
		if (!hint.animation.exists('pressed'))
		{
			hint.animation.addByPrefix('pressed', '${direction} press0000', 24, false);
		}

		hint.animation.play('static');
		hint.setGraphicSize(Width, Height);
		hint.updateHitbox();

		hint.solid = hint.moves = false;
		hint.immovable = true;
		hint.scrollFactor.set();

		// Start invisible like other hitbox hints
		hint.alpha = 0.00001;

		// Animate on touch
		var hintTween:FlxTween = null;

		hint.onDown.callback = function()
		{
			hint.animation.play('pressed');
			if (hintTween != null) hintTween.cancel();
			hintTween = FlxTween.tween(hint, {alpha: 1.0}, 0.075, {
				ease: FlxEase.circInOut,
				onComplete: function(_) { hintTween = null; }
			});
		};

		hint.onUp.callback = function()
		{
			hint.animation.play('static');
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

	/**
	 * Creates a triangular hint button using HSV colors from ClientPrefs.
	 * The triangle points in the direction specified (left, right, up, down).
	 */
	private function createHintTriangle(X:Float, Y:Float, Width:Int, Height:Int, Color:FlxColor, IDs:Array<FlxMobileInputID>, direction:String):FlxButton
	{
		var hint:FlxButton = new FlxButton(X, Y, IDs);

		// Create triangular bitmap
		var bitmap:BitmapData = new BitmapData(Width, Height, true, 0x00000000);

		for (px in 0...Width)
		{
			for (py in 0...Height)
			{
				var isInside = false;

				switch (direction)
				{
					case 'left':
						// Triangle pointing LEFT - filled on the right side
						var fillRatio:Float = px / Width;
						isInside = py >= Height * (1 - fillRatio) / 2 && py <= Height * (1 + fillRatio) / 2;
					case 'right':
						// Triangle pointing RIGHT - filled on the left side
						var fillRatio:Float = 1 - (px / Width);
						isInside = py >= Height * (1 - fillRatio) / 2 && py <= Height * (1 + fillRatio) / 2;
					case 'down':
						// Triangle pointing DOWN - filled on the bottom
						var fillRatio:Float = py / Height;
						isInside = px >= Width * (1 - fillRatio) / 2 && px <= Width * (1 + fillRatio) / 2;
					case 'up':
						// Triangle pointing UP - filled on the top
						var fillRatio:Float = 1 - (py / Height);
						isInside = px >= Width * (1 - fillRatio) / 2 && px <= Width * (1 + fillRatio) / 2;
				}

				if (isInside)
				{
					bitmap.setPixel32(px, py, (Color & 0x00FFFFFF) | 0x88000000);
				}
			}
		}

		var bgGraphic:flixel.graphics.FlxGraphic = FlxG.bitmap.add(bitmap, false, "hitbox_triangle_" + direction + "_" + Width + "x" + Height);
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

	// ─── Helpers ───────────────────────────────────────────────────────────────

	/**
	 * Converts arrow HSV values from ClientPrefs to a FlxColor.
	 * Index: 0=LEFT, 1=DOWN, 2=UP, 3=RIGHT
	 *
	 * arrowHSV[i][0] is a HUE SHIFT (same as the note shader in NotesSubState),
	 * so we apply it on top of each arrow's traditional base hue rather than
	 * treating it as an absolute hue. This keeps hitbox colours consistent with
	 * the visible note colours when the player customises them.
	 */
	// Traditional FNF note hues: purple(LEFT) cyan(DOWN) green(UP) red(RIGHT)
	static final ARROW_BASE_HUES:Array<Float> = [300.0, 200.0, 120.0, 0.0];

	static function getArrowColor(direction:Int):FlxColor
	{
		var hsv = ClientPrefs.arrowHSV[direction];
		var hue = (ARROW_BASE_HUES[direction] + hsv[0]) % 360;
		return FlxColor.fromHSB(hue, (100 + hsv[1]) / 100, (100 + hsv[2]) / 100);
	}

	static function layoutFromPrefs():HitboxLayout
	{
		return switch (funkin.data.ClientPrefs.hitboxLayout)
		{
			case 'Two Thumb': TWO_THUMB;
			case 'DPad':      DPAD;
			case 'Arrows':    ARROWS;
			case 'Triangle':   TRIANGLE;
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
