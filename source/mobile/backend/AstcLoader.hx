package mobile.backend;

import funkin.backend.Logger;

#if (android && cpp)
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.RectangleTexture;
import openfl.display3D.textures.TextureBase;
import openfl.Assets as OflAssets;
import openfl.events.Event;
import lime.utils.UInt8Array;
#end

/**
 * Loads raw ASTC texture files (16-byte header + compressed blocks) into
 * OpenFL BitmapData backed by a GPU-side compressed texture.
 *
 * ASTC files live next to their PNG counterpart with a .astc extension:
 *   assets/images/characters/bf.png  →  assets/images/characters/bf.astc
 * The original PNGs are never touched and always serve as fallback.
 * On devices that do not expose GL_KHR_texture_compression_astc_ldr
 * the loader returns null and the caller falls through to the PNG.
 *
 * Context-loss recovery: Android destroys the GPU context when the app is
 * backgrounded. BitmapData.fromTexture() has no CPU pixels and cannot be
 * restored automatically by OpenFL. This class registers a CONTEXT3D_CREATE
 * listener that re-uploads every tracked ASTC texture when the GL context
 * comes back, patching the existing RectangleTexture handles in-place so
 * all live BitmapData instances automatically see fresh GPU data.
 *
 * PNG fallback: if the .astc file is missing when the context is restored
 * (e.g. DLC uninstalled, SD-card corruption), the loader falls back to the
 * original PNG and switches that entry permanently to PNG-restore mode so
 * future restore cycles also use the PNG.
 */
@:access(openfl.display3D.textures.TextureBase)
@:access(openfl.display3D.Context3D)
@:access(openfl.display.BitmapData)
class AstcLoader
{
	// ASTC magic bytes (little-endian 0x5CA1AB13)
	static inline final MAGIC_0:Int = 0x13;
	static inline final MAGIC_1:Int = 0xAB;
	static inline final MAGIC_2:Int = 0xA1;
	static inline final MAGIC_3:Int = 0x5C;

	// ASTC header size in bytes
	static inline final HEADER_SIZE:Int = 16;

	// Compressed payloads at or below this size are kept in RAM so context
	// restoration can skip the disk re-read for small/medium textures.
	// At ASTC 8×8 this covers textures up to ~1024×1024.
	// Larger spritemaps re-read from disk on restore (lower RAM overhead vs.
	// occasional resume stutter is the accepted tradeoff).
	static inline final BYTES_CACHE_LIMIT:Int = 512 * 1024; // 512 KB

	#if (android && cpp)
	// Keyed by PNG path (= FunkinCache cache key).
	// glFormat == 0 is the PNG-fallback sentinel — valid ASTC entries always
	// arrive here with glFormat != 0 (blockSizeToGlFormat guards this).
	static var _recovery:Map<String, {
		astcPath:    String,
		rectTex:     RectangleTexture,
		width:       Int,
		height:      Int,
		glFormat:    Int,
		cachedBytes: Null<haxe.io.Bytes>
	}> = [];
	static var _listenerInstalled:Bool = false;
	#end

	/**
	 * Installs the CONTEXT3D_CREATE listener that re-uploads all tracked ASTC
	 * textures after an OpenGL context loss/restore cycle.
	 * Safe to call multiple times — only installs once.
	 * Call from Init.hx right after AstcSupport.check().
	 */
	public static function installContextHandler():Void
	{
		#if (android && cpp)
		if (_listenerInstalled) return;
		_listenerInstalled = true;
		FlxG.stage.stage3Ds[0].addEventListener(Event.CONTEXT3D_CREATE, _onContextRestored);
		#end
	}

	/**
	 * Removes a PNG cache key from the recovery map.
	 * Call from FunkinCache.removeFromCache() so evicted textures are not
	 * re-uploaded on context restoration.
	 */
	public static function removeTracking(cacheKey:String):Void
	{
		#if (android && cpp)
		_recovery.remove(cacheKey);
		#end
	}

