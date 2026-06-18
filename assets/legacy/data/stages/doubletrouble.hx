import funkin.game.shaders.ExtraDropShadowShader;
import funkin.utils.ProgressionUtil;

import openfl.filters.ShaderFilter;

import StringTools;

var ext = 'stages/mira/reactorRuined/';

var overlayShader:OverlayShader;

var greenShader:ExtraDropShadowShader = new ExtraDropShadowShader();
var bfShader:ExtraDropShadowShader = new ExtraDropShadowShader();
var gfShader:ExtraDropShadowShader = new ExtraDropShadowShader();
var petShader:ExtraDropShadowShader = new ExtraDropShadowShader();
var drops:Array<ExtraDropShadowShader> = [greenShader, bfShader, gfShader, petShader];

var thunderGroup:FlxSpriteGroup;

var toogusorange:FlxSprite;
var toogusblue:FlxSprite;
var tooguswhite:FlxSprite;
var red:Character;
var redElement:FlxSpriteElement;
var introFade:FlxSprite;
var wall:FlxSprite;
var glow:FlxSprite;
var mist:FlxBackdrop;
var mist2:FlxBackdrop;
var mist3:FlxBackdrop;
var mist4:FlxBackdrop;
var mist5:FlxBackdrop;
var mist6:FlxBackdrop; // cutscene mists
var mist7:FlxBackdrop;
var shine:FlxSprite;
var rainIntensity:Float = .1;
var heartRad:Float = 0;
var rainShader; // ty base game

var lightningDarken:Array<FlxSprite>;
var lightningLighten:Array<FlxSprite>;

var bfIntro:FunkinSprite;

public var nextThunder:Int = 4;
public var canThunder:Bool = true;

function onLoad()
{
	for (i in 1 ... 5) Paths.image('${ext}thunder$i');
	for (i in 1 ... 4) Paths.sound('stage/dtThunder$i');
	
	var sky:FlxSprite = new FlxSprite(-300, -900, Paths.image(ext + 'nightSky'));
	sky.antialiasing = true;
	sky.scrollFactor.set(.2, .2);
	sky.scale.set(5, 5);
	sky.updateHitbox();
	sky.active = false;
	add(sky);
	
	var stars:FlxSprite = new FlxSprite(-200, -200, Paths.image(ext + 'stars'));
	stars.scrollFactor.set(.03, .1);
	stars.active = false;
	add(stars);
	
	var clouds:FlxSprite = new FlxSprite(-750, -200, Paths.image(ext + 'clouds'));
	clouds.angle = -15;
	clouds.angularVelocity = .1;
	clouds.origin.set(clouds.width * .65, clouds.height + 1920);
	clouds.scrollFactor.set(.3, .3);
	add(clouds);
	
	thunderGroup = new FlxSpriteGroup();
	add(thunderGroup);
	
	glow = new FlxSprite(-200, -400, Paths.image('${ext}thunderGlow'));
	glow.blend = BlendMode.ADD;
	glow.scrollFactor.set(.05, .1);
	glow.scale.set(10, 12);
	glow.updateHitbox();
	add(glow);
	
	wall = new FlxSprite(-320, -520, Paths.image(ext + 'wall'));
	wall.scrollFactor.set(.9, .9);
	wall.active = false;
	add(wall);
	
	var floor:FlxSprite = new FlxSprite(-140, 750, Paths.image(ext + 'floor'));
	floor.active = false;
	add(floor);
	
	var blood:FlxSprite = new FlxSprite(640, 1280, Paths.image(ext + 'blood'));
	blood.blend = BlendMode.MULTIPLY;
	blood.active = false;
	add(blood);
	
	var pillars:FlxSprite = new FlxSprite(-120, 610, Paths.image(ext + 'pillars'));
	pillars.active = false;
	add(pillars);
	
	var bodies:FlxSprite = new FlxSprite(50, 1140, Paths.image(ext + 'bodies'));
	bodies.active = false;
	add(bodies);
	
	mist6 = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist6.scrollFactor.set(1.3, 1.3);
	mist6.velocity.set(40, 10);
	mist6.blend = BlendMode.ADD;
	mist6.setPosition(300, 700);
	mist6.scale.set(1.2, 1.2);
	mist6.updateHitbox();
	mist6.alpha = .9;
	
	mist7 = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist7.scrollFactor.set(1.3, 1.3);
	mist7.velocity.set(30, 40);
	mist7.blend = BlendMode.ADD;
	mist7.setPosition(300, 700);
	mist7.scale.set(1.8, 1.8);
	mist7.updateHitbox();
	mist7.alpha = .7;
	
	mist6.color = mist7.color = FlxColor.fromRGB(160, 110, 255);
	
	bfIntro = new FunkinSprite(2100, 1080).loadAtlas(ext + 'bfIntro', {cacheOnLoad: true, swfMode: true});
	bfIntro.addAnimByPrefix('intro', 'intro', 24, false);
	bfIntro.playAnim('intro');
	
	if (PlayState.startOnTime <= 0 && !PlayState.seenCutscene) checkIntro();
	
	var moon:FlxSprite = new FlxSprite(0, 0, Paths.image(ext + 'moon'));
	moon.scale.set(.4, .4);
	moon.updateHitbox();
	moon.screenCenter();
	moon.x += 1000;
	moon.y -= 900;
	moon.alpha = .25;
	moon.active = false;
	add(moon);
	
	shine = new FlxSprite(0, 0, Paths.image(ext + 'shine'));
	shine.scale.set(.4, .4);
	shine.updateHitbox();
	shine.screenCenter();
	shine.blend = BlendMode.ADD;
	shine.angularVelocity = 90;
	shine.x += 1020;
	shine.y -= 930;
	shine.alpha = .001;
	add(shine);
	
	wall.setColorTransform(1, 1, 1, 1, -18, -16, -12);
	
	lightningDarken = [boyfriendGroup, dadGroup, gfGroup, pet, bodies, bfIntro];
	lightningLighten = [wall, floor, pillars, blood, sky];
	
	new FlxTimer().start(2.6, thunder);
	
	FlxTween.tween(mist6, {alpha: 0}, 18, {onComplete: function(_) mist6.kill()});
	FlxTween.tween(mist7, {alpha: 0}, 24, {onComplete: function(_) mist7.kill()});
}

