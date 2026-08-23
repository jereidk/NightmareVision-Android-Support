import Date;

import funkin.states.substates.PauseSubState;

function onCreatePost()
{
	camSpecialThing([850, 650], [1200, 650]);
	if (Date.now().getDay() == 2) game.unlockAchievementPopup('tuesday_morning');
	PauseSubState.songName = 'tomongusPause';
}

function onLoad()
{
	var space:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image('stages/skeld/tomongus/tuesday/space'));
	space.scrollFactor.set(0.9, 0.9);
	add(space);
	
	var bg:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image('stages/skeld/tomongus/tuesday/bg'));
	add(bg);
}

function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case 'tuesdayblast':
			FlxG.sound.play(Paths.sound('stage/soundTuesday'));
			boyfriend.canDance = false;
		case 'tomongusdie':
			FlxG.sound.play(Paths.sound('stage/tomongus_Shot'));
	}
}
