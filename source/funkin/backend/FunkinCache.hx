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
		Paths.tempAtlasFramesCache.clear();

		// clear all sounds that are cached
		final soundKeys = [for (k in currentTrackedSounds.keys()) k];
		for (key in soundKeys)
		{
			if (!localTrackedAssets.exists(key) && !currentTrackedSounds.permanentKeys.contains(key))
			{
				removeFromCache(key);
			}
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
				removeFromCache(key);
			}
		}

		// Second pass: sweep FlxG.bitmap._cache for textures created outside FunkinCache
		// (makeGraphic, flixel-animate, HaxeUI, scripts).  These are never registered in
		// currentTrackedGraphics so the loop above never touches them, causing them to
		// accumulate across state transitions and grow GPU memory each visit.
		// Guard with useCount <= 0 so we never evict textures still held by live sprites
		// (e.g. health bar created before clearUnusedMemory runs mid-PlayState.create).
		@:privateAccess
		{
			final bitmapKeys:Array<String> = [for (k in FlxG.bitmap._cache.keys()) k];
			for (key in bitmapKeys)
			{
				if (currentTrackedGraphics.exists(key) || currentTrackedGraphics.permanentKeys.contains(key))
					continue;
				if (key.indexOf('flixel') >= 0)
					continue;
				final g:Null<FlxGraphic> = FlxG.bitmap._cache.get(key);
				if (g != null && g.useCount <= 0)
					disposeGraphic(g);
			}
		}

		forceGcPass();
	}

	/**
	 * Forces an immediate GC pass. Split out of clearUnusedMemory() so states
	 * can request one on its own -- clearStoredMemory()/clearUnusedMemory()
	 * only ever run at the START of create(), before that state's own new
	 * textures/atlases are loaded, so the decode garbage THIS state generates
	 * never gets swept by that pass. Left to hxcpp's own scheduler, that
	 * garbage was showing up as a [LARGE-GC] pause a second or two after the
	 * state had already finished loading and the player was already looking
	 * at it -- calling this again at the END of a texture-heavy create()
	 * bundles that same unavoidable pause into the loading transition itself
	 * instead of leaving it to surface later as a random-feeling stutter.
	 */
	public function forceGcPass():Void
	{
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
	 * Snapshot of every key currently in `FlxG.bitmap._cache`, for later diffing
	 * via `disposeNewSince()`. Call at the very start of a state's `create()`.
	 */
	public function snapshotBitmapKeys():haxe.ds.StringMap<Bool>
	{
		var snap = new haxe.ds.StringMap<Bool>();
		@:privateAccess for (k in FlxG.bitmap._cache.keys()) snap.set(k, true);
		return snap;
	}

	/**
	 * Force-disposes any `FlxG.bitmap._cache` entry that didn't exist in `snapshot`
	 * and isn't tracked/permanent. Call from a state's `destroy()` (after
	 * `super.destroy()`) with the snapshot taken at that state's `create()`.
	 *
	 * `clearUnusedMemory()`'s untracked-graphics sweep only evicts entries whose
	 * `useCount` has dropped to 0, which misses graphics still referenced by a
	 * stray static/closure outside the normal FlxGroup destroy chain (e.g. a
	 * `makeGraphic()` rect with a slightly different computed color each call,
	 * so it never reuses a cache key and keeps a live reference forever). Since
	 * this state is being destroyed, nothing it created ephemerally should
	 * legitimately outlive it, so this sweep ignores useCount entirely.
	 */
	public function disposeNewSince(snapshot:haxe.ds.StringMap<Bool>):Int
	{
		var disposed = 0;
		@:privateAccess
		{
			final bitmapKeys:Array<String> = [for (k in FlxG.bitmap._cache.keys()) k];
			for (key in bitmapKeys)
			{
				if (snapshot.exists(key)) continue;
				if (currentTrackedGraphics.exists(key) || currentTrackedGraphics.permanentKeys.contains(key)) continue;
				if (key.indexOf('flixel') >= 0) continue;

				final g:Null<FlxGraphic> = FlxG.bitmap._cache.get(key);
				if (g != null)
				{
					disposeGraphic(g);
					disposed++;
				}
			}
		}

		#if android
		if (disposed > 0) SystemMonitor.logMemoryEvent('disposeNewSince', 'force-disposed $disposed ephemeral graphic(s) still alive after destroy()');
		#end

		return disposed;
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
