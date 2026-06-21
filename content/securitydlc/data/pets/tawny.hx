function onStepHit()
{
if (curSong == 'Danger') {
	switch (curStep)
	{
		case 737:
            parent.canDance = false;
			parent.playAnim('death', true);
	}
}}