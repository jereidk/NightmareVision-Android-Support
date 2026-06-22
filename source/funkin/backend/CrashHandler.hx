package funkin.backend;

import flixel.addons.transition.FlxTransitionableState;

import openfl.events.ErrorEvent;
import openfl.errors.Error;
import openfl.events.UncaughtErrorEvent;
import openfl.Lib;

// todo more with this actually...
@:nullSafety
class CrashHandler
{
	static var _listenersRegistered:Bool = false;

	// Guard against FallbackState itself crashing and re-entering this handler
	// in a tight loop. Reset to false when the user taps "continue".
	static var _inFallback:Bool = false;

	#if (android && sys)
	// Updated every frame from the main thread via heartbeat().
	// The watchdog background thread checks if this goes stale (main thread blocked).
	static var _lastHeartbeat:Float = 0.0;

	public static function heartbeat():Void
	{
		_lastHeartbeat = haxe.Timer.stamp();
	}

	static function _startWatchdog(logDir:String):Void
	{
		sys.thread.Thread.create(() -> {
			while (true) {
				Sys.sleep(1.0);
				if (_lastHeartbeat > 0.0) {
					final delta = haxe.Timer.stamp() - _lastHeartbeat;
					if (delta > 8.0) {
						final msg = 'ANR WARNING: main thread blocked ${Std.int(delta)}s — possible ANR!';
						Sys.println(msg);
						try {
							var fo = sys.io.File.append(logDir + 'watchdog.log', false);
							fo.writeString('[${Date.now().toString()}] $msg\n');
							fo.close();
						} catch (_:Dynamic) {}
					}
				}
			}
		});
	}
	#end

	/**
	 * Register event listeners only — no file I/O, safe to call before storage
	 * permissions and directory init on mobile.
	 */
	public static function earlyInit():Void
	{
		if (_listenersRegistered) return;
		_listenersRegistered = true;
		// loaderInfo may not be fully initialised this early on some OpenFL builds;
		// wrap in try so we at least get the hxcpp handler even if this fails.
		try
		{
			Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		}
		catch (_:Dynamic) {}
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(onCriticalError);
		#end
	}

	/**
	 * Full init — calls earlyInit() then wires up the Java-level handlers on
	 * Android (install UncaughtExceptionHandler + read previous session crash)
	 * and starts the ANR watchdog thread.
	 * Requires storage to be available.
	 */
	public static function init()
	{
		earlyInit();
		#if android
		{
			final logDir  = mobile.backend.StorageSystem.getDirectory();
			final logPath = logDir + 'crash.log';
			// install() must run first — it sets sCrashLogPath so the tombstone
			// from readPreviousNativeCrash() knows where to save itself.
			mobile.backend.JavaCrashWrapper.install(logPath);
			final prevCrash = mobile.backend.JavaCrashWrapper.readPreviousNativeCrash();
			if (prevCrash != null)
				Logger.log('Previous session ended abnormally:\n$prevCrash', WARN);
			#if sys
			_startWatchdog(logDir);
			#end
		}
		#end
		Logger.log('CrashHandler: all handlers installed and active', NOTICE);
	}

	static function onCriticalError(message:String):Void
	{
		// Write crash.log directly BEFORE throwing — if this is a stack overflow
		// or memory corruption the Haxe exception machinery may not survive, so we
		// capture something now rather than rely on onUncaughtError.
		final report = 'C++ critical error: $message';
		try { Logger.log('CRITICAL: $report', ERROR); } catch (_:Dynamic) {}
		#if sys
		try
		{
			final logPath = #if android mobile.backend.StorageSystem.getDirectory() #else "./" #end + 'crash.log';
			_appendCrashLog(logPath, report);
		}
		catch (_:Dynamic) {}
		#end
		throw Std.string(message);
	}

	static function onUncaughtError(event:UncaughtErrorEvent)
	{
		// Double-fault guard: if FallbackState itself throws we end up here again.
		// Swallow the second crash rather than spinning in an infinite error loop.
		if (_inFallback)
		{
			event.preventDefault();
			event.stopImmediatePropagation();
			return;
		}
		_inFallback = true;

		FlxTransitionableState.skipNextTransIn = FlxTransitionableState.skipNextTransOut = true;

		var curFlxState:String = 'N/A';

		if (FlxG.state != null)
		{
			final cl = Type.getClass(FlxG.state);
			if (cl != null) curFlxState = 'FlxState: ' + (Type.getClassName(cl) ?? 'N/A');
			FlxG.state.persistentUpdate = FlxG.state.persistentDraw = false;
		}

		var message:String = Std.string(event.error);

		#if sys Sys.println #else trace #end (message);

		if (Std.isOfType(event.error, Error))
		{
			message = cast(event.error, Error).message;
		}
		else if (Std.isOfType(event.error, ErrorEvent))
		{
			message = cast(event.error, ErrorEvent).text;
		}

		var stackMessage:String = '';

		for (stackItem in haxe.CallStack.exceptionStack(true))
		{
			switch (stackItem)
			{
				case Method(classname, method):
					stackMessage += 'Function($classname.$method)';
				case CFunction:
					stackMessage += 'Function ';
				case Module(m):
					stackMessage += 'Module($m)';
				case LocalFunction(v):
					stackMessage += 'LocalFunction($v)';
				case FilePos(s, file, line, column):
					stackMessage += file + " (line " + line + ")";
			}

			stackMessage += '\n';
		}

		event.preventDefault();
		event.stopPropagation();
		event.stopImmediatePropagation();

		final callstackMessage = stackMessage.trim().length == 0 ? ' N/A' : '\n$stackMessage';

		var fullReport = '$curFlxState\n\nException caught: $message\n\nCallstack:$callstackMessage';

		// Mirror to game.log first — crash.log may be on external storage that
		// flushes slower; game.log is the authoritative developer log.
		try { Logger.log('CRASH: $fullReport', ERROR); } catch (_:Dynamic) {}

		// Write crash.log before touching Flixel state — survives double-faults
		// and native crashes that kill the process before FallbackState renders.
		#if sys
		try
		{
			final logPath = #if android mobile.backend.StorageSystem.getDirectory() #else "./" #end + 'crash.log';
			_appendCrashLog(logPath, fullReport);
		}
		catch (_:Dynamic) {}
		#end

		FlxG.switchState(() -> new FallbackState(fullReport, () -> {
			_inFallback = false;
			FlxG.switchState(() -> new MainMenuState());
		}));
	}

	#if sys
	static function _appendCrashLog(path:String, content:String):Void
	{
		try
		{
			final parent = haxe.io.Path.directory(path);
			if (parent.length > 0 && !sys.FileSystem.exists(parent))
				sys.FileSystem.createDirectory(parent);
			final stamp = try Date.now().toString() catch (_:Dynamic) 'unknown';
			var fo = sys.io.File.append(path, false);
			fo.writeString('--- CRASH [$stamp] ---\n$content\n\n');
			fo.close();
		}
		catch (_:Dynamic) {}
	}
	#end
}
