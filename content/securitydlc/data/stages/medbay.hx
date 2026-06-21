var ext = 'stages/dlc/medbay/';
var rimlight;
public var loBlack:FlxSprite;
public var loBlack2:FlxSprite;
public var guy3:FlxSprite;
public var guy2:FlxSprite;
public var blooodfuckkk:FlxSprite;
public var light:FlxSprite;

function onLoad()
{
	var bg:FlxSprite = new FlxSprite(-300, -100).loadGraphic(Paths.image(ext + 'wall'));
	add(bg);

	var shelf:FlxSprite = new FlxSprite(358, 290).loadGraphic(Paths.image(ext + 'shelf'));
	shelf.scrollFactor.set(0.99,1);
	add(shelf);

	var bloody:FlxSprite = new FlxSprite(-300, -100).loadGraphic(Paths.image(ext + 'bloody'));
	bloody.blend = BlendMode.MULTIPLY;
	bloody.scale.set(2,1);
	add(bloody);

	loBlack = new flixel.system.FlxBGSprite();
	loBlack.color = FlxColor.BLACK;
	loBlack.alpha = 0.001;
	loBlack.screenCenter();
	add(loBlack);
	
}
function onUpdatePost() {
    if (ClientPrefs.shaders) { var uv = dad.frame.uv;
    rimlight.setFloatArray('uFrameBounds', [uv.x, uv.y, uv.width, uv.height]);
    rimlight.setFloat('angOffset', dad.frame.angle * Math.PI / 180); }

	//if (ClientPrefs.shaders) checks for user settings if they have shaders enabled or not
}

function onCreatePost()
{
    if (ClientPrefs.shaders) {dad.shader = rimlight = newShader('rimlight1');
    dad.useRenderTexture = true;

    rimlight.setFloatArray('dropColor', [255, 0, 0]);
    
    rimlight.setBool('useMask', false);
    rimlight.setFloat('AA_STAGES', 100);
    rimlight.setFloat('thr', 0.01);
    
    rimlight.setFloat('hue', -10);
    rimlight.setFloat('saturation', -20);
    rimlight.setFloat('brightness', -10);
    
    rimlight.setFloat('str', 1);
    rimlight.setFloat('dist', 14);
    rimlight.setFloat('ang', 150 * Math.PI / 180);}

	blooodfuckkk = new FlxSprite().makeGraphic(FlxG.width * 4, FlxG.height + 700, FlxColor.RED);
	blooodfuckkk.alpha = 0.001;
	blooodfuckkk.screenCenter();
	blooodfuckkk.blend = BlendMode.MULTIPLY;
	blooodfuckkk.zIndex = 3;
	add(blooodfuckkk);

	snapCamToPos(800, 450);
	camSpecialThing([640, 450], [810, 450]);

	guy2 = new FlxSprite(-350, 760).loadGraphic(Paths.image(ext + 'kakosfriend'));
	guy2.scrollFactor.set(1.05,1);
	guy2.zIndex = 2;
	add(guy2);

	guy3 = new FlxSprite(1330, 650).loadGraphic(Paths.image(ext + 'gilbert'));
	guy3.scrollFactor.set(1.05,1);
	guy3.zIndex = 2;
	add(guy3);

	light = new FlxSprite(1200, -140);
	light.frames = Paths.getSparrowAtlas(ext + 'lights');
	light.animation.addByPrefix('lightson', 'lightson', 24, true);
	light.animation.addByPrefix('lightsoff', 'lightsoff', 24, true);
	light.animation.play('lightson');
	light.scrollFactor.set(1.1,1.1);
	light.zIndex = 2;
	add(light);

	var bloody2:FlxSprite = new FlxSprite(-300, -100).loadGraphic(Paths.image(ext + 'bloody'));
	bloody2.blend = BlendMode.SUBTRACT;
	bloody2.zIndex = 2;
	add(bloody2);

	var vignette:FlxSprite = new FlxSprite(-300, -100).loadGraphic(Paths.image(ext + 'vignette'));
	vignette.zIndex = 2;
	vignette.visible = true;
	add(vignette);

	loBlack2 = new FlxSprite().makeGraphic(FlxG.width * 4, FlxG.height + 700, FlxColor.BLACK);
	loBlack2.alpha = 0.001;
	loBlack2.screenCenter();
	loBlack2.zIndex = 2;
	add(loBlack2);

	refreshZ();
}