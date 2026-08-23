public var mom:Character;

public var bindMomNotes:Bool = true;

function onCountdownTick(tick:Int):Void
{
	if (mom == null || tick == 4) return;
	
	mom.onBeatHit(tick);
}

function onBeatHit():Void
{
	if (mom != null) mom.onBeatHit(curBeat);
}

function opponentNoteHitPre(note:Note):Void
{
	if (mom == null || !bindMomNotes) return;
	
	if (note.noteType == 'Opponent 2 Sing')
	{
		note.owner = mom;
	}
	else if (note.noteType == 'Both Opponents Sing')
	{
		characterSing(mom, note);
	}
}
