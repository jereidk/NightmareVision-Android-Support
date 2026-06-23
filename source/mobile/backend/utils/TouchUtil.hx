package mobile.backend.utils;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
#if FLX_TOUCH
import flixel.input.touch.FlxTouch;
#end
import flixel.input.mouse.FlxMouse;
import flixel.math.FlxPoint;

/**
 * Utility class for handling touch input within the FlxG context.
 * Based on FunkinCrew/Funkin TouchUtil with additions.
 */
class TouchUtil
{
/**
 * Indicates if any touch is currently pressed.
 */
public static var pressed(get, never):Bool;

/**
 * Indicates if any touch was just pressed this frame.
 */
public static var justPressed(get, never):Bool;

/**
 * Indicates if any touch was just released this frame.
 */
public static var justReleased(get, never):Bool;

/**
 * Indicates if any touch is released this frame.
 */
public static var released(get, never):Bool;

/**
 * Indicates if any touch is moved this frame.
 */
public static var justMoved(get, never):Bool;

/**
 * The first touch in the FlxG.touches list.
 */
#if mobile
public static var touch(get, never):FlxTouch;
#else
public static var touch(get, never):FlxMouse;
#end

/**
 * Checks if the specified object overlaps with any active touch.
 */
public static function overlaps(?object:FlxBasic, ?camera:FlxCamera):Bool
{
if (object == null || touch == null) return false;
return touch.overlaps(object, camera ?? object.camera);
}

/**
 * Checks if the specified object overlaps with any active touch using precise point checks.
 */
public static function overlapsComplex(?object:FlxObject, ?camera:FlxCamera):Bool
{
if (object == null || touch == null) return false;
if (camera == null) camera = object.cameras[0];
@:privateAccess
return object.overlapsPoint(touch.getWorldPosition(camera, object._point), true, camera);
}

/**
 * Checks if the specified object overlaps with a specific point using precise point checks.
 */
public static function overlapsComplexPoint(?object:FlxObject, point:FlxPoint, ?inScreenSpace:Bool = false, ?camera:FlxCamera):Bool
{
if (object == null || point == null) return false;
if (camera == null) camera = object.cameras[0];
@:privateAccess
if (object.overlapsPoint(point, inScreenSpace, camera))
{
point.putWeak();
return true;
}
point.putWeak();
return false;
}

/**
 * A helper function to check if the selection is pressed using touch.
 * Returns true when touch is released within 200ms and overlaps the object.
 */
public static function pressAction(?object:FlxBasic, ?camera:FlxCamera, useOverlapsComplex:Bool = true):Bool
{
if (TouchUtil.touch == null || (TouchUtil.touch != null && TouchUtil.touch.ticksDeltaSincePress > 200)) return false;

if (object == null && camera == null)
{
return justReleased;
}
else if (object != null)
{
final overlapsObject:Bool = useOverlapsComplex ? overlapsComplex(cast(object, FlxObject), camera) : overlaps(object, camera);
return justReleased && overlapsObject;
}

return false;
}

// Getters
@:noCompletion
inline static function get_justMoved():Bool return touch != null && touch.justMoved;

@:noCompletion
inline static function get_pressed():Bool return touch != null && touch.pressed;

@:noCompletion
inline static function get_justPressed():Bool return touch != null && touch.justPressed;

@:noCompletion
inline static function get_justReleased():Bool return touch != null && touch.justReleased;

@:noCompletion
static function get_released():Bool return touch != null && touch.released;

#if mobile
@:noCompletion
static function get_touch():FlxTouch
{
for (touch in FlxG.touches.list)
{
if (touch != null) return touch;
}
return FlxG.touches.getFirst();
}
#else
@:noCompletion
static function get_touch():FlxMouse
{
FlxG.mouse.visible = true;
return FlxG.mouse;
}
#end
}
