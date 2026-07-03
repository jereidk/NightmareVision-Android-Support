package funkin.backend;

import haxe.ds.IntMap;

import flixel.util.FlxStringUtil;

import openfl.Assets;

import flixel.graphics.FlxGraphic;

import openfl.display.BitmapData;
import openfl.media.Sound;

using funkin.backend.SystemMonitor;

class CacheMap<T>
{
	public function new() {}
	
	public var cache:Map<String, T> = [];
	public var permanentKeys:Array<String> = [];
	
	public function get(key:String):Null<T> return cache.get(key);
	
	public function exists(key:String) return cache.exists(key);
	
	public function set(key:String, value:T) cache.set(key, value);
	
	public function remove(key:String) return cache.remove(key);
	
	public function keys() return cache.keys();
	
	/**
	 * Adds a key to be considered permanent to the cache.
	 */
	public function addPermanentKey(key:String)
	{
		if (!permanentKeys.contains(key)) permanentKeys.push(key);
	}
}

@:access(openfl.display.BitmapData)
@:nullSafety
@:allow(funkin.FunkinAssets)
class FunkinCache
{
	/**
	 * Clears all graphics and sounds that are considered inactive. Flags everything to be inactive as well.
	 *
	 * use `clearUnusedMemory` afterwards to purge everything
	 */
	public function clearStoredMemory() // maybe rename
	{
		// @:privateAccess
		// for (key in FlxG.bitmap._cache.keys())
		// {
		// 	// ok this is dumb fix this later
		// 	if (!currentTrackedGraphics.exists(key)
		// 		&& !key.startsWith('pixels')
		// 		&& !key.contains('editors/notification_neutral.png')
		// 		&& !key.contains('editors/notification_success.png')
		// 		&& !key.contains('editors/notification_warn.png')) // for haxeui is a bit hacky will do for now //find out hwo to avoid haxeui nicer or just do a different caching method //rewrite soonish ok.
		// 	{
		// 		disposeGraphic(FlxG.bitmap.get(key));
		// 	}
		// }

		// clear all sounds that are cached
		final soundKeys = [for (k in currentTrackedSounds.keys()) k];
		for (key in soundKeys)
		{
			if (!localTrackedAssets.exists(key) && !currentTrackedSounds.permanentKeys.contains(key))
			{
				removeFromCache(key);
			}
		}

		// Clear stale atlas frame cache entries. This prevents cache coherency issues
		// where frame data points to disposed bitmaps when transitioning between songs.
		// tempAtlasFramesCache keys are stored WITHOUT .png extension.
		try
		{
			for (key in currentTrackedGraphics.keys())
			{
				if (!localTrackedAssets.exists(key) && !currentTrackedGraphics.permanentKeys.contains(key))
				{
					final cacheKey = key.endsWith('.png') ? key.substr(0, key.length - 4) : key;
					Paths.tempAtlasFramesCache.remove(cacheKey);
				}
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('clearStoredMemory: Failed to clear tempAtlasFramesCache: $e', WARN);
		}

		// flags everything to be cleared out next unused memory clear
		localTrackedAssets.clear();
		openfl.Assets.cache.clear("songs");
	}
	
	/**
	 * Clears the graphics cache of any inactive graphics.
	 */
	public function clearUnusedMemory()
	{
		final graphicKeys = [for (k in currentTrackedGraphics.keys()) k];
		for (key in graphicKeys)
		{
			if (!localTrackedAssets.exists(key) && !currentTrackedGraphics.permanentKeys.contains(key))
			{
				// tempAtlasFramesCache stores keys WITHOUT the .png extension,
				// while currentTrackedGraphics stores keys WITH extension.
				// Strip extension to clear stale frame cache entries.
				final cacheKey = key.endsWith('.png') ? key.substr(0, key.length - 4) : key;
				Paths.tempAtlasFramesCache.remove(cacheKey);
				removeFromCache(key);
			}
		}

		// Secondary sweep: free textures that entered FlxG.bitmap without going
		// through FunkinCache (FlxAnimate destroySpritemaps, script-loaded graphics,
		// makeGraphic remnants). We only touch entries absent from our own tracking
		// and with no live sprite references (useCount <= 0).
		@:privateAccess
		final bitmapKeys = [for (k in FlxG.bitmap._cache.keys()) k];
		for (key in bitmapKeys)
		{
			if (currentTrackedGraphics.exists(key)) continue;
			@:privateAccess
			final graphic = FlxG.bitmap._cache.get(key);
			if (graphic != null && graphic.useCount <= 0)
				FlxG.bitmap.remove(graphic, true);
		}

		openfl.system.System.gc();
		#if cpp
		cpp.vm.Gc.compact();
		#end
	}
	
	function new() {}
	
	public final currentTrackedGraphics:CacheMap<FlxGraphic> = new CacheMap();
	
	public final currentTrackedSounds:CacheMap<Sound> = new CacheMap();
	
	public final localTrackedAssets:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap<Bool>();
	
	/**
	 * Removes a asset from the cache
	 * @param key 
	 * @param disposeToo 
	 * @return Bool
	 */
	public function removeFromCache(key:String, disposeToo:Bool = true):Bool
	{
		if (currentTrackedGraphics.exists(key))
		{
			if (disposeToo) disposeGraphic(currentTrackedGraphics.get(key));
			currentTrackedGraphics.remove(key);
			#if (android && cpp)
			mobile.backend.AstcLoader.removeTracking(key);
			#end
			
			// #if VERBOSE_LOGS
			// Logger.log('Cleared Graphic [$key]');
			// #end
			
			return true;
		}
		
		if (currentTrackedSounds.exists(key))
		{
			if (disposeToo) Assets.cache.clear(key);
			currentTrackedSounds.remove(key);
			
			// #if VERBOSE_LOGS
			// Logger.log('Cleared Sound [$key]');
			// #end
			
			return true;
		}
		
		return false;
	}
	
	/**
	 * Disposes of a flxgraphic
	 * 
	 * frees its gpu texture as well.
	 * @param graphic 
	 */
	public function disposeGraphic(graphic:Null<FlxGraphic>)
	{
		if (graphic == null) return;
		if (graphic.bitmap != null && graphic.bitmap.__texture != null) graphic.bitmap.__texture.dispose();
		FlxG.bitmap.remove(graphic);
	}
	
	/**
	 * Caches and returns a new `FlxGraphic` instance.
	 * @param key the id to use in the cache.
	 * @param bitmap The bitmap to use.
	 * @param allowGPU if true, will only store in video memory.
	 */
	public function cacheBitmap(key:String, bitmap:BitmapData, allowGPU:Bool = true):FlxGraphic
	{
		#if android
		if (bitmap.width > 4096 || bitmap.height > 4096)
		{
			Logger.log('Oversized texture [$key]: ${bitmap.width}x${bitmap.height} exceeds 4096px — compress or convert to ASTC', WARN);
			SystemMonitor.notifyOversizedTexture(key, bitmap.width, bitmap.height);
		}
		#end

		if (allowGPU && ClientPrefs.gpuCaching)
		{
			bitmap.disposeImage();
		}

		var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, key);
		newGraphic.persist = true;
		newGraphic.destroyOnNoUse = false;
		
		localTrackedAssets.set(key, true);
		currentTrackedGraphics.set(key, newGraphic);
		return newGraphic;
	}
	
