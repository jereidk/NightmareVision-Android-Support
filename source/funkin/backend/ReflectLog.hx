package funkin.backend;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Dedicated log for HScript's dynamic `object.field` reflection breadcrumbs
 * (see SystemMonitor.logReflectAccess()). Kept out of sysmon.log entirely so
 * it can't compete with the actually-useful system diagnostics for rotation
 * space -- even narrowed to just the null-target/PlayableSong cases,
 * mixing it into the same file meant a burst of reflection breadcrumbs
 * could still rotate away GC/memory/FPS entries that matter more.
 *
 * Android-only, dev-mode-only, same gating as GameLogger/SystemMonitor.
 */
class ReflectLog
{
	static final MAX_BYTES:Int = 512 * 1024; // 512 KB -- narrow diagnostic trail, not a general log

	#if android
	static var logPath:String = '';
	#end

	public static function init():Void
	{
		#if android
		if (ClientPrefs == null || !ClientPrefs.inDevMode) return;

		final dir:String = mobile.backend.StorageSystem.getDirectory();
		logPath = dir + 'reflect.log';
		final oldPath = dir + 'reflect.log.old';

		try
		{
			if (FileSystem.exists(logPath) && FileSystem.stat(logPath).size > MAX_BYTES)
			{
				if (FileSystem.exists(oldPath)) FileSystem.deleteFile(oldPath);
				FileSystem.rename(logPath, oldPath);
			}
		}
		catch (e:Dynamic) {}

		_write('============================================================');
		_write('SESSION START  ' + Date.now().toString());
		_write('============================================================');
		#end
	}

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
		if (logPath.length == 0) return;
		try
		{
			final out = File.append(logPath, false);
			out.writeString(line + '\n');
			out.flush();
			out.close();
		}
		catch (e:Dynamic) {}
		#end
	}
}
