package funkin.scripts;

import extensions.hscript.Sharables;
import extensions.hscript.InterpEx;

import flixel.util.FlxDestroyUtil;
import flixel.util.FlxDestroyUtil.IFlxDestroyable;

/**
 * Container of `FunkinScript` instances
 *
 * idea from friens static fyr thanks
 */
@:nullSafety(Strict)
class ScriptGroup implements IFlxDestroyable
{
	/** Set true to log script calls slower than slowThresholdMs to trace/logcat */
	public static var timingEnabled:Bool = false;
	/** Minimum milliseconds before a script call is logged (when timingEnabled) */
	public static var slowThresholdMs:Float = 1.0;

	static final _emptyExclusions:Array<String> = [];

	public var scriptShareables:Sharables = new Sharables();
	
	/**
	 * Global interp parent applied to all scripts in the group
	 */
	public var parent(default, set):Dynamic;
	
	function set_parent(value:Dynamic)
	{
		parent = value;
		@:privateAccess
		for (i in members)
		{
			final interp:InterpEx = cast i.interp;
			if (interp.parent != parent)
			{
				interp.parent = parent;
				interp.sharedFields = scriptShareables;
			}
		}
		
		return parent;
	}
	
	/**
	 * array of all `FunkinScript` instances
	 */
	public var members:Array<FunkinScript> = [];

	// Memoizes "does any current member implement this event" so repeated,
	// per-frame calls (e.g. onMoveCamera, called every frame regardless of
	// whether any mod actually hooks it) can skip the full members loop —
	// and the per-script FunkinScript.exists() lookup inside it — once the
	// answer is known. exists() reads a script's own interp.variables map,
	// which is fixed once the script is parsed, so the answer only changes
	// when the member list itself changes (see addScript()/clear() below).
	final _hasHookCache:Map<String, Bool> = new Map();

	public function new(?parent:Dynamic)
	{
		@:privateAccess
		if (FlxG.game != null)
		{
			parent ??= FlxG.state;
		}
		
		@:bypassAccessor this.parent = parent;
	}
	
	/**
	 * Adds a new script to the group
	 * @param script 
	 */
	public function addScript(script:Null<FunkinScript>, allowDupeNames:Bool = false):Bool
	{
		if (script == null || (!allowDupeNames && exists(script.name))) return false;

		@:privateAccess
		final interp:InterpEx = cast script.interp;
		if (interp.parent != parent) interp.parent = parent;
		interp.sharedFields = scriptShareables;
		members.push(script);
		_hasHookCache.clear(); // the new script may implement events previously cached as unheard
		return true;
	}
	
	@:inheritDoc(funkin.scripts.FunkinScript.set)
	public function set(varName:String, arg:Dynamic)
	{
		if (members.length == 0) return;
		for (i in members)
		{
			i.set(varName, arg);
		}
	}

	@:inheritDoc(funkin.scripts.FunkinScript.call)
	public function call(event:String, ?args:Array<Dynamic>, ignoreStops:Bool = false, ?exclusions:Array<String>):Dynamic
	{
		// Fast path: skip all allocations when no scripts are loaded (common during vanilla gameplay).
		if (members.length == 0) return ScriptConstants.CONTINUE_FUNC;

		// Fast path: nothing currently loaded implements this event at all — skip the
		// members loop (and every per-script exists() lookup in it) entirely. Matters
		// most for hooks fired unconditionally every frame (e.g. onMoveCamera) when no
		// mod actually listens to them.
		if (_hasHookCache.get(event) == false) return ScriptConstants.CONTINUE_FUNC;

		exclusions ??= _emptyExclusions;

		var returnVal:Dynamic = ScriptConstants.CONTINUE_FUNC;
		var anyListener = false;

		for (i in members)
		{
			if (i == null || !i.exists(event) || exclusions.contains(i.name)) continue;

			// Set as soon as we know the answer, not after the loop — a halting
			// return below exits early, and the cache should still capture
			// "yes, something listens" even on that path.
			anyListener = true;
			_hasHookCache.set(event, true);

			final _t = timingEnabled ? haxe.Timer.stamp() : 0.0;

			var ret:Dynamic = i.call(event, args)?.returnValue;

			if (timingEnabled)
			{
				final _ms = (haxe.Timer.stamp() - _t) * 1000.0;
				if (_ms >= slowThresholdMs)
					trace('[ScriptPerf] ${i.name}::$event ${Math.round(_ms * 10) / 10}ms');
			}

			if (ret != null)
			{
				if (ScriptConstants.halting(ret) && !ignoreStops) return ret;

				if (ret != ScriptConstants.CONTINUE_FUNC) returnVal = ret;
			}
		}

		_hasHookCache.set(event, anyListener);

		return returnVal;
	}
	
	/**
	 * returns a script by name. returns `null` if it cannot be found
	 */
	public function getScript(name:String):Null<FunkinScript>
	{
		for (script in members)
			if (script.name == name) return script;
			
		return null;
	}
	
	/**
	 * Is true if a script with the given name exists
	 */
	public function exists(name:String):Bool
	{
		for (script in members)
			if (script.name == name) return true;
		return false;
	}
	
	/**
	 * Destroys all members
	 */
	public function destroy()
	{
		scriptShareables.clear();
		@:nullSafety(Off)
		scriptShareables = null;
		members = FlxDestroyUtil.destroyArray(members);
		@:bypassAccessor parent = null;
	}
	
	public function clear(callOnDestroy:Bool = true)
	{
		if (callOnDestroy) call('onDestroy', null, true);
		var toDestroy = members.copy();
		members = [];
		_hasHookCache.clear();
		for (script in toDestroy)
			script.destroy();
	}
}
