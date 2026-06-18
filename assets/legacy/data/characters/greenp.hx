function onKeyPress(k:Int):Void
{
	if (k == 2 && parent.getAnimName() == 'idle' && (tauntCharacter == null || tauntCharacter == parent))
	{
		parent.playAnim('singUP');
		parent.specialAnim = true;
		parent.animCurFrame = 5;
		parent.holding = true;
	}
}
