package mobile.controls;

import flixel.FlxG;
import flixel.input.FlxInput.FlxInputState;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxTileFrames;
import flixel.math.FlxPoint;
import flixel.util.FlxDestroyUtil;

import mobile.backend.flixel.FlxButton;
import mobile.backend.ScreenUtil;

import openfl.utils.Assets;
import openfl.display.BitmapData;

import mobile.backend.flixel.input.TouchInputManager;
import mobile.backend.flixel.input.FlxMobileInputID;

import funkin.data.ClientPrefs;
import funkin.FunkinAssets;

#if MODS_ALLOWED
import sys.FileSystem;
#end

enum MobileDPadMode
{
	UP_DOWN;
	LEFT_RIGHT;
	UP_LEFT_RIGHT;
	LEFT_FULL;
	RIGHT_FULL;
	CHART_EDITOR;
	NONE;
}

enum MobileActionMode
{
	A;
	B;
	X;
	A_B;
	A_B_C;
	STORYMENU;
	FREEPLAY;
	CHART_EDITOR;
	CHARACTER_EDITOR;
	NONE;
}

/**
 * Virtual Pad.... Virtual... Buttons
 *
 * @author StarNova (Cream.BR)
 */
class MobileVirtualPad extends TouchInputManager
{
	public var buttons:Array<FlxButton> = [];
	
	public var buttonLeft:FlxButton;
	public var buttonUp:FlxButton;
	public var buttonRight:FlxButton;
	public var buttonDown:FlxButton;
	public var buttonLeft2:FlxButton;
	public var buttonUp2:FlxButton;
	public var buttonRight2:FlxButton;
	public var buttonDown2:FlxButton;
	
	public var buttonA:FlxButton;
	public var buttonB:FlxButton;
	public var buttonC:FlxButton;
	public var buttonD:FlxButton;
	public var buttonE:FlxButton;
	public var buttonR:FlxButton;
	public var buttonV:FlxButton;
	public var buttonX:FlxButton;
	public var buttonY:FlxButton;
	public var buttonZ:FlxButton;
	public var buttonS:FlxButton;
	
	static var keyboardPressed:Bool = false;
	static var gamepadPressed:Bool = false;
	
	/** If true, this pad is for gameplay (not navigation) */
	public var forGameplay(default, null):Bool = false;
	
	/** Config this pad was last built with, pushed here each time reconfigure() borrows it for a substate. */
	var _configStack:Array<{dpad:MobileDPadMode, action:MobileActionMode, forGameplay:Bool}> = [];
	public var currentDPad(default, null):MobileDPadMode;
	public var currentAction(default, null):MobileActionMode;

	public function new(DPad:MobileDPadMode, Action:MobileActionMode, ?forGameplay:Bool = false)
	{
		super();
		_build(DPad, Action, forGameplay);
	}

	/**
	 * Rebuilds this pad's buttons in place for a new DPad/Action combination,
	 * remembering the current one so restorePrevious() can bring it back --
	 * lets a substate borrow and reshape an ancestor's already-existing pad
	 * instead of creating (and the ancestor's hiding) a second one. See
	 * MusicBeatSubstate.addVirtualPad()/removeVirtualPad() for the borrowing
	 * side of this.
	 */
	public function reconfigure(DPad:MobileDPadMode, Action:MobileActionMode, ?forGameplay:Bool):Void
	{
		_configStack.push({dpad: currentDPad, action: currentAction, forGameplay: this.forGameplay});
		_clearButtons();
		_build(DPad, Action, forGameplay ?? false);
	}

	/**
	 * Undoes the most recent reconfigure(), restoring this pad's previous
	 * button layout. Returns false (no-op) if there was nothing to restore --
	 * callers should fall back to their own cleanup in that case.
	 */
	public function restorePrevious():Bool
	{
		if (_configStack.length == 0) return false;
		final prev = _configStack.pop();
		_clearButtons();
		_build(prev.dpad, prev.action, prev.forGameplay);
		return true;
	}

	/** Destroys every current button/reference without destroying this pad itself. */
	function _clearButtons():Void
	{
		for (btn in buttons)
			FlxDestroyUtil.destroy(btn);
		buttons = [];

		buttonLeft = buttonUp = buttonRight = buttonDown = null;
		buttonLeft2 = buttonUp2 = buttonRight2 = buttonDown2 = null;
		buttonA = buttonB = buttonC = buttonD = buttonE = null;
		buttonR = buttonV = buttonX = buttonY = buttonZ = buttonS = null;
	}

