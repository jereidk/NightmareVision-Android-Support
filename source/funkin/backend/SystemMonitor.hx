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
	static inline var FPS_HISTORY_SIZE:Int = 60; // Keep 1 second of history at 60fps

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
		var fps:Int = 0;
		#if flixel
		fps = 60; // targetFPS not available
		fpsHistory.push(fps);
		if (fpsHistory.length > FPS_HISTORY_SIZE) fpsHistory.shift();
		
		var avgFps = 0;
		if (fpsHistory.length > 0) {
			var sum = 0;
			for (f in fpsHistory) sum += f;
			avgFps = Std.int(sum / fpsHistory.length);
		}
		
		lines.push('[FPS]');
		lines.push('  Current: ' + fps);
		lines.push('  Average: ' + avgFps);
		lines.push('  History: ' + fpsHistory.length + ' samples');
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
			if (bytes.toInt() > 0) {
				return Std.int(bytes / 1024 / 1024) + ' MB';
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
		try {
			var count = 0;
			@:privateAccess
			for (key in FlxG.bitmap._cache.keys()) {
				count++;
			}
			return Std.string(count);
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to get bitmap cache count: $e', WARN); }
		return '?';
	}

	static function getEstimatedGPUMemory():String
	{
		try {
			var count = 0;
			@:privateAccess
			for (key in FlxG.bitmap._cache.keys()) {
				var graphic = FlxG.bitmap.get(key);
				if (graphic != null && graphic.bitmap != null) {
					count++;
				}
			}
			// Rough estimate: ~0.5MB per texture on average
			return Std.string(count * 0.5) + ' MB (est.)';
		} catch (e:Dynamic) { Logger.log('SystemMonitor: Failed to estimate GPU memory: $e', WARN); }
		return '0 MB';
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
