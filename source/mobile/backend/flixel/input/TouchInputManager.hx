package mobile.backend.flixel.input;

import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import mobile.backend.flixel.input.FlxMobileInputID;
import mobile.backend.flixel.FlxButton;
import haxe.ds.Map;
import funkin.backend.SystemMonitor;

/**
 * Virtual button manager for mobile devices
 * @Authors: StarNova (Cream.BR)
 */
class TouchInputManager extends FlxTypedSpriteGroup<FlxButton>
{
	/**
	 * A dictionary that maps unique IDs to the actual instances of the buttons
	 */
	public var activeButtons:Map<FlxMobileInputID, FlxButton> = new Map<FlxMobileInputID, FlxButton>();

	// Resolved once instead of on every profBegin() call in update()/draw()
	// below -- Type.getClassName(Type.getClass(this)) doesn't change for the
	// lifetime of the instance.
	#if android
	final _profTagUpdate:String;
	final _profTagDraw:String;
	#end

	public function new()
	{
		super();
		RawTouchClock.init();
		refreshMappedButtons();
		#if android
		final className = Type.getClassName(Type.getClass(this));
		_profTagUpdate = 'touchInput:$className';
		_profTagDraw = 'touchInput:$className:draw';
		#end
	}

	// Base class for MobileVirtualPad (the on-screen D-pad/action buttons)
	// and MobileHitbox (the note-tap zones) -- neither overrode
	// update()/draw() before, so per-touch hit-testing and the buttons' own
	// draw cost were invisible, folded into whichever tag wraps the generic
	// Flixel member loop that reaches them ('flxMemberLoop'/'draw' during
	// gameplay). Tagged by concrete class name so the breakdown can tell
	// which of the two (if either) is actually costing anything.
	override function update(elapsed:Float):Void
	{
		#if android SystemMonitor.profBegin(_profTagUpdate); #end
		super.update(elapsed);
		#if android SystemMonitor.profEnd(); #end
	}

	override function draw():Void
	{
		#if android SystemMonitor.profBegin(_profTagDraw); #end
		super.draw();
		#if android SystemMonitor.profEnd(); #end
	}

	public inline function isPressed(id:FlxMobileInputID):Bool
	{
		return checkButtonState(id, PRESSED);
	}

	public inline function isJustPressed(id:FlxMobileInputID):Bool
	{
		return checkButtonState(id, JUST_PRESSED);
	}

	public inline function isJustReleased(id:FlxMobileInputID):Bool
	{
		return checkButtonState(id, JUST_RELEASED);
	}

	public inline function isAnyPressed(ids:Array<FlxMobileInputID>):Bool
	{
		return checkArrayState(ids, PRESSED);
	}

	public inline function isAnyJustPressed(ids:Array<FlxMobileInputID>):Bool
	{
		return checkArrayState(ids, JUST_PRESSED);
	}

	public inline function isAnyJustReleased(ids:Array<FlxMobileInputID>):Bool
	{
		return checkArrayState(ids, JUST_RELEASED);
	}

	/**
	 * Returns the millisecond timestamp (haxe.Timer.stamp() × 1000) of the last
	 * press event for the given input ID, captured inside the button's onDown
	 * handler rather than at frame boundaries. Returns 0 if the button has never
	 * been pressed or the ID is not mapped.
	 */
	public function getPressTimestampMs(id:FlxMobileInputID):Float
	{
		var btn = activeButtons.get(id);
		return btn != null ? btn.pressTimestampMs : 0.0;
	}

	/** Returns the millisecond timestamp of the last release for the given input ID. */
	public function getReleaseTimestampMs(id:FlxMobileInputID):Float
	{
		var btn = activeButtons.get(id);
		return btn != null ? btn.releaseTimestampMs : 0.0;
	}

	/**
	 * Returns the elapsed milliseconds since the given input was last pressed.
	 * Returns -1 if the input has never been pressed or is not mapped.
	 * Use this for timing-sensitive gameplay calculations.
	 *
	 * @param id The input ID to check
	 * @return Time elapsed since last press in milliseconds, or -1 if unavailable
	 */
	public function getTimeSincePressMs(id:FlxMobileInputID):Float
	{
		var pressTs = getPressTimestampMs(id);
		if (pressTs <= 0) return -1;
		return (haxe.Timer.stamp() * 1000.0) - pressTs;
	}

	/**
	 * Returns the elapsed milliseconds since the given input was last released.
	 * Returns -1 if the input has never been released or is not mapped.
	 *
	 * @param id The input ID to check
	 * @return Time elapsed since last release in milliseconds, or -1 if unavailable
	 */
	public function getTimeSinceReleaseMs(id:FlxMobileInputID):Float
	{
		var releaseTs = getReleaseTimestampMs(id);
		if (releaseTs <= 0) return -1;
		return (haxe.Timer.stamp() * 1000.0) - releaseTs;
	}

	/**
	 * Returns whether the input was pressed within the given time window (in milliseconds).
	 * Useful for checking "ghost taps" or forgiving input windows.
	 *
	 * @param id The input ID to check
	 * @param windowMs Time window in milliseconds
	 * @return True if pressed within the window
	 */
	public inline function wasPressedWithinMs(id:FlxMobileInputID, windowMs:Float):Bool
	{
		var elapsed = getTimeSincePressMs(id);
		return elapsed >= 0 && elapsed <= windowMs;
	}

	/**
	 * Returns whether the input was released within the given time window (in milliseconds).
	 * Useful for checking quick tap releases.
	 *
	 * @param id The input ID to check
	 * @param windowMs Time window in milliseconds
	 * @return True if released within the window
	 */
	public inline function wasReleasedWithinMs(id:FlxMobileInputID, windowMs:Float):Bool
	{
		var elapsed = getTimeSinceReleaseMs(id);
		return elapsed >= 0 && elapsed <= windowMs;
	}

	/**
	 * Checks the status of a specific button, or handles special cases such as ANY and NONE
	 */
	public function checkButtonState(id:FlxMobileInputID, state:InputState = JUST_PRESSED):Bool
	{
		switch (id)
		{
			case FlxMobileInputID.ANY:
				for (btn in activeButtons)
				{
					if (getRawState(btn, state)) return true;
				}
				return false;

			case FlxMobileInputID.NONE:
				return false;

			default:
				var btn = activeButtons.get(id);
				if (btn != null)
				{
					return getRawState(btn, state);
				}
		}
		return false;
	}

	function checkArrayState(ids:Array<FlxMobileInputID>, state:InputState = JUST_PRESSED):Bool
	{
		if (ids == null || ids.length == 0) return false;

		for (id in ids)
		{
			if (checkButtonState(id, state)) return true;
		}

		return false;
	}

	/**
	 * Returns the button's boolean property based on the desired state
	 */
	inline function getRawState(btn:FlxButton, state:InputState):Bool
	{
		return switch (state)
		{
			case PRESSED:       btn.pressed;
			case JUST_PRESSED:  btn.justPressed;
			case JUST_RELEASED: btn.justReleased;
		}
	}

	/**
	 * Scan all buttons added to the group and catalog them in the Map
	 */
	public function refreshMappedButtons():Void
	{
		activeButtons.clear();
		
		forEachExists(function(btn:FlxButton)
		{
			if (btn.IDs != null)
			{
				for (id in btn.IDs)
				{
					if (!activeButtons.exists(id))
					{
						activeButtons.set(id, btn);
					}
				}
			}
		});
	}
}

/**
 * Possible input states
 */
enum InputState
{
	PRESSED;
	JUST_PRESSED;
	JUST_RELEASED;
}
