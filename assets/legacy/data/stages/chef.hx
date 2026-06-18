import funkin.objects.stageobjects.AmongWalker;

var ext = 'stages/airship/chef/';
var chefBluelight:FlxSprite;
public var gray:FlxSprite;
var chefBlacklight:FlxSprite;
var saster:FlxSprite;
public var walker:AmongWalker;

function onLoad()
{
	var wall:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image(ext + 'Back Wall Kitchen'));
	wall.setGraphicSize(Std.int(wall.width * 0.8));
	add(wall);
	
	var floor:FlxSprite = new FlxSprite(-850, 1000).loadGraphic(Paths.image(ext + 'Chef Floor'));
	add(floor);
	
	var backshit:FlxSprite = new FlxSprite(-50, 170).loadGraphic(Paths.image(ext + 'Back Table Kitchen'));
	backshit.setGraphicSize(Std.int(backshit.width * 0.8));
	add(backshit);
	
	var oven:FlxSprite = new FlxSprite(1600, 400).loadGraphic(Paths.image(ext + 'oven'));
	oven.setGraphicSize(Std.int(oven.width * 0.8));
	add(oven);
	
	gray = new FlxSprite(1000, 525);
	gray.frames = Paths.getSparrowAtlas(ext + 'Boppers');
	gray.animation.addByPrefix('bop', 'grey', 24, false);
	gray.animation.play('bop');
	gray.setGraphicSize(Std.int(gray.width * 0.8));
	add(gray);
	
	saster = new FlxSprite(1300, 525);
	saster.frames = Paths.getSparrowAtlas(ext + 'Boppers');
	saster.animation.addByPrefix('bop', 'saster', 24, false);
	saster.animation.play('bop');
	saster.setGraphicSize(Std.int(saster.width * 1.2));
	add(saster);

	walker = new AmongWalker([0, 2500], 1080, 0.7, null);
	walker.x = (FlxG.random.bool(50) ? walker.xRange[0] + 50 : walker.xRange[1] - 50);
	walker.setCustom('tomato', ext + 'tomatungus');
	walker.addOffset('idle', 0, 0);
	walker.addOffset('walk', 0, 60);
	
	walker.onAction.add(function() walker.walkSpeed = FlxG.random.float(18, 21));
	walker.hibernating = true;
	walker.visible = true;
	stage.add(walker);

	var frontable:FlxSprite = new FlxSprite(800, 700).loadGraphic(Paths.image(ext + 'Kitchen Counter'));
	add(frontable);
	
	chefBluelight = new FlxSprite(0, -300).loadGraphic(Paths.image(ext + 'bluelight'));
	chefBluelight.blend = BlendMode.ADD;
	
	chefBlacklight = new FlxSprite(0, -300).loadGraphic(Paths.image(ext + 'black_overhead_shadow'));
	chefBlacklight.antialiasing = true;
	chefBlacklight.scrollFactor.set(1, 1);
	chefBlacklight.active = false;
}

function onSongStart()
{
	if (ClientPrefs.pet == 'minicrewmate') game.unlockAchievementPopup('im_hungry');
}

function onBeatHit()
{
	if (curBeat % 2 == 0)
	{
		gray.animation.play('bop');
		saster.animation.play('bop');
	}
	if (walker != null)
		walker.onBeatHit(curBeat);
}

function onStartCountdown()
{
	var fakeStartTimer = new FlxTimer().start((Conductor.crotchet / 1000) / playbackRate, function(tmr:FlxTimer) {
		if (tmr.loopsLeft % 2 == 0)
		{
			gray.animation.play('bop');
			saster.animation.play('bop');
		}
	}, 5);
}
function onUpdate(elapsed)
{
	if (walker.x > 2500) walker.right = false;
	if (walker.x < 500) walker.right = true;
}
function onCreatePost()
{
	snapCamToPos(1150, 800);
	camSpecialThing([1200, 800], [1400, 800]);
	add(chefBluelight);
	add(chefBlacklight);
}
