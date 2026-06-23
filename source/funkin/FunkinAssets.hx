package funkin;

import haxe.io.Bytes;

import openfl.media.Sound;
import openfl.utils.AssetType;
import openfl.display.BitmapData;
import openfl.Assets;

import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets;

import funkin.backend.FunkinCache;

/**
 * backend for retrieving and caching assets
 */
@:nullSafety(Strict)
class FunkinAssets
{
	/**
	 * Handles the caching of assets collected through `Paths`
	 */
	public static final cache:FunkinCache = new FunkinCache();

	private static var _assetListAllCache:Null<Array<String>> = null;
	private static var _assetListTypeCache:haxe.ds.StringMap<Array<String>> = new haxe.ds.StringMap();

	private static function getCachedAssetList(?type:AssetType):Array<String>
	{
		if (type == null)
		{
			if (_assetListAllCache == null) _assetListAllCache = Assets.list();
			return _assetListAllCache;
		}
		final key = Std.string(type);
		var cached = _assetListTypeCache.get(key);
		if (cached == null)
		{
			cached = Assets.list(type);
			_assetListTypeCache.set(key, cached);
		}
		return cached;
	}
	
	/**
	 * Safer alternative to directly using `haxe.Json.parse`
	 */
	public static function parseJson(content:String, ?pos:haxe.PosInfos):Null<Any>
	{
		try
		{
			return haxe.Json.parse(content);
		}
		catch (e)
		{
			Logger.log('failed to parse content\nException: ${e.message}', WARN, false, pos);
			return null;
		}
	}
	
	/**
	 * Parses a json using the json5 format.
	 */
	public static function parseJson5(content:String, ?pos:haxe.PosInfos):Null<Any>
	{
		try
		{
			#if json5hx
			return haxe.Json5.parse(content);
			#else
			return haxe.Json.parse(content);
			#end
		}
		catch (e)
		{
			Logger.log('failed to parse content\nException: ${e.message}', WARN, false, pos);
			return null;
		}
	}
	
