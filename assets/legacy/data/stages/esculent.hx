function onLoad()
{
	var bg:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image("stages/freeplay/esculent/background"));
	bg.setGraphicSize(Std.int(bg.width * 0.5));
	add(bg);
	
	var bg2:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image("stages/freeplay/esculent/scary ass shadow"));
	bg2.setGraphicSize(Std.int(bg.width * 0.5));
	add(bg2);
}

function onCreatePost()
{
	camSpecialThing([1200, 700], [1200, 700]);
	game.snapCamToPos(1200, 700);
	
	// We don't need these
	game.boyfriendGroup.kill();
	game.gfGroup.kill();
}