	public function cacheSound(key:String, sound:Sound):Sound
	{
		currentTrackedSounds.set(key, sound);
		localTrackedAssets.set(key, true);
		
		return sound;
	}
	
	/**
	 * Clears assets matching a specific path prefix.
	 * Useful for selective memory cleanup (e.g., freeplay songs, specific stages).
	 * 
	 * @param categoryPrefix Path prefix to match, e.g., "freeplay/" or "songs/week"
	 * @param clearFromPermanent Whether to also remove from permanent cache (default: false)
	 */
	public function clearCategoryAssets(categoryPrefix:String, clearFromPermanent:Bool = false):Int
	{
		var clearedCount = 0;

		// Clear graphics
		final gKeys = [for (k in currentTrackedGraphics.keys()) k];
		for (key in gKeys)
		{
			if (key.contains(categoryPrefix))
			{
				if (!clearFromPermanent && currentTrackedGraphics.permanentKeys.contains(key))
					continue;
				removeFromCache(key);
				clearedCount++;
			}
		}

		// Clear sounds
		final sKeys = [for (k in currentTrackedSounds.keys()) k];
		for (key in sKeys)
		{
			if (key.contains(categoryPrefix))
			{
				if (!clearFromPermanent && currentTrackedSounds.permanentKeys.contains(key))
					continue;
				removeFromCache(key);
				clearedCount++;
			}
		}
		
		return clearedCount;
	}
	
	public function toString():String
	{
		final bmpCache = [for (key in currentTrackedGraphics.keys()) key];
		final sndCache = [for (key in currentTrackedSounds.keys()) key];
		
		return 'Bmp Cache: $bmpCache\nSnd Cache: $sndCache';
	}
}
