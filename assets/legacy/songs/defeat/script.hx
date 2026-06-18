function onCreatePost()
{
	health = 1; // hmm
	comboX = 440;
	playHUD.updateIconsPosition();
	playHUD.updateIconPos = false;
	modManager.setValue("opponentSwap", 0.5, 0);
	for (i in opponentStrums)
		i.visible = false;
	playHUD.healthBar.alpha = 0;
}

function onUpdate() if (health > 1) health = 1;

function onSpawnNotePost(note:Note)
{
	note.visible = note.mustPress;
}

function onBeatHit()
{
	switch (curBeat)
	{
		case 16:
			camSpecialThing([750, 500], [750, 500], 0.6);
		case 32:
			defaultCamZoom = 0.7;
		case 48:
			defaultCamZoom = 0.8;
		case 68:
			defaultCamZoom = 0.5;
		case 100:
			camSpecialThing([500, 500], [900, 500], 0.6);
		case 164:
			camSpecialThing([750, 500], [750, 500], 0.5);
		case 194:
			defaultCamZoom = 0.6;
		case 212:
			defaultCamZoom = 0.7;
		case 228:
			defaultCamZoom = 0.8;
		case 244:
			defaultCamZoom = 0.85;
		case 260:
			defaultCamZoom = 0.6;
		case 292:
			defaultCamZoom = 0.75;
		case 360:
			camSpecialThing([500, 500], [900, 500], 0.6);
		case 424:
			camSpecialThing([750, 500], [750, 500], 0.7);
		case 456:
			defaultCamZoom = 0.8;
		case 472:
			defaultCamZoom = 0.9;
		case 488:
			defaultCamZoom = 1;
			FlxTween.tween(redscreen, {alpha: 1}, 0.2, {ease: FlxEase.expoOut});
	}
}
