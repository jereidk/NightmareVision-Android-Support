package funkin.backend;

import flixel.addons.transition.FlxTransitionSprite.TransitionStatus;
import funkin.input.Controls;

// incredibly basic. if you want to apply more to this feel free
class BaseTransitionState extends MusicBeatSubstate
{
	public var finishCallback:Void->Void = null;

	final status:TransitionStatus;

	public function new(status:TransitionStatus, ?finishCallback:Void->Void)
	{
		this.status = status;
		if (finishCallback != null) this.finishCallback = finishCallback;

		#if mobile
		// MusicBeatSubstate's own constructor (via super() below)
		// unconditionally sets isInSubstate = true, which routes
		// Controls.mobilePadJustReleased()/etc. to THIS substate's
		// virtualPad -- but a transition never creates one (it's a purely
		// visual fade with no navigation of its own), so for however long it
		// stays open (SwipeTransition's tween runs ~0.5s), the D-pad/A/B on
		// whatever real state or substate is actually underneath goes
		// completely dead. Every single state switch opens one of these
		// (see MusicBeatState.create()/startOutro()), so this isn't a rare
		// edge case -- it's a beat of dead input after every transition.
		// Capture/restore around super() so this substate is fully
		// transparent to virtual-pad routing instead.
		final wasInSubstate = Controls.instance?.isInSubstate ?? false;
		#end

		super();

		#if mobile
		if (Controls.instance != null) Controls.instance.isInSubstate = wasInSubstate;
		#end
	}
	
	/**
	 * ends the transition
	 */
	public function dispatchFinish()
	{
		if (finishCallback != null) finishCallback();
		FlxTimer.wait(0, close);
	}
}
