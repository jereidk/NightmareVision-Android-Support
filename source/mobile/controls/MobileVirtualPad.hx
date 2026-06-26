package mobile.controls;

import flixel.FlxG;
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
	
	public function new(DPad:MobileDPadMode, Action:MobileActionMode, ?forGameplay:Bool = false)
	{
		super();
		
		this.forGameplay = forGameplay;
		
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
			    buttonX = add(createButton(actionX - 258, baseY - 255, 'x', 0x99062D, [X]));
			    buttonS = add(createButton(actionX - 132, baseY - 255, 's', 0xFDD6AB, [NONE]));
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
		
		for (i in 0...4)
		{
			var pos = ClientPrefs.customPadPositions[i];
			if (pos[0] < 0 || pos[1] < 0)
			{
				pos = _defaultPosition(i);
				ClientPrefs.customPadPositions[i] = pos;
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
	
	private function createButton
		refreshMappedButtons();
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
			graphic = FlxG.bitmap.get(cacheKey);
			
			if (graphic == null) graphic = FlxGraphic.fromBitmapData(BitmapData.fromFile(modsPath), false, cacheKey);
		}
		else
		#end
		{
			if (!Assets.exists(path))
			{
				path = 'assets/mobile/virtualpad/default.png';
				cacheKey = path;
			}
			
			graphic = FlxG.bitmap.get(cacheKey);
			if (graphic == null) graphic = FlxGraphic.fromBitmapData(Assets.getBitmapData(path), false, cacheKey);
		}
		
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

		// Auto-hide gameplay pad in menus when navInputMode = 'Touch'
		// This allows native touch navigation in menus without interference
		if (forGameplay && ClientPrefs.navInputMode == 'Touch')
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
			// Only show pad when keyboard or gamepad is pressed during gameplay
			keyboardPressed = FlxG.keys.justPressed.ANY;
			gamepadPressed = false;
			if (FlxG.gamepads.numActiveGamepads > 0)
			{
				for (gamepad in FlxG.gamepads.getActiveGamepads())
				{
					if (gamepad.justPressed.ANY)
					{
						gamepadPressed = true;
						break;
					}
				}
			}
			if (keyboardPressed || gamepadPressed)
			{
				this.visible = true;
				for (btn in buttons)
				{
					btn.active = true;
					btn.visible = true;
				}
			}
			return;
		}

		// Normal behavior for non-gameplay pads or when Virtual Pad navigation is enabled
		if (FlxG.touches.justStarted().length > 0)
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

		if (FlxG.gamepads.numActiveGamepads > 0)
		{
			for (gamepad in FlxG.gamepads.getActiveGamepads())
			{
				if (gamepad.justPressed.ANY)
				{
					gamepadPressed = true;
					break;
				}
			}
		}

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
