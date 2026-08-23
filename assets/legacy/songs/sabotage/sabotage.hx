var wellFuckYouThen:Bool = false;

function onLoad()
{
	videoCutscene('week1/sabotage');
}

function onCreatePost()
{
	if (hasGfSkin)
	{
		if (gf.curCharacter != 'gf-ghost') speaker.alpha = 0;
		wellFuckYouThen = true;
	}
	else
	{
		gf.alpha = 0.001;
	}
}

function gfSpawn()
{
	gf.alpha = 1;
}

function onEvent(n, v1, v2)
{
	if (n == 'Legacy')
	{
		if (!wellFuckYouThen)
		{
			switch (v1)
			{
				case 'GF Appear':
					gf.alpha = 1;
				case 'sabotage notice':
					FlxTimer.wait(0.1, gfSpawn);
					dad.playAnim('ayo', true);
					dad.stunned = true;
					gf.playAnim('scared', true);
					gf.stunned = true;
				case 'sabotage back':
					dad.stunned = false;
					gf.stunned = false;
			}
		}
	}
}
