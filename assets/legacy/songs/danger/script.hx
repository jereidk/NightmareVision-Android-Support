function onLoad()
{
	videoCutscene('week3/danger', false);
}

function onCreatePost()
{
	snapCamToPos(1634.05, -54.3);
	camSpecialThing([1634.05, -54.3], [1734.05, -54.3], 0.3);
}

function onBeatHit()
{
	switch (curBeat)
	{
		case 1:
			camSpecialThing([1634.05, -54.3], [1634.05, -54.3], 0.3);
		case 64:
			camSpecialThing([800, 150], [1200, 150], 0.4);
		case 96:
			camSpecialThing([700, 150], [1200, 150], 0.6);
		case 128:
			camSpecialThing([800, 150], [1200, 150], 0.4);
		case 144:
			camSpecialThing([800, 150], [1200, 150], 0.5);
		case 152:
			camSpecialThing([800, 150], [1200, 150], 0.6);
		case 154:
			camSpecialThing([600, 150], [600, 150], 0.6);
		case 156:
			camSpecialThing([450, 150], [450, 150], 0.8);
		case 158:
			game.camGame.shake(0.01, (Conductor.stepCrotchet / 1000) * 4);
			camSpecialThing([450, 150], [450, 150], 0.6);
		case 160:
			camSpecialThing([800, 150], [1200, 150], 0.4);
		case 192:
			camSpecialThing([700, 150], [1200, 150], 0.6);
		case 256:
			camSpecialThing([800, 150], [1200, 150], 0.4);
		case 288:
			camSpecialThing([700, 150], [1200, 150], 0.6);
		case 320:
			camSpecialThing([1634.05, -54.3], [1634.05, -54.3], 0.3);
		case 384:
			camSpecialThing([700, 150], [1200, 150], 0.6);
	}
}