function thunder():Void // MAKE IT CLAP YES !!!
{
	nextThunder = -1;
	
	var thunder:FlxSprite = thunderGroup.recycle(FlxSprite);
	thunder.scrollFactor.set(.05, .05);
	thunder.loadGraphic(Paths.image('${ext}thunder${FlxG.random.int(1, 4)}'));
	thunder.flipX = FlxG.random.bool(50);
	thunder.x = FlxG.random.float(-1500, 1000);
	thunder.y = -700;
	
	thunder.alpha = 0;
	thunder.blend = BlendMode.ADD;
	FlxTween.tween(thunder, {alpha: FlxG.random.float(.5, 1)}, .1, {ease: FlxEase.sineIn, onComplete: function(_) {
		FlxTween.tween(thunder, {alpha: 0}, FlxG.random.float(1.5, 2.2), {ease: FlxEase.sineIn, onComplete: function(_) thunder.kill()});
	}});
	
	new FlxTimer().start(FlxG.random.float(.1, 2), function(_) FlxG.sound.play(Paths.sound('stage/dtThunder${FlxG.random.int(1, 3)}'), FlxG.random.float(.7, 1)));
	
	FlxTween.num(FlxG.random.float(.5, .7), .4, .5, {ease: FlxEase.elasticInOut, onComplete: function(_) {
		FlxTween.num(.4, 0, FlxG.random.float(.7, 1.2), {ease: FlxEase.sineIn, onComplete: function() setNextThunder()}, lightningStuff);
	}}, lightningStuff);
}

