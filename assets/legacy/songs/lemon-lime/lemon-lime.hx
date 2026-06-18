public function modchart(step:Int):Void
{
	switch (step)
	{
		case 0, 4, 11, 16, 23, 28, 32, 36, 43, 48, 55, 60, 79, 111:
			if (ClientPrefs.camZooms)
			{
				camGame.zoom += 0.03;
				camHUD.zoom += 0.03;
			}
			
		case 64:
			woo_party = 1;
		case 120, 508, 768:
			woo_party = 0;
			defaultCamZoom = 1.1;
		case 280, 344:
			defaultCamZoom = 0.9;
		case 271, 335:
			defaultCamZoom = 0.8;
		case 252, 384:
			defaultCamZoom = 1;
			woo_party = 1;
		case 416, 450:
			defaultCamZoom += 0.1;
		case 472, 504:
			defaultCamZoom -= 0.1;
		case 128, 256, 512:
			woo_party = 2;
			defaultCamZoom = 0.9;
			if (ClientPrefs.flashing) camGame.flash(FlxColor.WHITE, .5);
	}
}
