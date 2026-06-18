// Character scripts are basically the same as stage scripts so lol

function onCreatePost()
{
	onSectionHit(0);
}

function onSectionHit()
{
	var suffix:String = (mustHitSection ? '' : '-left');
	if (gf.curCharacter == 'upgirl')
	{
		if (game.gf.idleSuffix != suffix) // making sure shes not already looking in the direction we want
		{
			game.gf.playAnim('turn' + suffix, true);
			game.gf.idleSuffix = suffix;
			game.gf.recalculateDanceIdle();
			game.gf.danced = false; // fuck my gay life
		}
	}
}
