function onLoad()
{
	videoCutscene('week3/mando', true);
}

function onBeatHit()
{
	switch (curBeat)
	{
		case 32:
			defaultCamZoom = 0.7;
		case 96:
			defaultCamZoom = 0.7;
		case 128:
			camSpecialThing([350, 547.5], [650, 547.5]);
		case 192:
			defaultCamZoom = 0.8;
		case 196:
			defaultCamZoom = 0.9;
		case 200:
			camSpecialThing([300, 500], [700, 500], 0.6);
	}
}