function lightningStuff(intensity:Float):Void
{
	var c:FlxColor = FlxColor.interpolate(FlxColor.WHITE, FlxColor.BLACK, (1 - Math.pow(1 - intensity, 2)) * .8);
	for (sprite in lightningDarken)
	{
		if (sprite == null || !sprite.exists) continue;
		
		sprite.color = c;
	}
	
	var m:Float = (1 + intensity * 1.25);
	for (sprite in lightningLighten)
	{
		final ct = sprite.colorTransform;
		
		ct.redMultiplier = ct.greenMultiplier = ct.blueMultiplier = m;
	}
	
	for (drop in drops)
	{
		drop.layers[0].threshold = Math.pow(1 - intensity, 3);
	}
	
	glow.alpha = intensity;
}

function setNextThunder():Void
{
	nextThunder = (Math.ceil((curBeat + FlxG.random.int(4, 32)) / 2) * 2);
}

function checkIntro():Void
{
	if (ProgressionUtil.songIsClear('double-trouble') && (ClientPrefs.bfSkin != 'default' || ClientPrefs.gfSkin != 'default')) return;
	
	allowBFSkin = allowGFSkin = false;
	
	songStartCallback = intro;
}

function intro():Void
{
	PlayState.seenCutscene = true;
	
	inCutscene = true;
	camHUD.alpha = .0001;
	
	snapCamToPos(2350, 1320);
	camGame.zoom = 1.3;
	
	var introSound:FlxSound = FlxG.sound.load(Paths.sound('stage/dtIntro'));
	
	gf.playAnim('intro', true);
	bfIntro.playAnim('intro', true);
	
	FlxG.camera.followLerp = (1 / 20);
	
	new FlxTimer().start(.5, function(_) {
		FlxTween.tween(camGame, {zoom: .7}, 15, {ease: FlxEase.sineInOut});
	});
	
	FlxTween.tween(camFollow, {x: 2370, y: 1300}, 5.3, {ease: FlxEase.quadOut});
	new FlxTimer().start(5.3, function(_) {
		FlxTween.tween(camFollow, {x: 2400, y: 1200}, 7, {ease: FlxEase.sineInOut});
	});
	
	new FlxTimer().start(12, function(_) {
		inCutscene = false;
		startCountdown();
		
		triggerEventNote('camTween', '1100,1000,0.62', '6,smootherstepout');
		
		FlxTween.tween(camHUD, {alpha: 1}, 2, {ease: FlxEase.sineInOut});
		
		new FlxTimer().start(5, function(_) {
			bfShader.attachedSprite = boyfriend;
			remove(bfIntro, true);
			bfIntro.destroy();
			boyfriend.revive();
		});
	});
	
	new FlxTimer().start(1 / 30, function(_) introSound.play());
}

function onMoveCamera(who:String):Void
{
	defaultCamZoom = (who == 'dad' ? .5 : .7);
}

