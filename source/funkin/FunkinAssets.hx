package funkin;

import haxe.io.Bytes;

import openfl.media.Sound;
import openfl.utils.AssetType;
import openfl.display.BitmapData;
import openfl.Assets;

import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets;

import funkin.backend.FunkinCache;
#if (android && sys)
import mobile.backend.StorageSystem;
#end

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
		try
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
		catch (e:Dynamic)
		{
			Logger.log('getCachedAssetList: Failed to get asset list: $e', WARN);
			return [];
		}
	}

	/**
	 * Invalidates the cached asset list.
	 * Call this after loading mods, installing DLC, or any operation
	 * that may change the available assets on disk.
	 */
	public static function invalidateAssetListCache():Void
	{
		_assetListAllCache = null;
		_assetListTypeCache = new haxe.ds.StringMap();
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
	public static function getBitmapData(path:String, useCache:Bool = true, skipAstc:Bool = false):Null<BitmapData>
	{
		// Validate path
		if (path == null || path.length == 0)
		{
			Logger.log('getBitmapData: Invalid path (null or empty)', WARN);
			return null;
		}

		// On Android, try loading a GPU-compressed ASTC override first.
		// Checks external storage then bundled APK assets. Falls through to PNG
		// if ASTC is unsupported, no .astc mirror exists, or loading fails.
		//
		// skipAstc forces the PNG-only path below instead — needed by anything
		// that reads pixel data back off the result (ASTC textures load
		// straight to the GPU via BitmapData.fromTexture(), which has no CPU
		// pixels at all; see AstcLoader's own doc comment).
		#if (android && cpp)
		if (!skipAstc)
		{
			try
			{
				var astcBitmap = mobile.backend.AstcLoader.tryLoad(path);
				if (astcBitmap != null) return astcBitmap;
			}
			catch (e:Dynamic)
			{
				Logger.log('getBitmapData: ASTC load failed for "$path": $e', WARN);
			}
		}
		#end

		var bitmap:Null<BitmapData> = null;

		// Try FileSystem first (external storage / mods, DLC) for mod override support.
		// This ensures mods take priority over APK assets, matching getSoundUnsafe() behavior.
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		try
		{
			if (FileSystem.exists(path)) {
				var loadPath = path;
				#if (android && sys)
				try
				{
					// On Android, BitmapData.fromFile needs the full path with storage directory
					// StorageSystem.getDirectory() returns /storage/emulated/0/.ImpostorLegacy/
					loadPath = StorageSystem.getDirectory() + path;
				}
				catch (e:Dynamic)
				{
					Logger.log('getBitmapData: Failed to get storage directory: $e', WARN);
					loadPath = path;
				}
				#end

				try
				{
					bitmap = BitmapData.fromFile(loadPath);
				}
				catch (e:Dynamic)
				{
					Logger.log('getBitmapData: BitmapData.fromFile failed for "$loadPath": $e', WARN);
				}
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('getBitmapData: FileSystem check failed for "$path": $e', WARN);
		}
		#end

		// Fallback to APK bundled assets via Assets.getBitmapData.
		// This handles files that are packaged inside the APK or cached by OpenFL.
		if (bitmap == null)
		{
			#if android
			try
			{
				if (Assets.exists(path, IMAGE)) {
					// Do NOT pass allowCompressedTextures=false here: AstcLoader above can
					// legitimately fail even when a .astc exists (e.g. at very early startup,
					// before FlxG.stage.stage3Ds[0].context3D is ready), and for assets whose
					// .png was deleted after ASTC conversion, openfl's own ASTC path here is
					// the only remaining way to load them at all. Disabling it caused every
					// such asset to fall through to flixel-logo. The double-premultiply risk
					// this was meant to avoid is the lesser problem.
					bitmap = Assets.getBitmapData(path, useCache);
				}
			}
			catch (e:Dynamic)
			{
				Logger.log('getBitmapData: Assets.getBitmapData failed for "$path": $e', WARN);
			}
			#else
			// For non-Android platforms without MODS_ALLOWED.
			bitmap = Assets.getBitmapData(path, useCache);
			#end
		}

		return bitmap;
	}
	
	/**
	 *	Returns whether a given path exists.
	 */
	public static function exists(path:String, ?type:AssetType):Bool
	{
		// Validate path
		if (path == null || path.length == 0) return false;

		try
		{
			#if (MODS_ALLOWED || ASSET_REDIRECT)
			if (FileSystem.exists(path)) return true;
			#end
		}
		catch (e:Dynamic)
		{
			Logger.log('exists: FileSystem check failed for "$path": $e', WARN);
		}

		try
		{
			if (Assets.exists(path, type)) return true;
		}
		catch (e:Dynamic)
		{
			Logger.log('exists: Assets.exists check failed for "$path": $e', WARN);
		}

		// Assets.exists() only matches file assets, not directories.
		// Fall back to a prefix scan so callers that check if a directory
		// "exists" in the APK (e.g. WeekData scanning assets/data/weeks/)
		// get a correct answer even when nothing has been extracted.
		try
		{
			final prefix = StringTools.endsWith(path, '/') ? path : (path + '/');
			return Lambda.exists(getCachedAssetList(type), a -> StringTools.startsWith(a, prefix));
		}
		catch (e:Dynamic)
		{
			Logger.log('exists: Prefix scan failed for "$path": $e', WARN);
			return false;
		}
	}
	
	/**
	 * Reads a given directory and returns all file names inside.
	 *
	 * if it could not be found, an empty array will be returned.
	 */
	public static function readDirectory(directory:String):Array<String>
	{
		// Validate directory
		if (directory == null || directory.trim().length == 0) return [];

		#if (MODS_ALLOWED || ASSET_REDIRECT)
		try
		{
			if (FileSystem.exists(directory)) return FileSystem.readDirectory(directory);
		}
		catch (e:Dynamic)
		{
			Logger.log('readDirectory: FileSystem.readDirectory failed for "$directory": $e', WARN);
		}
		#end

		// Normalize to trailing slash so the prefix strip is clean.
		try
		{
			final hasTrailingSlash = StringTools.endsWith(directory, '/');
			final prefix = hasTrailingSlash ? directory : (directory + '/');

			// Extract the first path component after the prefix (file or folder name).
			// Deduplicate so a folder with many files appears only once.
			final seen = new haxe.ds.StringMap<Bool>();
			final result:Array<String> = [];

			for (a in getCachedAssetList())
			{
				try
				{
					if (!StringTools.startsWith(a, prefix)) continue;

					var rel = a.substring(prefix.length);
					if (rel.length == 0) continue;

					final slash = rel.indexOf('/');
					final entry = slash >= 0 ? rel.substring(0, slash) : rel;

					if (entry.length > 0 && !seen.exists(entry))
					{
						seen.set(entry, true);
						result.push(entry);
					}
				}
				catch (e:Dynamic)
				{
					Logger.log('readDirectory: Error processing entry "$a": $e', WARN);
					continue;
				}
			}
			return result;
		}
		catch (e:Dynamic)
		{
			Logger.log('readDirectory: Asset list scan failed for "$directory": $e', WARN);
			return [];
		}
	}

	public static function isDirectory(directory:String):Bool
	{
		// Validate directory
		if (directory == null || directory.trim().length == 0) return false;

		#if (MODS_ALLOWED || ASSET_REDIRECT)
		try
		{
			if (FileSystem.exists(directory)) return FileSystem.isDirectory(directory);
		}
		catch (e:Dynamic)
		{
			Logger.log('isDirectory: FileSystem check failed for "$directory": $e', WARN);
		}
		#end

		try
		{
			final hasTrailingSlash = StringTools.endsWith(directory, '/');
			final prefix = hasTrailingSlash ? directory : (directory + '/');

			for (a in getCachedAssetList())
			{
				try
				{
					if (StringTools.startsWith(a, prefix)) return true;
				}
				catch (e:Dynamic)
				{
					Logger.log('isDirectory: Error checking entry "$a": $e', WARN);
					continue;
				}
			}
			return false;
		}
		catch (e:Dynamic)
		{
			Logger.log('isDirectory: Asset list scan failed for "$directory": $e', WARN);
			return false;
		}
	}
	
	/**
	 * retrieves a flxgraphic instance from key.
	 * 
	 * @param useCache Retrieves from the cache if possible. Otherwise, it will be cached
	 * @param allowGPU If true and is enabled in settings, the graphic will be cached on in video memory
	 */
	public static function getGraphicUnsafe(key:String, useCache:Bool = true, allowGPU:Bool = true):Null<FlxGraphic>
	{
		// Validate key
		if (key == null || key.length == 0)
		{
			Logger.log('getGraphicUnsafe: Invalid key (null or empty)', WARN);
			return null;
		}

		try
		{
			if (useCache && cache.currentTrackedGraphics.exists(key))
			{
				cache.localTrackedAssets.set(key, true);
				return cache.currentTrackedGraphics.get(key);
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('getGraphicUnsafe: Cache lookup failed for "$key": $e', WARN);
		}

		var bitmap:Null<BitmapData> = getBitmapData(key);

		if (bitmap != null)
		{
			try
			{
				return cache.cacheBitmap(key, bitmap, allowGPU);
			}
			catch (e:Dynamic)
			{
				Logger.log('getGraphicUnsafe: cacheBitmap failed for "$key": $e', WARN);
				return null;
			}
		}

		// Log failure details
		#if android
		try
		{
			Logger.log("[getGraphicUnsafe] FAILED for: $key", WARN);
			Logger.log('  - BitmapData result was null', WARN);
			Logger.log('  - Key: $key', WARN);
			Logger.log('  - FileSystem.exists: ${sys.FileSystem.exists(key)}', WARN);
			Logger.log('  - Assets.exists: ${Assets.exists(key, IMAGE)}', WARN);
		}
		catch (e:Dynamic)
		{
			Logger.log("[getGraphicUnsafe] Diagnostic logging failed: $e", WARN);
		}
		#end

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
			// Validate key
			if (key == null || key.length == 0)
			{
				Logger.log('getGraphic: Invalid key (null or empty)', WARN);
				return FlxG.bitmap.add('flixel/images/logo/default.png');
			}

			final graphic:Null<FlxGraphic> = getGraphicUnsafe(key, useCache, allowGPU);

			if (graphic != null)
			{
				return graphic;
			}

			Logger.log('graphic ($key) was not found. Returning flixel-logo instead', WARN);

			// FALLBACK DIAGNOSTIC - Detailed logging for debugging
			#if android
			try
			{
				Logger.log("[FunkinAssets] GRAPHIC FALLBACK TRIGGERED for: $key", WARN);
				Logger.log('  Date: ${Date.now()}', WARN);
				Logger.log('  WHAT HAPPENED: The graphic was not found in any asset source.', WARN);
				Logger.log('  ATTEMPTED SOURCES:', WARN);
				Logger.log('    1. ASTC compressed override (mobile.backend.AstcLoader)', WARN);
				Logger.log('    2. Assets.getBitmapData() [APK bundled]', WARN);
				Logger.log('    3. FileSystem.exists() + BitmapData.fromFile() [external]', WARN);
				Logger.log('    4. Flixel internal cache', WARN);
				Logger.log('  DIAGNOSTIC INFO:', WARN);
				Logger.log('    FileSystem.exists(key): ${sys.FileSystem.exists(key)}', WARN);
				Logger.log('    Assets.exists(key, IMAGE): ${Assets.exists(key, IMAGE)}', WARN);
				Logger.log('  ACTION: Returning Flixel logo as fallback.', WARN);
				Logger.log('  FIX: Check if file exists in assets/legacy/images/ and verify Project.xml includes it.', WARN);
			}
			catch (e:Dynamic)
			{
				Logger.log("[FunkinAssets] GRAPHIC FALLBACK DIAGNOSTIC LOGGING FAILED: $e", WARN);
			}
			#else
			Logger.log("[FunkinAssets] GRAPHIC FALLBACK TRIGGERED for: $key", WARN);
			#end

			return FlxG.bitmap.add('flixel/images/logo/default.png');
	}
	
	/**
	 * Makes a relative loose-file path (already confirmed to exist via
	 * FileSystem.exists()) absolute for Android's native file loaders.
	 * lime's C++ media decoders (OGG::Decode/WAV::Decode/VorbisFile, and
	 * BitmapData.fromFile before this had the same fix) open files via
	 * lime::fopen(), which is backed by SDL's SDL_IOFromFile() rather than a
	 * plain POSIX fopen() -- on Android, SDL resolves a relative path
	 * against its own APK-asset lookup first, not this app's actual
	 * external-storage working directory, so a relative "content/<mod>/..."
	 * path that sys.FileSystem.exists() (hxcpp's own check, unaffected by
	 * this) already found still fails to open through these calls. No-op on
	 * every other platform.
	 */
	#if (android && sys)
	public static function androidStoragePath(path:String):String
	{
		try
		{
			return StorageSystem.getDirectory() + path;
		}
		catch (e:Dynamic)
		{
			Logger.log('androidStoragePath: Failed to get storage directory: $e', WARN);
			return path;
		}
	}
	#else
	public static inline function androidStoragePath(path:String):String
		return path;
	#end

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
			cache.localTrackedAssets.set(key, true);
			return cache.currentTrackedSounds.get(key);
		}
		
		var sound:Null<Sound> = null;

		#if (MODS_ALLOWED || ASSET_REDIRECT)
		if (FileSystem.exists(key))
		{
			// Sound.fromFile() ends up in lime's native OGG::Decode/WAV::Decode,
			// which open the file via lime::fopen() -- backed by SDL's
			// SDL_IOFromFile(), NOT a plain POSIX fopen(). On Android, SDL
			// resolves a relative path against its own APK-asset lookup
			// first, not against this app's actual working directory, so a
			// relative "content/<mod>/..." path that sys.FileSystem.exists()
			// (hxcpp's own check, which DOES resolve correctly) just found
			// still fails to open here. getBitmapData() above already hit
			// this exact issue for images and fixed it the same way: hand
			// the native loader a full absolute path instead.
			final loadPath = androidStoragePath(key);

			try
			{
				sound = Sound.fromFile(loadPath);
			}
			catch (e:Dynamic)
			{
				// Sound.fromFile() throws (not returns null) on decode
				// failure. Falls through to the VorbisFile-based decoder
				// below as a last resort -- it shares the same underlying
				// native file-open path, so this mostly guards against a
				// genuinely bad/unsupported file rather than the path issue
				// above (already handled by loadPath), but costs nothing to
				// try before giving up to the beep fallback.
				Logger.log('Sound.fromFile failed for ($loadPath): $e', WARN);
				sound = null;
			}
		}
		else
		#end
		if (Assets.exists(key, SOUND)) sound = Assets.getSound(key, true);

		if (sound == null) sound = getVorbisSound(key);

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
		// VorbisFile.fromFile() opens the file through the exact same
		// native lime::fopen()/SDL_IOFromFile() path as Sound.fromFile() --
		// see androidStoragePath()'s own doc comment. Only meaningful once a
		// loose file is confirmed to exist; a bundled/APK-relative key
		// passes through unchanged.
		#if (MODS_ALLOWED || ASSET_REDIRECT)
		final loadPath = FileSystem.exists(key) ? androidStoragePath(key) : key;
		#else
		final loadPath = key;
		#end

		final vorbisFile = lime.media.vorbis.VorbisFile.fromFile(loadPath);

		if (vorbisFile == null) return null;
		
		final buffer = lime.media.AudioBuffer.fromVorbisFile(vorbisFile);
		
		return Sound.fromAudioBuffer(buffer);
		#end
	}
}
