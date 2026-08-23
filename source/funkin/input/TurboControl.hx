package funkin.input;

import flixel.input.gamepad.FlxGamepadInputID;
import flixel.group.FlxGroup;
import flixel.FlxBasic;

class TurboControlGroup extends FlxTypedGroup<TurboControl>
{
	override function onMemberAdd(member:TurboControl):Void
	{
		if (member != null)
			member.turbos = members;
		
		super.onMemberAdd(member);
	}
}

class TurboControl extends FlxBasic // very basic turbo control thingy
{
	public var rate:Float = (1 / 12);
	public var initialDelay:Float = (1 / 3);
	
	public var turbos:Array<TurboControl> = [];
	public var buttons:Null<Array<Int>> = null; // for controllers
	public var keys:Array<Int>;
	
	public var holding:Bool = false;
	
	var _pressedElapsed:Float = 0;
	
	var _pressed:Bool = false;
	
	public function new(keys:Array<Int>, rate:Float = 0.1)
	{
		super();
		this.keys = keys;
		this.rate = rate;
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		var justPressed:Bool = false;
		var pressed:Bool = false;
		
		if (buttons != null)
		{
			for (button in buttons)
			{
				justPressed = FlxG.gamepads.anyJustPressed(button);
				pressed = FlxG.gamepads.anyPressed(button);
				
				if (pressed) break;
			}
		}
		
		justPressed = (justPressed || FlxG.keys.anyJustPressed(keys));
		pressed = (pressed || FlxG.keys.anyPressed(keys));
		
		if (!holding)
		{
			if (justPressed)
			{
				for (turbo in turbos)
				{
					turbo.holding = (turbo == this);
				}
			}
		}
		else if (!pressed)
		{
			holding = false;
		}
		
		if (holding)
		{
			if (_pressedElapsed == 0)
			{
				_pressed = true;
			}
			else if (_pressedElapsed >= (initialDelay + rate))
			{
				_pressed = true;
				_pressedElapsed -= rate;
			}
			else
			{
				_pressed = false;
			}
			
			_pressedElapsed += elapsed;
		}
		else
		{
			_pressedElapsed = 0;
			_pressed = false;
		}
	}
	
	public var PRESSED(get, never):Bool;
	
	function get_PRESSED():Bool
	{
		return _pressed;
	}
	
	public static function fromControl(action:String, rate:Float = 0.1)
	{
		var keys = ClientPrefs.keyBinds.get(action);
		if (keys == null) throw 'what. $action keybinds doesnt exist.';
		
		var instance = new TurboControl(keys, rate);
		
		if (action.startsWith('ui_')) // hacky but im just porting this from something else //clean it up if ud like
		{
			instance.buttons = switch (action.split('_')[1])
			{
				case 'left': [FlxGamepadInputID.DPAD_LEFT, FlxGamepadInputID.LEFT_STICK_DIGITAL_LEFT];
				
				case 'right': [FlxGamepadInputID.DPAD_RIGHT, FlxGamepadInputID.LEFT_STICK_DIGITAL_RIGHT];
				
				case 'down': [FlxGamepadInputID.DPAD_DOWN, FlxGamepadInputID.LEFT_STICK_DIGITAL_DOWN];
				
				case 'up': [FlxGamepadInputID.DPAD_UP, FlxGamepadInputID.LEFT_STICK_DIGITAL_UP];
				
				default: null;
			}
		}
		else
		{
			instance.buttons = ClientPrefs.gamepadBinds.get(action);
		}
		
		return instance;
	}
}