function onCreatePost()
{
	boyfriend.useRenderTexture = gf.useRenderTexture = dad.useRenderTexture = pet.useRenderTexture = bfIntro.useRenderTexture = true;
	
	if (inCutscene)
	{
		boyfriend.kill();
		stage.insert(stage.members.indexOf(boyfriendGroup) - 1, bfIntro);
		bfShader.attachedSprite = bfIntro;
	}
	else
	{
		bfIntro.destroy();
		bfShader.attachedSprite = boyfriend;
	}
	
	var core:FlxSprite = new FlxSprite(500, 1560, Paths.image(ext + 'core')); // well wats left of it anyway
	core.scrollFactor.set(1.3, 1.3);
	core.active = false;
	add(core);
	
	mist = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist.scrollFactor.set(1.2, 1.2);
	mist.velocity.x = 60;
	mist.blend = BlendMode.ADD;
	mist.alpha = .3;
	mist.y = 200;
	mist.color = 0xFF000000;
	add(mist);
	
	mist2 = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist2.scrollFactor.set(1.3, 1.3);
	mist2.velocity.x = 110;
	mist2.blend = BlendMode.ADD;
	mist2.setPosition(300, -200);
	mist2.scale.set(1.2, 1.2);
	mist2.updateHitbox();
	mist2.alpha = .2;
	add(mist2);
	
	mist3 = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist3.scrollFactor.set(1.3, 1.3);
	mist3.velocity.x = 50;
	mist3.blend = BlendMode.ADD;
	mist3.setPosition(300, -200);
	mist3.scale.set(1.2, 1.2);
	mist3.updateHitbox();
	mist3.alpha = .15;
	add(mist3);
	
	mist4 = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist4.scrollFactor.set(1.4, 1.4);
	mist4.velocity.x = 150;
	mist4.blend = BlendMode.ADD;
	mist4.setPosition(300, -200);
	mist4.scale.set(1.2, 1.2);
	mist4.updateHitbox();
	mist4.alpha = .1;
	add(mist4);
	
	mist5 = new FlxBackdrop(Paths.image(ext + 'mist'), 0x01);
	mist5.scrollFactor.set(1.3, 1.3);
	mist5.velocity.x = 20;
	mist5.blend = BlendMode.ADD;
	mist5.setPosition(300, -200);
	mist5.scale.set(1.2, 1.2);
	mist5.updateHitbox();
	mist5.alpha = .05;
	add(mist5);
	
	add(mist6);
	add(mist7);
	
	bfShader.setAdjustColor(-78, -25, -15, -58);
	bfShader.addLayer([
		.8, 0, 0, 0, 0,
		0, 1, 0, 0, 0,
		.3, 0, 1, 0, 0,
		0, 0, 0, 1, 0
	], 90, 35, .01, 1, .5);
	
	greenShader.copyFrom(petShader.copyFrom(gfShader.copyFrom(bfShader)));
	greenShader.setAdjustColor(-28, -22, -10, -60);
	
	bfShader.layers[0].angle = 110;
	greenShader.layers[0].angle = 70;
	
	camSpecialThing([1300, 900], [2000, 1100]);
	// camGame.zoom = 1;
	isCameraOnForcedPos = true;
	
	introFade = new flixel.system.FlxBGSprite();
	introFade.color = FlxColor.BLACK;
	introFade.camera = camOther;
	add(introFade);
	
	FlxTween.tween(introFade, {alpha: 0}, 2);
	
	red = new Character(-420, -390, 'doubleTroubleRed');
	red.danceEveryNumBeats = 2;
	red.origin.set();
	red.animation.onFrameChange.add(function(_, _, _) dad._renderTextureDirty = true);
	
	var lightoverlay:FlxSprite = new FlxSprite(1850, 1100).loadGraphic(Paths.image(ext + 'light'));
	lightoverlay.antialiasing = true;
	lightoverlay.scale.set(6, 6);
	lightoverlay.updateHitbox();
	lightoverlay.blend = BlendMode.ADD;
	lightoverlay.scrollFactor.set(1.2, 1.2);
	lightoverlay.active = false;
	add(lightoverlay);
	
	var lightoverlay2:FlxSprite = new FlxSprite(2250,  1100).loadGraphic(Paths.image(ext + 'light'));
	lightoverlay2.antialiasing = true;
	lightoverlay2.scale.set(6, 6);
	lightoverlay2.updateHitbox();
	lightoverlay2.blend = BlendMode.ADD;
	lightoverlay2.scrollFactor.set(1.2, 1.2);
	lightoverlay2.active = false;
	add(lightoverlay2);
	
	FlxTween.tween(lightoverlay, {alpha: .25}, .5, {type: 4, ease: FlxEase.sineInOut});
	FlxTween.tween(lightoverlay2, {alpha: .25}, .5, {startDelay: .5, type: 4, ease: FlxEase.sineInOut});
	
	redElement = new animate.internal.elements.FlxSpriteElement(red);
	redElement.active = false;
	
	if (dad.library != null)
	{
		var placeholder = dad.library.getSymbol('red placeholder');
		
		if (placeholder != null)
			placeholder.timeline.layers[0].forEachFrame((frame) -> {
				for (i in frame.elements)
					i.visible = false;
					
				frame.add(redElement);
			});
	}
	
	// overlayShader = new funkin.game.shaders.OverlayShader();
	// overlayShader.setBitmapOverlay(Paths.image(ext + 'overlay').bitmap);
	
	rainShader = newShader('rain');
	if (rainShader != null)
	{
		rainShader.setFloatArray('uScreenResolution', [FlxG.width, FlxG.height]);
		rainShader.setFloat('uTime', 0);
		rainShader.setFloat('uScale', FlxG.height / 200);
		rainShader.setFloat('uIntensity', rainIntensity);
	}
	
	camGame.filters = [new ShaderFilter(rainShader) /*, new ShaderFilter(overlayShader)*/];
	
	gfShader.attachedSprite = gf;
	petShader.attachedSprite = pet;
	greenShader.attachedSprite = dad;
	
	lightningStuff(0);
}

