import flixel.addons.effects.FlxSkewedSprite;

var colorSwap:HSLColorSwap = (ClientPrefs.shaders ? new funkin.game.shaders.HSLColorSwap() : null);
var colorSwapShader;
var ext:String = 'stages/jorsawsee/o2/';
var xx:Float = 130, yy:Float = 325;
var wall:FlxSkewedSprite;
var cues:FlxSkewedSprite;
var table:FlxSkewedSprite;
var overlay:FlxSprite;
var s:FlxSprite;
var vignetteOverlay:OverlayShader = null;
var simpleVignette:FlxSprite;
var vignette:FlxSprite;
var scaryLight:FlxSprite;
var body:FlxSprite;

function onLoad()
{
	colorSwapShader = colorSwap?.shader;
	
	add(wall = new FlxSkewedSprite(-347 + xx, -122 + yy, Paths.image(ext + 'wall')));
	wall.shader = colorSwapShader;
	wall.origin.y = wall.frameHeight;
	wall.scrollFactor.set(.97, .9);
	add(s = new FlxSprite(-283 + xx, 397 + yy, Paths.image(ext + 'floor')));
	s.shader = colorSwapShader;
	s.scrollFactor.set(.95, .92);
	add(s = new FlxSprite(153 + xx, 602 + yy, Paths.image(ext + 'shadows')));
	s.scale.set(1.13, 1.13);
	s.shader = colorSwapShader;
	s.scrollFactor.set(.95, .92);
	add(cues = new FlxSkewedSprite(186 + xx, 12 + yy, Paths.image(ext + 'cueHolder')));
	cues.shader = colorSwapShader;
	cues.origin.y = cues.frameHeight;
	cues.scrollFactor.set(.99, .95);
	add(collage = new FlxSkewedSprite(-217 + xx, 55 + yy, Paths.image(ext + 'collage')));
	collage.shader = colorSwapShader;
	collage.origin.y = 50;
	collage.scrollFactor.set(.97, .9);
	add(s = new FlxSprite(-238 + xx, 342 + yy, Paths.image(ext + 'tables')));
	s.shader = colorSwapShader;
	s.scrollFactor.set(.93, .91);
	add(s = new FlxSprite(832 + xx, 65 + yy, Paths.image(ext + 'dartBoard')));
	s.shader = colorSwapShader;
	s.scrollFactor.set(.95, .92);
	add(s = new FlxSprite(1245 + xx, 73 + yy, Paths.image(ext + 'dartBoard')));
	s.shader = colorSwapShader;
	s.scale.set(.98, .98);
	s.scrollFactor.set(.95, .92);
	add(s = new FlxSprite(782 + xx, 52 + yy, Paths.image(ext + 'dartsLeft')));
	s.shader = colorSwapShader;
	s.scrollFactor.set(.95, .92);
	add(s = new FlxSprite(1272 + xx, 64 + yy, Paths.image(ext + 'dartsRight')));
	s.shader = colorSwapShader;
	s.scrollFactor.set(.95, .92);
	
	add(body = new FlxSprite(-10 + xx, 520 + yy, Paths.image(ext + 'body')));
	body.scale.set(1.25, 1.25);
	body.scrollFactor.set(.92, .92);
	body.visible = false;
}

function onCreatePost()
{
	add(table = new FlxSkewedSprite(-22 + xx, 672 + yy, Paths.image(ext + 'billiardTable')));
	table.shader = colorSwapShader;
	table.scale.set(1.1, 1.1);
	table.scrollFactor.set(1.3, 1.2);
	add(s = new FlxSprite(420 + xx, 872 + yy, Paths.image(ext + 'aitball')));
	s.shader = colorSwapShader;
	s.scale.set(1.1, 1.1);
	s.scrollFactor.set(1.35, 1.45);
	
	add(overlay = new FlxSprite(0, 220, Paths.image(ext + 'overlay')));
	overlay.scale.set(4, 4);
	overlay.updateHitbox();
	overlay.blend = 0;
	
	add(scaryLight = new FlxSprite(520 + xx, 150 + yy, Paths.image(ext + 'absoluteLamp')));
	scaryLight.scrollFactor.set(.85, .75);
	scaryLight.scale.set(4, 4);
	scaryLight.blend = 0;
	scaryLight.color = 0xffffbbbb;
	scaryLight.visible = false;
	
	if (ClientPrefs.shaders)
	{
		vignetteOverlay = new funkin.game.shaders.OverlayShader();
		vignetteOverlay.setBitmapOverlay(Paths.image(ext + 'vignetteOverlay').bitmap);
	}
	else
	{
		add(simpleVignette = new FlxSprite(-80, -40, Paths.image(ext + 'vignetteMultiply')));
		simpleVignette.scale.set(4.5, 4.5);
		simpleVignette.updateHitbox();
		simpleVignette.scrollFactor.set();
		simpleVignette.blend = 9;
		simpleVignette.visible = false;
	}
	
	add(vignette = new FlxSprite(-80, -40, Paths.image(ext + 'vignetteMultiply')));
	vignette.scale.set(4.5, 4.5);
	vignette.updateHitbox();
	vignette.scrollFactor.set();
	vignette.blend = 9;
	vignette.visible = false;
	
	if (boyfriend.gameoverLoopDeathSound == null) boyfriend.gameoverLoopDeathSound = 'Jorsawsee_Loop';
	if (boyfriend.gameoverConfirmDeathSound == null) boyfriend.gameoverConfirmDeathSound = 'Jorsawsee_End';
}

function onUpdatePost()
{
	collage.skew.x = ((10 - FlxG.camera.scroll.x) / 80);
	wall.skew.x = ((200 - FlxG.camera.scroll.x) / 110);
	cues.skew.x = ((200 - FlxG.camera.scroll.x) / 150);
	table.skew.x = ((200 - FlxG.camera.scroll.x) / 18);
	
	var flicker:Float = (ClientPrefs.flashing ? FlxG.random.float(.7, 1) : 1);
	scaryLight.alpha = FlxMath.remapToRange(Math.sin(Conductor.songPosition / 700), -1, 1, .4, flicker);
}

var scaryColorSwap:ColorSwap;

public function scary()
{
	if (ClientPrefs.shaders)
	{
		colorSwap.hue = -.1;
		colorSwap.saturation = .1;
		colorSwap.lightness = -.5;
		
		body.shader = dad.shader = boyfriend.shader = pet.shader = scaryColorSwap.shader;
	}
	else
	{
		simpleVignette.visible = true;
	}
	
	dad.camDisplacement = boyfriend.camDisplacement = 5;
}

public function prepareScary()
{
	if (ClientPrefs.shaders)
	{
		scaryColorSwap = new funkin.game.shaders.ColorSwap();
		
		scaryColorSwap.hue = -.05;
		scaryColorSwap.brightness = -.4;
		scaryColorSwap.saturation = .2;
	}
	
	if (vignetteOverlay != null)
	{
		camGame.filters = [new openfl.filters.ShaderFilter(vignetteOverlay)];
		camHUD.filters = [new openfl.filters.ShaderFilter(vignetteOverlay)];
	}
	
	body.visible = vignette.visible = scaryLight.visible = true;
	
	overlay.visible = false;
}
