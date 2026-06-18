import flixel.ui.FlxButton;

public var dbGroup = new FlxSpriteGroup();

function onCreatePost()
{
	if (!ClientPrefs.inDevMode) return;
	// trace('well hey');
	game.paused = false;
	dbGroup.camera = game.camOther;
	dbGroup.visible = false;
	add(dbGroup);
	
	final GAYLINE:Int = 90;
	
	closeButton = new FlxButton(GAYLINE, 700, 'restart song', FlxG.resetState);
	dbGroup.add(closeButton);
	lqButton = new FlxButton(GAYLINE * 2, 700, getBool('LQ', ClientPrefs.lowQuality), () -> {
		ClientPrefs.lowQuality = !ClientPrefs.lowQuality;
		ClientPrefs.flush();
		lqButton.text = getBool('LQ', ClientPrefs.lowQuality);
	});
	dbGroup.add(lqButton);
	flButton = new FlxButton(GAYLINE * 3, 700, getBool('FL', ClientPrefs.flashing), () -> {
		ClientPrefs.flashing = !ClientPrefs.flashing;
		ClientPrefs.flush();
		flButton.text = getBool('FL', ClientPrefs.flashing);
	});
	dbGroup.add(flButton);
	shButton = new FlxButton(GAYLINE * 4, 700, getBool('SH', ClientPrefs.shaders), () -> {
		ClientPrefs.shaders = !ClientPrefs.shaders;
		ClientPrefs.flush();
		shButton.text = getBool('SH', ClientPrefs.shaders);
	});
	dbGroup.add(shButton);
	
	msButton = new FlxButton(GAYLINE * 5, 700, getBool('MS', ClientPrefs.middleScroll), () -> {
		ClientPrefs.middleScroll = !ClientPrefs.middleScroll;
		ClientPrefs.flush();
		msButton.text = getBool('MS', ClientPrefs.middleScroll);
	});
	dbGroup.add(msButton);
	// getBool('Low Quality Mode', ClientPrefs.lowQuality) + getBool('Flashing Lights', ClientPrefs.flashing);
}

function onUpdate()
{
	if (ClientPrefs.inDevMode || PlayState.chartingMode)
	{
		if (FlxG.keys.pressed.THREE) playbackRate = 2;
		if (FlxG.keys.released.THREE) playbackRate = 1;
	}
}
