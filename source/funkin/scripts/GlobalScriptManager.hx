package funkin.scripts;

import flixel.FlxG;
import flixel.util.FlxDestroyUtil;
import haxe.io.Path;
import funkin.backend.Logger;
#if mobile
import mobile.backend.StorageSystem;
#end

using StringTools;

/**
 * Manages global scripts that persist across all states.
 *
 * Global scripts are loaded from external storage `scripts/` (or APK assets at startup) and
 * survive state transitions — unlike per-state scripts which are destroyed
 * when the state changes.
 *
 * Hooks dispatched (in addition to per-state scriptGroup):
 *   onStateCreate(stateInstance)  – when a new state is created
 *   onStateDestroy(stateInstance) – right before a state is destroyed
 *   onCreate()                    – same per-state timing
 *   onUpdate(elapsed)             – every frame
 *   onDestroy()                   – when the manager itself is destroyed
 *
 * Usage from inside a global script (HScript):
 *   function onStateCreate(state) {
 *       trace('Entered: ' + Type.getClassName(Type.getClass(state)));
 *   }
 *
 * Global scripts can also define functions that other scripts can call
 * via scriptShareables.
 */
@:nullSafety(Strict)
class GlobalScriptManager
{
	/** Singleton instance, created in Main.hx. */
	public static var instance(default, null):Null<GlobalScriptManager> = null;

	/** The persistent script group shared across all states. */
	public var scriptGroup(default, null):ScriptGroup;

	/**
	 * Initializes the global script manager.
	 * Call once from Main.hx at startup.
	 */
	public static function init():Void
	{
		if (instance == null)
		{
			instance = new GlobalScriptManager();
			Logger.log('[GlobalScriptManager] Initialized', NOTICE);
		}
	}

	function new()
	{
		scriptGroup = new ScriptGroup();

		// Automatically load all scripts from assets/scripts/global/
		_loadScripts();

		// Update parent reference when state changes
		FlxG.signals.preStateSwitch.add(function()
		{
			_updateParent();
		});
	}

	/**
	 * Loads all `.hx` script files from the global scripts directory.
	 */
	function _loadScripts():Void
	{
		#if sys
		var checkedDirs = new haxe.ds.StringMap();

		// Check external storage first (mobile only) — 'scripts/' overrides APK versions
		#if mobile
		var extDir = Path.addTrailingSlash(StorageSystem.getDirectory()) + 'scripts/';
		if (checkedDirs.get(extDir) == null)
		{
			checkedDirs.set(extDir, true);
			_loadScriptsFrom(extDir);
		}
		#end

		// Check virtual assets path (APK) — lower priority
		var globalDir = Paths.getCorePath('scripts/global/');
		if (checkedDirs.get(globalDir) == null)
		{
			checkedDirs.set(globalDir, true);
			_loadScriptsFrom(globalDir);
		}
		#end
	}

	/**
	 * Loads all `.hx` scripts from a given directory path.
	 */
	#if sys
	function _loadScriptsFrom(dirPath:String):Void
	{
		if (sys.FileSystem.exists(dirPath))
		{
			var files = sys.FileSystem.readDirectory(dirPath);
			var loaded = 0;
			for (file in files)
			{
				if (!FunkinScript.isHxFile(file)) continue;

				var fullPath = '$dirPath$file';
				var scriptName = 'global_' + haxe.io.Path.withoutExtension(file);

				if (scriptGroup.exists(scriptName)) continue;

				var script = FunkinScript.fromFile(fullPath, scriptName);
				if (script != null && !script.__garbage)
				{
					scriptGroup.parent = FlxG.state;
					scriptGroup.addScript(script);
					loaded++;
					Logger.log('[GlobalScriptManager] Loaded: $file', NOTICE);
				}
			}
			Logger.log('[GlobalScriptManager] Loaded $loaded global scripts', NOTICE);
		}
	}
	#end

	/**
	 * Updates the parent reference so global scripts always access
	 * the current state's properties.
	 */
	public function _updateParent():Void
	{
		if (FlxG.state != null)
		{
			scriptGroup.parent = FlxG.state;
		}
	}

	/**
	 * Sets a variable in all global scripts.
	 */
	public function set(varName:String, value:Dynamic):Void
	{
		scriptGroup.set(varName, value);
	}

	/**
	 * Calls a hook on all global scripts.
	 * Returns the return value or ScriptConstants.CONTINUE_FUNC.
	 */
	public function call(event:String, ?args:Array<Dynamic>, ignoreStops:Bool = false):Dynamic
	{
		return scriptGroup.call(event, args, ignoreStops);
	}

	/**
	 * Called by MusicBeatState when a state is created.
	 */
	public function onStateCreate(state:Dynamic):Void
	{
		_updateParent();
		scriptGroup.set('state', state);
		scriptGroup.call('onStateCreate', [state]);
	}

	/**
	 * Called by MusicBeatState when a state is destroyed.
	 */
	public function onStateDestroy(state:Dynamic):Void
	{
		scriptGroup.call('onStateDestroy', [state]);
	}

	/**
	 * Called by MusicBeatState on every frame.
	 */
	public function onUpdate(elapsed:Float):Void
	{
		scriptGroup.call('onUpdate', [elapsed]);
	}

	/**
	 * Cleans up all global scripts.
	 * Call on game shutdown.
	 */
	public function destroy():Void
	{
		scriptGroup.call('onDestroy');
		scriptGroup = FlxDestroyUtil.destroy(scriptGroup);
		instance = null;
	}
}
