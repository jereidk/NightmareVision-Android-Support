var cutscene = (hasBfSkin || hasGfSkin) ? 'week2/ejected-empty' : 'week2/ejected';

function onCreatePost()
{
	camGame.alpha = camHUD.alpha = 0;
	taskGroup.visible = false;
	
	intro = new FunkinVideoSprite();
	intro.onFormat(() -> {
		intro.cameras = [camOther];
		intro.setGraphicSize(FlxG.width);
		intro.screenCenter();
		add(intro);
	});
	intro.onEnd(() -> {
		camGame.alpha = 1;
		camHUD.alpha = 1;
		camGame.flash(0xFFFFFFFF, 0.35);
		intro.kill();
	});
	intro.load(Paths.video(cutscene), [FunkinVideoSprite.muted]);
	intro.antialiasing = ClientPrefs.globalAntialiasing;
	
	// Desync prevention (at least as much as I can do)
	intro.play();
	intro.pause();
	intro.tiedToGame = false;

	//camSpecialThing([-650, 700], [650, 800]);
}

function onSongStart()
{
	intro.play();
	intro.tiedToGame = true;
}

var camZoomOnWho:Bool = true;

function onMoveCamera(isDad)
{
	if(!camZoomOnWho) return;
	if (isDad == 'boyfriend')
	{
		defaultCamZoom = 0.6;
	}
	else
	{
		defaultCamZoom = 0.45;
	}
}

function onUpdate()
{
	if (FlxG.keys.justPressed.Z && ClientPrefs.inDevMode)
	{
		trace('SKIP TO DROP');
		setSongTime(24000);
		clearNotesBefore(Conductor.songPosition);
	}
}

function onEvent(name, v1, v2)
{
	switch (name)
	{
		case 'Legacy':
			switch (v1)
			{
				case 'snapgreen':
					defaultCamZoom = 0.45;
					camZoomOnWho = false;
					isCameraOnForcedPos = true;
					snapCamToPos(-100, 700);
				case 'snapbf':
					isCameraOnForcedPos = true;
					snapCamToPos(650, 700);
				case 'snapmid':
					camZoomOnWho = false;
					isCameraOnForcedPos = false;
					camSpecialThing([300, 700], [300, 700], 0.4);
				case 'snapno':
					isCameraOnForcedPos = false;
					camZoomOnWho = true;
					resetCam();
				case 'zoom':
					camZoomOnWho = v2 == '1';
				case 'mc':
					camSpecialThing([275, 550], [275, 550]);
				case 'just in case':
					taskGroup.visible = true;
					startTaskSong();
					if (intro != null)
					{
						camGame.alpha = 1;
						camHUD.alpha = 1;
						intro.kill();
						camGame.flash(FlxColor.WHITE, 0.35);
					}
			}
	}
}
