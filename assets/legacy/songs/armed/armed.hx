import funkin.game.shaders.ColorSwap;

var ext = 'stages/henry/';
var armedDark:FlxSprite;
var dustcloud:FlxSprite;
var altIcon:Bool = false;
var shader:HSLColorSwap;
var endingVideo:FunkinVideoSprite; // maybe move to a different state??? for that #immersion but i dont think it matters

function onLoad()
{
	if (PlayState.isStoryMode)
	{
		songStartCallback = armedIntro;
		
		armedDark = new FlxSprite(-300, -300).makeScaledGraphic(FlxG.width * 2, FlxG.height * 2, FlxColor.BLACK);
		armedDark.visible = false;
		armedDark.zIndex = 0;
		stage.add(armedDark);
		
		dustcloud = new FlxSprite(120, 450);
		dustcloud.frames = Paths.getSparrowAtlas(ext + 'Dust_Cloud');
		dustcloud.animation.addByPrefix('dust', 'dust clouds', 24, false);
		dustcloud.antialiasing = ClientPrefs.globalAntialiasing;
		dustcloud.zIndex = 1;
		stage.add(dustcloud);
		
		endingVideo = new FunkinVideoSprite();
		endingVideo.onFormat(() -> {
			endingVideo.setGraphicSize(0, FlxG.height);
			endingVideo.updateHitbox();
			endingVideo.screenCenter();
			endingVideo.cameras = [camOther];
			endingVideo.antialiasing = ClientPrefs.globalAntialiasing;
		});
		endingVideo.onEnd(endSong);
		endingVideo.load(Paths.video('henry/henryEnd'));
		add(endingVideo);
		endingVideo.visible = false;
		
		songEndCallback = armedOutro;
	}
	
	mom = new Character(-60, 210, 'reginald');
	startCharacterPos(mom);
	stage.add(mom);
	mom.zIndex = 3;
	
	dadGroup.zIndex = 2;
}

function onCreatePost()
{
	refreshZ();
}

function armedIntro()
{
	for (i in [boyfriend, gf, mom, pet])
	{
		i.alpha = 0;
	}
	
	camHUD.visible = false;
	armedDark.visible = true;
	
	dad.playAnim('intro', false);
	dustcloud.animation.play('dust');
	
	new FlxTimer().start(3.2, function(tmr:FlxTimer) {
		FlxTween.tween(gf, {alpha: 1}, 1.5);
		FlxTween.tween(mom, {alpha: 1}, 1.5);
		FlxTween.tween(boyfriend, {alpha: 1}, 1.5);
		FlxTween.tween(pet, {alpha: 1}, 1.5);
		FlxTween.tween(armedDark, {alpha: 0}, 1.5);
	});
	
	new FlxTimer().start(5, function(tmr:FlxTimer) {
		camHUD.visible = true;
		startCountdown();
	});
}

function opponentNoteHit(note)
{
	var change:Bool = note.noteType == 'Opponent 2 Sing';
	
	refreshArmedIcon(change);
}

function refreshArmedIcon(changeIcon:Bool)
{
	if (changeIcon == altIcon) return;
	
	altIcon = changeIcon;
	if (hasColor) playHUD.scoreTxt.color = (altIcon ? mom : dad).healthColour;
	playHUD.healthBar.setColors((altIcon ? mom : dad).healthColour, boyfriend.healthColour);
	playHUD.iconP2.changeIcon(altIcon ? 'reginald' : 'rhm');
}

function shaderFlash(a = 0, b = 0.05, ?ignoreOption = false)
{
	if (!ignoreOption)
	{
		if (!ClientPrefs.flashing) return;
	}
	colorShader.flash = 1;
	FlxTween.tween(colorShader, {flash: a}, b, {ease: FlxEase.expoOut});
}

function armedOutro()
{
	camFollow.setPosition(1000, 550);
	isCameraOnForcedPos = true;
	canPause = false;
	inCutscene = true;
	
	colorShader = new ColorSwap();
	boyfriend.shader = colorShader.shader;
	FlxTween.tween(camHUD, {alpha: 0}, 0.7, {ease: FlxEase.quadInOut});
	FlxG.sound.play(Paths.sound('stage/teleport_sound'));
	
	new FlxTimer().start(0.45, function(tmr:FlxTimer) {
		shaderFlash(0, 0.73);
	});
	
	new FlxTimer().start(1.28, function(tmr:FlxTimer) {
		shaderFlash(0.1, 0.55);
		gf.shader = colorShader.shader;
	});
	
	new FlxTimer().start(1.93, function(tmr:FlxTimer) {
		// colorShader.setFloat('amount',1);
		shaderFlash(0.2, 0.2);
	});
	
	new FlxTimer().start(1.3, function(tmr:FlxTimer) {
		shaderFlash(0.1, 0.55);
		pet.shader = colorShader.shader;
	});
	
	new FlxTimer().start(2.23, function(tmr:FlxTimer) {
		if (ClientPrefs.flashing) shaderFlash(0.4, 0.22);
		else FlxTween.tween(colorShader, {flash: 1}, 0.47, {ease: FlxEase.expoIn});
	});
	new FlxTimer().start(2.55, function(tmr:FlxTimer) {
		shaderFlash(0.8, 0.05);
	});
	
	new FlxTimer().start(2.7, function(tmr:FlxTimer) {
		colorShader.flash = 1;
		FlxTween.tween(boyfriend, {"scale.y": 0}, 0.7, {ease: FlxEase.expoOut});
		FlxTween.tween(boyfriend, {"scale.x": 3.5}, 0.7, {ease: FlxEase.expoOut});
	});
	
	new FlxTimer().start(2.8, function(tmr:FlxTimer) {
		FlxTween.tween(gf, {"scale.y": 0}, 0.7, {ease: FlxEase.expoOut});
		FlxTween.tween(gf, {"scale.x": 3.5}, 0.7, {ease: FlxEase.expoOut});
	});
	
	new FlxTimer().start(2.85, function(tmr:FlxTimer) {
		FlxTween.tween(pet, {"scale.y": 0}, 0.7, {ease: FlxEase.expoOut});
		FlxTween.tween(pet, {"scale.x": 3.5}, 0.7, {ease: FlxEase.expoOut});
	});
	
	new FlxTimer().start(4, function(tmr:FlxTimer) {
		camFollow.setPosition(700, 550);
	});
	
	new FlxTimer().start(4.5, function(tmr:FlxTimer) {
		FlxG.camera.fade(FlxColor.BLACK, 1.4, false, function() {
			endingVideo.visible = true;
			endingVideo.play();
		}, true);
	});
}
