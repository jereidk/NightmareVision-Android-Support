package funkin.game.marathon;

import flixel.FlxG;

@:access(funkin.states.PlayState)
class DirectionModifier extends MaraModifier
{
	public function new()
	{
		super();
		name = "Switch Directions";
		description = "wow bro";
	}
	
	override public function onActive()
	{
		isActive = true;
	}
	
	override public function onCreatePost()
	{
		if (isActive)
		{
			trace("WE CAN MOVE BRO");
			PlayState.instance.modManager.queueEase(-15, 0, "transform0X", 340, 'quadInOut', 0);
			PlayState.instance.modManager.queueEase(-15, 0, "transform3X", -340, 'quadInOut', 0);
		}
	}
	
	override public function onRemove()
	{
		isActive = false;
	}
}
