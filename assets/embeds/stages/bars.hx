import flixel.addons.effects.FlxSkewedSprite;

import openfl.filters.ShaderFilter;

var fg:BGSprite;
var fg2:BGSprite;
var grid:FlxSkewedSprite;
var gridUnder:FlxSkewedSprite;
var gridShader;
var gridUnderShader;
var vhsShader;
var vhsFrame:Int = 0;
var fgBaseY:Float = 0;
var fg2BaseY:Float = 0;
var dadBaseY:Float = 0;
var bfBaseY:Float = 0;
var waveTime:Float = 0;
var gridScrollY:Float = 0;
var dankBlack:FlxSprite;

function showdankBlack():Void
{
	if (dankBlack == null)
	{
		dankBlack = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		dankBlack.setGraphicSize(FlxG.width, FlxG.height);
		dankBlack.updateHitbox();
		dankBlack.scrollFactor.set();
		dankBlack.camera = camOther;
		add(dankBlack);
	}
	else
	{
		dankBlack.revive();
		dankBlack.visible = true;
	}
	
	dankBlack.alpha = 1;
}

function onLoad()
{
	game.countdownSounds = false;
	
	FlxG.camera.pixelPerfectRender = true;
	
	gridShader = newShader('gridperspective');
	gridUnderShader = newShader('gridperspective');
	
	var grahdient = new BGSprite('bars/grahdient', -5000, 0, 0, 0);
	grahdient.antialiasing = false;
	grahdient.setGraphicSize(1280, 720);
	grahdient.scale.x *= 2;
	grahdient.setPosition(-500, 0);
	grahdient.scrollFactor.set(0, 0);
	grahdient.updateHitbox();
	add(grahdient);
	
	add(grid = new FlxSkewedSprite(0, -1000, Paths.image('bars/gridBars')));
	grid.alpha = 0.3;
	grid.antialiasing = false;
	grid.origin.set(grid.frameWidth * 0.5, 0);
	grid.scale.set(2.8, 1.7);
	grid.scrollFactor.set(0.1, 0.1);
	grid.screenCenter(FlxAxes.X);
	grid.y -= 450;
	grid.x -= 1700;
	
	gridShader.setFloat('uTopWidth', 1.9);
	gridShader.setFloat('uBottomWidth', 0.4);
	gridShader.setFloat('uDepthPow', 1.15);
	gridShader.setFloat('uScrollY', 0);
	grid.shader = gridShader;
	
	grid.updateHitbox();
	
	add(gridUnder = new FlxSkewedSprite(0, 0, Paths.image('bars/gridBars')));
	gridUnder.alpha = grid.alpha;
	gridUnder.antialiasing = false;
	gridUnder.origin.set(gridUnder.frameWidth * 0.5, 0);
	gridUnder.scale.set(grid.scale.x, grid.scale.y);
	gridUnder.scrollFactor.set(grid.scrollFactor.x, grid.scrollFactor.y);
	gridUnder.flipY = true;
	gridUnder.screenCenter(FlxAxes.X);
	gridUnder.x = grid.x;
	gridUnder.y = grid.y + grid.height + 0;
	
	gridUnderShader.setFloat('uTopWidth', 1.9);
	gridUnderShader.setFloat('uBottomWidth', 0.4);
	gridUnderShader.setFloat('uDepthPow', 1.15);
	gridUnderShader.setFloat('uScrollY', 0);
	gridUnder.shader = gridUnderShader;
	
	gridUnder.updateHitbox();
	
	fg = new BGSprite('bars/stage', -200, 375, 1, 1);
	fg.antialiasing = false;
	fg.setGraphicSize(Std.int(fg.width * 6));
	fg.updateHitbox();
	add(fg);
	
	fg2 = new BGSprite('bars/stage2', 900, 375, 1, 1);
	fg2.antialiasing = false;
	fg2.setGraphicSize(Std.int(fg2.width * 6));
	fg2.updateHitbox();
	add(fg2);
	
	fgBaseY = fg.y;
	fg2BaseY = fg2.y;
}

function onCreatePost()
{
	camSpecialThing([650, 475], [1000, 475]);
	camHUD.alpha = 0;
	camGame.zoom = 3;
	snapCamToPos(800, 300);
	isCameraOnForcedPos = true;
	hasCovers = 0;
	
	if (ClientPrefs.shaders)
	{
		vhsShader = newShader('vhs');
		vhsShader.setInt('uFrame', 0);
		vhsShader.setFloat('uInterlace', 1.0);
		
		camGame.filters = [new ShaderFilter(vhsShader)];
	}
	
	for (character in [boyfriend, dad])
	{
		character.setPosition(Math.round(character.x), Math.round(character.y));
		character.origin.set(Math.round(character.origin.x), Math.round(character.origin.y)); // fuck you ! fuck you ! fuck y
	}
	
	dadBaseY = dad.y;
	bfBaseY = boyfriend.y;
	
	showdankBlack();
}

function onSongStart()
{
	game.countdownSounds = true;
	
	if (dankBlack != null)
	{
		FlxTween.tween(dankBlack, {alpha: 0}, 0.2,
			{
				ease: FlxEase.quadOut,
				onComplete: function(_) {
					dankBlack.visible = false;
					dankBlack.kill();
				}
			});
	}
}

function onUpdate(elapsed:Float)
{
	waveTime += elapsed;
	
	if (vhsShader != null)
	{
		vhsFrame += 1;
		vhsShader.setInt('uFrame', vhsFrame);
		vhsShader.setFloat('uInterlace', 1.0);
	}
	
	gridScrollY += elapsed * 0.02;
	gridShader.setFloat('uScrollY', -gridScrollY);
	gridUnderShader.setFloat('uScrollY', -gridScrollY);
	
	var wave = Math.sin(waveTime * 1.5) * 6;
	fg.y = fgBaseY + wave;
	fg2.y = fg2BaseY - wave;
	
	dad.y = dadBaseY + wave;
	boyfriend.y = bfBaseY - wave;
}

function onDestroy()
{
	camGame.filters = [];
}

function onGameOverStart()
{
	camGame.filters = [];
}

function onEvent(eventName, value1, value2)
{
	if (value1 == 'bye')
	{
		showdankBlack();
		return;
	}
	
	switch (eventName)
	{
		case 'tomongusdie':
			FlxG.sound.play(Paths.sound('stage/tomongus_Shot'));
	}
}
