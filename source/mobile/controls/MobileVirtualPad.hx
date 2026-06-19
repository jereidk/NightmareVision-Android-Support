package mobile.controls;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxTileFrames;
import flixel.math.FlxPoint;
import flixel.util.FlxDestroyUtil;

import mobile.backend.flixel.FlxButton;

import openfl.utils.Assets;
import openfl.display.BitmapData;

import mobile.backend.flixel.input.TouchInputManager;
import mobile.backend.flixel.input.FlxMobileInputID;

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
	
	public function new(DPad:MobileDPadMode, Action:MobileActionMode)
	{
		super();
		
		var screenW = FlxG.width;
		var screenH = FlxG.height;
		var dPad2_X = 420; // Move para os lados (maior = mais para a direita)
		var dPad2_Y = screenH - 620; // Move para cima/baixo (maior = mais para cima) só para mim n esquecer sempre q for mexer
		
		switch (DPad)
		{
			case UP_DOWN:
				buttonUp = add(createButton(0, FlxG.height - 255, 'up', 0x00FF00, [UP, noteUP]));
				buttonDown = add(createButton(0, FlxG.height - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
			case LEFT_RIGHT:
				buttonLeft = add(createButton(0, FlxG.height - 135, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(127, FlxG.height - 135, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
			case UP_LEFT_RIGHT:
				buttonUp = add(createButton(105, FlxG.height - 243, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft = add(createButton(0, FlxG.height - 135, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(207, FlxG.height - 135, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
			case LEFT_FULL:
				buttonUp = add(createButton(105, FlxG.height - 345, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft = add(createButton(0, FlxG.height - 243, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(207, FlxG.height - 243, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
				buttonDown = add(createButton(105, FlxG.height - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
			case CHART_EDITOR:
                buttonUp = add(createButton(305, FlxG.height - 345, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft = add(createButton(200, FlxG.height - 243, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight = add(createButton(407, FlxG.height - 243, 'right', 0xFF0000, [RIGHT, noteRIGHT]));		
				buttonDown = add(createButton(305, FlxG.height - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
			case NONE:
				// lmao
			default:
				buttonUp = add(createButton(0, FlxG.height - 255, 'up', 0x00FF00, [UP, noteUP]));
				buttonDown = add(createButton(0, FlxG.height - 135, 'down', 0x00FFFF, [DOWN, noteDOWN]));
		}
		switch (Action)
		{
			case A:
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case B:
				buttonB = add(createButton(screenW - 132, screenH - 135, 'b', 0xFFCB00, [B]));
			case X:
				buttonX = add(createButton(screenW - 132, screenH - 135, 'x', 0x99062D, [X]));
			case A_B:
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case A_B_C:
				buttonC = add(createButton(screenW - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case STORYMENU:
			    buttonR = add(createButton(screenW - 510, screenH - 135, 'r', 0x00D0FF, [NONE]));
				buttonC = add(createButton(screenW - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case FREEPLAY:
			    buttonX = add(createButton(screenW - 258, screenH - 255, 'x', 0x99062D, [X]));
			    buttonS = add(createButton(screenW - 132, screenH - 255, 's', 0xFDD6AB, [NONE]));
			    buttonR = add(createButton(screenW - 510, screenH - 135, 'r', 0x00D0FF, [NONE]));
				buttonC = add(createButton(screenW - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case CHART_EDITOR:
				buttonV = add(createButton(screenW - 258, screenH - 495, 'v', 0x49A9B2, [V]));
				buttonS = add(createButton(screenW - 132, screenH - 615, 's', 0xFDD6AB, [NONE]));
				buttonX = add(createButton(screenW - 132, screenH - 495, 'x', 0x99062D, [X]));
				buttonD = add(createButton(screenW - 258, screenH - 255, 'd', 0x0078FF, [D]));
				buttonC = add(createButton(screenW - 132, screenH - 375, 'c', 0x44FF00, [C]));
				buttonY = add(createButton(screenW - 258, screenH - 375, 'y', 0x4A35B9, [Y]));
				buttonZ = add(createButton(screenW - 132, screenH - 255, 'z', 0xCCB98E, [Z]));
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case CHARACTER_EDITOR:
				buttonUp2 = add(createButton(dPad2_X + 105, dPad2_Y, 'up', 0x00FF00, [UP, noteUP]));
				buttonLeft2 = add(createButton(dPad2_X, dPad2_Y + 105, 'left', 0xFF00FF, [LEFT, noteLEFT]));
				buttonRight2 = add(createButton(dPad2_X + 210, dPad2_Y + 105, 'right', 0xFF0000, [RIGHT, noteRIGHT]));
				buttonDown2 = add(createButton(dPad2_X + 105, dPad2_Y + 210, 'down', 0x00FFFF, [DOWN, noteDOWN]));
				buttonV = add(createButton(screenW - 510, screenH - 255, 'v', 0x49A9B2, [V]));
				buttonD = add(createButton(screenW - 510, screenH - 135, 'd', 0x0078FF, [D]));
				buttonX = add(createButton(screenW - 384, screenH - 255, 'x', 0x99062D, [X]));
				buttonC = add(createButton(screenW - 384, screenH - 135, 'c', 0x44FF00, [C]));
				buttonY = add(createButton(screenW - 258, screenH - 255, 'y', 0x4A35B9, [Y]));
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonZ = add(createButton(screenW - 132, screenH - 255, 'z', 0xCCB98E, [Z]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
			case NONE:
				// lmao
			default:
				buttonB = add(createButton(screenW - 258, screenH - 135, 'b', 0xFFCB00, [B]));
				buttonA = add(createButton(screenW - 132, screenH - 135, 'a', 0xFF0000, [A]));
		}
		
		scrollFactor.set();
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
