package mobile.controls;

import flixel.FlxG;
import flixel.FlxCamera;

import funkin.data.ClientPrefs;
import mobile.controls.MobileVirtualPad;

/**
 * Owns the single, app-lifetime MobileVirtualPad instance and its overlay
 * camera. Registered on FlxG.plugins instead of any FlxState's own group,
 * so its update()/draw() run every frame unconditionally -- immune to
 * persistentUpdate/persistentDraw, substate nesting, and FlxG.cameras.reset()
 * on state switches. Those three were exactly what broke the old
 * per-state-owned/"borrowed" pad: a borrowed pad stayed a member of
 * whichever state originally created it, so pausing (persistentUpdate =
 * false) silently stopped it from ever receiving update()/touch again while
 * still drawing, and a full state switch (FlxG.cameras.reset()) wiped its
 * camera with no way back.
 *
 * Every caller just requests a shape (`request`) and releases it
 * (`release`), passing itself as `owner`. The ownership stack is keyed by
 * object identity, not call order, so release() finds and removes the
 * right entry even when states are torn down out of LIFO order (e.g. a
 * pause-menu "Back to Menu" switching state directly while the substate
 * chain above it is still open).
 */
class VirtualPadManager
{
	static var pad:MobileVirtualPad;
	static var cam:FlxCamera;
	static var _cameraHookBound:Bool = false;

	static var _stack:Array<{owner:Dynamic, dpad:MobileDPadMode, action:MobileActionMode, forGameplay:Bool}> = [];

	public static var instance(get, never):MobileVirtualPad;
	static function get_instance():MobileVirtualPad return pad;

	/** The pad's dedicated overlay camera -- e.g. so a caller can sync its alpha to a fade. Null until the first request(). */
	public static var camera(get, never):FlxCamera;
	static function get_camera():FlxCamera return cam;

	static function _ensure():Void
	{
		if (pad != null) return;

		pad = new MobileVirtualPad(NONE, NONE, false);
		pad.visible = false;
		FlxG.plugins.addPlugin(pad);

		_ensureCamera();

		if (!_cameraHookBound)
		{
			_cameraHookBound = true;
			// FunkinGame.switchState() calls FlxG.cameras.reset() on every full
			// state switch -- and CameraFrontEnd.remove()'s default Destroy =
			// true means that doesn't just clear the list, it fully destroys
			// every camera in it (FlxCamera.destroy() nulls out flashSprite,
			// the OpenFL display object CameraFrontEnd.add() re-attaches via
			// addChildAt()). Re-adding that same, now-destroyed camera object
			// crashed immediately -- "Error #2007: Parameter child must be
			// non-null" -- the instant Flixel tried to addChildAt(null). Needs
			// a genuinely fresh FlxCamera every switch, not a re-add of the
			// old one; see _ensureCamera(). preStateSwitch fires right after
			// FlxG.cameras.reset() but before the new state's create() runs,
			// so the pad already has a working camera by the time anything
			// calls request() during that create().
			FlxG.signals.preStateSwitch.add(_ensureCamera);
		}
	}

	static function _ensureCamera():Void
	{
		if (cam != null && FlxG.cameras.list.indexOf(cam) != -1) return; // still alive and registered

		cam = new FlxCamera();
		cam.bgColor.alpha = 0;
		FlxG.cameras.add(cam, false);
		if (pad != null) pad.cameras = [cam];
	}

	public static function request(owner:Dynamic, dpad:MobileDPadMode, action:MobileActionMode, forGameplay:Bool = false, forceShow:Bool = false):Void
	{
		final modeCheck = forGameplay ? ClientPrefs.gameInputMode : ClientPrefs.navInputMode;
		if (!forceShow && modeCheck != 'Virtual Pad') return;

		_ensure();

		// Replace any earlier entry from this same owner instead of stacking
		// a duplicate (e.g. a nav-mode change re-requesting while already open).
		_removeFromStack(owner);

		_stack.push({owner: owner, dpad: dpad, action: action, forGameplay: forGameplay});
		pad.visible = true;
		pad.rebuild(dpad, action, forGameplay);
	}

	public static function release(owner:Dynamic):Void
	{
		if (pad == null) return;

		_removeFromStack(owner);

		if (_stack.length > 0)
		{
			final top = _stack[_stack.length - 1];
			pad.rebuild(top.dpad, top.action, top.forGameplay);
		}
		else
		{
			pad.visible = false;
		}
	}

	static function _removeFromStack(owner:Dynamic):Void
	{
		var i = _stack.length;
		while (--i >= 0)
		{
			if (_stack[i].owner == owner)
			{
				_stack.splice(i, 1);
				break;
			}
		}
	}
}
