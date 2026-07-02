var ext:String = 'stages/freeplay/who/'; // knowing this stage is a lot more complex i added an ext var!
var bg:FlxSprite;
var whoAngered:FlxSprite;
var meeting:FlxSprite;
var furiousRage:FlxSprite;
var emergency:FlxSprite;
var starsBG:FlxBackDrop;
var starsFG:FlxBackDrop;
var whoend:FlxText;

function onLoad()
{
	addCharacterToList('bluewho', 1);
	addCharacterToList('whitemad', 1);
	
	starsBG = new FlxBackdrop(Paths.image('menu/common/starBG'), FlxAxes.XY, 1, 1);
	starsBG.setPosition(111.3, 67.95);
	starsBG.visible = false;
	add(starsBG);
	
	starsFG = new FlxBackdrop(Paths.image('menu/common/starFG'), FlxAxes.XY, 5, 5);
	starsFG.setPosition(54.3, 59.45);
	starsFG.visible = false;
	add(starsFG);
	
    whoend = new flixel.text.FlxText(0, 1120, -1, 'i love my boyfriend');
	whoend.setFormat(Paths.font('vcr.ttf'), 50, 0xFFFFFFFF);
	whoend.antialiasing = false;
	insert(0, whoend);
	whoend.text = Lang.str('who-end');
	whoend.updateHitbox();
	whoend.x = 1100 - (whoend.frameWidth / 2);
	
	whoAngered = new FlxSprite(-1000, 975);
	whoAngered.loadGraphic(Paths.image(ext + "mad mad dude"));
	whoAngered.visible = false;
	add(whoAngered);

	bg = new FlxSprite(0, 100);
	bg.loadGraphic(Paths.image(ext + "deadguy"));
	add(bg);
	pet.zIndex = 0;

	meeting = new FlxSprite(0, -100);
	meeting.frames = Paths.getSparrowAtlas(ext + 'meeting');
	meeting.animation.addByPrefix('buzz', 'meeting buzz', 16, false);
	meeting.setGraphicSize(Std.int(meeting.width * 1.4));
	meeting.updateHitbox();
	meeting.screenCenter();
	meeting.cameras = [camOther];
	meeting.visible = false;
	// meeting.animation.play('buzz', true);
	add(meeting);

	furiousRage = new FlxSprite(0, 0);
	furiousRage.loadGraphic(Paths.image(ext + "KILLYOURSELF"));
	furiousRage.setGraphicSize(Std.int(furiousRage.width * 0.9));
	furiousRage.cameras = [camOther];
	furiousRage.screenCenter(FlxAxes.X);
	furiousRage.visible = false;
	add(furiousRage);
	
	emergency = new FlxSprite(0, 350);
	emergency.loadGraphic(Paths.image(ext + "emergency"));
	emergency.setGraphicSize(Std.int(emergency.width * 0.7));
	emergency.cameras = [camOther];
	emergency.screenCenter(FlxAxes.X);
	emergency.visible = false;
	add(emergency);
	
	for (i in [bg, starsBG, starsFG, meeting, furiousRage, emergency, whoAngered])
	{
		i.antialiasing = ClientPrefs.globalAntialiasing;
	}
}

function onCreatePost()
{	
	game.isCameraOnForcedPos = true;
	game.snapCamToPos(1100, 1150);
}

function onUpdate(elapsed)
{
	if (starsFG.visible)
	{
		starsFG.x += elapsed * 45;
		starsBG.x += elapsed * 25;
		camZooming = false;
	}
}

function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case '':
			switch (value1)
			{
				case 'who buzz':
					var val2:Int = Std.parseInt(value2);
					if (Math.isNaN(val2)) val2 = 0;
					switch (val2)
					{
						case 0:
							camHUD.visible = false;
							meeting.visible = true;
							meeting.animation.play('buzz');
							meeting.animation.finishCallback = function(pog:String) {
								furiousRage.visible = true;
								emergency.visible = true;
							}
						case 1:
							whoend.visible = true;
							furiousRage.visible = false;
							emergency.visible = false;
							bg.visible = false;
							pet.visible = false;
							meeting.visible = false;
							boyfriendGroup.visible = false;
							dadGroup.visible = false;
							starsBG.visible = true;
							starsFG.visible = true;
							whoAngered.visible = true;
							FlxTween.angle(whoAngered, 0, 720, 10);
							FlxTween.tween(whoAngered, {x: 3000}, 10);
							defaultCamZoom = 0.5;
							FlxG.camera.zoom = 0.5;
							game.snapCamToPos(1100, 1150);
					}
			}
		case 'Cam lock in Who': // fuck it
			switch (value1)
			{
				case '':
					game.defaultCamZoom = FlxG.camera.zoom = 0.7;
					game.snapCamToPos(1100, 1150);
				case 'in':
					game.defaultCamZoom = FlxG.camera.zoom = 1.2;
					switch (value2)
					{
						case 'dad':
							game.snapCamToPos(762, 1264);
						case '':
							game.snapCamToPos(1528.5, 1264);
					}
			}
	}
}
