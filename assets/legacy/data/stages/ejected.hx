var intro:FunkinVideoSprite;
var black:FlxSprite;
var tweeningChar:Bool = false;
var cloudScroll:Array<FlxSprite> = [];
var farClouds:Array<FlxSprite> = [];
var middleBuildings:Array<FlxSprite>;
var rightBuildings:Array<FlxSprite>;
var leftBuildings:Array<FlxSprite>;
var ejectedSpeed:Float = 9;
var fgCloud:FlxSprite;
var speedlines:FlxBackdrop;
public var sky:FlxSprite;
var speedPass:Array<Float> = [11000, 11000, 11000, 11000];
var farSpeedPass:Array<Float> = [11000, 11000, 11000, 11000, 11000, 11000, 11000];
var ext:String = 'stages/mira/ejected/';
var platform:FlxSprite;

var grayShader:ColorMatrixShader = (ClientPrefs.shaders ? new funkin.game.shaders.ColorMatrixShader() : null);

function onLoad()
{
	if (grayShader != null) grayShader.setAdjustColor(-7, -6, 0, -30);
	
	// 21.3
	
	ejectedSpeed = ClientPrefs.flashing ? 9 : 3.3;
	camZoomingDecay = .5;
	
	sky = new FlxSprite(-2372.25 + (1000), -4181.7 + (656 * 5)).loadGraphic(Paths.image(ext + 'sky'));
	sky.antialiasing = true;
	sky.scale.set(5, 5);
	sky.updateHitbox();
	sky.scrollFactor.set(0, 0);
	add(sky);
	
	fgCloud = new FlxSprite(-2660.4, -402).loadGraphic(Paths.image(ext + 'fgClouds'));
	fgCloud.antialiasing = true;
	fgCloud.scale.set(2, 2);
	fgCloud.updateHitbox();
	fgCloud.scrollFactor.set(0.2, 0.2);
	add(fgCloud);
	
	rightBuildings = [];
	leftBuildings = [];
	middleBuildings = [];
	for (i in 0...2)
	{
		var rightBuilding = new FlxSprite(1022.3, -390.45);
		rightBuilding.loadGraphic(Paths.image(ext + 'buildingB'));
		rightBuilding.antialiasing = true;
		rightBuilding.scale.set(2, 2);
		rightBuilding.updateHitbox();
		rightBuilding.scrollFactor.set(0.5, 0.5);
		add(rightBuilding);
		rightBuildings.push(rightBuilding);
	}
	
	for (i in 0...2)
	{
		var middleBuilding = new FlxSprite(-76.15, 1398.5);
		middleBuilding.loadGraphic(Paths.image(ext + 'buildingA'));
		middleBuilding.antialiasing = true;
		middleBuilding.scale.set(2, 2);
		middleBuilding.updateHitbox();
		middleBuilding.scrollFactor.set(0.5, 0.5);
		add(middleBuilding);
		middleBuildings.push(middleBuilding);
	}
	
	for (i in 0...2)
	{
		var leftBuilding = new FlxSprite(-1099.3, 7286.55);
		leftBuilding.loadGraphic(Paths.image(ext + 'buildingB'));
		leftBuilding.antialiasing = true;
		leftBuilding.scale.set(2, 2);
		leftBuilding.updateHitbox();
		leftBuilding.scrollFactor.set(0.5, 0.5);
		add(leftBuilding);
		leftBuildings.push(leftBuilding);
	}
	
	rightBuildings[0].y = 6803.1;
	middleBuildings[0].y = 8570.5;
	leftBuildings[0].y = 14050.2;
	
	platform = new FlxSprite(955, 1200);
	platform.frames = Paths.getSparrowAtlas('stages/common/platform');
	platform.animation.addByPrefix('bop', 'floating', 24, true);
	platform.animation.play('bop');
	platform.alpha = 0.00001;
	
	add(platform);
}

