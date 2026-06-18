import funkin.data.ClientPrefs;

public function modchart(step:Int):Void
{
	switch (step)
	{
		case 240, 246, 252:
			woo_party = 0;
			if (ClientPrefs.flashing)
			{
				camGame.stopFade();
				camGame.flash(FlxColor.WHITE, 1);
				camGame._fxFlashAlpha = .25;
			}
			defaultCamZoom += .07;
			if (ClientPrefs.camZooms)
			{
				camGame.zoom += 0.03;
				camHUD.zoom += 0.03;
			}
			
		case 1600:
			defaultCamZoom = 1.2;
		case 128, 768:
			woo_party = 1;
			defaultCamZoom = 1;
		case 1660:
			defaultCamZoom = 0.9;
			woo_party = 0;
		case 1024:
			woo_party = 2;
			defaultCamZoom = 0.9;
		case 256, 516, 646, 1280, 1414:
			woo_party = 2;
			defaultCamZoom = 0.8;
			camGame.stopFade();
			if (ClientPrefs.flashing) camGame.flash(FlxColor.WHITE, .5);
		case 512, 640, 1264, 1408:
			woo_party = 0;
			defaultCamZoom = 1;
		case 1152, 1216:
			woo_party = 4;
		case 1200:
			woo_party = 2;
		case 1272:
			defaultCamZoom = 1.1;
		case 1536:
			woo_party = 0;
			defaultCamZoom = 1;
		case 1600, 1648:
			defaultCamZoom += .05;
		case 1656, 1660:
			defaultCamZoom -= .1;
	}
}
