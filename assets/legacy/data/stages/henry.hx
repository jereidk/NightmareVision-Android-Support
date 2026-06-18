var ext = 'stages/henry/';

function onLoad()
{
	var bg:FlxSprite = new FlxSprite(-1600, -300).loadGraphic(Paths.image(ext + 'stage'));
	add(bg);
}

function onEvent(n, v1, v2)
{
	switch (n)
	{
		case 'Ellie Drop':
			pauseOverwrite = 'ellie';
			mom.visible = true;
			dad.playAnim('shock', false);
			dad.specialAnim = true;
			mom.playAnim('enter', false);
			mom.specialAnim = true;
			iconP2.changeIcon('ellie');
			
		default:
			switch (v1)
			{
				case 'forcecamtarget':
					camCurTarget = switch (v2)
					{
						case 'mom': mom;
						default: null;
					}
			}
	}
}

function onCreatePost()
{
	camSpecialThing([700, 550], [1000, 550], 0.7);
}
