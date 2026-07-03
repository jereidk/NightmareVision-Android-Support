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

	// State-transition leak tracking
	static var _texCountBefore:Int = 0;
	static var _prevStateName:String = '';

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

	/**
	 * Call every frame (from MusicBeatState.update).
	 * Logs a warning to sysmon.log when a frame takes SPIKE_FACTOR × the rolling average.
	 */
	public static function checkFrame(elapsed:Float):Void
	{
		if (!enabled) return;

		_smoothElapsed = _smoothElapsed * 0.95 + elapsed * 0.05;

		if (elapsed > _smoothElapsed * SPIKE_FACTOR)
		{
			var now = haxe.Timer.stamp();
			if (now - _lastSpikeTime > SPIKE_COOLDOWN)
			{
				_lastSpikeTime = now;
				var spikeMs = Std.int(elapsed * 1000);
				var normalMs = Std.int(_smoothElapsed * 1000);
				#if flixel
				var state = _shortName(Type.getClassName(Type.getClass(FlxG.state)));
				_write('[SPIKE] ${spikeMs}ms  (avg ~${normalMs}ms)  state=$state');
				#else
				_write('[SPIKE] ${spikeMs}ms  (avg ~${normalMs}ms)');
				#end
			}
		}
	}

	/**
	 * Called by FunkinCache when a texture exceeds 4096 px on either axis.
	 * Mirrors the warning to sysmon.log so it persists between runs.
	 */
	public static function notifyOversizedTexture(key:String, w:Int, h:Int):Void
	{
		if (!enabled) return;
		_write('[OVERSIZED] $key  ${w}x${h}  — compress or convert to ASTC');
	}

	#if flixel
	static function _onPreStateSwitch():Void
	{
		_prevStateName = FlxG.state != null ? _shortName(Type.getClassName(Type.getClass(FlxG.state))) : 'Unknown';
		_texCountBefore = _getRawBitmapCount();
	}

	static function _onPostStateSwitch():Void
	{
		var after = _getRawBitmapCount();
		var diff = after - _texCountBefore;
		var newName = FlxG.state != null ? _shortName(Type.getClassName(Type.getClass(FlxG.state))) : 'Unknown';
		var sign = diff >= 0 ? '+' : '';
		_write('[STATE] $_prevStateName → $newName  |  textures: $_texCountBefore → $after (${sign}${diff})');
		if (diff > 30)
			_write('  [!] Large texture growth — verify $_prevStateName calls clearStoredMemory/clearUnusedMemory');
	}

	static function _getRawBitmapCount():Int
	{
		var n = 0;
		@:privateAccess for (_ in FlxG.bitmap._cache.keys()) n++;
		return n;
	}
	#end

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
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to write to log file: $e', WARN); }
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
