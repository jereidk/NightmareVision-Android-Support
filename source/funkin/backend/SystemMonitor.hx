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

	// Monotonic session clock (haxe.Timer.stamp() at init()) used to append a
	// "t+SSSSSms" field to every timestamp — wall-clock HH:MM:SS alone can't
	// distinguish ordering between two lines that land in the same second,
	// which happened more than once in real device logs (a [SPIKE] and a
	// [LARGE-GC] both landing at the same wall-clock second).
	static var _startStamp:Float = 0.0;

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

	// SPIKE_FACTOR is relative to the recent average, which is itself inflated
	// during dense note sections — a genuinely huge GC collection (tens of MB)
	// can land in a frame that's slow in absolute terms but not 3.5x slower than
	// an already-elevated average, so it never fires as a [SPIKE] and never gets
	// cause-attributed. This fires on an absolute byte threshold instead, so it
	// catches those regardless of how busy the surrounding frames already are.
	static var _lastLargeGcTime:Float = -999.0;
	static inline final LARGE_GC_THRESHOLD_BYTES:Int = 10 * 1024 * 1024; // 10MB
	static inline final LARGE_GC_COOLDOWN:Float = 1.0;

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

	// _write() used to open+append+flush+close the file on every single call —
	// every [SPIKE]/[GAMEPLAY]/[LARGE-GC] line paid a fresh file-open syscall on
	// Android flash storage, which is exactly why WRITE_SUPPRESS_S above had to
	// exist in the first place. Now _write() only appends to an in-memory
	// buffer (no I/O); the buffer is flushed to one file handle kept open for
	// the whole session, either every FLUSH_LINE_THRESHOLD lines or every
	// FLUSH_INTERVAL_S seconds, whichever comes first. Actual disk I/O — and
	// the spike-suppression window — now only happens on that periodic flush,
	// not on every logged event.
	static var _writeBuffer:StringBuf = new StringBuf();
	static var _bufferedLines:Int = 0;
	static var _lastFlushTime:Float = 0.0;
	static inline final FLUSH_LINE_THRESHOLD:Int = 20;
	static inline final FLUSH_INTERVAL_S:Float = 1.0;
	#if (android && sys)
	static var _fileOut:sys.io.FileOutput = null;
	#end
	static var _totalBytesWritten:Int = 0;
	static inline final RUNTIME_LOG_CAP_BYTES:Int = 5 * 1024 * 1024; // 5MB

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

	// [LARGE-GC] tells you how much a collection freed, but not how long it
	// took to accumulate — 42MB freed after 30s of light gameplay reads very
	// differently from 42MB freed after 3s of dense notes. This tracks heap
	// growth on every frame that ISN'T itself a collection, so it holds
	// "bytes allocated since the last collection" at all times; read (and
	// reset) whenever any collection actually fires, alongside how long that
	// took, to turn a one-off byte count into an allocation rate.
	static var _heapGrowthSinceLastGc:Float = 0.0;
	static var _lastGcGrowthResetTime:Float = 0.0;
	#end

	// Every-frame GC accumulation across a whole [GAMEPLAY] reporting window
	// (distinct from noteGcCollision(), which only watches the noteHitDispatch
	// span specifically). Folds into the next gameplay line regardless of
	// which tag the pause happened to land in — noteHitDispatch, notesLoop,
	// draw, script, whatever was being timed when the collection ran.
	static var _frameGcCollisions:Int = 0;
	static var _frameGcBytesFreed:Int = 0;
	static inline final FRAME_GC_THRESHOLD_BYTES:Int = 100 * 1024;

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

			_startStamp = haxe.Timer.stamp();
			#if cpp
			// Seed with the real current usage instead of the 0.0 default —
			// otherwise the very first checkFrame() sees a fake multi-MB "growth"
			// (0 → actual heap usage) that would otherwise pollute the very first
			// _heapGrowthSinceLastGc reading.
			_lastGcUsage = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			_lastGcGrowthResetTime = _startStamp;
			#end

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
		var tMs = Std.int((haxe.Timer.stamp() - _startStamp) * 1000);
		return '[' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()) + ' t+${tMs}ms]';
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
		lines.push('  Total RAM: ' + getTotalRAM());
		lines.push('  Free RAM: ' + getFreeRAM());

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
		_write('  RAM Free: ' + getFreeRAM());
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
		// Snapshot before any reset below, so a collision this exact frame can
		// still report what accumulated leading up to it.
		var growthBeforeThisGc = _heapGrowthSinceLastGc;
		var growthSecBeforeThisGc = now - _lastGcGrowthResetTime;
		if (gcFreed > FRAME_GC_THRESHOLD_BYTES)
		{
			_frameGcCollisions++;
			_frameGcBytesFreed += Std.int(gcFreed);
			_heapGrowthSinceLastGc = 0;
			_lastGcGrowthResetTime = now;
		}
		else if (gcFreed < 0)
		{
			_heapGrowthSinceLastGc += -gcFreed;
		}
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
			// 100KB, not 1MB: matches noteGcCollision()'s threshold below — smaller
			// partial collections (e.g. NativeAlloc-triggered ones) still fully
			// explain a frame hitch and shouldn't fall through to "cause unknown".
			else if (gcFreed > 100 * 1024) cause = '  [GC freed ${Std.int(gcFreed / 1024)}KB${_growthSuffix(growthBeforeThisGc, growthSecBeforeThisGc)}]';
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
			_write('[SPIKE] ${spikeMs}ms  (avg ~${normalMs}ms)  state=$state$cause${_systemMemContext()}');
			#else
			_write('[SPIKE] ${spikeMs}ms  (avg ~${normalMs}ms)${_systemMemContext()}');
			#end
			_lastScriptNote = '';
		}
		#if cpp
		// Absolute-threshold check, separate from the relative [SPIKE] trigger above
		// (see LARGE_GC_THRESHOLD_BYTES comment) — only fires if this exact frame
		// didn't already get a [SPIKE] line, so a single event doesn't double-report.
		else if (gcFreed > LARGE_GC_THRESHOLD_BYTES && now - _lastLargeGcTime > LARGE_GC_COOLDOWN)
		{
			_lastLargeGcTime = now;
			#if flixel
			var state = _shortName(Type.getClassName(Type.getClass(FlxG.state)));
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
			else cause = '  [no texture/member change — plain heap garbage]';
			_write('[LARGE-GC] ${Std.int(gcFreed / 1024)}KB freed${_growthSuffix(growthBeforeThisGc, growthSecBeforeThisGc)}  state=$state$cause${_systemMemContext()}');
			#else
			_write('[LARGE-GC] ${Std.int(gcFreed / 1024)}KB freed${_growthSuffix(growthBeforeThisGc, growthSecBeforeThisGc)}${_systemMemContext()}');
			#end
		}
		#end

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

	// Wall-clock (not game-elapsed) start of the current reporting window, so
	// we can compare "real time this window actually took" against "sum of
	// everything we profiled inside it". A real device log showed the tagged
	// phases (draw/script/superUpdate/notesLoop/...) adding up to a small
	// fraction of the real time elapsed during the worst fps drops — this
	// makes that gap a hard, logged number instead of something inferred by
	// hand from fps + tag sums, to find out whether the missing time is CPU
	// work we're just not tagging yet, or something outside our control
	// entirely (GPU/vsync/compositor).
	static var _gameplayWindowStartStamp:Float = 0.0;

	// DRS's own "[DRS] frame-cache on/off" log only goes to Logger (FLX_DEBUG
	// console, invisible in release) — no way to tell from sysmon.log whether
	// it ever actually engaged during a laggy section. Track state + how many
	// times it flipped ON since the last report, folded into the [GAMEPLAY] line.
	static var _drsActiveNow:Bool = false;
	static var _drsActivations:Int = 0;

	/** Call whenever PlayState updates _drsActive, so [GAMEPLAY] lines can show whether DRS was actually engaged. */
	public static function reportDrsState(active:Bool):Void
	{
		if (!enabled) return;
		if (active && !_drsActiveNow) _drsActivations++;
		_drsActiveNow = active;
	}

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
		var breakdown = _profBreakdown();
		var taggedMs = _profTotal();

		final nowStamp = haxe.Timer.stamp();
		final realWindowMs = (nowStamp - _gameplayWindowStartStamp) * 1000;
		_gameplayWindowStartStamp = nowStamp;
		var gapSuffix = '';
		if (realWindowMs > 0)
		{
			final unaccountedMs = realWindowMs - taggedMs;
			final unaccountedPct = Std.int(unaccountedMs / realWindowMs * 100);
			gapSuffix = '  unaccounted=${Std.int(unaccountedMs)}ms(${unaccountedPct}%)';
		}

		var gcSuffix = _gcCollisions > 0 ? '  [GC hit noteHitDispatch x$_gcCollisions, ~${Std.int(_gcBytesFreed / 1024)}KB]' : '';
		var gcHoldSuffix = _gcCollisionsHoldRelease > 0 ? '  [GC hit holdRelease x$_gcCollisionsHoldRelease, ~${Std.int(_gcBytesFreedHoldRelease / 1024)}KB]' : '';
		var gcDrawSuffix = _gcCollisionsDraw > 0 ? '  [GC hit draw x$_gcCollisionsDraw, ~${Std.int(_gcBytesFreedDraw / 1024)}KB]' : '';
		#if cpp
		var gcAnySuffix = _frameGcCollisions > 0 ? '  [GC(any frame) x$_frameGcCollisions, ~${Std.int(_frameGcBytesFreed / 1024)}KB]' : '';
		#else
		var gcAnySuffix = '';
		#end
		var suffix = breakdown.length > 0 ? '  [$breakdown]' : '';
		var drsSuffix = '  drs=${_drsActiveNow ? "ON" : "off"}${_drsActivations > 0 ? " (x" + _drsActivations + " this window)" : ""}';
		_write('[GAMEPLAY$mark] song=$songName t=${Std.int(t)}s notes=$noteCount fields=$playFieldCount fps=$fps$suffix$gapSuffix$drsSuffix$gcSuffix$gcHoldSuffix$gcDrawSuffix$gcAnySuffix');
		_drsActivations = 0;
		profReset();
	}

	/** Reset the sampling cadence — call when a song starts so the first sample lands ~1s in, not mid-timer from the previous song. */
	public static function resetGameplayTimer():Void
	{
		_gameplayLogTimer = 0.0;
		_gameplayWindowStartStamp = haxe.Timer.stamp();
	}

	// ==================== PHASE PROFILING ====================

	// Answers "what specifically is slow" instead of just "it's slow": wrap
	// the handful of expensive phases in PlayState.update() (input/hit
	// detection, the falling-notes loop, modchart, camera, scripts) with
	// profBegin/profEnd, and the accumulated per-tag time since the last
	// report gets folded straight into the next [GAMEPLAY] line — so a slow
	// window shows e.g. "notesLoop=612ms keyShit=140ms script=88ms" instead
	// of just "fps=36".
	static var _profTags:Array<String> = [];
	static var _profMs:Map<String, Float> = new Map();

	// A single note hit pushes/pops this stack ~10-12 times (noteHitDispatch, hitPreScript,
	// hitStrum, hitsoundPlay/hitHealth, hitCharSing, hitSplash, hitNoteScript, hitDispose,
	// hitFocus, hitAudioSfx, hitPopUp). It used to be Array<{tag:String, t:Float}> — an
	// anonymous-object literal allocated fresh on every single profBegin() call, meaning the
	// very act of measuring noteHitDispatch was itself feeding the GC pressure it was built to
	// diagnose. Two parallel arrays (hxcpp keeps Array<String>/Array<Float> unboxed) give the
	// same LIFO push/pop behavior with no per-call allocation.
	static var _profStackTags:Array<String> = [];
	static var _profStackTimes:Array<Float> = [];

	/** Marks the start of a named phase. Must be paired with profEnd(). Cheap no-op when monitoring is off. */
	public static inline function profBegin(tag:String):Void
	{
		if (enabled)
		{
			_profStackTags.push(tag);
			_profStackTimes.push(haxe.Timer.stamp());
		}
	}

	/** Marks the end of the most recently opened phase, accumulating its elapsed time under its tag. */
	public static function profEnd():Void
	{
		if (!enabled || _profStackTags.length == 0) return;
		var tag = _profStackTags.pop();
		var startT = _profStackTimes.pop();
		var ms = (haxe.Timer.stamp() - startT) * 1000;
		if (!_profMs.exists(tag))
		{
			_profMs.set(tag, 0);
			_profTags.push(tag);
		}
		_profMs.set(tag, _profMs.get(tag) + ms);
	}

	// Biggest-first "tag=Xms tag2=Yms" summary of everything accumulated
	// since the last profReset(). Entries under half a millisecond are
	// dropped as noise.
	static function _profBreakdown():String
	{
		var entries = [for (t in _profTags) {tag: t, ms: _profMs.get(t)}];
		entries.sort((a, b) -> a.ms < b.ms ? 1 : (a.ms > b.ms ? -1 : 0));
		var parts = [for (e in entries) if (e.ms >= 0.5) '${e.tag}=${Std.int(e.ms)}ms'];
		return parts.join(' ');
	}

	// Sum of every tag accumulated since the last profReset() — used to
	// compare against real wall-clock time for a reporting window (see
	// _gameplayWindowStartStamp) to find out how much of each window isn't
	// covered by any profBegin/profEnd span at all.
	static function _profTotal():Float
	{
		var total:Float = 0;
		for (t in _profTags) total += _profMs.get(t);
		return total;
	}

	/** Clears accumulated phase timings — call after folding them into a report. */
	public static function profReset():Void
	{
		_profTags = [];
		_profMs.clear();
		_profStackTags.resize(0);
		_profStackTimes.resize(0);
		_gcCollisions = 0;
		_gcBytesFreed = 0;
		_gcCollisionsHoldRelease = 0;
		_gcBytesFreedHoldRelease = 0;
		_gcCollisionsDraw = 0;
		_gcBytesFreedDraw = 0;
		_frameGcCollisions = 0;
		_frameGcBytesFreed = 0;
	}

	// ==================== GC COLLISION DETECTION ====================

	// noteHitDispatch (and its own nested sub-tags, all profiled above) kept
	// reporting 60-140ms per accumulation window while every single sub-tag
	// inside it summed to a small fraction of that — the code path itself
	// isn't slow, something is pausing WHILE it runs. A GC collection landing
	// inside a wall-clock-timed span looks exactly like this: the paused
	// thread's elapsed time balloons but no line of Haxe code actually took
	// that long, so it can't show up under any specific sub-tag. Confirm (or
	// rule out) that by sampling heap usage immediately before/after the
	// dispatch call — a many-KB drop within one call means a collection ran
	// during it, not just sometime in the same frame.
	static var _gcCollisions:Int = 0;
	static var _gcBytesFreed:Int = 0;

	// Same idea, applied to holdRelease (dance()'s string interpolation was found
	// and fixed here, but the span is also where Character.set_holding() runs a
	// full playAnim() switch back to idle — worth its own counter to confirm
	// whether a GC collision still lands in this specific span independently of
	// noteHitDispatch's.
	static var _gcCollisionsHoldRelease:Int = 0;
	static var _gcBytesFreedHoldRelease:Int = 0;

	// Same idea, applied to the whole draw() call. checkFrame()'s [SPIKE]/[LARGE-GC]
	// detectors only know a collection happened SOMETIME during the frame, not
	// whether it landed inside draw() specifically — this confirms it directly,
	// bracketing the exact same super.draw() call the "draw" prof tag already
	// times, so a draw=100ms+ line can be read as "was a GC collision" vs.
	// "was actually 100ms of rendering work" instead of guessing from correlation.
	static var _gcCollisionsDraw:Int = 0;
	static var _gcBytesFreedDraw:Int = 0;

	/** Snapshot heap usage right before a span you want to check for a GC collision. */
	public static inline function gcUsageSnapshot():Float
	{
		return enabled ? cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) : 0;
	}

	/** Compares against a gcUsageSnapshot() taken before the span; records a collision if the heap shrank enough to imply one ran during it. */
	public static function noteGcCollision(before:Float):Void
	{
		if (!enabled) return;
		final after = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
		final freed = before - after;
		if (freed > 100 * 1024) // >100KB freed inside one call is not normal allocator bookkeeping
		{
			_gcCollisions++;
			_gcBytesFreed += Std.int(freed);
		}
	}

	/** Same as noteGcCollision(), but tracked separately for the holdRelease span. */
	public static function holdReleaseGcCollision(before:Float):Void
	{
		if (!enabled) return;
		final after = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
		final freed = before - after;
		if (freed > 100 * 1024) // >100KB freed inside one call is not normal allocator bookkeeping
		{
			_gcCollisionsHoldRelease++;
			_gcBytesFreedHoldRelease += Std.int(freed);
		}
	}

	/** Same as noteGcCollision(), but tracked separately for the draw() span. */
	public static function drawGcCollision(before:Float):Void
	{
		if (!enabled) return;
		final after = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
		final freed = before - after;
		if (freed > 100 * 1024) // >100KB freed inside one call is not normal allocator bookkeeping
		{
			_gcCollisionsDraw++;
			_gcBytesFreedDraw += Std.int(freed);
		}
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
		_writeBuffer.add(timestamp() + ' ' + line + '\n');
		_bufferedLines++;
		var now = haxe.Timer.stamp();
		if (_bufferedLines >= FLUSH_LINE_THRESHOLD || now - _lastFlushTime >= FLUSH_INTERVAL_S)
			_flushBuffer();
		#end
	}

	/**
	 * Writes the buffered lines to disk and flushes. Cheap no-op if the
	 * buffer is empty. Called periodically by _write(), and forced from
	 * CrashHandler right before an uncaught error is reported so the last
	 * buffered lines (often the most useful ones) aren't lost.
	 */
	public static function flush():Void
	{
		#if (android && sys)
		if (_writeBuffer.length == 0) return;
		try {
			var chunk = _writeBuffer.toString();
			if (_fileOut == null) _fileOut = File.append(logPath, false);
			_fileOut.writeString(chunk);
			_fileOut.flush();
			_writeBuffer = new StringBuf();
			_bufferedLines = 0;
			_lastFlushTime = haxe.Timer.stamp();
			_totalBytesWritten += chunk.length;
			// Suppress spike detection after real file I/O so write latency
			// doesn't appear as a fake frame spike in the log.
			_suppressUntil = haxe.Timer.stamp() + WRITE_SUPPRESS_S;
		} catch (e:Dynamic) {
			Logger.log('SystemMonitor: flush failed: $e', WARN);
			_fileOut = null; // force a reopen attempt next time
		}
		// init() only trims the log at startup, so a single very long session
		// could otherwise grow it unbounded — rotate mid-session too, same as
		// the startup check, once we've personally written past the cap.
		if (_totalBytesWritten > RUNTIME_LOG_CAP_BYTES) _rotateLog();
		#end
	}

	static inline function _flushBuffer():Void
		flush();

	#if (android && sys)
	static function _rotateLog():Void
	{
		try {
			if (_fileOut != null) { _fileOut.close(); _fileOut = null; }
			if (FileSystem.exists(logPath)) FileSystem.deleteFile(logPath);
			_totalBytesWritten = 0;
			_fileOut = File.append(logPath, false);
			var marker = timestamp() + ' ============================================================\n'
				+ timestamp() + ' [LOG ROTATED — hit the ' + Std.int(RUNTIME_LOG_CAP_BYTES / 1024 / 1024) + 'MB runtime cap, earlier lines this session were discarded]\n'
				+ timestamp() + ' ============================================================\n';
			_fileOut.writeString(marker);
			_fileOut.flush();
			_totalBytesWritten += marker.length;
		} catch (e:Dynamic) {
			Logger.log('SystemMonitor: log rotation failed: $e', WARN);
			_fileOut = null;
		}
	}
	#end

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
			var bytes = Native.getSystemTotalMemory();
			var memMB = Std.int(bytes.toInt() / 1024 / 1024);
			if (memMB > 0) return memMB + ' MB';
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get total RAM: $e', WARN); }
		#end
		return '?';
	}

	// Formats the "how long did this take to accumulate" context for a GC
	// collision — turns a one-off byte count into an allocation rate, so
	// "42MB freed" reads as either "over 30s of light gameplay" (unremarkable)
	// or "over 3s of dense notes" (something is allocating heavily per note).
	#if cpp
	static inline function _growthSuffix(growthBytes:Float, growthSec:Float):String
	{
		if (growthBytes <= 0 || growthSec <= 0) return '';
		return ', grew ${Std.int(growthBytes / 1024)}KB over ${Std.int(growthSec * 10) / 10}s';
	}
	#end

	// Android's low-memory killer watches this same figure (/proc/meminfo's
	// MemAvailable). If it's low right when a [SPIKE] or [LARGE-GC] fires,
	// the OS squeezing overall system memory is a much stronger, more
	// actionable lead than anything we can infer from our own texture-cache
	// diffing — this had zero visibility before, since lime's SDL backend
	// receives Android's onTrimMemory callback but silently discards it
	// (SDLApplication.cpp's SDL_EVENT_LOW_MEMORY case is a no-op).
	static function _systemMemContext():String
	{
		#if (android && cpp)
		try {
			var availBytes = Native.getSystemAvailableMemory();
			var totalBytes = Native.getSystemTotalMemory();
			var availMB = Std.int(availBytes.toInt() / 1024 / 1024);
			var totalMB = Std.int(totalBytes.toInt() / 1024 / 1024);
			if (availMB > 0 && totalMB > 0)
			{
				var pct = Std.int(availMB / totalMB * 100);
				return '  sysFree=${availMB}MB/${totalMB}MB(${pct}%)';
			}
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get system memory context: $e', WARN); }
		#end
		return '';
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
