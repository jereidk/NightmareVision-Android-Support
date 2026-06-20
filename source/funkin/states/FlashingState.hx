package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.effects.FlxFlicker;
import flixel.addons.transition.FlxTransitionableState;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;

class FlashingState extends MusicBeatState
{
	public static var leftState:Bool = false;
	
	var warnText:FlxText;
	
	override function create()
	{
		super.create();
		
		warnText = new FlxText(0, 0, FlxG.width,
			"WARNING!\n\n"
			+ "This mod contains effects that may trigger photosensitivity.\n"
			#if android
			+ "Tap B to disable these effects now.\n"
			+ "Tap A to keep them on."
			#else
			+ "Press ESCAPE to disable these effects now.\n"
			+ "Press ENTER to keep them on."
			#end
			+ "\n\nYou may change this anytime in the Options menu.", 32);
		warnText.setFormat(Paths.DEFAULT_FONT, 32, FlxColor.WHITE, CENTER);
		warnText.screenCenter();
		add(warnText);

		#if mobile
		addVirtualPad(NONE, A_B);
		#end
	}

	override function update(elapsed:Float)
	{
		if (!leftState && (controls.ACCEPT || controls.BACK)) {
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			
			ClientPrefs.photosensitive = controls.BACK;
			FlxG.sound.play(Paths.sound('confirmMenu'));
			
			if (controls.BACK)
			{
				FlxTween.tween(warnText, {alpha: 0}, 1,
				{
					onComplete: function(twn:FlxTween) {
						FlxG.switchState(TitleState.new);
					}
				});
			}
			else
			{
				FlxFlicker.flicker(warnText, 1, 0.1, false, true, function(flk:FlxFlicker) {
					new FlxTimer().start(0.5, function(tmr:FlxTimer) {
						FlxG.switchState(TitleState.new);
					});
				});
			}
			
			leftState = true;
		}
		
		super.update(elapsed);
	}
}
