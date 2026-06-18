import funkin.states.TitleState;
import funkin.data.FinaleState;

var playedCredits:Bool = false;

function onEndSong():Void
{
	if (isStoryMode && !playedCredits)
	{
		camGame.visible = false;
		playedCredits = true;
		
		persistentUpdate = persistentDraw = false;
		openSubState(new funkin.states.substates.CreditsRollSubState(false, function() endSong()));
		
		return Function_Stop;
	}
	
	ClientPrefs.finaleState = FinaleState.COMPLETE;
	ClientPrefs.flush();
	
	game.unlockAchievementPopup('finale');
	if (game.songMisses == 0) game.unlockAchievementPopup('no_miss_finale');
	
	return Function_Continue;
}

function postEndSong():Void
{
	if (playedCredits)
	{
		camOther.fade(2, FlxColor.BLACK);
		
		new FlxTimer().start(2, function(_) {
			TitleState.initialized = false;
			FlxG.resetGame();
		});
		
		return Function_Stop;
	}
}