	function _build(DPad:MobileDPadMode, Action:MobileActionMode, forGameplay:Bool):Void
	{
		this.forGameplay = forGameplay;
		currentDPad = DPad;
		currentAction = Action;

		var screenW = FlxG.width;
		var screenH = FlxG.height;
		var safe = ScreenUtil.safeArea();
		var safeTop    = Std.int(safe.top);
		var safeBottom = Std.int(safe.bottom);
		var safeLeft   = Std.int(safe.left);
		var safeRight  = Std.int(safe.right);
		var baseY = screenH - safeBottom;
		var dPad_X = safeLeft;
		var actionX = screenW - safeRight;
		var dPad2_X = safeLeft + 420; // Move para os lados (maior = mais para a direita)
		var dPad2_Y = baseY - 620; // Move para cima/baixo (maior = mais para cima) só para mim n esquecer sempre q for mexer
		
		// Custom/RightFull gameplay layouts replace the D-pad buttons entirely
		// (see _loadCustomPositions()/_rightSideLayout() below) -- this used to
		// build the default LEFT_FULL positions here regardless, then build a
		// SECOND full set of 4 buttons on top via those functions without ever
		// removing the first set, since createButton() unconditionally adds
		// and pushes every button it makes. That left two full D-pads active
		// and receiving touches at once for anyone using Custom or RightFull.
		// Skip building the default set at all when we know it'll be replaced.
		final dPadOverridden = forGameplay && (ClientPrefs.virtualPadLayout == 'Custom' || ClientPrefs.virtualPadLayout == 'RightFull');
		if (!dPadOverridden)
		switch (DPad)
		{
			case UP_DOWN:
				buttonUp = add(createButton(dPad_X, baseY - 255, 'up', 0x00FF00, [UP, noteUP]));
				buttonDown = add(createButton(dPad_X, baseY - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
			case LEFT_RIGHT:
				buttonLeft = add(createButton(dPad_X, baseY - 135, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(dPad_X + 127, baseY - 135, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
			case UP_LEFT_RIGHT:
				buttonUp = add(createButton(dPad_X + 105, baseY - 243, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft = add(createButton(dPad_X, baseY - 135, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(dPad_X + 207, baseY - 135, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
			case LEFT_FULL:
				buttonUp = add(createButton(dPad_X + 105, baseY - 345, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft = add(createButton(dPad_X, baseY - 243, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(dPad_X + 207, baseY - 243, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
				buttonDown = add(createButton(dPad_X + 105, baseY - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
			case CHART_EDITOR:
                buttonUp = add(createButton(dPad_X + 305, baseY - 345, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft = add(createButton(dPad_X + 200, baseY - 243, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(dPad_X + 407, baseY - 243, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
				buttonDown = add(createButton(dPad_X + 305, baseY - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
			case NONE:
				// lmao
			default:
				buttonUp = add(createButton(dPad_X, baseY - 255, 'up', 0x00FF00, [UP, noteUP]));
				buttonDown = add(createButton(dPad_X, baseY - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
		}
		switch (Action)
		{
			case A:
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case B:
				buttonB = add(createButton(actionX - 132, screenH - 135, 'b', 0xFFCB00, [B]));
			case X:
				buttonX = add(createButton(actionX - 132, screenH - 135, 'x', 0x99062D, [X]));
			case A_B:
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case A_B_C:
				buttonC = add(createButton(actionX - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case STORYMENU:
			    buttonR = add(createButton(actionX - 510, screenH - 135, 'r', 0x00D0FF, [NONE]));
				buttonC = add(createButton(actionX - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case FREEPLAY:
			    buttonR = add(createButton(actionX - 510, screenH - 135, 'r', 0x00D0FF, [NONE]));
				buttonC = add(createButton(actionX - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case CHART_EDITOR:
				buttonV = add(createButton(actionX - 258, baseY - 495, 'v', 0x49A9B2, [V]));
				buttonS = add(createButton(actionX - 132, baseY - 615, 's', 0xFDD6AB, [NONE]));
				buttonX = add(createButton(actionX - 132, baseY - 495, 'x', 0x99062D, [X]));
				buttonD = add(createButton(actionX - 258, baseY - 255, 'd', 0x0078FF, [D]));
				buttonC = add(createButton(actionX - 132, baseY - 375, 'c', 0x44FF00, [C]));
				buttonY = add(createButton(actionX - 258, baseY - 375, 'y', 0x4A35B9, [Y]));
				buttonZ = add(createButton(actionX - 132, baseY - 255, 'z', 0xCCB98E, [Z]));
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case CHARACTER_EDITOR:
				buttonUp2 = add(createButton(dPad2_X + 105, dPad2_Y, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft2 = add(createButton(dPad2_X, dPad2_Y + 105, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight2 = add(createButton(dPad2_X + 210, dPad2_Y + 105, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
				buttonDown2 = add(createButton(dPad2_X + 105, dPad2_Y + 210, 'down', 0x00FFFF, [DOWN, noteDOWN]));
				buttonV = add(createButton(actionX - 510, baseY - 255, 'v', 0x49A9B2, [V]));
				buttonD = add(createButton(actionX - 510, screenH - 135, 'd', 0x0078FF, [D]));
				buttonX = add(createButton(actionX - 384, baseY - 255, 'x', 0x99062D, [X]));
				buttonC = add(createButton(actionX - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonY = add(createButton(actionX - 258, baseY - 255, 'y', 0x4A35B9, [Y]));
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonZ = add(createButton(actionX - 132, baseY - 255, 'z', 0xCCB98E, [Z]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case NONE:
				// lmao
			default:
				buttonB = add(createButton(actionX - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(actionX - 132, screenH - 135, 'a', 0xFF0000, [A]));
		}
		
		scrollFactor.set();
		// CUSTOM / RightFull layouts: override positions if configured
		if (forGameplay)
		{
			if (ClientPrefs.virtualPadLayout == 'Custom')
				_loadCustomPositions();
			else if (ClientPrefs.virtualPadLayout == 'RightFull')
				_rightSideLayout();
		}
		
		refreshMappedButtons();
	}
	
	/**
	 * Load custom button positions from ClientPrefs.
	 * Uses the new JSON map (customPadPositionsJson) first for all buttons,
	 * then falls back to legacy customPadPositions for backward compatibility.
	 */
	function _loadCustomPositions():Void
	{
		var dirs = ['left', 'down', 'up', 'right'];
		var colors = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000];
		var ids = [
			[LEFT, noteLEFT],
			[DOWN, noteDOWN],
			[UP, noteUP],
			[RIGHT, noteRIGHT]
		];
		var keys = ['buttonLeft', 'buttonDown', 'buttonUp', 'buttonRight'];

		// Try to load from the JSON map first (set by VirtualPadCustomizerSubState)
		var jsonMap:Map<String, Array<Float>> = _parseCustomPositionsJson();
		
		for (i in 0...4)
		{
			var pos:Array<Float>;

			// Check JSON map first
			if (jsonMap.exists(keys[i]))
			{
				pos = jsonMap.get(keys[i]);
			}
			// Then legacy array
			else if (ClientPrefs.customPadPositions[i][0] >= 0)
			{
				pos = ClientPrefs.customPadPositions[i];
			}
			// Finally default
			else
			{
				pos = _defaultPosition(i);
			}

			var btn = createButton(pos[0], pos[1], dirs[i], colors[i], ids[i]);
			switch (i)
			{
				case 0: buttonLeft = add(btn);
				case 1: buttonDown = add(btn);
				case 2: buttonUp = add(btn);
				case 3: buttonRight = add(btn);
			}
		}
	}

	/**
	 * Parse the customPadPositionsJson string into a usable Map.
	 * Returns empty map if not set or invalid JSON.
	 */
	static function _parseCustomPositionsJson():Map<String, Array<Float>>
	{
		var map = new Map<String, Array<Float>>();
		var raw = ClientPrefs.customPadPositionsJson;
		if (raw == null || raw == "") return map;
		try
		{
			var parsed:Dynamic = haxe.Json.parse(raw);
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
		catch (e:Dynamic) {}
		return map;
	}
	
	function _defaultPosition(i:Int):Array<Float>
	{
		var safe = ScreenUtil.safeArea();
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
	
	function _rightSideLayout():Void
	{
		var screenW = FlxG.width;
		var safe = ScreenUtil.safeArea();
		var safeRight = Std.int(safe.right);
		var baseY = FlxG.height - Std.int(safe.bottom);
		
		buttonUp = add(createButton(screenW - safeRight - 260, baseY - 300, 'up', 0x00FF00, [UP, noteUP]));
		buttonLeft = add(createButton(screenW - safeRight - 20, baseY - 220, 'left', 0xFF00FF, [LEFT, noteLEFT]));
		buttonRight = add(createButton(screenW - safeRight - 140, baseY - 220, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
		buttonDown = add(createButton(screenW - safeRight - 140, baseY - 140, 'down', 0x00FFFF, [DOWN, noteDOWN]));
	}
	
	
	private function createButton(X:Float, Y:Float, Graphic:String, Color:Int, IDs:Array<FlxMobileInputID>):FlxButton
	{
		var graphic:FlxGraphic = null;
		var path:String = 'assets/mobile/virtualpad/${Graphic}.png';
		var cacheKey:String = path;

		#if MODS_ALLOWED
		var modsPath:String = Paths.modFolders('mobile/virtualpad/${Graphic}.png');
		if (FileSystem.exists(modsPath))
		{
			cacheKey = modsPath;
			graphic = FunkinAssets.cache.currentTrackedGraphics.get(cacheKey);
			if (graphic == null)
				graphic = FunkinAssets.cache.cacheBitmap(cacheKey, BitmapData.fromFile(modsPath));
		}
		else
		#end
		{
			if (!Assets.exists(path))
			{
				path = 'assets/mobile/virtualpad/default.png';
				cacheKey = path;
			}

			graphic = FunkinAssets.cache.currentTrackedGraphics.get(cacheKey);
			if (graphic == null)
				graphic = FunkinAssets.cache.cacheBitmap(cacheKey, Assets.getBitmapData(path));
		}
		FunkinAssets.cache.currentTrackedGraphics.addPermanentKey(cacheKey);
		
		var button = new FlxButton(X, Y, IDs);
		
		button.frames = FlxTileFrames.fromGraphic(graphic, FlxPoint.weak(Std.int(graphic.width / 3), graphic.height));
		
		button.solid = false;
		button.moves = false;
		button.immovable = true;
		button.scrollFactor.set();
		button.color = Color;
		button.alpha = funkin.data.ClientPrefs.virtualPadAlpha;
		
		#if FLX_DEBUG button.ignoreDrawDebug = true; #end
		
		buttons.push(button);
		return button;
	}
	
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Hide the gameplay pad entirely whenever a substate covers PlayState
		// (pause menu, cosmetics locker, etc.) -- PlayState keeps ticking this
		// pad underneath any open substate via persistentUpdate, but every one
		// of those substates already brings its own dedicated pad/touch UI for
		// its own navigation, so the gameplay D-pad has nothing useful to do
		// there regardless of navInputMode.
		// This used to only special-case navInputMode == 'Touch' (with a
		// keyboard/gamepad press bringing the pad back) -- for 'Virtual Pad'
		// nav mode specifically, that left the gameplay D-pad fully visible
		// and active AT THE SAME TIME as the substate's own pad (e.g. the
		// pause menu's addVirtualPad(UP_DOWN, A_B)), both receiving touches
		// and likely overlapping on screen. And for 'Touch' mode, the escape
		// hatch back to the gameplay pad via keyboard/gamepad was never
		// actually needed once inside a substate -- that substate's own UI
		// already covers its own input needs. (The Touch-mode softlock this
		// replaced -- the gameplay pad staying hidden during ordinary,
		// unpaused gameplay -- is fixed by requiring subState != null here,
		// same as before.)
		if (forGameplay && FlxG.state.subState != null)
		{
			if (this.visible)
			{
				this.visible = false;
				for (btn in buttons)
				{
					btn.active = false;
					btn.visible = false;
				}
			}
			return;
		}

		// Normal behavior for non-gameplay pads or when Virtual Pad navigation is enabled
		// (FlxG.touches.justStarted() would allocate a fresh Array every frame just to check
		// its length and immediately discard it - scan the existing touch list instead)
		var anyTouchJustStarted = false;
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				anyTouchJustStarted = true;
				break;
			}
		}
		if (anyTouchJustStarted)
		{
			if (!this.visible)
			{
				this.visible = true;
				keyboardPressed = false;
				gamepadPressed = false;
				for (btn in buttons)
				{
					btn.active = true;
					btn.visible = true;
				}
			}
		}

		keyboardPressed = FlxG.keys.justPressed.ANY;

		// FlxG.gamepads.getActiveGamepads() would allocate a fresh Array every frame just to
		// scan it for a justPressed button; anyButton() checks the same state with no allocation.
		if (FlxG.gamepads.anyButton(JUST_PRESSED)) gamepadPressed = true;

		if (keyboardPressed || gamepadPressed)
		{
			if (this.visible)
			{
				this.visible = false;
				for (btn in buttons)
				{
					btn.active = false;
					btn.visible = false;
				}
			}
		}
	}
	
	override public function destroy():Void
	{
		for (btn in buttons)
			FlxDestroyUtil.destroy(btn);
			
		super.destroy();
	}
}
