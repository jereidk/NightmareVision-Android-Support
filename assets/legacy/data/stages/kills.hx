function onLoad()
{
	var bg:FlxSprite = new FlxSprite(-620, -227);
	bg.loadGraphic(Paths.image("stages/freeplay/kills/killbg"));
	add(bg);
}

function onCreatePost()
{
	game.isCameraOnForcedPos = true;
	game.snapCamToPos(500, 600);
}

function opponentNoteHit(note)
{
	boyfriend.playAnim(note.skin.data.singAnimations[note.noteData] + '-alt', true);
	boyfriend.holdTimer = 0;
	
	if (!note.isSustainNote && health > 0.1) health -= 0.015;
}
