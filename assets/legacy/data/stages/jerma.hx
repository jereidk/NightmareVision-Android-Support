var ext = 'stages/freeplay/jerma/';

function onLoad()
{
	var bg:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image(ext + "jerma"));
	add(bg);
	var vig:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image(ext + "vignette"));
	add(vig);
	vig.cameras = [camOther];
}

function onCreatePost()
{
	jermscare = new FlxSprite(600, 200);
	jermscare.frames = Paths.getSparrowAtlas(ext + 'jermaSCARY');
	jermscare.animation.addByPrefix('bop', 'sussyjerma', 24, false);
	jermscare.visible = false;
	jermscare.scale.set(2.5, 2.5);
	add(jermscare);

	snapCamToPos(800, 450);
	camSpecialThing([900, 450], [1000, 625]);
}


function onStepHit() {
	switch (curStep)
	{
		case 998:
		jermscare.visible = true;
		jermscare.animation.play('bop');
		case 1024:
		jermscare.kill();
	}
}