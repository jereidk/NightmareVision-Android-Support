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

	// Reused for scriptGroup.call('onUpdate', ...) below instead of allocating
	// a fresh [elapsed] array every frame.
	final _updateArgs:Array<Dynamic> = [0.0];

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

		// Update parent reference after state changes so global scripts
		// reference the new state, not the outgoing one.
		FlxG.signals.postStateSwitch.add(function()
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

				var script = FunkinScript.fromFile(fullPath, scriptName, null, scriptGroup.scriptShareables);
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
	 *
	 * Dev-only: reloads every global script from disk first, so editing a
	 * file in the external `scripts/` folder takes effect on the next state
	 * entry (e.g. backing out to a menu and back into a song) instead of
	 * requiring a full app restart -- the previous behaviour, since
	 * `_loadScripts()` only ever ran once from `init()`.
	 */
	public function onStateCreate(state:Dynamic):Void
	{
		if (funkin.data.ClientPrefs.inDevMode) reload();

		_updateParent();
		scriptGroup.set('state', state);
		scriptGroup.call('onStateCreate', [state]);
	}

	/**
	 * Tears down and re-scans all global scripts from disk (external
	 * storage first, then the bundled fallback) -- see `onStateCreate()`'s
	 * doc comment for why this runs automatically in dev mode.
	 */
	public function reload():Void
	{
		scriptGroup.call('onDestroy');
		scriptGroup = FlxDestroyUtil.destroy(scriptGroup);
		scriptGroup = new ScriptGroup();
		_loadScripts();
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
		_updateArgs[0] = elapsed;
		scriptGroup.call('onUpdate', _updateArgs);
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
