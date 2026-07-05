package funkin.backend;

#if android
import openfl.system.System as OpenFLSystem;
#end

#if (android && sys)
import sys.FileSystem;
import sys.io.File;
#end

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;
import flixel.FlxG;

#if (android && cpp)
import external.Native;
#end

/**
 * System Monitor - Captures and logs system/resource information
 * 
 * Logs to `sysmon.log` in external storage with:
 * - GPU memory usage (if available)
 * - CPU/RAM info
 * - Flixel bitmap cache stats
 * - FPS tracking
 * - Asset loading snapshots
 * 
 * Only active when ClientPrefs.inDevMode is true.
 * Useful for debugging memory leaks and performance issues on Android.
 */
class SystemMonitor
{
	/**
	 * Enable/disable system monitoring
	 */
	public static var enabled:Bool = true;

	/**
	 * Log file path (set by init())
	 */
	static var logPath:String = '';

	/**
	 * Previous FPS values for averaging
	 */
	static var fpsHistory:Array<Int> = [];
	static inline var FPS_HISTORY_SIZE:Int = 60;

	// Frame-spike tracking
	static var _smoothElapsed:Float = 0.016;
	static var _lastSpikeTime:Float = -999.0;
	static inline final SPIKE_FACTOR:Float = 3.5;
	static inline final SPIKE_COOLDOWN:Float = 2.0;

	// Above this, a wall-clock gap between checkFrame() calls almost certainly
	// isn't a real single-frame hitch — it's this state's update() not having
	// run at all for a while (a FlxSubstate without persistentUpdate was open,
	// or the app was backgrounded), since MusicBeatSubstate doesn't call
	// checkFrame() itself. Treat gaps past this as a resume, not a spike.
	static inline final MAX_REASONABLE_GAP:Float = 4.0;

	// Self-suppression: skip spike detection right after file I/O so we
	// don't report the write latency as a fake frame spike.
	static var _suppressUntil:Float = 0.0;
	static inline final WRITE_SUPPRESS_S:Float = 0.15;

	// Script timing: annotate the next spike with which script event caused it
	static var _lastScriptNote:String = '';
	static inline final SCRIPT_NOTE_MS:Float = 5.0;   // >5ms → annotate next spike
	static inline final SCRIPT_LOG_MS:Float = 33.0;   // >33ms (1 frame @30fps) → write immediately

	// Member-growth leak detection
	static var _prevMemberCount:Int = -1;
	static var _memberGrowthStreak:Int = 0;
	static var _memberCheckTimer:Int = 0;
	static inline final MEMBER_CHECK_INTERVAL:Int = 60;   // check every N frames
	static inline final MEMBER_GROWTH_THRESHOLD:Int = 8;  // members added per interval
	static inline final MEMBER_GROWTH_STREAK:Int = 4;     // consecutive checks before warning

	// State-transition texture tracking
	static var _texCountBefore:Int = 0;
	static var _prevStateName:String = '';
	// Keys present before the switch — diffed on post to list exactly what loaded
	static var _keysBefore:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();
	// Last texture count seen when each state NAME was exited — re-entry leak detector
	static var _stateTexOnExit:haxe.ds.StringMap<Int> = new haxe.ds.StringMap();

	// GC spike detection
	#if cpp
	static var _lastGcUsage:Float = 0.0;
	#end

	// Per-frame evidence capture for "[cause unknown]" spikes: texture/sound
	// loads and sudden member-count jumps that happen to land in the same
	// frame as a spike are much stronger evidence than nothing at all.
	static var _lastBitmapCount:Int = -1;
	static var _lastBitmapKeys:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();
	static var _lastFrameMemberCount:Int = -1;

