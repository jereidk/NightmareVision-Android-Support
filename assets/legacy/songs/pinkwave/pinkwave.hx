function onCreatePost()
{
	pretenderDark = new FlxSprite(-800, -500); // This could probably be a solid graphic that gets its color changed based off of timers
	pretenderDark.frames = Paths.getSparrowAtlas(ext + 'pretender_dark');
	pretenderDark.animation.addByPrefix('anim', 'amongdark', 24, false);
	pretenderDark.animation.play('anim');
	pretenderDark.alpha = 0.0001;
	if (isStoryMode) songEndCallback = pretender;
	add(pretenderDark);
}

function onLoad() readDialogue();

function pretender()
{
	inCutscene = true;
	triggerEventNote('Camera Follow Pos', 400, 150);
	canPause = false;
	camZooming = true;
	
	for (i in [tomato, longus, greymira, ventNotSus, pretenderDark])
	{
		i.animation.play('anim', true);
	}
	
	if (ClientPrefs.flashing) pretenderDark.alpha = 1;
	else
	{
		FlxTimer.wait(4.2, () -> {
			pretenderDark.alpha = 1;
		});
	}
	FlxG.sound.play(Paths.sound('stage/pretender_kill'));
	defaultCamZoom = 0.75;
	
	FlxTween.tween(camHUD, {alpha: 0}, 0.4);
	FlxTween.tween(gf, {alpha: 0.1}, 0.4);
	FlxTween.tween(dad, {alpha: 0.25}, 0.4);
	FlxTween.tween(boyfriend, {alpha: 0.25}, 0.4);
	
	new FlxTimer().start(9, function(tmr:FlxTimer) {
		endSong();
	});
}