	/**
	 * Retrieves the Bytes of a given file from its path
	 */
	public static function getBytes(path:String):Bytes
	{
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(path)) return File.getBytes(path);
		#end
		if (Assets.exists(path)) return Assets.getBytes(path);
		else
		{
			throw 'Couldnt find file at path [$path]';
		}
	}
	
	/**
	 * Retrieves the content of a given file from its path
	 */
	public static function getContent(path:String):String
	{
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(path)) return File.getContent(path);
		else
		#end
		if (Assets.exists(path)) return Assets.getText(path);
		else
		{
			throw 'Couldnt find file at path [$path]';
		}
	}
	
	/**
	 * Retrives a bitmap instance from path.
	 *
	 * Will return null in the case it cannot be found.
	 */
	public static function getBitmapData(path:String, useCache:Bool = true):Null<BitmapData>
	{
		// On Android, try loading a GPU-compressed ASTC override first.
		// Checks external storage then bundled APK assets. Falls through to PNG
		// if ASTC is unsupported, no .astc mirror exists, or loading fails.
		#if (android && cpp)
		var astcBitmap = mobile.backend.AstcLoader.tryLoad(path);
		if (astcBitmap != null) return astcBitmap;
		#end

		var bitmap:Null<BitmapData> = null;
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(path)) {
			#if android
			trace('DEBUG getBitmapData: trying BitmapData.fromFile for $path');
			#end
			bitmap = BitmapData.fromFile(path);
			#if android
			trace('DEBUG getBitmapData: BitmapData.fromFile result=${bitmap != null}');
			#end
			// If relative path failed on Android, try with full path
			#if android
			if (bitmap == null) {
				var fullPath = Sys.getCwd() + path;
				trace('DEBUG getBitmapData: trying full path: $fullPath');
				bitmap = BitmapData.fromFile(fullPath);
				trace('DEBUG getBitmapData: full path result=${bitmap != null}');
			}
			#end
		}
		else #end if (Assets.exists(path, IMAGE)) bitmap = Assets.getBitmapData(path, useCache);

		return bitmap;
	}
	
	/**
	 *	Returns whether a given path exists.
	 */
	public static function exists(path:String, ?type:AssetType):Bool
	{
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(path)) return true;
		#end
		if (Assets.exists(path, type)) return true;
		// Assets.exists() only matches file assets, not directories.
		// Fall back to a prefix scan so callers that check if a directory
		// "exists" in the APK (e.g. WeekData scanning assets/data/weeks/)
		// get a correct answer even when nothing has been extracted.
		final prefix = StringTools.endsWith(path, '/') ? path : (path + '/');
		return Lambda.exists(getCachedAssetList(type), a -> StringTools.startsWith(a, prefix));
	}
	
	/**
	 * Reads a given directory and returns all file names inside.
	 * 
	 * if it could not be found, an empty array will be returned.
	 */
	public static function readDirectory(directory:String):Array<String>
	{
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(directory)) return FileSystem.readDirectory(directory);
		#end
		if (directory.trim().length == 0) return [];
		// Normalize to trailing slash so the prefix strip is clean.
		final prefix = StringTools.endsWith(directory, '/') ? directory : (directory + '/');
		// Extract the first path component after the prefix (file or folder name).
		// Deduplicate so a folder with many files appears only once.
		final seen = new haxe.ds.StringMap<Bool>();
		final result:Array<String> = [];
		for (a in getCachedAssetList())
		{
			if (!StringTools.startsWith(a, prefix)) continue;
			var rel = a.substring(prefix.length);
			final slash = rel.indexOf('/');
			final entry = slash >= 0 ? rel.substring(0, slash) : rel;
			if (entry.length > 0 && !seen.exists(entry))
			{
				seen.set(entry, true);
				result.push(entry);
			}
		}
		return result;
	}

	public static function isDirectory(directory:String):Bool
	{
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(directory)) return FileSystem.isDirectory(directory);
		#end
		if (directory.trim().length == 0) return false;
		final prefix = StringTools.endsWith(directory, '/') ? directory : (directory + '/');
		return Lambda.exists(getCachedAssetList(), a -> StringTools.startsWith(a, prefix));
	}
	
	/**
	 * retrieves a flxgraphic instance from key.
	 * 
	 * @param useCache Retrieves from the cache if possible. Otherwise, it will be cached
	 * @param allowGPU If true and is enabled in settings, the graphic will be cached on in video memory
	 */
	public static function getGraphicUnsafe(key:String, useCache:Bool = true, allowGPU:Bool = true):Null<FlxGraphic>
	{
		if (useCache && cache.currentTrackedGraphics.exists(key))
		{
			cache.localTrackedAssets.push(key);
			return cache.currentTrackedGraphics.get(key);
		}
		
		var bitmap:Null<BitmapData> = getBitmapData(key);
		
		if (bitmap != null)
		{
			return cache.cacheBitmap(key, bitmap, allowGPU);
		}
		
		return null;
	}
	
	/**
	 * retrieves a flxgraphic instance from key.
	 * 
	 * @param useCache Retrieves from the cache if possible. Otherwise, it will be cached
	 * @param allowGPU If true and is enabled in settings, the graphic will be cached on in video memory
	 */
	public static function getGraphic(key:String, useCache:Bool = true, allowGPU:Bool = true):FlxGraphic
		{
			#if android
			var cwd = Sys.getCwd();
			var fullPath = cwd + key;
			trace("DEBUG getGraphic: key=" + key + " cwd=" + cwd + " fullPath=" + fullPath + " exists=" + sys.FileSystem.exists(fullPath));
			#end

			final graphic:Null<FlxGraphic> = getGraphicUnsafe(key, useCache, allowGPU);

			if (graphic != null)
			{
				return graphic;
			}

			Logger.log('graphic ($key) was not found. Returning flixel-logo instead');

			return FlxG.bitmap.add('flixel/images/logo/default.png');
	}
	
	/**
	 * Retrives a Sound instance from key.
	 * 
	 * If the sound could not be found, a beep sound will be given in place.
	 * 
	 * @param useCache Retrieves from the cache if possible. Otherwise, it will be cached
	 */
	public static function getSound(key:String, useCache:Bool = true):Sound
	{
		final sound:Null<Sound> = getSoundUnsafe(key, useCache);
		
		if (sound != null)
		{
			return sound;
		}
		
		Logger.log('sound ($key) was not found. Returning beep instead');
		
		return FlxAssets.getSoundAddExtension('flixel/sounds/beep');
	}
	
	/**
	 * Retrives a Sound instance from key.
	 * 
	 * If the sound could not be found, null will be returned.
	 * 
	 * @param useCache Retrieves from the cache if possible. Otherwise, it will be cached
	 */
	public static function getSoundUnsafe(key:String, useCache:Bool = true):Null<Sound>
	{
		if (useCache && cache.currentTrackedSounds.exists(key))
		{
			cache.localTrackedAssets.push(key);
			return cache.currentTrackedSounds.get(key);
		}
		
		var sound:Null<Sound> = null;
		
		#if (MODS_ALLOWED || ASSET_REDIRECT) if (FileSystem.exists(key)) sound = Sound.fromFile(key);
		else #end if (Assets.exists(key, SOUND)) sound = Assets.getSound(key, true);
		
		if (sound != null)
		{
			cache.cacheSound(key, sound);
		}
		
		return sound;
	}
	
	/**
	 * Constructs a Sound instance out of a `OGG Vorbis` file providing dramatically faster load times on larger files.
	 * 
	 * These do not support `.wav` and should be using sparingly
	 */
	public static function getVorbisSound(key:String):Null<Sound>
	{
		if (key.extension() != 'ogg') return null;
		
		#if !lime_vorbis
		// trace('gulp');
		return null;
		#else
		final vorbisFile = lime.media.vorbis.VorbisFile.fromFile(key);
		
		if (vorbisFile == null) return null;
		
		final buffer = lime.media.AudioBuffer.fromVorbisFile(vorbisFile);
		
		return Sound.fromAudioBuffer(buffer);
		#end
	}
}
