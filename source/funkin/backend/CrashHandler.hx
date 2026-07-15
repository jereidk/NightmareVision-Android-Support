package funkin.backend;

import flixel.addons.transition.FlxTransitionableState;

import openfl.events.ErrorEvent;
import openfl.errors.Error;
import openfl.events.UncaughtErrorEvent;
import openfl.Lib;

// todo more witht his actually...
@:nullSafety
class CrashHandler
{
	public static function init()
	{
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		//
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(onCriticalError);
		#end
	}
	
	static function onCriticalError(message:String):Void
	{
		throw Std.string(message);
	}
	
	static function onUncaughtError(event:UncaughtErrorEvent)
	{
		// SystemMonitor buffers sysmon.log lines in memory and only flushes
		// periodically — force it out now so the last buffered lines (often
		// the most useful ones for diagnosing what led to this crash) aren't
		// lost if the process dies right after this handler runs.
		#if android SystemMonitor.flush(); #end

		FlxTransitionableState.skipNextTransIn = FlxTransitionableState.skipNextTransOut = true;

		var curFlxState:String = 'N/A';
		var stateInfo:String = '';

		if (FlxG.state != null)
		{
			final cl = Type.getClass(FlxG.state);
			if (cl != null) curFlxState = 'FlxState: ' + (Type.getClassName(cl) ?? 'N/A');
			FlxG.state.persistentUpdate = FlxG.state.persistentDraw = false;

			// Capture additional state info for debugging
			try
			{
				stateInfo += '\nState members: ${FlxG.state.members.length} sprites';
				if (Reflect.hasField(FlxG.state, 'stage'))
				{
					var stage = Reflect.getProperty(FlxG.state, 'stage');
					stateInfo += '\nStage: ${stage != null ? Type.getClassName(Type.getClass(stage)) : 'null'}';
				}
			}
			catch (e:Dynamic) {}
		}

		var message:String = Std.string(event.error);

		// Not trace()/Logger.log() -- this fires from inside the uncaught-error
		// handler itself, so keep it to the one thing that can't itself throw.
		// GameLogger.write() below is what actually makes this durable; this
		// line is just so it's visible via logcat too, same as it always was.
		#if sys Sys.println #else trace #end (message);
		#if android GameLogger.write('[CRASHHANDLER] ' + message); #end

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

		var fullReport = '$curFlxState\n\nException caught: $message$stateInfo\n\nCallstack:$callstackMessage';

		// Write crash log before touching Flixel state — this survives double-faults
		// and native crashes that kill the process before FallbackState renders.
		#if sys
		try
		{
			final logPath = #if android mobile.backend.StorageSystem.getDirectory() #else "./" #end + 'crash.log';
			sys.io.File.saveContent(logPath, fullReport);
		}
		catch (e:Dynamic) { Logger.log('CrashHandler: Failed to write crash log: $e', ERROR); }
		#end

		FlxG.switchState(() -> new FallbackState(fullReport, () -> FlxG.switchState(() -> new MainMenuState())));
	}
}
