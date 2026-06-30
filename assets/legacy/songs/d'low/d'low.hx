var fakeIcon:FlxSprite; // to prevent icon beats

function onLoad()
{
	readDialogue();
}

function onCreatePost()
{
	fakeIcon = new HealthIcon('yellow-dead', false);
	fakeIcon.cameras = [camHUD];
	fakeIcon.setPosition(playHUD.iconP2.x, playHUD.iconP2.y);
	fakeIcon.visible = false;
	add(fakeIcon);
}

function goodNoteHit(note)
{
	if (note.noteType == 'Alt Animation')
	{
		game.boyfriend.playAnim('pull', true);
		game.boyfriend.specialAnim = true;
	}
}

function onUpdate(elapsed)
{
	fakeIcon.x = playHUD.healthBar.barCenter - (150 / 2) - 26 * 2;
}

function onEvent(eventName, value1, value2)
{
	if (eventName == "Legacy")
	{
		if (value1 == 'dlow death')
		{
			playHUD.iconP2.visible = false;
			fakeIcon.visible = true;
			dad.playAnim('death');
			dad.canDance = false;
			camSpecialThing([450, 500], [450, 500], 0.7);
			
			if (boyfriend.curCharacter == 'bfsusreal')
			{
				boyfriend.playAnim('shoot', true);
				boyfriend.specialAnim = boyfriend.skipDance = true;
			}
			else if (boyfriend.hasAnim('scared'))
			{
				boyfriend.playAnim('scared', true);
				boyfriend.specialAnim = boyfriend.skipDance = true;
			}
			
			if (boyfriend.curCharacter == 'yellowplayable') playHUD.iconP1.changeIcon('yellow');
		}
	}
}