	/**
	 * Initialize system monitoring
	 * Only activates if ClientPrefs.inDevMode is true.
	 */
	public static function init():Void
	{
		#if (android && sys)
		// Only enable monitoring in developer mode
		if (ClientPrefs == null || !ClientPrefs.inDevMode) {
			enabled = false;
			return;
		}
		
		try {
			var dir:String = mobile.backend.StorageSystem.getDirectory();
			logPath = dir + 'sysmon.log';
			
			// Clear or start fresh
			try {
				if (FileSystem.exists(logPath)) {
					var stat = FileSystem.stat(logPath);
					if (stat.size > 2 * 1024 * 1024) { // > 2MB
						FileSystem.deleteFile(logPath);
					}
				}
			} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to check log file: $e', WARN); }
			
			_write('============================================================');
			_write('SYSTEM MONITOR START  ' + Date.now().toString());
			_write('============================================================');
			_write('Device Info:');
			_write('  Platform: ' + getPlatform());
			_write('  OS: ' + getOSInfo());
			_write('');

			#if flixel
			FlxG.signals.preStateSwitch.add(_onPreStateSwitch);
			FlxG.signals.postStateSwitch.add(_onPostStateSwitch);
			#end
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to initialize: $e', WARN); }
		#end
	}

	/**
	 * Get current timestamp
	 */
	static function timestamp():String
	{
		var d = Date.now();
		return '[' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()) + ']';
	}

	static inline function pad(n:Int):String
		return StringTools.lpad(Std.string(n), '0', 2);

