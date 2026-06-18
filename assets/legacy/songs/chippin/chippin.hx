var idontwanttocodeitlikethis = false;

function onBeatHit()
{
	switch (curBeat)
	{
		case 168:
			fugly_cam_event = false;
			snapCamToPos(800, 450, true);
			camGame.zoom = 0.7;
			idontwanttocodeitlikethis = true;
		case 170:
			snapCamToPos(600, 450, true);
			camGame.zoom = 0.75;
			camSpecialThing([600, 450], [800, 450], 0.75);
		case 172:
			cameraSpeed = 0.5;
			isCameraOnForcedPos = false;
		case 176:
			idontwanttocodeitlikethis = false;
			camZooming = true;
			defaultCamZoomAdd = -0.17;
			cameraSpeed = 1;
	}
	
	//    switch(curBeat) {
	
	//  }
}

function onUpdate(elapsed)
{
	if (idontwanttocodeitlikethis) camZooming = false;
}

function onCreatePost()
{
	defaultCamZoom = 0.58; // lol
}
