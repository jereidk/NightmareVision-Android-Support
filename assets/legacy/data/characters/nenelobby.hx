// Lowkey a lot of this code is taken from psych but I don't see a reason not to use it

var VULTURE_THRESHOLD:Float = 0.5;
var MIN_BLINK_DELAY:Int = 3;
var MAX_BLINK_DELAY:Int = 7;
var blinkCountdown:Int = 3;
var neneState:Int = 0; // Enums don't work in hscript!

/*
	neneState value cheat sheet:
	STATE_DEFAULT = 0
	STATE_PRE_RAISE = 1
	STATE_RAISE = 2
	STATE_READY = 3
	STATE_LOWER = 4
 */
function onCreatePost()
{
	if (gf != null)
	{
		gf.animation.callback = function(name:String, frameNumber:Int, frameIndex:Int) {
			switch (neneState)
			{
				case 1:
					if (name == 'danceLeft' && frameNumber >= 14)
					{
						animationFinished = true;
						transitionState();
					}
				default:
					// Ignore.
			}
		}
	}
}
function goodNoteHit()
{
	if (combo == 50) gf.playAnimForDuration('combo50', 1.2, true);
	
	if (combo == 200) gf.playAnimForDuration('combo200', 1.2, true);
}

var animationFinished:Bool = false;

function onUpdate(elapsed)
{
	animationFinished = gf.isAnimFinished();
	transitionState();
}

function onUpdatePost()
{
	if (ClientPrefs.inDevMode && showDevInfo) dbText = (dbText + '\nneneState: ' + neneState + '\nblinkCountdown: ' + blinkCountdown);
}

function onBeatHit()
{
	switch (neneState)
	{
		case 3:
			if (blinkCountdown == 0)
			{
				gf.playAnim('idleKnife', false);
				blinkCountdown = FlxG.random.int(MIN_BLINK_DELAY, MAX_BLINK_DELAY);
			}
			else blinkCountdown -= 1;
			
		default:
			// In other states, don't interrupt the existing animation.
	}
}

function transitionState()
{
	switch (neneState)
	{
		case 0:
			if (game.health <= VULTURE_THRESHOLD)
			{
				neneState = 1;
				gf.skipDance = true;
			}
			
		case 1:
			if (game.health > VULTURE_THRESHOLD)
			{
				neneState = 0;
				gf.skipDance = false;
			}
			else if (animationFinished)
			{
				neneState = 2;
				gf.playAnim('raiseKnife');
				gf.skipDance = true;
				gf.danced = true;
				animationFinished = false;
			}
			
		case 2:
			if (animationFinished)
			{
				neneState = 3;
				animationFinished = false;
			}
			
		case 3:
			if (game.health > VULTURE_THRESHOLD)
			{
				neneState = 4;
				gf.playAnim('lowerKnife');
			}
			
		case 4:
			if (animationFinished)
			{
				neneState = 0;
				animationFinished = false;
				gf.skipDance = false;
			}
	}
}
