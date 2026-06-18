package funkin.game.marathon;

import flixel.FlxG;

import funkin.objects.SnowEmitter;

@:access(funkin.states.PlayState)
class SnowModifier extends MaraModifier
{
	public var snowAlpha = 1;
	public var snowEmitter:SnowEmitter;
	
	public function new()
	{
		super();
		name = "Snowstorm";
		description = "so much snow";
	}
	
	override public function onActive()
	{
		snowEmitter = new SnowEmitter(-600, -600, 2700);
		snowEmitter.start(false, ClientPrefs.lowQuality ? 0.1 : 0.05);
		snowEmitter.scrollFactor.x.set(1, 1);
		snowEmitter.scrollFactor.y.set(1, 1);
		snowEmitter.camera = PlayState.instance.camOther;
		snowEmitter.speed.set(900, 1100);
		snowEmitter.frequency = 0.01;
		trace(snowEmitter.frequency);
		PlayState.instance.add(snowEmitter);
		snowEmitter.alpha.active = false;
		snowEmitter.onEmit.add((particle) -> particle.alpha = snowAlpha);
		snowEmitter.zIndex = 13;
		
		isActive = true;
	}
	
	override public function onRemove()
	{
		isActive = false;
	}
}
