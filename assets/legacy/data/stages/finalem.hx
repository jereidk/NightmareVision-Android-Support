import funkin.game.shaders.DropShadowShader;
import funkin.states.substates.PauseSubState;

var ext = 'stages/void/finale/';
var defeatFinaleStuff:FlxSpriteGroup = new FlxSpriteGroup();
var finaleBGStuff:FlxSpriteGroup = new FlxSpriteGroup();
var finaleFGStuff:FlxSpriteGroup = new FlxSpriteGroup();
var finaleFlashbackStuff:FlxSprite;
var finaleDarkFG:FlxSprite;
var finaleLight:FlxSprite;
var lightoverlay:FlxSprite;
var finaleMode:Bool = false;
var bars:FlxSpriteGroup;
public var rimlightExcludedSkins:Array<String> = ['blackp']; // ig we need this now

// Double-tap-to-skip: the flashback build-up (onCreatePost's hidden HUD/dark
// overlay through 'Finale Drop' at finaleDropTime) runs entirely inside live,
// scored gameplay (real notes spawn from ~9600ms on) -- skipping it means
// jumping the song clock forward and manually replaying just the end-state
// 'Finale Drop' would have set, not freezing/killing a video like every
// other cutscene song in this pack.
var skipCutsceneText:FlxText;
var finaleSkipped:Bool = false;
var lastSkipTapPos:Float = -9999;
var finaleDropTime:Float = 20400;
var doubleTapWindowMs:Float = 500;

function onLoad()
{
	var bars:FlxSpriteGroup = new FlxSpriteGroup();
	bars.cameras = [camHUD];
	add(bars);
	
	for (i in 0...2) // maybe this is doin too much idk
	{
		var bar = new FlxSprite().makeScaledGraphic(FlxG.width + 3, 90, FlxColor.BLACK);
		bar.y = i == 1 ? 630 : 0;
		bars.add(bar);
	}
	
	finaleFlashbackStuff = new FlxSprite(-290, -160);
	finaleFlashbackStuff.frames = Paths.getSparrowAtlas(ext + 'finaleFlashback');
	finaleFlashbackStuff.animation.addByPrefix('moog', 'finaleFlashback moog', 24, false);
	finaleFlashbackStuff.animation.addByPrefix('toog', 'finaleFlashback toog', 24, false);
	finaleFlashbackStuff.animation.addByPrefix('doog', 'finaleFlashback doog', 24, false);
	finaleFlashbackStuff.animation.play('moog');
	finaleFlashbackStuff.setGraphicSize(Std.int(finaleFlashbackStuff.width * 1.6));
	finaleFlashbackStuff.alpha = 0.001;
	finaleFlashbackStuff.scrollFactor.set(); // this matters !??
	
	var defeatthing:FlxSprite = new FlxSprite(-400, 2000, Paths.image('stages/void/finale/defeat'));
	// defeatthing.frames = Paths.getSparrowAtlas('stages/void/defeat');
	// defeatthing.animation.addByPrefix('bop', 'defeat', 24, false);
	// defeatthing.animation.play('bop');
	defeatthing.setGraphicSize(Std.int(defeatthing.width * 1.3));
	defeatthing.scrollFactor.set(0.8, 0.8);
	defeatFinaleStuff.add(defeatthing);
	
	var mainoverlayDK:FlxSprite = new FlxSprite(250, 475).loadGraphic(Paths.image('stages/void/defeatfnf'));
	mainoverlayDK.setGraphicSize(Std.int(mainoverlayDK.width * 4));
	mainoverlayDK.updateHitbox();
	mainoverlayDK.alpha = 0.0001;
	defeatFinaleStuff.add(mainoverlayDK);
	
	var bg0:FlxSprite = new FlxSprite(-600, -400).makeScaledGraphic(3000, 2000, 0xFF0D0A1B);
	
	var bgScale = 1.3;
	
	// The "props" atlas got split into two ASTC pages (props-0: bg/dark,
	// props-1: dead/fore/lamp/splat) at some point, but this script still
	// asked for all six frames from a single "props" atlas that no longer
	// exists — every one of these sprites loaded blank as a result.
	var bg1:FlxSprite = new FlxSprite(800, -270).loadFromSheet(ext + 'props-1', 'dead');
	bg1.scrollFactor.set(0.8, 0.8);
	bg1.scale.set(bgScale, bgScale);

	var bg2:FlxSprite = new FlxSprite(-790, -530).loadFromSheet(ext + 'props-0', 'bg');
	bg2.updateHitbox();
	bg2.scrollFactor.set(0.9, 0.9);
	bg2.scale.set(bgScale, bgScale);

	var bg3:FlxSprite = new FlxSprite(370, 1200).loadFromSheet(ext + 'props-1', 'splat');
	bg3.updateHitbox();
	bg3.scale.set(bgScale, bgScale);

	var bg4:FlxSprite = new FlxSprite(990, -380).loadFromSheet(ext + 'props-1', 'lamp');
	bg4.updateHitbox();
	bg4.scale.set(bgScale, bgScale);

	var bg5:FlxSprite = new FlxSprite(-750, 160).loadFromSheet(ext + 'props-1', 'fore');
	bg5.updateHitbox();
	bg5.scale.set(bgScale, bgScale);

	var dark:FlxSprite = new FlxSprite(-950, -160).loadFromSheet(ext + 'props-0', 'dark');
	dark.scale.set(1.3, 1.3);
	dark.blend = BlendMode.MULTIPLY;
	
	finaleLight = new FlxSprite(-230, -200);
	finaleLight.frames = Paths.getSparrowAtlas(ext + 'light');
	finaleLight.animation.addByPrefix('bop', 'light', 24, false);
	finaleLight.animation.play('bop');
	finaleLight.setGraphicSize(Std.int(finaleLight.width * 4)); // GRRR
	finaleLight.updateHitbox();
	finaleLight.setGraphicSize(Std.int(finaleLight.width * 1.1));
	finaleLight.scrollFactor.set(0.8, 0.8);
	finaleLight.blend = BlendMode.ADD;
	
	finaleBGStuff.add(bg0);
	finaleBGStuff.add(bg1);
	finaleBGStuff.add(bg2);
	finaleFGStuff.add(bg3);
	finaleFGStuff.add(bg4);
	finaleFGStuff.add(bg5);
	if (!ClientPrefs.lowQuality)finaleFGStuff.add(dark);
	finaleFGStuff.add(finaleLight);
	
	finaleBGStuff.alpha = 0.001;
	finaleFGStuff.alpha = 0.001;
	
	add(defeatFinaleStuff);
	add(finaleBGStuff);
}

