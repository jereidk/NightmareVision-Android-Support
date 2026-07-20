// Shared by every song/stage script (auto-loaded from this folder -- see
// PlayState.hx's addSongScripts('scripts')) -- a reusable double-tap-to-skip
// gesture for mid-song cutscenes that run DURING live, scored gameplay
// (Finale's flashback build-up, Ejected's task-reveal video, ...), as
// opposed to videoCutscene()'s pre-countdown videos (dialogue.hx), which
// already have their own working BACK-button skip and don't need this.
//
// A specific song/stage script owns ALL of the "what does skipping actually
// DO" logic (setSongTime()/clearNotesBefore() + replaying whatever
// end-state the cutscene's own reveal event sets, via triggerEventNote())
// -- this file only owns the shared UI/gesture: the on-screen text, the
// double-tap detection, and the halfway-point gate that keeps both hidden
// and inert for the first half of the cutscene.

var _cutsceneSkipText:FlxText;
var _cutsceneSkipActive:Bool = false;
var _cutsceneSkipDone:Bool = false;
var _cutsceneSkipStart:Float = 0;
var _cutsceneSkipEnd:Float = 0;
var _cutsceneSkipCallback:Void->Void;
var _cutsceneSkipLastTapPos:Float = -9999;
var _cutsceneSkipWindowMs:Float = 500;
var _cutsceneSkipTextShown:Bool = false;

// This script is auto-loaded into EVERY song (see PlayState.hx's
// addSongScripts('scripts')), but registerSkippableCutscene() is only ever
// called by a handful of stage scripts (currently just ejected.hx). Without
// this, onUpdate() paid full hscript interpreter dispatch cost every single
// frame of every song, for nothing, just to hit its own early-return guard.
// Suppressed by default; registerSkippableCutscene()/onSkip flip it on/off.
script.suppressedEvents.set('onUpdate', true);

/**
 * Registers a skippable mid-song cutscene. Call once (e.g. from
 * onCreatePost()) from any song/stage script whose cutscene runs
 * concurrently with real gameplay. startTime/endTime are the cutscene's
 * bounds in Conductor.songPosition ms -- the skip gesture is live and
 * visible from startTime through the HALFWAY point of that window, then
 * hides and stops checking input for the second half (skipping only makes
 * sense once the player has actually seen enough of it to want to). onSkip
 * is called exactly once, when the player double-taps during that window;
 * it's responsible for the actual time jump and for replaying whatever
 * end-state the cutscene's own reveal event would have set.
 */
public function registerSkippableCutscene(startTime:Float, endTime:Float, onSkip:Void->Void):Void
{
	_cutsceneSkipActive = true;
	_cutsceneSkipDone = false;
	_cutsceneSkipStart = startTime;
	_cutsceneSkipEnd = endTime;
	_cutsceneSkipCallback = onSkip;
	_cutsceneSkipLastTapPos = -9999;
	_cutsceneSkipTextShown = false;
	script.suppressedEvents.set('onUpdate', false);

	if (_cutsceneSkipText == null)
	{
		_cutsceneSkipText = new FlxText(0, 0, FlxG.width, Lang.str('cutscene_skip_double_tap', 'Tap two time to skip this cutscene'));
		_cutsceneSkipText.setFormat(Paths.font("liberbold.ttf"), 18, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_cutsceneSkipText.borderSize = 2;
		_cutsceneSkipText.scrollFactor.set();
		_cutsceneSkipText.y = FlxG.height - _cutsceneSkipText.height - 20;
		_cutsceneSkipText.camera = camOther;
		_cutsceneSkipText.zIndex = 999;
		_cutsceneSkipText.alpha = 0;
		_cutsceneSkipText.visible = false;
		add(_cutsceneSkipText);
	}
}

function onUpdate(elapsed)
{
	if (!_cutsceneSkipActive || _cutsceneSkipDone) return;

	final halfway = _cutsceneSkipStart + (_cutsceneSkipEnd - _cutsceneSkipStart) * 0.5;
	final inWindow = Conductor.songPosition >= _cutsceneSkipStart && Conductor.songPosition < halfway;

	if (inWindow && !_cutsceneSkipTextShown)
	{
		_cutsceneSkipTextShown = true;
		_cutsceneSkipText.visible = true;
		FlxTween.cancelTweensOf(_cutsceneSkipText);
		_cutsceneSkipText.alpha = 0;
		FlxTween.tween(_cutsceneSkipText, {alpha: 1}, 0.6);
	}
	else if (!inWindow && _cutsceneSkipTextShown)
	{
		_cutsceneSkipTextShown = false;
		FlxTween.cancelTweensOf(_cutsceneSkipText);
		FlxTween.tween(_cutsceneSkipText, {alpha: 0}, 0.4, {onComplete: function() _cutsceneSkipText.visible = false});
	}

	if (!inWindow) return;

	for (touch in FlxG.touches.list)
	{
		if (touch.justPressed)
		{
			if (Conductor.songPosition - _cutsceneSkipLastTapPos < _cutsceneSkipWindowMs)
				_doCutsceneSkip();
			else
				_cutsceneSkipLastTapPos = Conductor.songPosition;
			break;
		}
	}
}

function _doCutsceneSkip():Void
{
	if (_cutsceneSkipDone) return;
	_cutsceneSkipDone = true;
	_cutsceneSkipActive = false;
	_cutsceneSkipTextShown = false;
	script.suppressedEvents.set('onUpdate', true);

	FlxTween.cancelTweensOf(_cutsceneSkipText);
	_cutsceneSkipText.visible = false;
	_cutsceneSkipText.alpha = 0;

	if (_cutsceneSkipCallback != null) _cutsceneSkipCallback();
}
