function onLoad()
{
	parent.useRenderTexture = true;
	parent.alpha = .8;
}

function onUpdate(elapsed:Float):Void
{
	if (FlxG.keys.justPressed.SPACE && boyfriend.curCharacter == 'bf-ghost' && boyfriend.getAnimName() == 'idle-loop')
	{
		boyfriend.playAnim('hey');
		boyfriend.specialAnim = true;
		boyfriend.holding = true;
	}
}
