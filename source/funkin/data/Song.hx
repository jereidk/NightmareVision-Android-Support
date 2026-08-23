package funkin.data;

typedef SongSection =
{
	var sectionNotes:Array<Dynamic>;
	var mustHitSection:Bool;
	
	var ?sectionBeats:Int;
	var gfSection:Bool;
	var bpm:Float;
	var changeBPM:Bool;
	var altAnim:Bool;
}

typedef Song =
{
	var song:String;
	var notes:Array<SongSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var ?trackSwap:Bool;
	var speed:Float;
	
	var keys:Int;
	var lanes:Int;
	
	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	
	var arrowSkins:Array<String>;
	var ?flags:haxe.DynamicAccess<Dynamic>;
	
	var allowBFskin:Bool;
	var allowGFskin:Bool;
	var allowPet:Bool;
	
	var ?format:String;
}
