var reactorIntro:Bool = (PlayState.isStoryMode && !PlayState.seenCutscene);

function onCreatePost()
{
	if (reactorIntro) camGame.fade(FlxColor.BLACK, 0);
	
	camSpecialThing([1725, 1100], [1725, 1100], defaultCamZoom, 0);
	
	PlayState.seenCutscene = true;
}

function onEvent(n, v1, v2)
{
	switch (n)
	{
		case 'Legacy':
			switch (v1)
			{
				case 'base':
					camSpecialThing([1450, 1150], [1950, 1150], 0.8);
				case 'mid':
					camSpecialThing([1725, 1100], [1725, 1100], 0.7);
				case 'mid2':
					camSpecialThing([1725, 1100], [1725, 1100], 0.8);
				case 'mid3':
					camSpecialThing([1725, 1200], [1725, 1200], 0.9);
			}
	}
}

function onSongStart():Void
{
	if (!reactorIntro) return;
	
	camGame.alpha = 1;
	camGame.zoom += .2;
	camGame.scroll.y -= 400; // zzz
	camGame.fade(FlxColor.BLACK, 2, true);
	
	FlxTween.tween(camGame, {zoom: camGame.zoom - .2}, 5, {ease: FlxEase.expoOut});
}

function onBeatHit():Void // im sso lazy to mak this an event im sowwy
{
	if (PlayState.isStoryMode && curBeat == 712)
	{
		camGame.fade(FlxColor.BLACK, Conductor.crotchet * .024);
		
		FlxTween.tween(camGame, {'scroll.x': camGame.scroll.x + 400, 'scroll.y': camGame.scroll.y + 100, zoom: camGame.zoom + .2}, Conductor.crotchet * .032, {ease: FlxEase.sineInOut});
	}
}
