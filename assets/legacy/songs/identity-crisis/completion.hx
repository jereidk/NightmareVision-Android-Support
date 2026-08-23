import funkin.data.FinaleState;
import funkin.states.TitleState;

var finale:Bool = false;

function onEndSong():Void {
	if (finale) {
		ClientPrefs.finaleState = FinaleState.ACTIVE;
		ClientPrefs.flush();
		
		TitleState.initialized = false;
		FlxG.resetGame();
		return;
	}
	
	if (ClientPrefs.finaleState != FinaleState.INACTIVE) return;
	
	FlxTween.tween(camGame, {zoom: .5}, 2, {ease: FlxEase.sineIn});
	FlxTween.tween(camHUD, {zoom: 2.5}, 1, {ease: FlxEase.sineIn});
	
	camHUD.fade(FlxColor.BLACK, 2);
	
	finale = true;
	canPause = false;
	
	FlxTimer.wait(2, function() {
		camHUD.visible = camGame.visible = false;
		
		videoCheckStory = PlayState.seenCutscene = false;
		videoCutscene('finale', false, false, function() endSong());
		PlayState.seenCutscene = true;
		
		for (caption in video.captions._queue) // this is why we need ssa format
		{
			caption.text.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.RED, FlxTextAlign.CENTER, null, FlxColor.BLACK);
			caption.recalculate();
		}
	});
	
	return Function_Stop;
}
