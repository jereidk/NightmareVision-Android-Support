package funkin.objects.menu;

import flixel.input.gamepad.FlxGamepad.FlxGamepadModel;
import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets.FlxGraphicAsset;
import flixel.group.FlxSpriteGroup;

/**
 * The UI controls of menus with Language and Left to Right support!
**/
class AmongControls extends FlxSpriteGroup
{
	static var _lastInputType:Null<FlxGamepadModel> = null; // if its null that means keyboard.
	
	/**
	 * The padding between most nodes.
	**/
	final PADDING:Int = 12;
	
	/**
	 * basically just puts it down lol
	**/
	final controlY:Int = FlxG.height - 42;
	
	var showBlackBox:Bool;
	
	var inputs:Array<Array<String>>;
	
	var dummyText:FlxText;
	
	public function new(c:Array<Array<String>>, blackBox:Bool = false)
	{
		super();
		
		showBlackBox = blackBox;
		inputs = c;
		
		dummyText = new FlxText();
		
		refreshBar();
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		checkInputType();
	}
	
	function checkInputType()
	{
		if (FlxG.gamepads.anyInput())
		{
			final curModel = FlxG.gamepads.firstActive?.detectedModel;
			
			if (curModel != null && _lastInputType != curModel)
			{
				_lastInputType = curModel;
				refreshBar();
			}
		}
		else if (FlxG.keys.firstJustPressed() != -1 && _lastInputType != null)
		{
			_lastInputType = null;
			refreshBar();
		}
	}
	
	function refreshBar()
	{
		forEach(spr -> spr?.destroy());
		
		clear();
		
		var controlX:Float = 12;
		
		for (i in 0...inputs.length)
		{
			var controlIcon:FlxSprite = add(new FlxSprite(controlX, controlY, getInputVisual(inputs[i][0])));
			
			controlX += (controlIcon.width + PADDING);
			
			var controlTip = add(new FlxSprite(controlX, controlY, getTextAsGraphic(Lang.str(inputs[i][1], inputs[i][1]))));
			
			controlTip.y += Math.round((controlIcon.height - controlTip.height) * .5 + 3);
			
			controlX += (controlTip.width + PADDING);
		}
		
		if (Lang.hasSpecial('rightToLeft'))
		{
			for (member in members) member.x = (FlxG.width - member.x - member.width);
		}
		
		if (showBlackBox) insert(0, new FlxSprite(0, controlY).makeScaledGraphic(FlxG.width + 1, 42, FlxColor.BLACK));
	}
	
	function getInputVisual(str:String):FlxGraphicAsset
	{
		var path = 'menu/common/controls/';
		
		switch (str)
		{
			case 'arrow':
				return Paths.image(path + (_lastInputType == null ? 'arrow' : 'dpad'));
				
			case 'tab':
				if (_lastInputType == null) return Paths.image(path + str);
				else return Paths.image(path + getFaceButton('X'));
			case 'esc':
				if (_lastInputType == null) return Paths.image(path + str);
				else return Paths.image(path + getFaceButton('B'));
				
			case 'enter':
				if (_lastInputType == null) return Paths.image(path + str);
				else return Paths.image(path + getFaceButton('A'));
			
			case 'reset':
				return Paths.image(path + (_lastInputType == null ? 'reset' : 'L3'));
		}
		
		return getTextAsGraphic(str);
	}
	
	inline function getFaceButton(faceButton:String)
	{
		return switch (_lastInputType)
		{
			default:
				'X_' + faceButton;
				
			case PS4 | PS5:
				'PS4_' + faceButton;
				
			case SWITCH_PRO:
				'X_' + switch (faceButton) // we gotta invert the button
				{
					case 'A': 'B';
					case 'B': 'A';
					case 'X': 'Y';
					case 'Y': 'X';
					default: faceButton;
				}
		}
	}
	
	inline function getTextAsGraphic(str:String) // i actually do not know why i did this but it works still ig
	{
		if (!dummyText?.exists) return null;
		
		dummyText.setFormat(Paths.font('vcr.ttf'), 20);
		dummyText.text = str;
		
		@:privateAccess
		dummyText.regenGraphic();
		
		return FlxGraphic.fromGraphic(dummyText.graphic, true);
	}
	
	override function destroy()
	{
		dummyText = FlxDestroyUtil.destroy(dummyText);
		super.destroy();
	}
}
