import funkin.data.ClientPrefs;

public function modchart(step:Int):Void
{
	switch (step)
	{
		case 128:
			woo_party = 1;
		case 256, 384, 768, 896:
			defaultCamZoom = 1.1;
			woo_party = 0;
		case 498, 560, 688, 1008:
			defaultCamZoom = 0.75;
		case 570, 698, 1272:
			defaultCamZoom = 0.8;
		case 574, 702:
			defaultCamZoom = 0.8;
		case 512, 1024:
			defaultCamZoom = 0.9;
			woo_party = 1;
		case 752, 758, 764:
			woo_party = 0;
			if (ClientPrefs.camZooms)
			{
				camGame.zoom += 0.03;
				camHUD.zoom += 0.03;
			}
			
		case 260, 388, 772, 900:
			woo_party = 2;
			defaultCamZoom = 0.9;
			if (ClientPrefs.flashing) camGame.flash(FlxColor.WHITE, .5);
		case 272, 336:
			defaultCamZoom = 1;
		case 22, 54, 86, 118, 152, 184, 216, 248, 656, 528, 1046, 1078, 1110, 1142, 1176, 1208, 1240: // zoom in
			defaultCamZoom = 0.95;
		case 32, 64, 96, 128, 160, 192, 224, 288, 352, 544, 672, 576, 704, 1056, 1088, 1120, 1152, 1184, 1216, 1248: // zoom out
			defaultCamZoom = 0.9;
	}
}
