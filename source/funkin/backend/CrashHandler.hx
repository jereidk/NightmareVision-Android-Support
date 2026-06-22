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

	/**
	 * Register event listeners only — no file I/O, safe to call before storage
	 * permissions and directory init on mobile.
	 */
	public static function earlyInit():Void
	{
		if (_listenersRegistered) return;
		_listenersRegistered = true;
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(onCriticalError);
		#end
	}

	/**
	 * Full init — calls earlyInit() then wires up the Java-level handlers on
	 * Android (install UncaughtExceptionHandler + read previous session crash).
	 * Requires storage to be available.
	 */
	public static function init()
	{
		earlyInit();
		#if android
		{
			final logPath = mobile.backend.StorageSystem.getDirectory() + 'crash.log';
			final prevCrash = mobile.backend.JavaCrashWrapper.readPreviousNativeCrash();
			if (prevCrash != null)
				Logger.log('Previous session ended abnormally:\n$prevCrash', WARN);
			mobile.backend.JavaCrashWrapper.install(logPath);
		}
		#end
	}

	static function onCriticalError(message:String):Void
	{
		// Write crash.log directly BEFORE throwing — if this is a stack overflow
		// or memory corruption the Haxe exception machinery may not survive, so we
		// capture something now rather than rely on onUncaughtError.
		#if sys
		try
		{
			final logPath = #if android mobile.backend.StorageSystem.getDirectory() #else "./" #end + 'crash.log';
			_appendCrashLog(logPath, 'C++ critical error: $message');
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

		// Write crash log before touching Flixel state — this survives double-faults
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
		final header = '--- CRASH [${Date.now().toString()}] ---\n';
		var fo = sys.io.File.append(path, false);
		fo.writeString(header + content + '\n\n');
		fo.close();
	}
	#end
}
