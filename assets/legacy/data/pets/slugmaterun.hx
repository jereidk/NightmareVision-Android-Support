function onStepHit()
{
if (curSong == 'Danger') {
	switch (curStep)
	{
		case 737:
            pet.y -= 100;
            parent.canDance = false;
			parent.playAnim('death', true);
	}
}}