function onGameOverStart()
{
	camGame.filters.resize(0);
}

var redSnap:Bool = false;
function onEvent(eventName, value1, value2)
{
	if (value1 == 'red')
	{
		isCameraOnForcedPos = true;
		FlxG.camera.zoom = defaultCamZoom = 1;
		snapCamToPos(900, 725);
	}
	if (value1 == 'green')
	{
		isCameraOnForcedPos = true;
		snapCamToPos(1000, 950);
		FlxG.camera.zoom = defaultCamZoom = 0.6;
	}
	if (value1 == 'bf')
	{
		isCameraOnForcedPos = true;
		snapCamToPos(2250, 1200);
		FlxG.camera.zoom = defaultCamZoom = 0.9;
	}
	if (value1 == 'all')
	{
		isCameraOnForcedPos = true;
		snapCamToPos(1650, 925);
		FlxG.camera.zoom = defaultCamZoom = 0.45;
	}
	
	if (eventName == 'Legacy')
	{
		if (value1 == 'Red Snap')
		{
			red.playAnim('snap', true);
			red.idleSuffix = '-mad';
			red.specialAnim = true;
			redSnap = true;
		}
		else if (value1 == 'Shiny')
		{
			FlxTween.tween(shine, {alpha: 1}, .3, {ease: FlxEase.sineIn});
			new FlxTimer().start(.3, function(_) FlxTween.tween(shine, {alpha: 0}, 1.5, {ease: FlxEase.sineOut}));
		}
		else if (value1 == 'Goodbye')
		{
			FlxTween.tween(camGame, {alpha: 0}, 2);
			FlxTween.tween(camHUD, {alpha: 0}, 2);
			canThunder = false;
		}
	}
}

function onUpdate(elapsed:Float):Void
{
	red.update(elapsed);
}

function onDestroy():Void
{
	red.destroy();
}

function onUpdatePost(elapsed:Float):Void
{
	if (rainShader != null)
	{
		heartRad += elapsed;
		rainShader.setFloatArray('uCameraBounds',
			[game.camGame.scroll.x + game.camGame.viewMarginX, game.camGame.scroll.y + game.camGame.viewMarginY, game.camGame.scroll.x
				+ game.camGame.viewMarginX
				+ game.camGame.width, game.camGame.scroll.y
				+ game.camGame.viewMarginY
				+ game.camGame.height]);
		rainShader.setFloat('uTime', heartRad);
		rainShader.setFloat('uIntensity', rainIntensity);
	}
}

function opponentNoteHitPre(note)
{
	var greenSing:Bool = (note.noteType == 'Opponent 2 Sing');
	
	if (note.noteType == 'Both Opponents Sing')
	{
		if (redSnap) note.animSuffix = '-mad'; // im jsut so tired
		characterSing(red, note);
		if (redSnap) note.animSuffix = '';
	}
	else if (!greenSing)
	{
		if (redSnap) note.animSuffix = '-mad';
		note.owner = red;
	}
	else
	{
		if (!note.isSustainNote && (!StringTools.startsWith(red.animation.name, 'sing') || red.holdTimer >= Conductor.stepCrotchet / 1500))
		{
			red.playAnim(note.skin.singAnimations[note.noteData] + '-balance');
			red.holdTimer = 0;
		}
	}
}

function onBeatHit()
{
	red.onBeatHit(curBeat);
	
	if (canThunder && nextThunder >= 0 && curBeat >= nextThunder) thunder();
}

function onCountdownTick()
{
	red.onBeatHit(curBeat);
}
