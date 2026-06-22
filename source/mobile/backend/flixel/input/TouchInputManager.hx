package mobile.backend.flixel.input;

import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import mobile.backend.flixel.input.FlxMobileInputID;
import mobile.backend.flixel.FlxButton;
import haxe.ds.Map;

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

	public function new()
	{
		super();
		refreshMappedButtons();
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