	/**
	 * Derives the ASTC path for a PNG path and attempts to load it.
	 * Checks external storage first, then falls back to bundled APK assets.
	 * The returned BitmapData is registered for automatic context-loss recovery.
	 * Returns null if ASTC is unsupported, no .astc exists, or loading fails.
	 */
	public static function tryLoad(pngPath:String):Null<BitmapData>
	{
		#if (android && cpp)
		if (!AstcSupport.isSupported) return null;

		var astcPath = deriveAstcPath(pngPath);
		if (astcPath == null) return null;

		// External storage (extracted APK assets, DLC overrides) takes priority.
		if (sys.FileSystem.exists(astcPath))
		{
			try
			{
				var bytes = sys.io.File.getBytes(astcPath);
				return _loadAndTrack(pngPath, astcPath, bytes);
			}
			catch (e:Dynamic)
			{
				Logger.log('AstcLoader: failed to read $astcPath — $e', WARN);
				return null;
			}
		}

		// Bundled APK asset — allows shipping pre-compressed ASTC inside the APK.
		if (OflAssets.exists(astcPath))
		{
			var bytes = OflAssets.getBytes(astcPath);
			if (bytes != null) return _loadAndTrack(pngPath, astcPath, bytes);
		}

		return null;
		#else
		return null;
		#end
	}

	/**
	 * Loads an .astc file from the filesystem and returns a GPU-backed BitmapData.
	 * Only call this after confirming the file exists and ASTC is supported.
	 * Note: textures loaded via this method are NOT tracked for context-loss recovery.
	 * Use tryLoad() for managed loading.
	 */
	public static function load(astcPath:String):Null<BitmapData>
	{
		#if (android && cpp)
		try
		{
			return loadFromBytes(astcPath, sys.io.File.getBytes(astcPath));
		}
		catch (e:Dynamic)
		{
			Logger.log('AstcLoader: failed to load $astcPath — $e', WARN);
			return null;
		}
		#else
		return null;
		#end
	}

	/**
	 * Uploads already-read ASTC bytes to the GPU and returns a BitmapData.
	 * Shared by both the filesystem and bundled-asset paths.
	 * Note: textures loaded via this method are NOT tracked for context-loss recovery.
	 * Use tryLoad() for managed loading.
	 */
	public static function loadFromBytes(astcPath:String, bytes:haxe.io.Bytes):Null<BitmapData>
	{
		#if (android && cpp)
		try
		{
			var result = _loadInternal(astcPath, bytes);
			return result == null ? null : result.bitmap;
		}
		catch (e:Dynamic)
		{
			Logger.log('AstcLoader: failed to load $astcPath — $e', WARN);
			return null;
		}
		#else
		return null;
		#end
	}

	// ---------------------------------------------------------------------------

	#if (android && cpp)

	/**
	 * Loads ASTC bytes, wraps in BitmapData, and registers in the recovery map
	 * so the texture survives an OpenGL context loss/restore cycle.
	 */
	static function _loadAndTrack(pngPath:String, astcPath:String, bytes:haxe.io.Bytes):Null<BitmapData>
	{
		try
		{
			var result = _loadInternal(astcPath, bytes);
			if (result == null) return null;

			// Keep the compressed bytes in RAM for small textures so context
			// restoration can skip the disk I/O round-trip. The bytes reference
			// is shared (no copy) — we just prevent it from being GC'd.
			var payloadSize = bytes.length - HEADER_SIZE;
			var cached:Null<haxe.io.Bytes> = (payloadSize <= BYTES_CACHE_LIMIT) ? bytes : null;

			_recovery.set(pngPath, {
				astcPath:    astcPath,
				rectTex:     result.rectTex,
				width:       result.width,
				height:      result.height,
				glFormat:    result.glFormat,
				cachedBytes: cached
			});

			return result.bitmap;
		}
		catch (e:Dynamic)
		{
			Logger.log('AstcLoader: failed to load $astcPath — $e', WARN);
			return null;
		}
	}

