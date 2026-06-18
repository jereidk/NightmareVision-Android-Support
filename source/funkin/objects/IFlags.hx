package funkin.objects;

interface IFlags
{
	public var flags:haxe.DynamicAccess<Dynamic>;
	
	public function hasFlag(flag:String):Bool;
	public function getFlag(flag:String):Dynamic;
}
