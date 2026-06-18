import funkin.data.ClientPrefs;

function onLoad()
{
	var thebackground = new FlxSprite(-4, 0);
	thebackground.frames = Paths.getSparrowAtlas('stages/freeplay/nuzzus/nuzzus');
	thebackground.animation.addByPrefix('bop', 'bg', 24, true);
	thebackground.animation.play('bop');
	thebackground.antialiasing = false;
	thebackground.setGraphicSize(Std.int(thebackground.width * 5));
	add(thebackground);
}

function onCreatePost()
{
	hasCovers = 0;
	playHUD.ratingPrefix = 'ui/nuzzus/';
	playHUD.ratingSuffix = '-nuzzus'; // UI SCALE IS SET IN utils.hx
	game.isCameraOnForcedPos = true;
	game.snapCamToPos(123, 250);
	
	// This might be a bad idea
	var blah:String = Paths.font('apple_kid.ttf');
	var sobEmoji:Bool = StringTools.endsWith(blah, 'apple_kid.ttf') && ClientPrefs.language != 'english';
	scoreTxt.setFormat(sobEmoji ? Paths.font('vcr.ttf') : Paths.font("apple_kid.ttf"), sobEmoji ? scoreTxt.size : 50, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	
	iconP1.alpha = 0;
	iconP2.alpha = 0;
	healthBar.alpha = 0;
}
