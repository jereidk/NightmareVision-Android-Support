function onEvent(name, v1, v2)
{
	if (boyfriend.curCharacter != 'bfsusreal') return;
	// LOL
	switch (v1)
	{
		case 'p1':
			triggerEventNote("Camera Follow Pos", "1000", "650");
		case 'p2':
			triggerEventNote("HUD Fade", "0", "1");
		case 'p3':
			triggerEventNote("tuesdayblast", "", "");
		case 'p4':
			triggerEventNote("Play Animation", "prep", "Dad");
		case 'p5':
			triggerEventNote("Play Animation", "shoot", "BF");
		case 'p6':
			triggerEventNote("Play Animation", "shot", "Dad");
		case 'p7':
			triggerEventNote("Alt Idle Animation", "Dad", "-alt");
	}
}
