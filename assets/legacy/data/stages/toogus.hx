var ext = 'stages/mira/cafeteria/';
public var loBlack:FlxSprite;
public var bfvent:FlxSprite;
public var ldSpeaker:FlxSprite;
var walkers:Array<AmongWalker> = [];

public var bg:FlxSprite;
public var fg:FlxSprite;
public var tn:FlxSprite;

function onLoad()
{
	// none of the first 3 objects line up 1:1 bc they were cropped and they don't round up/down the same yay!!!
	
	bg = new FlxSprite(-207, 37).loadGraphic(Paths.image(ext + 'mirabg'));
	bg.setGraphicSize(Std.int(bg.width * 1.06));
	
	fg = new FlxSprite(-1649, 49).loadGraphic(Paths.image(ext + 'mirafg'));
	fg.setGraphicSize(Std.int(fg.width * 1.06));
	
	tn = new FlxSprite(-1659, 42).loadGraphic(Paths.image(ext + 'table_bg'));
	tn.setGraphicSize(Std.int(tn.width * 1.06));
	tn.zIndex = 10;
	
	loBlack = new flixel.system.FlxBGSprite();
	loBlack.color = FlxColor.BLACK;
	loBlack.alpha = 0.001;
	loBlack.screenCenter();
	loBlack.zIndex = 12;
	
	bfvent = new FlxSprite(70, 200);
	bfvent.frames = Paths.getSparrowAtlas(ext + 'bf_mira_vent');
	bfvent.animation.addByPrefix('vent', 'bf vent', 24, false);
	bfvent.animation.play('vent');
	bfvent.alpha = 0;
	
	ldSpeaker = new FlxSprite(400, 385);
	ldSpeaker.frames = Paths.getSparrowAtlas(ext + 'stereo_taken');
	ldSpeaker.animation.addByPrefix('boom', 'stereo boom', 24, false);
	ldSpeaker.zIndex = 11;
	ldSpeaker.alpha = 0;
	
	for (i in [bg, fg, bfvent, tn, ldSpeaker, loBlack])
	{
		add(i);
	}
}

function onCreatePost()
{
	camSpecialThing([500, 475], [900, 475]);
}

function onEvent(eventName, value1, value2)
{
	if (eventName == 'Toogus Sax')
	{
		canFollow = false;
		camFollow.x = 400;
		isCameraOnForcedPos = true;
		FlxTween.tween(camFollow, {x: 600, y: camFollow.y - 5}, 11);
		FlxTween.tween(game, {defaultCamZoom: .82}, 11, {ease: FlxEase.sineInOut});
	}
	else if (eventName == 'Legacy')
	{
		if (value1 == 'Toogus Sax Out')
		{
			FlxTween.cancelTweensOf(camFollow);
			FlxTween.cancelTweensOf(game);
			
			canFollow = true;
			isCameraOnForcedPos = false;
			
			defaultCamZoom = .9;
		}
	}
}
