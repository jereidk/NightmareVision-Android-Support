using StringTools;

var ROZEBUD_ILOVEROZEBUD_HEISAWESOME:FlxSprite; // this is the var name and you can't stop me -rzbd
var torfloor:FlxSprite;
var torwall:FlxSprite;
var torglasses:FlxSprite;
var windowlights:FlxSprite;
var leftblades:FlxSprite;
var rightblades:FlxSprite;
var montymole:FlxSprite;
var torlight:FlxSprite;
var startDark:FlxSprite;
var ziffyStart:FlxSprite;
var bladeDistance:Float = 120;
var ext = 'stages/misc/torture/';

function onLoad()
{	
	torfloor = new FlxSprite(-1376.3, 494.65).loadGraphic(Paths.image(ext + 'tort_floor'));
	torfloor.active = false;
	add(torfloor);
	
	torwall = new FlxSprite(-921.95, -850).loadGraphic(Paths.image(ext + 'torture_wall'));
	torwall.scrollFactor.set(0.8, 0.8);
	torwall.active = false;
	add(torwall);
	
	torglasses = new FlxSprite(551.8, 594.3).loadGraphic(Paths.image(ext + 'torture_glasses_preblended'));
	torglasses.scrollFactor.set(1.2, 1.2);
	torglasses.active = false;
	
	windowlights = new FlxSprite(-159.2, -605.95).loadGraphic(Paths.image(ext + 'windowlights'));
	windowlights.active = false;
	windowlights.alpha = 0.31;
	windowlights.blend = BlendMode.ADD;
	windowlights.zIndex = 3;
	
	leftblades = new FlxSprite(213.05, -670);
	leftblades.frames = Paths.getSparrowAtlas(ext + 'leftblades');
	leftblades.animation.addByPrefix('spin', 'blad', 24, false);
	leftblades.animation.play('spin');
	leftblades.scrollFactor.set(1.4, 1.4);
	leftblades.active = true;
	
	rightblades = new FlxSprite(827.75, -670);
	rightblades.frames = Paths.getSparrowAtlas(ext + 'rightblades');
	rightblades.animation.addByPrefix('spin', 'blad', 24, false);
	rightblades.animation.play('spin');
	rightblades.scrollFactor.set(1.4, 1.4);
	rightblades.active = true;
	
	ROZEBUD_ILOVEROZEBUD_HEISAWESOME = new FlxSprite(-390, -190);
	ROZEBUD_ILOVEROZEBUD_HEISAWESOME.frames = Paths.getSparrowAtlas(ext + 'torture_roze');
	ROZEBUD_ILOVEROZEBUD_HEISAWESOME.animation.addByPrefix('thing', '', 24, false);
	ROZEBUD_ILOVEROZEBUD_HEISAWESOME.antialiasing = true;
	ROZEBUD_ILOVEROZEBUD_HEISAWESOME.alpha = .001;
	add(ROZEBUD_ILOVEROZEBUD_HEISAWESOME);
}

function onCreatePost()
{
	camSpecialThing([640, 350], [640, 300]);
	
	camHUD.alpha = 0;
	
	add(torglasses);
	add(windowlights);
	add(leftblades);
	add(rightblades);
	
	montymole = new FlxSprite(14.05, 439.7);
	montymole.frames = Paths.getSparrowAtlas(ext + 'monty');
	montymole.animation.addByPrefix('idle', 'mole idle', 24, true);
	montymole.animation.play('idle');
	montymole.antialiasing = true;
	montymole.scrollFactor.set(1.6, 1.6);
	montymole.active = true;
	montymole.zIndex = 2;
	add(montymole);
	
	torlight = new FlxSprite(-410, -480.45).loadGraphic(Paths.image(ext + 'torture_glow2'));
	torlight.active = false;
	torlight.alpha = 0.25;
	torlight.blend = BlendMode.ADD;
	torlight.zIndex = 3;
	add(torlight);
	
	startDark = new flixel.system.FlxBGSprite();
	startDark.color = FlxColor.BLACK;
	startDark.zIndex = 5;
	add(startDark);
	
	ziffyStart = new FlxSprite();
	ziffyStart.frames = Paths.getSparrowAtlas(ext + 'ziffy');
	ziffyStart.animation.addByPrefix('idle', 'Opening', 24, false);
	ziffyStart.visible = false;
	ziffyStart.screenCenter();
	ziffyStart.scrollFactor.set(0, 0);
	ziffyStart.zIndex = 5;
	add(ziffyStart);
	
	skipCountdown = true;
	
	camGame.targetOffset.y = -100;
}

