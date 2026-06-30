var ext:String = 'stages/misc/chippin/';
public var fugly_cam_event:Bool = false;

function onStepHit()
{
	if (curStep == 448)
	{
		fugly_cam_event = true;
		camSpecialThing([750, 300], [750, 300], 0.6);
	}
}

function onCreatePost()
{
	camSpecialThing([600, 450], [800, 450]);
}

function onUpdate(elapsed)
{
	/*
		// I don't wanna play this song!
		if (FlxG.keys.justPressed.Z)
		{
			setSongTime(44 * 1000);
			clearNotesBefore(Conductor.songPosition);
		}
		if (FlxG.keys.justPressed.X)
		{
			setSongTime(71 * 1000);
			clearNotesBefore(Conductor.songPosition);
	}*/
	
	var DALAPSED:Float = elapsed / 0.016;
	if (fugly_cam_event && defaultCamZoom > 0.4)
	{
		defaultCamZoom -= 0.0005 * DALAPSED;
	}
}

function onLoad()
{

	pet.scale.set(1.5,1.5);
	var sky:FlxSprite = new FlxSprite(-1100, -800).loadGraphic(Paths.image(ext + 'back'));
	sky.scrollFactor.set(0, 0);
	add(sky);
	
	var back:FlxSprite = new FlxSprite(-1100, -800).loadGraphic(Paths.image(ext + 'backBuildings'));
	back.scrollFactor.set(0.2, 0.2);
	add(back);
	var sign:FlxSprite = new FlxSprite(-1100, -800).loadGraphic(Paths.image(ext + 'bg2'));
	sign.scrollFactor.set(0.4, 0.4);
	add(sign);
	
	var main:FlxSprite = new FlxSprite(-1100, -800).loadGraphic(Paths.image(ext + 'mainBuildings'));
	main.scrollFactor.set(0.4, 0.4);
	add(main);
	
	var glow:FlxSprite = new FlxSprite(-1100, -800).loadGraphic(Paths.image(ext + 'glow'));
	glow.scrollFactor.set(0.5, 0.5);
	glow.blend = BlendMode.ADD;
	add(glow);
	
	var glow:FlxSprite = new FlxSprite(-1100, -800).loadGraphic(Paths.image(ext + 'balcony'));
	add(glow);
	/*makeLuaSprite('sky','back',-1100, -800);
		setLuaSpriteScrollFactor('sky', 0, 0);
		addLuaSprite('sky',false);

		makeLuaSprite('back','backBuildings',-1100, -800);
		setLuaSpriteScrollFactor('back', 0.2, 0.2);
		addLuaSprite('back',false);

		makeLuaSprite('sign','bg2',-1100, -800);
		setLuaSpriteScrollFactor('sign', 0.4, 0.4);
		addLuaSprite('sign',false);

		makeLuaSprite('main','mainBuildings',-1100, -800);
		setLuaSpriteScrollFactor('main', 0.4, 0.4);
		addLuaSprite('main',false);

		makeLuaSprite('glow','glow',-1100, -800);
		setLuaSpriteScrollFactor('glow', 0.5, 0.5);
		setLuaSpriteScrollFactor('glow', 0.5, 0.5);
		setBlendMode('glow', 'ADD');
		addLuaSprite('glow',false);

		makeLuaSprite('balcony','balcony',-1100, -800);
		setLuaSpriteScrollFactor('balcony', 1, 1);
		addLuaSprite('balcony',false);
	 */
}
