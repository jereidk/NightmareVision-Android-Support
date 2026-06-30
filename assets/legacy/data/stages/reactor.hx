var ext = 'stages/mira/reactor/';
var toogusorange:FlxSprite;
var toogusblue:FlxSprite;

var coreClaw:FunkinSprite;
var coreGlow:FunkinSprite;
var coreRing:FunkinSprite;

function onLoad()
{
	var bg0:FlxSprite = new FlxSprite(290, 0).loadGraphic(Paths.image(ext + 'wallbgthing'));
	bg0.scale.set(2, 2);
	bg0.updateHitbox();
	add(bg0);
	
	var bg:FlxSprite = new FlxSprite(0, 762).loadGraphic(Paths.image(ext + 'floornew'));
	add(bg);
	
	toogusorange = new FlxSprite(875, 890);
	toogusorange.frames = Paths.getSparrowAtlas(ext + 'yellowglita');
	toogusorange.animation.addByPrefix('bop', 'Pillars with crewmates instance 1', 24, false);
	toogusorange.animation.play('bop');
	toogusorange.setGraphicSize(Std.int(toogusorange.width * 1));
	add(toogusorange);
	
	var bg2:FlxSprite = new FlxSprite(408, 579).loadGraphic(Paths.image(ext + 'backbars'));
	add(bg2);
	
	toogusblue = new FlxSprite(450, 995);
	toogusblue.frames = Paths.getSparrowAtlas(ext + 'browngeoff');
	toogusblue.animation.addByPrefix('bop', 'Pillars with crewmates instance 1', 24, false);
	toogusblue.animation.play('bop');
	toogusblue.setGraphicSize(Std.int(toogusblue.width * 1));
	add(toogusblue);
	
	var bg3:FlxSprite = new FlxSprite(58, 546).loadGraphic(Paths.image(ext + 'frontpillars'));
	add(bg3);
	
	coreGlow = new FunkinSprite(1150, 60).loadAtlas('${ext}coreGlow');
	coreGlow.scale.set(2.7, 2.7);
	coreGlow.updateHitbox();
	add(coreGlow);
	
	if (ClientPrefs.flashing)
	{
		coreGlow.addAnimByPrefix('bop', 'reactor core', 24, false);
	}
	else
	{
		coreGlow.addAnimByIndices('bop', 'reactor core', [for (i in 25 ... 30) i], 24, false);
	}
	coreGlow.animation.play('bop');
	
	coreRing = new FunkinSprite(1295, 212).loadAtlas('${ext}coreRing');
	coreRing.addAnimByPrefix('ring', 'reactor core ring', 24, true);
	coreRing.animation.play('ring');
	coreRing.scale.set(1.35, 1.35);
	coreRing.blend = BlendMode.ADD;
	coreRing.updateHitbox();
	add(coreRing);
	coreClaw = new FunkinSprite(1222, 395).loadGraphic(Paths.image('${ext}coreClaw'));
	add(coreClaw);
	
	coreGlow.scrollFactor.set(.95, .95);
	coreRing.scrollFactor.set(.95, .95);
	coreClaw.scrollFactor.set(.98, 1.3);
}

function onCreatePost()
{
	var lightoverlay:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image(ext + 'frontblack'));
	lightoverlay.scale.set(4, 4);
	lightoverlay.updateHitbox();
	add(lightoverlay);
	
	var mainoverlay:FlxSprite = new FlxSprite(750, 100);
	mainoverlay.frames = Paths.getSparrowAtlas(ext + 'yeahman');
	mainoverlay.animation.addByPrefix('bop', 'Reactor Overlay Top instance 1', 24, true);
	mainoverlay.animation.play('bop');
	mainoverlay.blend = BlendMode.ADD;
	add(mainoverlay);
	
	if (ClientPrefs.shaders)
	{
		var blackRimlightBase:ExtraDropShadowShader = new funkin.game.shaders.ExtraDropShadowShader();
		
		blackRimlightBase.threshold = .05;
		blackRimlightBase.setColorMatrix([
			.8, -.1, .2, 0, -60,
			.04, .3, .05, 0, 6,
			.23, .45, .4, 0, -26,
			0, 0, 0, 1, 0
		]);
		blackRimlightBase.addLayer([
			1, .3, 0, 0, 125,
			.1, 1, 0, 0, 114,
			-.1, -.1, 1, 0, 80,
			0, 0, 0, 1, 0
		], 120, 20, .05);
		blackRimlightBase.addLayer(
			blackRimlightBase.addLayer([
				.8, .7, -.5, 0, 34,
				-.05, 0.68, 0, 0, 12,
				.2, .75, .61, 0, -25,
				0, 0, 0, 1, 0
			], 95, 38, .05)
		.colorMatrix, 140, 32, .05);
		
		if (hasBfSkin)
		{
			bfRim = blackRimlightBase;
			bfRim.attachedSprite = boyfriend;
			boyfriend.useRenderTexture = true;
		}
		
		if (hasGfSkin)
		{
			gfRim = new funkin.game.shaders.ExtraDropShadowShader().copyFrom(blackRimlightBase);
			gfRim.layers[0].angle = gfRim.layers[1].angle = gfRim.layers[2].angle = 90;
			gfRim.attachedSprite = gf;
			gf.useRenderTexture = true;
		}
		
		if (hasPet)
		{
			petRim = new funkin.game.shaders.ExtraDropShadowShader().copyFrom(blackRimlightBase);
			petRim.attachedSprite = pet;
			pet.useRenderTexture = true;
		}
	}
	
	else
	{
		if (hasBfSkin) boyfriend.color = 0xffe080a6;
		
		if (hasGfSkin) gf.color = 0xffe080a6;
		
		if (hasPet) pet.color = 0xffe080a6;
	}
}

function onBeatHit():Void
{
	if (curBeat % 2 == 0)
	{
		toogusorange.animation.play('bop', true);
		toogusblue.animation.play('bop', true);
		
		if (ClientPrefs.photosensitive || curBeat % 4 == 0) coreGlow.animation.play('bop', true);
	}
}

function onCountdownTick(tick:Int):Void
{
	if (tick % 2 == 0)
	{
		toogusorange.animation.play('bop', true);
		toogusblue.animation.play('bop', true);
	}
}