	/**
	 * Parses the ASTC header, uploads the payload to the GPU, and returns the
	 * BitmapData together with the metadata needed for context-loss re-upload.
	 */
	static function _loadInternal(path:String, bytes:haxe.io.Bytes):Null<{bitmap:BitmapData, rectTex:RectangleTexture, width:Int, height:Int, glFormat:Int}>
	{
		if (bytes.length < HEADER_SIZE) return null;

		// Verify ASTC magic
		if (bytes.get(0) != MAGIC_0 || bytes.get(1) != MAGIC_1
			|| bytes.get(2) != MAGIC_2 || bytes.get(3) != MAGIC_3)
		{
			Logger.log('AstcLoader: invalid magic in $path', WARN);
			return null;
		}

		var blockW:Int = bytes.get(4);
		var blockH:Int = bytes.get(5);
		// bytes[6] = block depth, always 1 for 2-D textures

		// Width and height are stored as 24-bit little-endian
		var width:Int  = bytes.get(7)  | (bytes.get(8)  << 8) | (bytes.get(9)  << 16);
		var height:Int = bytes.get(10) | (bytes.get(11) << 8) | (bytes.get(12) << 16);

		if (width <= 0 || height <= 0) return null;

		var glFormat:Int = blockSizeToGlFormat(blockW, blockH);
		if (glFormat == 0)
		{
			Logger.log('AstcLoader: unsupported block size ${blockW}x${blockH} in $path', WARN);
			return null;
		}

		// Require Stage3D context (available after the first render frame)
		var context3D:Null<Context3D> = FlxG.stage.stage3Ds[0].context3D;
		if (context3D == null) return null;
		var gl = context3D.gl;

		var astcTex = _uploadCompressed(gl, bytes, width, height, glFormat);
		if (astcTex == null) return null;

		// -----------------------------------------------------------------------
		// Wrap in an OpenFL RectangleTexture so BitmapData.fromTexture() works.
		// createRectangleTexture allocates a throw-away placeholder GL texture;
		// we delete it immediately and inject our ASTC texture instead.
		// -----------------------------------------------------------------------
		var rectTex:RectangleTexture = context3D.createRectangleTexture(width, height, Context3DTextureFormat.BGRA, false);
		gl.deleteTexture(rectTex.__textureID); // free the placeholder
		rectTex.__textureID = astcTex;         // inject ASTC texture

		var bitmap = BitmapData.fromTexture(rectTex);
		return {bitmap: bitmap, rectTex: rectTex, width: width, height: height, glFormat: glFormat};
	}

	/**
	 * Uploads the ASTC payload (bytes after the 16-byte header) to a new GL
	 * texture with the given compressed format and returns the texture object,
	 * or null on GL error.
	 */
	static function _uploadCompressed(gl:Dynamic, bytes:haxe.io.Bytes, width:Int, height:Int, glFormat:Int):Dynamic
	{
		var imgLen:Int = bytes.length - HEADER_SIZE;
		var imgData = new UInt8Array(imgLen);
		for (i in 0...imgLen)
			imgData[i] = bytes.get(HEADER_SIZE + i);

		var astcTex = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, astcTex);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.compressedTexImage2D(gl.TEXTURE_2D, 0, glFormat, width, height, 0, imgData);
		gl.bindTexture(gl.TEXTURE_2D, null);

		var glErr:Int = gl.getError();
		if (glErr != 0)
		{
			gl.deleteTexture(astcTex);
			Logger.log('AstcLoader: GL error 0x${StringTools.hex(glErr, 4)}', WARN);
			return null;
		}