function onCreatePost()
{
	// thanks fnf wekly
	if (hasBfSkin && !boyfriend.getFlag('floating'))
	{
		platform.shader = grayShader;
		platform.alpha = 1;
	}
	
	pet.shader = gf.shader = boyfriend.shader = dad.shader = grayShader;
	
	if (!ClientPrefs.lowQuality && ClientPrefs.flashing)
	{
		for (i in 0...3)
		{
			// now i could add the clouds manually
			// but i wont!!! trolled
			var newCloud:FlxSprite = new FlxSprite();
			newCloud.frames = Paths.getSparrowAtlas(ext + 'scrollingClouds');
			newCloud.animation.addByPrefix('idle', 'Cloud' + i, 24, false);
			newCloud.animation.play('idle');
			
			switch (i)
			{
				case 0:
					newCloud.setPosition(-9.65, -224.35);
					newCloud.scrollFactor.set(0.8, 0.8);
				case 1:
					newCloud.setPosition(-1342.85, -350.45);
					newCloud.scrollFactor.set(0.6, 0.6);
				case 2:
					newCloud.setPosition(1784.65, -957.05);
					newCloud.scrollFactor.set(1.3, 1.3);
				case 3:
					newCloud.setPosition(-2217.45, -1377.65);
					newCloud.scrollFactor.set(1, 1);
			}
			add(newCloud);
			cloudScroll.push(newCloud);
		}
		
		for (i in 0...7)
		{
			var newCloud:FlxSprite = new FlxSprite();
			newCloud.frames = Paths.getSparrowAtlas(ext + 'scrollingClouds');
			newCloud.animation.addByPrefix('idle', 'Cloud' + i, 24, false);
			newCloud.animation.play('idle');
			newCloud.alpha = 0.5;
			
			switch (i)
			{
				case 0:
					newCloud.setPosition(-1308, -1039.9);
				case 1:
					newCloud.setPosition(464.3, -890.5);
				case 2:
					newCloud.setPosition(2458.45, -1085.85);
				case 3:
					newCloud.setPosition(-666.95, -172.05);
				case 4:
					newCloud.setPosition(-1616.6, 1016.95);
				case 5:
					newCloud.setPosition(1714.25, 200.45);
				case 6:
					newCloud.setPosition(-167.05, 710.25);
			}
			add(newCloud);
			farClouds.push(newCloud);
		}
	}
	
	gf.scrollFactor.set(0.7, 0.7);
	
	speedlines = new FlxBackdrop().loadGraphic(Paths.image(ext + 'speedlines'));
	speedlines.scale.set(3, 3);
	speedlines.updateHitbox();
	speedlines.scrollFactor.set(.3, .3);
	speedlines.alpha = 0.5;
	add(speedlines);
	
	pet.origin.set(pet.width / 2, pet.height / 2);
	
	pet.setColorTransform(1, 1, 1, 1, 0, 20, 40, -127);
	pet.colorTransform.alphaMultiplier = 2; // fuck you funkin crew.
	pet.scrollFactor.set(1.2, 1.2);
	
	if (pet.getFlag('spin') != false) pet.angularVelocity = 450;
}

