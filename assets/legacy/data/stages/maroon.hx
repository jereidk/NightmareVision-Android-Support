import funkin.objects.SnowEmitter;

var snowAlpha = 0.8;
var snowEmitter:SnowEmitter;
var ext:String = 'stages/polus/maroon/'; // Edit polus to your stage name.

function onLoad()
{
	var bg:FlxSprite = new FlxSprite(-200).loadGraphic(Paths.image(ext + "newsky"));
	bg.scrollFactor.x = 0.7;
	bg.scale.set(0.75, 0.75);	

	var cloud:FlxSprite = new FlxSprite(-100).loadGraphic(Paths.image(ext + "newcloud"));
	cloud.scrollFactor.x = 0.9;
	cloud.alpha = 0.9;

	var rocks:FlxSprite = new FlxSprite().loadGraphic(Paths.image(ext + "newrocks"));
	rocks.alpha = 0.49;

	var backwall:FlxSprite = new FlxSprite().loadGraphic(Paths.image(ext + "backwall"));
	backwall.scrollFactor.x = 0.9;
	var ground:FlxSprite = new FlxSprite().loadGraphic(Paths.image(ext + "newstage"));
	
	snowEmitter = new SnowEmitter(1000, 800, 2700);
	snowEmitter.start(false, ClientPrefs.lowQuality ? 0.1 : 0.04);
	snowEmitter.scrollFactor.x.set(1, 1.5);
	snowEmitter.scrollFactor.y.set(1, 1.5);
	add(snowEmitter);
	snowEmitter.alpha.active = false;
	snowEmitter.onEmit.add((particle) -> particle.alpha = snowAlpha);
	snowEmitter.zIndex = 13;
	snowEmitter.speed.set(1000, 1500);
	
	var lava:FlxSprite = new FlxSprite().loadGraphic(Paths.image(ext + "newlava"));
	lava.blend = BlendMode.ADD;
	
	for (i in [bg, cloud, rocks, backwall, ground, lava])
	{
		i.scale.set(0.75, 0.75);
		add(i);
	}
}

function goodNoteHit(note)
{
	if (note.noteType == 'Hey!')
	{
		game.boyfriend.playAnim('hey', true);
		game.boyfriend.specialAnim = true;
	}
}

function onCreatePost()
{
	camSpecialThing([1600, 1300], [1800, 1300]);
	var mainoverlay:FlxSprite = new FlxSprite(0, 0);
	mainoverlay.loadGraphic(Paths.image(ext + "newoverlay"));
	mainoverlay.scrollFactor.set(1, 1);
	mainoverlay.scale.set(0.75, 0.75);
	mainoverlay.alpha = 0.44;
	mainoverlay.blend = 0;
	if(!ClientPrefs.lowQuality) add(mainoverlay);
}
