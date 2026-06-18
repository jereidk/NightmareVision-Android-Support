import funkin.data.ClientPrefs;

public function modchart(step:Int):Void
{
	switch (step)
	{
		case 64, 96, 640:
			defaultCamZoom = 1;
			woo_party = 1;
		case 92, 124, 1408:
			woo_party = 0;
			defaultCamZoom = 0.9;
		case 128, 900:
			woo_party = 2;
			camZooming = true;
			defaultCamZoom = 0.8;
		case 198, 214, 414:
			defaultCamZoom += 0.05;
		case 230, 246, 430:
			defaultCamZoom -= 0.05;
		case 256:
			defaultCamZoom = 0.9;
		case 894:
			defaultCamZoom = 0.75;
		case 1417, 1422, 1427, 1438:
			camZoomingMult = 0;
			camZoomingDecay *= .6;
			defaultCamZoom *= 1.05;
			if (ClientPrefs.camZooms)
			{
				camGame.zoom += 0.015;
				camHUD.zoom += 0.015;
			}
	}
}
