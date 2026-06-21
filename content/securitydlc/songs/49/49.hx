function onLoad()
{
    videoCutscene('49');
}

function onStepHit() //song event
{
	if (curStep == 993)
	{
		greypet.alpha = 0.001;
		deadtawny.alpha = 1;
		tawny.alpha = 0.001;
        camSpecialThing([270, 450], [850, 450]);
	}
}