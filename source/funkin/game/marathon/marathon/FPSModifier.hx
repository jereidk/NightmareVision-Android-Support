package funkin.game.marathon;

import flixel.FlxG;

@:access(funkin.states.PlayState)
class FPSModifier extends MaraModifier
{
	public function new()
	{
		super();
		name = "Low FPS";
		description = "lol 30 fps";
	}
	
	override public function onActive()
	{
		FlxG.updateFramerate = 30;
		FlxG.drawFramerate = 30;
		isActive = true;
	}
	
	override public function onRemove()
	{
		FlxG.updateFramerate = ClientPrefs.framerate;
		FlxG.drawFramerate = ClientPrefs.framerate;
		isActive = false;
	}
}
