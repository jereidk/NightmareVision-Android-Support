package mobile.psychlua;

import psychlua.FunkinLua;

class MobileFunctions
{
	public static function implement(funk:FunkinLua)
	{
		#if LUA_ALLOWED
		var lua:State = funk.lua;

		#if mobile
		Lua_helper.add_callback(lua, "touchUtilJustPressed", TouchUtil.justPressed);
		Lua_helper.add_callback(lua, "touchUtilPressed", TouchUtil.pressed);
		Lua_helper.add_callback(lua, "touchUtilJustReleased", TouchUtil.justReleased);
		Lua_helper.add_callback(lua, "setHitboxVisible", function(visible:Bool = false):Void
		{
			// hitbox is null when gameInputMode is 'Virtual Pad' or 'Note Tap'
			// (neither uses a MobileHitbox at all) -- this call would already
			// have crashed for the former; guard both now.
			if (PlayState.instance?.hitbox != null) PlayState.instance.hitbox.visible = visible;
		});
		Lua_helper.add_callback(lua, "enableKeyboard", function()
		{
			FlxG.stage.window.textInputEnabled = true;
		});
		#end
		#end
	}
}