		return astcTex;
	}

	/**
	 * Called when the Stage3D context is created or recreated after context loss.
	 *
	 * For each tracked texture:
	 *   • glFormat != 0 (ASTC mode): uses cachedBytes if available (no I/O for
	 *     small textures), else re-reads from disk/APK. On missing file, falls
	 *     through to PNG fallback.
	 *   • glFormat == 0 (PNG fallback mode): re-uploads from the original PNG.
	 *
	 * On the initial CONTEXT3D_CREATE (before any ASTC textures are loaded) the
	 * recovery map is empty and this function returns immediately.
	 */
	static function _onContextRestored(_:Dynamic):Void
	{
		var context3D:Null<Context3D> = FlxG.stage.stage3Ds[0].context3D;
		if (context3D == null) return;
		var gl = context3D.gl;

		var restored = 0;
		var failed = 0;
		var toRemove:Array<String> = [];

		// pngPath (the map key) is the original PNG asset path, which doubles as
		// the FunkinCache cache key. This loop is synchronous: small textures skip
		// I/O via cachedBytes; large ones (> BYTES_CACHE_LIMIT) re-read from disk.
		// If testing reveals a noticeable resume stutter, stagger 1-2 textures per
		// frame with a FlxTimer queue — _recovery stays the authoritative source.
		for (pngPath => entry in _recovery)
		{
			// PNG fallback mode — the .astc was missing on a previous restore;
			// this entry now permanently uses the PNG source.
			if (entry.glFormat == 0)
			{
				if (_restoreFromPng(context3D, pngPath))
					restored++;
				else
				{
					toRemove.push(pngPath);
					failed++;
				}
				continue;
			}

			// ASTC mode: prefer in-RAM cached bytes (small textures), otherwise
			// re-read from disk/APK to avoid an I/O stall only when necessary.
			var bytes:Null<haxe.io.Bytes> = entry.cachedBytes;
			if (bytes == null)
			{
				try
				{
					if (sys.FileSystem.exists(entry.astcPath))
						bytes = sys.io.File.getBytes(entry.astcPath);
					else if (OflAssets.exists(entry.astcPath))
						bytes = OflAssets.getBytes(entry.astcPath);
				}
				catch (e:Dynamic) {}
			}

			if (bytes == null)
			{
				// .astc file disappeared (DLC removed, SD-card corruption, etc.).
				// Attempt PNG fallback so live sprites are not permanently black.
				Logger.log('AstcLoader: context restore — ${entry.astcPath} missing, trying PNG fallback', WARN);
				if (_restoreFromPng(context3D, pngPath))
					restored++;
				else
				{
					toRemove.push(pngPath);
					failed++;
				}
				continue;
			}

			var freshTex = _uploadCompressed(gl, bytes, entry.width, entry.height, entry.glFormat);
			if (freshTex == null)
			{
				// GL upload error (driver-side failure). PNG fallback won't help
				// since the context itself may be in a bad state. Skip and log.
				failed++;
				continue;
			}

			// The old __textureID is a dead handle after context loss; the driver
			// already freed all GPU resources. Overwrite with the fresh handle.
			// The BitmapData holds a reference to this same RectangleTexture, so
			// the renderer automatically uses the new handle on the next draw.
			entry.rectTex.__textureID = freshTex;
			restored++;
		}

		for (key in toRemove)
			_recovery.remove(key);

		if (restored > 0 || failed > 0)
			Logger.log('AstcLoader: context restored — $restored textures re-uploaded, $failed failed', WARN);
	}

	/**
	 * Restores a tracked texture from its PNG counterpart.
	 *
	 * Creates a temporary RectangleTexture, uploads the PNG BitmapData to it
	 * via OpenFL's standard path (handles BGRA/RGBA format internally), then
	 * transfers the GL handle to entry.rectTex. Sets the temporary wrapper's
	 * __textureID to 0 so any future cleanup call on it is a harmless no-op
	 * (gl.deleteTexture(0) is defined as a no-op by the GL spec).
	 *
	 * Permanently marks the entry as PNG mode (glFormat = 0) so all subsequent
	 * context-restore cycles also re-upload from PNG without retrying the ASTC.
	 */
	static function _restoreFromPng(context3D:Context3D, pngPath:String):Bool
	{
		var entry = _recovery.get(pngPath);
		if (entry == null) return false;

		var pngBitmap:Null<BitmapData> = null;
		try
		{
			// Mirrors FunkinAssets.getBitmapData: filesystem first (external
			// storage / mods, absolute path), then OflAssets for APK-bundled
			// assets (relative path — not on the real filesystem, so
			// sys.FileSystem.exists returns false and we fall through).
			if (sys.FileSystem.exists(pngPath))
				pngBitmap = BitmapData.fromFile(pngPath);
			else if (OflAssets.exists(pngPath))
				pngBitmap = OflAssets.getBitmapData(pngPath);
		}
		catch (e:Dynamic) {}

		if (pngBitmap == null)
		{
			Logger.log('AstcLoader: PNG fallback failed for $pngPath — file not found', WARN);
			return false;
		}

		// Upload PNG pixels via OpenFL's standard path (format conversion handled
		// internally) into a temporary RectangleTexture, then steal its GL handle.
		var tempTex:RectangleTexture = context3D.createRectangleTexture(
			pngBitmap.width, pngBitmap.height, Context3DTextureFormat.BGRA, false);
		tempTex.uploadFromBitmapData(pngBitmap);
		var handle = tempTex.__textureID;
		tempTex.__textureID = 0; // orphan wrapper — handle ownership moves to entry.rectTex
		entry.rectTex.__textureID = handle;
		pngBitmap.dispose();

		// Mark entry as PNG mode for all future context-restore cycles.
		entry.glFormat = 0;
		entry.cachedBytes = null; // ASTC bytes no longer needed

		Logger.log('AstcLoader: PNG fallback succeeded for $pngPath', WARN);
		return true;
	}

	/**
	 * Maps an ASTC block size to the corresponding GL_COMPRESSED_RGBA_ASTC_*_KHR
	 * constant (RGBA linear variants, 0x93B0-0x93BD).
	 * Returns 0 for unknown block sizes.
	 */
	static function blockSizeToGlFormat(bw:Int, bh:Int):Int
	{
		return switch ([bw, bh])
		{
			case [4, 4]:   0x93B0; // GL_COMPRESSED_RGBA_ASTC_4x4_KHR
			case [5, 4]:   0x93B1;
			case [5, 5]:   0x93B2; // GL_COMPRESSED_RGBA_ASTC_5x5_KHR
			case [6, 5]:   0x93B3;
			case [6, 6]:   0x93B4; // GL_COMPRESSED_RGBA_ASTC_6x6_KHR
			case [8, 5]:   0x93B5;
			case [8, 6]:   0x93B6;
			case [8, 8]:   0x93B7; // GL_COMPRESSED_RGBA_ASTC_8x8_KHR  ← default for this project
			case [10, 5]:  0x93B8;
			case [10, 6]:  0x93B9;
			case [10, 8]:  0x93BA;
			case [10, 10]: 0x93BB; // GL_COMPRESSED_RGBA_ASTC_10x10_KHR
			case [12, 10]: 0x93BC;
			case [12, 12]: 0x93BD; // GL_COMPRESSED_RGBA_ASTC_12x12_KHR
			default: 0;
		};
	}

	/**
	 * Derives the ASTC file path from a PNG asset path.
	 * The .astc file lives next to the .png — only the extension changes.
	 *
	 *   assets/images/characters/bf.png  →  assets/images/characters/bf.astc
	 *   /sdcard/.ImpostorLegacy/assets/images/bf.png
	 *     → /sdcard/.ImpostorLegacy/assets/images/bf.astc
	 */
	public static function deriveAstcPath(pngPath:String):Null<String>
	{
		if (!pngPath.endsWith('.png')) return null;
		return pngPath.substr(0, pngPath.length - 4) + '.astc';
	}

	#end // android && cpp
}
