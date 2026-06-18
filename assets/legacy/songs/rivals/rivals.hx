function onEvent(n, v1, v2)
{
	if (n == 'Legacy' && v1 == 'TOMONGUS BOIII')
	{
		if (boyfriend.curCharacter == 'bf-pixel' || boyfriend.curCharacter == 'bfsus-pixel')
		{
			triggerEventNote('flash', '0', '');
			changeCharacter('bfsus-pixel', 0);
			changeCharacter('hamster', 1);
			boyfriend.playAnim('shoot');
			boyfriend.skipDance = true;
			FlxG.sound.play(Paths.sound('stage/tomongus_Shot'));
		}
	}
}