function onUpdate(elapsed)
{
	if (!gf.getFlag('floating') && hasGfSkin) gf.angle = -25 + Math.sin(Conductor.songPosition / 500) * 10;

	pet.x += Math.sin(Conductor.songPosition / 100) * 200 * FlxG.elapsed; //ive got a final test in 2 hours wish me luck
	pet.y = 800 + Math.sin(Conductor.songPosition / 100) * 50;
	
	var musicTime:Float = Conductor.songPosition;
	funTime = musicTime;
	if (speedlines != null) speedlines.y = -(funTime * 2 * (ClientPrefs.flashing ? 1.75 : .75));

	if (isDead) return;
	camHUD.y = Math.sin((Conductor.songPosition / 1000) * (Conductor.bpm / 60) * 1.0) * 15;
	camHUD.angle = Math.sin((Conductor.songPosition / 1200) * (Conductor.bpm / 60) * -1.0) * 1.2;
	
	var porns:Array<FlxSprite> = cloudScroll.members;
	
	if (cloudScroll.length >= 3)
	{
		for (i in 0...cloudScroll.length)
		{
			cloudScroll[i].y = FlxMath.lerp(cloudScroll[i].y, cloudScroll[i].y - speedPass[i], FlxMath.bound(elapsed * ejectedSpeed, 0, 1));
			if (cloudScroll[i].y < -1789.65)
			{
				// im not using flxbackdrops so this is how we're doing things today
				var randomScale = FlxG.random.float(1.5, 2.2);
				var randomScroll = FlxG.random.float(1, 1.3);
				
				speedPass[i] = FlxG.random.float(1100, 1300);
				
				cloudScroll[i].scale.set(randomScale, randomScale);
				cloudScroll[i].scrollFactor.set(randomScroll, randomScroll);
				cloudScroll[i].x = FlxG.random.float(-3578.95, 3259.6);
				cloudScroll[i].y = 2196.15;
			}
		}
	}
	if (farClouds.length == 7)
	{
		for (i in 0...farClouds.length)
		{
			farClouds[i].y = FlxMath.lerp(farClouds[i].y, farClouds[i].y - farSpeedPass[i], FlxMath.bound(elapsed * ejectedSpeed, 0, 1));
			if (farClouds[i].y < -1614)
			{
				var randomScale = FlxG.random.float(0.2, 0.5);
				var randomScroll = FlxG.random.float(0.2, 0.4);
				
				farSpeedPass[i] = FlxG.random.float(1100, 1300);
				
				farClouds[i].scale.set(randomScale, randomScale);
				farClouds[i].scrollFactor.set(randomScroll, randomScroll);
				farClouds[i].x = FlxG.random.float(-2737.85, 3485.4);
				farClouds[i].y = 1738.6;
			}
		}
	}
	// AAAAAAAAAAAAAAAAAAAA
	if (leftBuildings.length > 0)
	{
		for (i in 0...leftBuildings.length)
		{
			leftBuildings[i].y = middleBuildings[i].y + 5888;
		}
	}
	if (middleBuildings.length > 0)
	{
		for (i in 0...middleBuildings.length)
		{
			if (middleBuildings[i].y < -11759.9)
			{
				middleBuildings[i].y = 3190.5;
				middleBuildings[i].animation.play(FlxG.random.bool(50) ? '1' : '2');
			}
			middleBuildings[i].y = FlxMath.lerp(middleBuildings[i].y, middleBuildings[i].y - 1300, FlxMath.bound(elapsed * ejectedSpeed, 0, 1));
		}
	}
	if (rightBuildings.length > 0)
	{
		for (i in 0...rightBuildings.length)
		{
			rightBuildings[i].y = leftBuildings[i].y;
		}
	}
	
	if (!tweeningChar && !inCutscene)
	{
		tweeningChar = true;
		
		if (!hasBfSkin || boyfriend.getFlag('floating'))
			FlxTween.tween(boyfriendGroup, {x: FlxG.random.float(BF_X - 15, BF_X + 15), y: FlxG.random.float(BF_Y - 15, BF_Y + 15)}, 0.4, {ease: FlxEase.smoothStepInOut});
		
		FlxTween.tween(gf,
			{
				x: FlxG.random.float(game.GF_X - 10, game.GF_X + 10),
				y: FlxG.random.float(game.GF_Y - 10, game.GF_Y + 10)
			}, 0.4,
			{
				ease: FlxEase.smoothStepInOut
			});
		
		FlxTween.tween(dad, {x: FlxG.random.float(DAD_X - 15, DAD_X + 15), y: FlxG.random.float(game.DAD_Y - 15, DAD_Y + 15)}, 0.4, {
			ease: FlxEase.smoothStepInOut,
			onComplete: function(_) tweeningChar = false
		});
	}
	
	if (!inCutscene && ClientPrefs.flashing) camGame.shake(0.002, 0.1);
	
	if (fgCloud != null)
	{
		fgCloud.y = FlxMath.lerp(-402 - 300, -402 - 500, songPercent);
	}
}