function onCreatePost()
{
	addCharacterToList('blackparasite', 1);
	
	camHUD.alpha = 0.001;
	playHUD.iconP1.visible = false;
	playHUD.iconP2.visible = false;
	playHUD.healthBar.visible = false;
	playHUD.timeBar.visible = false;
	playHUD.timeTxt.visible = false;
	canFollow = false;
	camSpecialThing([750, 800], [750, 800], 0.8);
	
	add(finaleFGStuff);
	if (!ClientPrefs.lowQuality) add(finaleFlashbackStuff);
	
	lightoverlay = new FlxSprite(-550, 250).loadGraphic(Paths.image('stages/void/iluminao omaga'));
	lightoverlay.scale.set(4, 4);
	lightoverlay.updateHitbox();
	lightoverlay.blend = BlendMode.ADD;
	lightoverlay.antialiasing = ClientPrefs.globalAntialiasing;
	add(lightoverlay);
	
	finaleDarkFG = new FlxSprite(-1000, -900).makeScaledGraphic(FlxG.width * 3, FlxG.height * 3, FlxColor.BLACK);
	finaleDarkFG.scrollFactor.set();
	add(finaleDarkFG);
	
	dadGroup.zIndex = 1;
	finaleFGStuff.zIndex = 2;
	finaleFlashbackStuff.zIndex = 3;
	lightoverlay.zIndex = 4;
	finaleDarkFG.zIndex = 5;
	
	opponentStrums.visible = false;
	modManager.setValue("alpha", 1, 1);

	// camOther, not camHUD -- camHUD.alpha is 0.001 for the whole
	// flashback (see above), which would make this text invisible too.
	skipCutsceneText = new FlxText(0, 0, FlxG.width, Lang.str('finale_skip_cutscene', 'Tap two time to skip this cutscene'));
	skipCutsceneText.setFormat(Paths.font("liberbold.ttf"), 18, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	skipCutsceneText.borderSize = 2;
	skipCutsceneText.scrollFactor.set();
	skipCutsceneText.y = FlxG.height - skipCutsceneText.height - 20;
	skipCutsceneText.camera = camOther;
	skipCutsceneText.zIndex = 20;
	add(skipCutsceneText);

	refreshZ();
	
	if (ClientPrefs.shaders)
	{
		var blackRimlightBase:ExtraDropShadowShader = new funkin.game.shaders.ExtraDropShadowShader();
		
		blackRimlightBase.threshold = .05;
		blackRimlightBase.strength = .85;
		blackRimlightBase.setColorMatrix([
			.4, .5, -.2, 0, -50,
			-.25, .7, -.15, 0, -20,
			.42, -.35, .85, 0, -72,
			0, 0, 0, 1, 0
		]);
		blackRimlightBase.addLayer([
			.7, .5, 1, 0, 192,
			.3, .4, -.5, 0, 64,
			-.1, .2, .35, 0, 74,
			0, 0, 0, 1, 0
		], 10, 14, .01);
		blackRimlightBase.addLayer(
			blackRimlightBase.addLayer([
				.9, .6, .4, 0, 4,
				-.2, .5, .1, 0, -18,
				-.2, .2, .4, 0, -28,
				0, 0, 0, 1, 0
			], 12, 40, .01, .4)
		.colorMatrix, 96, 24, .01, .4);
		
		if (hasBfSkin && boyfriend.getFlag('backlit') != true)
		{
			bfRim = blackRimlightBase;
			bfRim.attachedSprite = boyfriend;
			boyfriend.useRenderTexture = true;
		}
		
		if (hasPet)
		{
			petRim = new funkin.game.shaders.ExtraDropShadowShader().copyFrom(blackRimlightBase);
			petRim.attachedSprite = pet;
			pet.useRenderTexture = true;
		}
	}
	
	PauseSubState.songName = 'blackPause';
}

function onBeatHit()
{
	if (!ClientPrefs.lowQuality && curBeat % 4 == 0) finaleLight.animation.play('bop');
}

function onUpdate(elapsed)
{
	if (Conductor.songPosition >= 0 && Conductor.songPosition < 9600)
	{
		FlxG.camera.zoom = FlxMath.lerp(FlxG.camera.zoom, 1, FlxMath.bound(elapsed * 0.01, 0, 1));
	}

	if (!finaleSkipped && Conductor.songPosition >= 0 && Conductor.songPosition < finaleDropTime)
	{
		skipCutsceneText.visible = true;

		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				if (Conductor.songPosition - lastSkipTapPos < doubleTapWindowMs)
					skipFinaleCutscene();
				else
					lastSkipTapPos = Conductor.songPosition;
				break;
			}
		}
	}
	else if (skipCutsceneText != null)
	{
		skipCutsceneText.visible = false;
	}
}

