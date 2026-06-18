function onLoad()
{
	var bg:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image("stages/freeplay/drippypop/ng"));
	add(bg);
}

function onCreatePost()
{
	camSpecialThing([1200, 600], [1350, 600]);
}

function onEvent(eventName, value1, value2)
{
	if (eventName == 'Legacy')
	{
		if (value1 == 'dripCam')
		{
			switch (value2)
			{
				case 'pico':
					camCurTarget = game.gf;
					camSpecialThing([1350, 600], [1300, 370]); // picos cam pos slightly lower than in vanilla v4 on purpose
					defaultCamZoom = 1.1;
				default:
					camCurTarget = null;
					camSpecialThing([1200, 600], [1350, 600]);
					defaultCamZoom = 0.9;
			}
		}
	}
}
