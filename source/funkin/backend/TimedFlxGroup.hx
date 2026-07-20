package funkin.backend;

import flixel.FlxBasic;
import flixel.group.FlxGroup.FlxTypedGroup;

/**
 * Drop-in replacement for `FlxTypedGroup<T>` that wraps its own update() in
 * a profBegin/profEnd span under a fixed tag. PlayState's `notes`/`susTrails`/
 * `playFields` are plain FlxTypedGroup instances added as top-level state
 * members -- their own share of the generic per-member update cascade
 * ('flxMemberLoop', see MusicBeatState.update()) was invisible before this,
 * same gap Stage.hx/TouchInputManager.hx's own update() overrides existed
 * to close for the objects they wrap. Doesn't touch what happens INSIDE the
 * loop (each child's own update() is untouched, still exactly what
 * FlxTypedGroup.update() already does) -- only times the group's own call as
 * a whole, so this doesn't multiply per-note overhead the way tagging every
 * individual Note/SustainTrail would.
 */
class TimedFlxGroup<T:FlxBasic> extends FlxTypedGroup<T>
{
	final _profTag:String;

	public function new(profTag:String, maxSize:Int = 0)
	{
		super(maxSize);
		_profTag = profTag;
	}

	override function update(elapsed:Float):Void
	{
		#if android SystemMonitor.profBegin(_profTag); #end
		super.update(elapsed);
		#if android SystemMonitor.profEnd(); #end
	}
}
