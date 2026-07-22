package mobile.backend.flixel.input;

import openfl.events.TouchEvent;
import flixel.FlxG;

/**
 * Records the true OS-event timestamp of each touch press, independent of
 * Flixel's per-frame button polling.
 *
 * `FlxButton.onDownHandler()` only runs once a frame notices the touch via
 * `checkTouchOverlap()`, so `pressTimestampMs` (previously `haxe.Timer.stamp()`
 * read inside that handler) reflects when the frame polled the touch, not when
 * the OS actually delivered it - on a 60fps frame that gap can be up to ~16ms,
 * enough to matter for note-hit timing. `TouchEvent.TOUCH_BEGIN` fires
 * asynchronously at the real event time (confirmed in FlxTouchManager, which
 * already listens to it to update `FlxInput` state), so listening for it here
 * and stamping it immediately gives every button a true event-time timestamp
 * to look up instead.
 */
class RawTouchClock
{
	static var _pressTimes:Map<Int, Float> = new Map();
	static var _initialized:Bool = false;

	public static function init():Void
	{
		if (_initialized) return;
		_initialized = true;
		FlxG.stage.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
	}

	static function onTouchBegin(event:TouchEvent):Void
	{
		_pressTimes.set(event.touchPointID, lime.system.System.getTimer());
	}

	/**
	 * True OS-event millisecond timestamp of the most recent TOUCH_BEGIN for
	 * this pointer ID, or -1 if none was ever recorded (e.g. mouse input).
	 */
	public static function getPressTime(touchPointID:Int):Float
	{
		var t = _pressTimes.get(touchPointID);
		return t != null ? t : -1;
	}
}
