function onLoad()
{
	videoCutscene('jorsawsee/turbulence', false);
}

var dadX:Float, dadY:Float;

final sineInOut = FlxEase.sineInOut;
final quintIn = FlxEase.quintIn;
final quartIn = FlxEase.quartIn;
final quadOut = FlxEase.quadOut;
final quadIn = FlxEase.quadIn;
final sineIn = FlxEase.sineIn;

function onCreatePost():Void
{
	dadX = dad.x;
	dadY = dad.y;
}

function delta(n:Float, min:Float, max:Float)
{
	return FlxMath.bound(FlxMath.remapToRange(n, min, max, 0, 1), 0, 1);
}

function onUpdate(elapsed:Float):Void
{
	if (isDead) return;
	
	crazy = 1;
	dad.x = dadX;
	dad.y = dadY;
	
	final musicTime:Float = getSongTime();
	
	if (musicTime >= 108214) // STUPID math stuff
	{ // faster
		bfOff[0] = (1000 + sineInOut(delta(musicTime, 108214, 124058)) * 150);
		bfOff[1] = (800 + sineInOut(delta(musicTime, 108214, 124058)) * 150);
		
		dadOff[0] = (360 + quadIn(delta(musicTime, 108214, 124058)) * 2000);
		dadOff[1] = (400 + quadIn(delta(musicTime, 108214, 124058)) * 500);
		dad.x += (quadIn(delta(musicTime, 108214, 124058)) * 2100); // good bye mungus
		dad.x += (quartIn(delta(musicTime, 123800, 124158)) * 2200);
		dad.y += (quintIn(delta(musicTime, 108214, 124158)) * 300);
		
		if (musicTime < 124058)
		{
			crazy += (sineIn(delta(musicTime, 108214, 124058)) * 4);
		}
		else
		{
			crazy += (4 - quadOut(delta(musicTime, 124058, 124058 + 2500)) * 4);
		}
	}
}
