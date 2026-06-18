function onLoad()
{
	var bg:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image("stages/freeplay/idk/toby"));
	bg.antialiasing = false;
	add(bg);
}

function onCreatePost()
{
	hasCovers = 0;
	
	game.isCameraOnForcedPos = true;
	game.snapCamToPos(420, 300);
}