	/**
	 * Log current system stats snapshot
	 */
	public static function logSnapshot(tag:String = 'SNAPSHOT'):Void
	{
		if (!enabled) return;

		var lines:Array<String> = [];
		lines.push('');
		lines.push('============================================================');
		lines.push('[' + tag + '] ' + Date.now().toString());
		lines.push('============================================================');

		// FPS Stats
		#if flixel
		var fps = DebugDisplay.instance != null ? DebugDisplay.instance.currentFPS : 0;
		var avgMs = _smoothElapsed > 0 ? Std.int(_smoothElapsed * 1000) : 0;
		lines.push('[FPS]');
		lines.push('  Current: $fps');
		lines.push('  Avg frame: ~${avgMs}ms');
		#end

		// Memory Stats
		lines.push('');
		lines.push('[MEMORY]');
		lines.push('  Total RAM: ' + getTotalRAM() + ' MB');
		lines.push('  Free RAM: ' + getFreeRAM() + ' MB');

		#if (openfl_v22_up)
		try {
			lines.push('  OpenFL Memory: N/A');
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get OpenFL memory info: $e', WARN); }
		#end

		// Flixel Bitmap Cache Stats
		lines.push('');
		lines.push('[FLX BITMAP CACHE]');
		#if flixel
		lines.push('  Cache Count: ' + getBitmapCacheCount());
		lines.push('  GPU Memory: ' + getEstimatedGPUMemory());
		#end

		// Asset Stats
		lines.push('');
		lines.push('[ASSETS]');
		lines.push('  Loaded Graphics: ' + getLoadedGraphicsCount());
		lines.push('  Loaded Sounds: ' + getLoadedSoundsCount());

		// Write all lines
		for (line in lines) {
			_write(line);
		}
	}

	/**
	 * Log a memory event (texture loaded, garbage collected, etc.)
	 */
	public static function logMemoryEvent(event:String, details:String = ''):Void
	{
		if (!enabled) return;
		_write('');
		_write('[MEM EVENT] ' + event);
		if (details.length > 0) {
			_write('  Details: ' + details);
		}
		
		// Also log current memory state
		_write('  RAM Free: ' + getFreeRAM() + ' MB');
		#if flixel
		_write('  GPU Textures: ' + getBitmapCacheCount());
		#end
	}

	/**
	 * Log GPU context info
	 */
	public static function logGPUInfo():Void
	{
		if (!enabled) return;
		
		_write('');
		_write('[GPU INFO]');
		
		#if (openfl && html5 == false)
		try {
			// Context3D info
			var context = openfl.display3D.Context3D.current;
			if (context != null) {
				_write('  Context: Active');
				#if (openfl_v22_up)
				// More GPU info if available
				#end
			}
		} catch (e:Dynamic) {
			Logger.log('SystemMonitor: Failed to get GPU context: $e', WARN);
			_write('  Context: Not available');
		}
		#end
		
		_write('  Renderer: ' + getRendererInfo());
		_write('  Driver: ' + getDriverInfo());
	}

	/**
	 * Log current state context
	 */
	public static function logStateChange(fromState:String, toState:String):Void
	{
		if (!enabled) return;
		_write('');
		_write('[STATE CHANGE]');
		_write('  From: ' + fromState);
		_write('  To: ' + toState);
		logSnapshot('POST_STATE_' + toState);
	}

	// ==================== AUTO DIAGNOSTICS ====================

	// Wall-clock timestamp of the previous checkFrame() call, used to measure
	// the true frame delta independent of Flixel's own elapsed clamp.
	static var _lastCheckTime:Float = 0.0;

	/**
	 * Call every frame (from MusicBeatState.update).
	 * Detects frame spikes and steady member-count growth within a state.
	 * Skips detection right after file I/O to avoid self-reporting write latency.
	 */
	public static function checkFrame(elapsed:Float):Void
	{
		if (!enabled) return;

		var now = haxe.Timer.stamp();

		// `elapsed` here is FlxG.elapsed, which FlxGame.updateElapsed() hard-clamps
		// to FlxG.maxElapsed (0.1s / 100ms) before any state ever sees it — so a
		// real 300ms or 2000ms stall was being reported as an identical "100ms"
		// spike, indistinguishable from a genuine 100ms hitch. Measuring the
		// wall-clock gap between calls here bypasses that clamp entirely, since
		// this function runs once per real frame regardless of what value
		// Flixel hands to game logic.
		var realElapsed = (_lastCheckTime > 0) ? (now - _lastCheckTime) : elapsed;
		_lastCheckTime = now;

		// A substate without persistentUpdate was almost certainly open for
		// this whole gap (checkFrame only runs from MusicBeatState, never
		// MusicBeatSubstate) — not a genuine hitch. Reset quietly.
		if (realElapsed > MAX_REASONABLE_GAP)
		{
			_smoothElapsed = 0.016;
			return;
		}

		// Self-suppression window: file I/O in _write can take 20-100ms on
		// Android flash storage. Still update the EMA but skip spike reporting.
		if (now < _suppressUntil)
		{
			_smoothElapsed = _smoothElapsed * 0.95 + realElapsed * 0.05;
			return;
		}

		_smoothElapsed = _smoothElapsed * 0.95 + realElapsed * 0.05;

		// GC delta: a large drop in heap usage means GC ran during this frame
		#if cpp
		var gcNow = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
		var gcFreed = _lastGcUsage - gcNow;
		_lastGcUsage = gcNow;
		#end

		// Evidence for otherwise-"unknown" spikes: did the texture cache or the
		// member list change size during this exact frame? Cheap to track every
		// frame (just a count); only pay for the full key diff when a spike
		// actually fires (rare, gated by SPIKE_COOLDOWN).
		#if flixel
		var curBitmapCount = _getRawBitmapCount();
		var curFrameMemberCount = FlxG.state != null ? FlxG.state.members.length : -1;
		var texDelta = (_lastBitmapCount >= 0) ? (curBitmapCount - _lastBitmapCount) : 0;
		var memberDelta = (_lastFrameMemberCount >= 0 && curFrameMemberCount >= 0) ? (curFrameMemberCount - _lastFrameMemberCount) : 0;
		#end

		if (realElapsed > _smoothElapsed * SPIKE_FACTOR && now - _lastSpikeTime > SPIKE_COOLDOWN)
		{
			_lastSpikeTime = now;
			var spikeMs = Std.int(realElapsed * 1000);
			var normalMs = Std.int(_smoothElapsed * 1000);
			#if flixel
			var state = _shortName(Type.getClassName(Type.getClass(FlxG.state)));
			// Attribute the cause: texture/sound load > GC > slow script > member churn > unknown (with mem delta as a last resort)
			var cause:String;
			if (texDelta > 0)
			{
				var newKeys:Array<String> = [];
				@:privateAccess for (k in FlxG.bitmap._cache.keys())
					if (!_lastBitmapKeys.exists(k)) newKeys.push(k);
				newKeys.sort((a, b) -> Reflect.compare(a, b));
				var shown = newKeys.slice(0, 6).map(_keyTail);
				cause = '  [+$texDelta texture(s) loaded: ${shown.join(", ")}${newKeys.length > 6 ? "…" : ""}]';
			}
			#if cpp
			else if (gcFreed > 1024 * 1024) cause = '  [GC freed ${Std.int(gcFreed / 1024)}KB]';
			#end
			else if (_lastScriptNote.length > 0) cause = '  [script: $_lastScriptNote]';
			else if (memberDelta > 5) cause = '  [+$memberDelta objects added to state]';
			else
			{
				#if cpp
				var memDeltaKB = Std.int(-gcFreed / 1024); // positive = heap grew, negative = freed (below the 1MB GC threshold above)
				cause = '  [cause unknown, mem ${memDeltaKB >= 0 ? "+" : ""}${memDeltaKB}KB]';
				#else
				cause = '  [cause unknown]';
				#end
			}
			_write('[SPIKE] ${spikeMs}ms  (avg ~${normalMs}ms)  state=$state$cause');
			#else
			_write('[SPIKE] ${spikeMs}ms  (avg ~${normalMs}ms)');
			#end
			_lastScriptNote = '';
		}

		#if flixel
		_lastBitmapCount = curBitmapCount;
		_lastFrameMemberCount = curFrameMemberCount;
		if (texDelta > 0 || _lastBitmapKeys.keys().hasNext() == false)
		{
			_lastBitmapKeys = new haxe.ds.StringMap();
			@:privateAccess for (k in FlxG.bitmap._cache.keys()) _lastBitmapKeys.set(k, true);
		}
		#end

		#if flixel
		if (++_memberCheckTimer >= MEMBER_CHECK_INTERVAL)
		{
			_memberCheckTimer = 0;
			_checkMemberGrowth();
		}
		#end
	}

	/**
	 * Report how long a script event took. Call around scriptGroup.call() in
	 * MusicBeatState. Fast events (<5ms) are silently discarded; slow ones
	 * annotate the next spike; very slow ones (>33ms) are written immediately.
	 */
	public static function reportScriptTime(event:String, ms:Float):Void
	{
		if (!enabled) return;
		if (ms < SCRIPT_NOTE_MS) return;
		_lastScriptNote = '$event ${Std.int(ms)}ms';
		if (ms > SCRIPT_LOG_MS)
		{
			#if flixel
			var state = _shortName(Type.getClassName(Type.getClass(FlxG.state)));
			_write('[SLOW SCRIPT] $event  ${Std.int(ms)}ms  state=$state');
			#else
			_write('[SLOW SCRIPT] $event  ${Std.int(ms)}ms');
			#end
		}
	}

	/**
	 * Called by FunkinCache when a texture exceeds 4096 px on either axis.
	 */
	public static function notifyOversizedTexture(key:String, w:Int, h:Int):Void
	{
		if (!enabled) return;
		_write('[OVERSIZED] $key  ${w}x${h}  — compress or convert to ASTC');
	}

	// ==================== GAMEPLAY PROFILING ====================

	// checkFrame()'s spike detector compares each frame against a rolling
	// average that adapts to whatever's currently happening — so a song
	// section that settles into a sustained 35fps plateau (heavy note
	// density, not a one-off hitch) just becomes the new "normal" and never
	// fires a [SPIKE]. This instead samples on a fixed cadence regardless of
	// whether the frame looked anomalous, with the gameplay context (song
	// time, live note/sustain count) needed to tell which section of which
	// song is actually the expensive one.
	static var _gameplayLogTimer:Float = 0.0;
	static inline final GAMEPLAY_LOG_INTERVAL:Float = 1.0; // seconds between samples
	static inline final GAMEPLAY_FPS_WARN:Int = 50;        // below this, flag the line

	/**
	 * Call once per frame from PlayState.update() during an active song.
	 * Writes a one-line FPS + note-density snapshot roughly once a second —
	 * cheap enough to run unconditionally, frequent enough to correlate a
	 * drop with a specific song section afterward.
	 */
	public static function reportGameplayFrame(elapsed:Float, songName:String, songTimeMs:Float, noteCount:Int, playFieldCount:Int):Void
	{
		if (!enabled) return;

		_gameplayLogTimer += elapsed;
		if (_gameplayLogTimer < GAMEPLAY_LOG_INTERVAL) return;
		_gameplayLogTimer = 0.0;

		#if flixel
		var fps = DebugDisplay.instance != null ? DebugDisplay.instance.currentFPS : 0;
		#else
		var fps = 0;
		#end
		var mark = fps < GAMEPLAY_FPS_WARN ? '!' : ' ';
		var t = songTimeMs / 1000;
		_write('[GAMEPLAY$mark] song=$songName t=${Std.int(t)}s notes=$noteCount fields=$playFieldCount fps=$fps');
	}

	/** Reset the sampling cadence — call when a song starts so the first sample lands ~1s in, not mid-timer from the previous song. */
	public static function resetGameplayTimer():Void
	{
		_gameplayLogTimer = 0.0;
	}

	#if flixel
	static function _onPreStateSwitch():Void
	{
		_prevStateName = FlxG.state != null ? _shortName(Type.getClassName(Type.getClass(FlxG.state))) : 'Unknown';
		_texCountBefore = _getRawBitmapCount();

		// Snapshot the full key set so we can diff exactly what loads next
		_keysBefore = new haxe.ds.StringMap();
		@:privateAccess for (k in FlxG.bitmap._cache.keys())
			_keysBefore.set(k, true);

		// Record how many textures this state had when it exited
		_stateTexOnExit.set(_prevStateName, _texCountBefore);
	}

	static function _onPostStateSwitch():Void
	{
		var after = _getRawBitmapCount();
		var diff = after - _texCountBefore;
		var newName = FlxG.state != null ? _shortName(Type.getClassName(Type.getClass(FlxG.state))) : 'Unknown';
		var sign = diff >= 0 ? '+' : '';
		_write('[STATE] $_prevStateName → $newName  |  textures: $_texCountBefore → $after (${sign}${diff})');

		if (diff > 0)
		{
			// Collect the actual keys that are new (not in pre-switch snapshot)
			var newKeys:Array<String> = [];
			@:privateAccess for (k in FlxG.bitmap._cache.keys())
				if (!_keysBefore.exists(k)) newKeys.push(k);

			newKeys.sort((a, b) -> Reflect.compare(a, b));

			// Show up to 15 — display only the filename portion to keep lines short
			var shown = newKeys.slice(0, 15).map(_keyTail);
			_write('  Loaded by $newName (${newKeys.length}): ' + shown.join(', ')
				+ (newKeys.length > 15 ? '  … +${newKeys.length - 15} more' : ''));
		}

		// Re-entry leak detector: if we've visited this state before and it
		// now has more textures than when we last left it, something accumulated.
		var prevExitCount = _stateTexOnExit.get(newName);
		if (prevExitCount != null && after > prevExitCount + 5)
			_write('  [REVISIT LEAK] $newName had $prevExitCount textures last exit, now ${after} (+${after - prevExitCount}) — accumulating each visit');

		if (diff > 30)
			_write('  [!] $newName loaded $diff textures — verify it releases them on exit');

		_keysBefore = new haxe.ds.StringMap(); // free snapshot memory

		// Reset member-growth tracking for the incoming state
		_prevMemberCount = -1;
		_memberGrowthStreak = 0;
		_memberCheckTimer = 0;
	}

	static function _checkMemberGrowth():Void
	{
		if (FlxG.state == null) return;
		var count = FlxG.state.members.length;
		if (_prevMemberCount >= 0 && count > _prevMemberCount + MEMBER_GROWTH_THRESHOLD)
		{
			_memberGrowthStreak++;
			if (_memberGrowthStreak >= MEMBER_GROWTH_STREAK)
			{
				_memberGrowthStreak = 0;
				var state = _shortName(Type.getClassName(Type.getClass(FlxG.state)));
				_write('[LEAK?] $state members: $_prevMemberCount → $count (+${count - _prevMemberCount}) across ${MEMBER_CHECK_INTERVAL * MEMBER_GROWTH_STREAK} frames — objects added but not removed');
			}
		}
		else if (count <= _prevMemberCount)
		{
			_memberGrowthStreak = 0;
		}
		_prevMemberCount = count;
	}

	static function _getRawBitmapCount():Int
	{
		var n = 0;
		@:privateAccess for (_ in FlxG.bitmap._cache.keys()) n++;
		return n;
	}
	#end

	// Returns the last path segment of a texture key, e.g.
	// "assets/images/characters/bf/bf-idle" → "bf-idle"
	static inline function _keyTail(key:String):String
	{
		var i = key.lastIndexOf('/');
		return i >= 0 ? key.substring(i + 1) : key;
	}

	static inline function _shortName(cls:String):String
	{
		var i = cls.lastIndexOf('.');
		return i >= 0 ? cls.substring(i + 1) : cls;
	}

	// ==================== HELPERS ====================

	static function _write(line:String):Void
	{
		#if (android && sys)
		if (logPath.length == 0) return;
		try {
			var out = File.append(logPath, false);
			out.writeString(timestamp() + ' ' + line + '\n');
			out.flush();
			out.close();
			// Suppress spike detection after file I/O so write latency
			// doesn't appear as a fake frame spike in the log.
			_suppressUntil = haxe.Timer.stamp() + WRITE_SUPPRESS_S;
		} catch (e:Dynamic) { Logger.log('SystemMonitor: _write failed: $e', WARN); }
		#end
	}

	static function formatBytes(bytes:Int):String
	{
		if (bytes < 1024) return bytes + ' B';
		if (bytes < 1024 * 1024) return Std.int(bytes / 1024) + ' KB';
		return Std.int(bytes / (1024 * 1024)) + ' MB';
	}

	// ==================== SYSTEM INFO ====================

	static function getPlatform():String
	{
		#if android
		return 'Android';
		#elseif ios
		return 'iOS';
		#elseif mac
		return 'macOS';
		#elseif windows
		return 'Windows';
		#elseif linux
		return 'Linux';
		#elseif html5
		return 'HTML5';
		#else
		return 'Unknown';
		#end
	}

	static function getOSInfo():String
	{
		#if android
		try {
			#if openfl_v22_up
			return 'Android API ' + openfl.utils.SystemResources.getAndroidSDKVersion();
			#else
			return 'Android (legacy)';
			#end
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get Android SDK version: $e', WARN); }
		return 'Android';
		#elseif (lime && lime_legacy)
		return lime.system.System.platformVersion;
		#else
		return 'N/A';
		#end
	}

	static function getTotalRAM():String
	{
		#if (android && cpp)
		try {
			return 'N/A'; // Android doesn't expose total RAM easily
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get total RAM: $e', WARN); }
		#end
		return '?';
	}

	static function getFreeRAM():String
	{
		#if (android && cpp)
		try {
			var bytes = Native.getTaskMemory();
			var memMB = Std.int(bytes.toInt() / 1024 / 1024);
			if (memMB > 0) {
				return memMB + ' MB';
			}
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get task memory: $e', WARN); }
		#end
		return '?';
	}

	static function getRendererInfo():String
	{
		#if (openfl && html5 == false)
		try {
			return openfl.display.Caps.renderer;
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get renderer info: $e', WARN); }
		#end
		return 'N/A';
	}

	static function getDriverInfo():String
	{
		#if (openfl && html5 == false)
		try {
			return openfl.display.Caps.driver;
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get driver info: $e', WARN); }
		#end
		return 'N/A';
	}

	// ==================== FLIXEL HELPERS ====================

	#if flixel
	static function getBitmapCacheCount():String
	{
		return Std.string(_getRawBitmapCount());
	}

	static function getEstimatedGPUMemory():String
	{
		// ~0.5 MB per texture (rough)
		return Std.string(_getRawBitmapCount() * 0.5) + ' MB (est.)';
	}
	#end

	static function getLoadedGraphicsCount():String
	{
		#if (openfl && !html5)
		try {
			var list = openfl.Assets.list(openfl.utils.AssetType.IMAGE);
			return Std.string(list.length);
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get loaded graphics count: $e', WARN); }
		#end
		return '?';
	}

	static function getLoadedSoundsCount():String
	{
		#if (openfl && !html5)
		try {
			var list = openfl.Assets.list(openfl.utils.AssetType.SOUND);
			return Std.string(list.length);
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get loaded sounds count: $e', WARN); }
		#end
		return '?';
	}
}