var notes = PlayState.SONG.notes;
function onUpdatePost(elapsed:Float)
{
	if (notes[curSection].mustHitSection)
	{
		if (game.camCurTarget == gf) game.camCurTarget = null;
	}
	else
	{
		var dadSings:Bool = (StringTools.startsWith(dad.getAnimName(), 'sing'));
		
		if (dadSings || StringTools.startsWith(gf.getAnimName(), 'sing'))
		{
			if (!dadSings) game.camCurTarget = gf;
			
			dadOff[0] = (dadSings ? 690 : 590);
		}
	}
	
	leftblades.x = (213.05 + bladeDistance) - (60 * health);
	rightblades.x = (827.75 - bladeDistance) + (60 * health);
}

function onMoveCamera(focus)
{
	defaultCamZoom = (focus == 'boyfriend' ? 1.2 : .9);
}

function onEvent(n, v1, v2)
{
	if (n == 'Legacy')
	{
		switch (v1)
		{
			case 'intro':
				ziffyStart.visible = true;
				ziffyStart.animation.play("idle", true);
				ziffyStart.screenCenter();
				ziffyStart.y -= 120;
				
			case 'why dont we begin':
				ziffyStart.visible = false;
				ziffyStart.destroy();
				
			case 'start':
				FlxTween.tween(startDark, {alpha: 0}, (Conductor.crotchet * 28) / 1000,
					{
						onComplete: function(t) {
							startDark.destroy();
						}
					});
				
				camGame.zoom = 2.1;
				FlxTween.tween(camGame, {zoom: 1.1}, 10, {ease: FlxEase.sineIn});
				FlxTween.tween(camGame.targetOffset, {y: 0}, 10, {ease: FlxEase.sineIn});
				
			case 'saw':
				FlxG.sound.play(Paths.sound('stage/ziffSaw'), 1);
				FlxTween.tween(leftblades, {y: leftblades.y + 300}, (Conductor.crotchet * 4) / 1000, {ease: FlxEase.quintOut});
				FlxTween.tween(rightblades, {y: rightblades.y + 300}, (Conductor.crotchet * 4) / 1000, {ease: FlxEase.quintOut});
				
				FlxTween.cancelTweensOf(camGame, ['zoom']);
				FlxTween.tween(camGame, {zoom: .9}, 1, {ease: FlxEase.sineOut});
				
			case 'rozebud':
				camZooming = false;
				
				ROZEBUD_ILOVEROZEBUD_HEISAWESOME.alpha = 1;
				ROZEBUD_ILOVEROZEBUD_HEISAWESOME.animation.play('thing');
				ROZEBUD_ILOVEROZEBUD_HEISAWESOME.animation.finishCallback = function(_) ROZEBUD_ILOVEROZEBUD_HEISAWESOME.kill();
				
				FlxTween.tween(camGame, {zoom: .7}, (Conductor.crotchet * 4) / 1000, {ease: FlxEase.quintOut});
				
			case 'bye':
				camZooming = true;
				
				FlxTween.num(bladeDistance, 150, (Conductor.crotchet * 4) / 1000, {ease: FlxEase.quartOut}, function(n) bladeDistance = n);
				FlxTween.tween(game, {health: .05}, (Conductor.crotchet * 4) / 1000, {ease: FlxEase.quartOut});
		}
	}
}

function opponentNoteHitPre(note)
{
	if (note.noteType == 'Opponent 2 Sing')
	{
		note.noAnimation = true;
	}
}

function opponentNoteHitPre(note)
{
	if (note.noteType == 'Opponent 2 Sing') note.owner = gf;
	else if (note.noteType == 'Both Opponents Sing') characterSing(gf, note);
}

function onBeatHit()
{
	leftblades.animation.play('spin', true);
	rightblades.animation.play('spin', true);
}
