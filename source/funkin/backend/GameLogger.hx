package funkin.backend;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Persistent rolling log file. Android-only: writes every Logger and trace()
 * call to game.log in external storage (same folder as crash.log).
 *
 * Rotation: when game.log exceeds MAX_BYTES, it is renamed to game.log.old
 * (overwriting the previous .old) and a fresh game.log is started.
 * Maximum on-disk footprint: ~4 MB (two files of MAX_BYTES each).
 */
class GameLogger
{
	static final MAX_BYTES:Int = 2 * 1024 * 1024; // 2 MB per file

	#if android
	static var logPath:String = '';
	static var oldPath:String = '';
	#end

	/**
	 * Must be called once, as early as possible in Init.create().
	 * Opens (or rotates) game.log and installs the haxe.Log.trace interceptor.
	 */
	public static function init():Void
	{
		#if android
		final dir:String = mobile.backend.StorageSystem.getDirectory();
		logPath = dir + 'game.log';
		oldPath = dir + 'game.log.old';

		try
		{
			if (FileSystem.exists(logPath) && FileSystem.stat(logPath).size > MAX_BYTES)
			{
				if (FileSystem.exists(oldPath)) FileSystem.deleteFile(oldPath);
				FileSystem.rename(logPath, oldPath);
			}
		}
		catch (e:Dynamic) { Sys.println('[GameLogger] Failed to rotate log: ' + Std.string(e)); }

		_write('============================================================');
		_write('SESSION START  ' + Date.now().toString());
		_write('============================================================');

		// Chain onto whatever trace handler is already installed (including
		// DISABLE_TRACES no-ops) so we capture everything without breaking
		// any existing behaviour.
		final prev = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?pos:haxe.PosInfos)
		{
			prev(v, pos);
			_write(stamp() + ' [TRACE] ' + haxe.Log.formatOutput(v, pos));
		};
		#end
	}

	/**
	 * Called by Logger.log() to mirror every formatted log line to the file.
	 * The `line` string already contains the [WARN]/[ERROR]/etc. prefix.
	 */
	public static function write(line:String):Void
	{
		#if android
		if (logPath.length == 0) return;
		_write(stamp() + ' ' + line);
		#end
	}

	static function stamp():String
	{
		final d = Date.now();
		return '[' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()) + ']';
	}

	static inline function pad(n:Int):String
		return StringTools.lpad(Std.string(n), '0', 2);

	static function _write(line:String):Void
	{
		#if android
		try
		{
			final out = File.append(logPath, false);
			out.writeString(line + '\n');
			out.flush();
			out.close();
		}
		catch (e:Dynamic) { Sys.println('[GameLogger] Failed to write to log: ' + Std.string(e)); }
		#end
	}
}
