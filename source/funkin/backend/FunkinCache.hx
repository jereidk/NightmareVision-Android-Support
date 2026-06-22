package funkin.backend;

import haxe.ds.IntMap;

import flixel.util.FlxStringUtil;

import openfl.Assets;

import flixel.graphics.FlxGraphic;

import openfl.display.BitmapData;
import openfl.media.Sound;

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
	// ─── Tier 1: current (active state) ───────────────────────────────────────
	public final currentTrackedGraphics:CacheMap<FlxGraphic> = new CacheMap();
	public final currentTrackedSounds:CacheMap<Sound>        = new CacheMap();

	/** Keys marked as in-use for the current frame / loading cycle. */
	public final localTrackedAssets:Array<String> = [];

	// ─── Tier 2: previous (previous state, kept alive through the transition) ─
	// Freed completely on the next clearUnusedMemory() call.
	var _prevGraphics:Map<String, FlxGraphic> = [];
	var _prevSounds:Map<String, Sound>        = [];

	// ──────────────────────────────────────────────────────────────────────────

	function new() {}

	/**
	 * Moves the current tracked assets into the "previous" tier so they remain
	 * alive during the transition animation, then resets the current tier.
	 *
	 * Call at the start of a new state's create().
	 * Follow with clearUnusedMemory() once the new state's assets are loaded.
	 */
	public function clearStoredMemory()
	{
		// Previous tier had its turn — dispose it now before it's overwritten.
		_evictPrevious();

		// Move non-permanent current graphics → previous.
		for (key in [for (k in currentTrackedGraphics.keys()) k])
		{
			if (currentTrackedGraphics.permanentKeys.contains(key)) continue;

			final graphic = currentTrackedGraphics.get(key);
			if (graphic != null) _prevGraphics.set(key, graphic);
			currentTrackedGraphics.remove(key);
		}

		// Move non-permanent current sounds → previous.
		for (key in [for (k in currentTrackedSounds.keys()) k])
		{
			if (currentTrackedSounds.permanentKeys.contains(key)) continue;

			final sound = currentTrackedSounds.get(key);
			if (sound != null) _prevSounds.set(key, sound);
			currentTrackedSounds.remove(key);
		}

		localTrackedAssets.resize(0);
		openfl.Assets.cache.clear("songs");
	}

	/**
	 * Frees the previous tier (transition is over) and also purges any current
	 * graphics that are no longer tracked by localTrackedAssets.
	 *
	 * Call after the new state has finished loading its assets.
	 */
	public function clearUnusedMemory()
	{
		// Transition is complete — free whatever lived in the previous tier.
		_evictPrevious();

		// Also clear current graphics that are no longer needed this state.
		for (key in [for (k in currentTrackedGraphics.keys()) k])
		{
			if (!localTrackedAssets.contains(key) && !currentTrackedGraphics.permanentKeys.contains(key))
			{
				Paths.tempAtlasFramesCache.remove(key);
				removeFromCache(key);
			}
		}

		openfl.system.System.gc();
		#if cpp
		cpp.vm.Gc.compact();
		#end
	}

	/**
	 * Removes an asset from ALL tiers (current + previous) and disposes GPU
	 * textures.
	 */
	public function removeFromCache(key:String, disposeToo:Bool = true):Bool
	{
		if (currentTrackedGraphics.exists(key))
		{
			if (disposeToo) _disposeGraphicAndTracking(key, currentTrackedGraphics.get(key));
			currentTrackedGraphics.remove(key);
			return true;
		}

		if (currentTrackedSounds.exists(key))
		{
			if (disposeToo) Assets.cache.clear(key);
			currentTrackedSounds.remove(key);
			return true;
		}

		// Also sweep previous tier if it survived that far.
		if (_prevGraphics.exists(key))
		{
			if (disposeToo) _disposeGraphicAndTracking(key, _prevGraphics.get(key));
			_prevGraphics.remove(key);
			return true;
		}

		if (_prevSounds.exists(key))
		{
			if (disposeToo) Assets.cache.clear(key);
			_prevSounds.remove(key);
			return true;
		}

		return false;
	}

	/**
	 * Disposes a FlxGraphic, releasing its GPU texture.
	 */
	public function disposeGraphic(graphic:Null<FlxGraphic>)
	{
		if (graphic != null && graphic.bitmap != null && graphic.bitmap.__texture != null)
			graphic.bitmap.__texture.dispose();
		@:nullSafety(Off) FlxG.bitmap.remove(graphic);
	}

	/**
	 * Caches and returns a new `FlxGraphic` instance.
	 */
	public function cacheBitmap(key:String, bitmap:BitmapData, allowGPU:Bool = true):FlxGraphic
	{
		#if android
		if (bitmap.width > 4096 || bitmap.height > 4096)
			Logger.log('Oversized texture [$key]: ${bitmap.width}x${bitmap.height} exceeds 4096px — compress or convert to ASTC', WARN);
		#end

		if (allowGPU && ClientPrefs.gpuCaching)
			bitmap.disposeImage();

		var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, key);
		newGraphic.persist = true;
		newGraphic.destroyOnNoUse = false;

		localTrackedAssets.push(key);
		currentTrackedGraphics.set(key, newGraphic);

		// If this key was in the previous tier, remove it from there — it's live again.
		if (_prevGraphics.exists(key)) _prevGraphics.remove(key);

		return newGraphic;
	}

	public function cacheSound(key:String, sound:Sound):Sound
	{
		currentTrackedSounds.set(key, sound);
		localTrackedAssets.push(key);

		if (_prevSounds.exists(key)) _prevSounds.remove(key);

		return sound;
	}

	/**
	 * If `key` is being held in the "previous" tier, move it back into the
	 * current tier (re-marking it as in-use) and return it.
	 *
	 * This lets a freshly-entered state reuse an asset that the outgoing state
	 * had cached, instead of reloading it from disk. Returns null when the key
	 * is not present in the previous tier.
	 */
	public function reviveGraphic(key:String):Null<FlxGraphic>
	{
		final graphic = _prevGraphics.get(key);
		if (graphic == null) return null;

		_prevGraphics.remove(key);
		currentTrackedGraphics.set(key, graphic);
		localTrackedAssets.push(key);
		return graphic;
	}

	/**
	 * Sound counterpart to reviveGraphic(): promotes a sound from the previous
	 * tier back to the current tier. Returns null if not held in previous.
	 */
	public function reviveSound(key:String):Null<Sound>
	{
		final sound = _prevSounds.get(key);
		if (sound == null) return null;

		_prevSounds.remove(key);
		currentTrackedSounds.set(key, sound);
		localTrackedAssets.push(key);
		return sound;
	}

	public function toString():String
	{
		final bmpCache = [for (key in currentTrackedGraphics.keys()) key];
		final sndCache = [for (key in currentTrackedSounds.keys()) key];
		return 'Bmp Cache: $bmpCache\nSnd Cache: $sndCache';
	}

	// ─── Internal helpers ──────────────────────────────────────────────────────

	function _evictPrevious():Void
	{
		for (key in [for (k in _prevGraphics.keys()) k])
		{
			_disposeGraphicAndTracking(key, _prevGraphics.get(key));
		}
		_prevGraphics = [];

		for (key in [for (k in _prevSounds.keys()) k])
		{
			Assets.cache.clear(key);
		}
		_prevSounds = [];
	}

	inline function _disposeGraphicAndTracking(key:String, graphic:Null<FlxGraphic>):Void
	{
		disposeGraphic(graphic);
		#if (android && cpp)
		mobile.backend.AstcLoader.removeTracking(key);
		#end
	}
}
