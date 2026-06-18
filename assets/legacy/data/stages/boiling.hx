import flixel.FlxSprite;
import flixel.effects.particles.FlxEmitterMode;

import funkin.game.shaders.DropShadowShader;
import funkin.objects.SnowEmitter;

var snowAlpha = 0.3;
var snowEmitter:SnowEmitter;
var emberEmitter:FlxEmitter;
var ext = 'stages/polus/maroon/boiling/';
var lavaOverlay:FlxSprite;
var lava:FlxSprite;
var ground:FlxSprite;

function onLoad()
{
	lava = new FlxSprite(270, -330);
	lava.frames = Paths.getSparrowAtlas(ext + 'wallBP');
	lava.animation.addByPrefix('bop', 'Back wall and lava', 24, true);
	if (!ClientPrefs.lowQuality) lava.animation.play('bop');
	lava.scrollFactor.set(0.8, 0.8);
	add(lava);
	
	FlxTween.tween(lava, {y: -500}, 200);
	
	ground = new FlxSprite(1050, 650).loadGraphic(Paths.image(ext + 'platform'));
	add(ground);
	
	var bubbles = new FlxSprite(800, 850);
	bubbles.frames = Paths.getSparrowAtlas(ext + 'bubbles');
	bubbles.animation.addByPrefix('bop', 'Lava Bubbles', 24, true);
	bubbles.animation.play('bop');
	add(bubbles);
	emberEmitter = new FlxEmitter(-1200, 1000);
	
	for (i in 0...150)
	{
		var p = new FlxParticle();
		p.frames = Paths.getSparrowAtlas(ext + 'ember');
		p.animation.addByPrefix('ember', 'ember', 24, true);
		p.animation.play('ember');
		p.exists = false;
		p.animation.curAnim.curFrame = FlxG.random.int(0, 9);
		p.blend = BlendMode.ADD;
		emberEmitter.add(p);
	}
	emberEmitter.launchMode = FlxEmitterMode.SQUARE;
	emberEmitter.velocity.set(-50, -400, 50, -800, -100, 0, 100, -800);
	emberEmitter.scale.set(1, 1, 0.8, 0.8, 0, 0, 0, 0);
	emberEmitter.drag.set(0, 0, 0, 0, 5, 5, 10, 10);
	emberEmitter.width = 4200.45;
	emberEmitter.alpha.set(1, 1);
	emberEmitter.lifespan.set(4, 4.5);
	// heartEmitter.loadParticles(Paths.image('mira/littleheart', 'impostor'), 500, 16, true);
	
	snowEmitter = new SnowEmitter(900, -800, 2700);
	snowEmitter.start(false, ClientPrefs.lowQuality ? 0.5 : 0.5);
	snowEmitter.scrollFactor.x.set(1, 1.5);
	snowEmitter.scrollFactor.y.set(1, 1.5);
	add(snowEmitter);
	snowEmitter.alpha.active = false;
	snowEmitter.onEmit.add((particle) -> particle.alpha = snowAlpha);
	snowEmitter.zIndex = 13;
	
	redscreen = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFFF24400);
	redscreen.scrollFactor.set();
	redscreen.alpha = 0.001;
	redscreen.cameras = [camHUD];
	add(redscreen);
	
	emberEmitter.start(false, FlxG.random.float(0.3, 0.4), 100000);
}

function onCreatePost()
{
	camSpecialThing([1760, 300], [1900, 400]);

	lavaOverlay = new FlxSprite(1000, -50).loadGraphic(Paths.image(ext + 'overlaythjing'));
	lavaOverlay.scale.set(1.5, 1.5);
	lavaOverlay.blend = BlendMode.ADD;
	lavaOverlay.alpha = 0.7;
	
	add(lavaOverlay);
	if (!ClientPrefs.lowQuality) add(emberEmitter);
	
	if (hasBfSkin && game.boyfriend.curCharacter == 'bfpolus')
	{
		triggerEventNote('Change Character', 'dad', 'maroonplayableoplava');
		game.dad.x = 1050;
		game.dad.y = 330;
		triggerEventNote('Change Character', 'boyfriend', 'bf-lava');
		camSpecialThing([1760, 400], [1900, 400]);
	}
	if (game.boyfriend.curCharacter == 'maroonplayable')
	{
		triggerEventNote('Change Character', 'boyfriend', 'maroonplayablelava');
	}
	
	pet.zIndex = 0;
	lavaOverlay.zIndex = 2;
	emberEmitter.zIndex = 2;
	snowEmitter.zIndex = 2;
	redscreen.zIndex = 3;
	
	if (ClientPrefs.shaders)
	{
		var blackRimlightBase:ExtraDropShadowShader = new funkin.game.shaders.ExtraDropShadowShader();
		
		blackRimlightBase.setColorMatrix([
			0.8,   0,   0, 0, 16,
			-.1, 0.6, -.1, 0,  0,
			  0,   0, 0.6, 0,  8,
			  0,   0,   0, 1,  0
		]);
		blackRimlightBase.addLayer([
			1.5, -.1, .2, 0, 64,
			-.3, 1.2,  0, 0, 32,
			  0,   0,  1, 0,  0,
			  0,   0,  0, 1,  0
		], 330, 25, .01);
		
		if (hasBfSkin && boyfriend.curCharacter != 'bf-lava' && boyfriend.curCharacter != 'maroonplayablelava')
		{
			bfRim = blackRimlightBase;
			bfRim.attachedSprite = boyfriend;
			boyfriend.useRenderTexture = (boyfriend.curCharacter == 'bf-ghost');
		}
		if (hasPet)
		{
			petRim = new funkin.game.shaders.ExtraDropShadowShader().copyFrom(blackRimlightBase);
			petRim.layers[0].angle = 50;
			petRim.layers[1].angle = 50;
			petRim.attachedSprite = pet;
			pet.useRenderTexture = false;
		}
	}
}

function onEvent(n, v1, v2)
{
	switch (n)
	{
		case 'Legacy':
			switch (v1)
			{
				case 'byebye':
					// FlxTween.tween(game.boyfriend, {y: 1500}, 2, {ease: FlxEase.expoInOut});
					// FlxTween.tween(game.dad, {y: 1200}, 2, {ease: FlxEase.expoInOut});
					// FlxTween.tween(ground, {y: 1500}, 2, {ease: FlxEase.expoInOut});
					// FlxTween.tween(pet, {y: 1500}, 2, {ease: FlxEase.expoInOut});
					// FlxTween.cancelTweensOf(lava);
					// FlxTween.tween(lava, {y: -550}, 4, {ease: FlxEase.expoInOut});
					camSpecialThing(null, [1900, 300], 0.8);
					triggerEventNote('setChrom', '-5', '2');
					FlxTween.tween(redscreen, {alpha: 1}, 2, {ease: FlxEase.expoInOut});
			}
	}
}
