package funkin.game.marathon;

@:access(funkin.states.PlayState)
class MaraModifier
{
	public var name:String = "Base";
	public var description:String = "";
	public var isActive:Bool = false;
	
	public function new() {}
	
	public function onActive():Void {}
	
	public function onRemove():Void {}
	
	public function update(elapsed:Float) {}
	
	public function init():Void {}
	
	public function onSongStart():Void {}
	
	public function onCreatePost():Void {}
}