// Fast-forwards straight to 'Finale Drop' instead of freezing/killing a
// video like every other cutscene song -- setSongTime()/clearNotesBefore()
// mirror the same no-penalty time-skip pair already used elsewhere in this
// engine (e.g. PauseSubState's skip-to-time path), and triggerEventNote()
// (not a direct onEvent() call) is the same sanctioned "synthesize this
// event as if the chart fired it" API double-kill.hx already uses for
// 'Change Character' -- it runs the full engine dispatch (including this
// script's own onEvent), not just this file's local switch case.
function skipFinaleCutscene():Void
{
	if (finaleSkipped) return;
	finaleSkipped = true;

	setSongTime(finaleDropTime);
	clearNotesBefore(Conductor.songPosition);

	// 'HUD Fade' '1' (the chart event that normally restores this) never
	// fires since we're jumping straight past its 9600ms timestamp -- without
	// this, camHUD stays at onCreatePost()'s near-invisible flashback alpha
	// (0.001) for the rest of the song.
	camHUD.alpha = 1;

	triggerEventNote('Finale Drop', '', '');
	triggerEventNote('Change Character', '1', 'blackparasite');

	skipCutsceneText.visible = false;
}

function onSongStart()
{
	// finaleDarkFG.alpha = FlxMath.lerp(finaleDarkFG.alpha, 0, FlxMath.bound(elapsed * 0.5, 0, 1));
	FlxTween.tween(finaleDarkFG, {alpha: 0}, 9.6);
}

function onMoveCamera(isDad)
{
	if (finaleMode) if (isDad == 'boyfriend')
	{
		game.defaultCamZoom = 0.5;
	}
	else
	{
		game.defaultCamZoom = 0.4;
	}
}

function onEvent(name, v1, v2)
{
	switch (name)
	{
		case 'Finale Flashback Change':
			finaleFlashbackStuff.alpha = 0.5;
			switch (v1)
			{
				case 'moog':
					finaleFlashbackStuff.animation.play('moog');
				case 'toog':
					finaleFlashbackStuff.animation.play('toog');
				case 'doog':
					finaleFlashbackStuff.animation.play('doog');
				case 'flash':
					FlxG.camera.fade(FlxColor.WHITE, 1.2, false, function() {
						FlxG.camera.fade(FlxColor.RED, 0.6, true);
						finaleFlashbackStuff.alpha = 0;
					});
			}
			
		case 'Finale Drop':
			finaleMode = true;
			camSpecialThing([500, 600], [700, 700]);
			health = 0.2; // used to be 0.1 but im nicer
			finaleBGStuff.alpha = 1;
			finaleFGStuff.alpha = 1;
			defeatFinaleStuff.visible = false;
			lightoverlay.visible = false;
			healthBar.visible = true;
			canFollow = true;
			finaleUIOn();
			scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, 0xFFff1266, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			playHUD.updateIconPos = false;
			camGame.flash(0xFFff1266, 0.75);
		case 'Finale End':
			camOther.flash(0xFFff1266, 5);
			camHUD.visible = false;
			camGame.visible = false;
	}
}
