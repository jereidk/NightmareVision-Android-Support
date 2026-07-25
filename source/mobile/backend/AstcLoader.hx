package mobile.backend;

import funkin.backend.Logger;

#if (android && cpp)
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.RectangleTexture;
import openfl.display3D.textures.TextureBase;
import openfl.Assets as OflAssets;
import openfl.Assets;
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

	// Regular (non-ASTC) bitmaps whose CPU pixel buffer FunkinCache's
	// `gpuCaching` freed via disposeImage(). Unlike the ASTC map above,
	// these were never GPU-only -- they have a real source file, so recovery
	// doesn't need the RectangleTexture-handle-stealing dance the ASTC path
	// requires. See _restoreGpuCachedBitmap().
	static var _gpuCachedBitmaps:Map<String, BitmapData> = [];
	#end

	/**
	 * Installs the CONTEXT3D_CREATE listener that re-uploads all tracked ASTC
	 * textures after an OpenGL context loss/restore cycle, and requests the
	 * Stage3D's Context3D so tryLoad()/_loadInternal() actually get one.
	 *
	 * Nothing else in this codebase (or in OpenFL's own OpenGL-renderer
	 * bootstrap) ever calls `stage3D.requestContext3D()` on its own -- that
	 * call is the only thing that populates `stage3Ds[0].context3D`
	 * (Stage3D.__createContext() just does `context3D = stage.context3D`,
	 * a reference to the SAME Context3D OpenFL's normal 2D renderer already
	 * created and is already drawing every frame with -- see
	 * openfl.display.Stage's own OPENGL-renderer setup -- so this does not
	 * create a second/competing GL context or affect 2D rendering at all).
	 * Without ever requesting it, `stage3Ds[0].context3D` stays null for the
	 * entire session, so every tryLoad() call permanently no-ops past its
	 * "no Stage3D context yet" guard and silently falls through to the PNG
	 * fallback -- fine for assets that ship both, but the actual bug behind
	 * DLC/optional song assets that ship ASTC-only ever rendering as the
	 * Flixel-logo fallback instead of loading.
	 *
	 * Safe to call multiple times — only installs once.
	 * Call from Init.hx right after AstcSupport.check().
	 */
	public static function installContextHandler():Void
	{
		#if (android && cpp)
		if (_listenerInstalled) return;
		_listenerInstalled = true;
		var stage3D = FlxG.stage.stage3Ds[0];
		// Must add the listener before requestContext3D() -- it throws if none is present.
		stage3D.addEventListener(Event.CONTEXT3D_CREATE, _onContextRestored);
		stage3D.requestContext3D();
		#end
	}

	/**
	 * Registers a regular (non-ASTC) BitmapData for context-loss recovery.
	 * Call from FunkinCache.cacheBitmap() right before bitmap.disposeImage()
	 * -- once that runs, OpenFL frees this BitmapData's CPU pixels the next
	 * time it uploads to the GPU (see BitmapData.getTexture()'s own
	 * `if (!readable && image != null) image = null;`), so a later context
	 * loss recreates an empty texture with nothing left to re-upload from.
	 * Tracking it here means _onContextRestored() can re-decode the
	 * original file and hand it a fresh `image` to upload instead.
	 */
	public static function trackGpuCached(key:String, bitmap:BitmapData):Void
	{
		#if (android && cpp)
		_gpuCachedBitmaps.set(key, bitmap);
		#end
	}

	/** Stops tracking a gpuCaching'd bitmap -- call when it's evicted from FunkinCache. */
	public static function untrackGpuCached(key:String):Void
	{
		#if (android && cpp)
		_gpuCachedBitmaps.remove(key);
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
		if (!AstcSupport.isSupported) {
			// Logger.log('[AstcLoader] ASTC not supported on this device', NOTICE);
			return null;
		}

		var astcPath = deriveAstcPath(pngPath);
		if (astcPath == null) {
			Logger.log('[AstcLoader] Cannot derive ASTC path from: ' + pngPath, WARN);
			return null;
		}

		// On Android, convert relative path to absolute path for external storage.
		// This matches the pattern already used by FunkinAssets.getBitmapData().
		// See FunkinAssets.androidStoragePath() for why this is needed on Android.
		var loadPath = funkin.FunkinAssets.androidStoragePath(astcPath);
		
		var bytes:Null<haxe.io.Bytes> = null;

		try
		{
			// External storage (extracted APK assets, DLC overrides) takes priority.
			if (sys.FileSystem.exists(loadPath))
			{
				bytes = sys.io.File.getBytes(loadPath);
			}
			// Bundled APK asset — allows shipping pre-compressed ASTC inside the APK.
			else if (OflAssets.exists(astcPath) || Assets.exists(astcPath))
			{
				bytes = OflAssets.getBytes(astcPath);
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('AstcLoader: failed to read $astcPath — $e', WARN);
		}

		if (bytes != null)
		{
			return loadAndTrack(pngPath, astcPath, bytes);
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
	 *
	 * Public (unlike the other internal helpers in this file) because
	 * LoadingState's background preload thread reads ASTC bytes off disk
	 * ahead of time (safe, no GL involved) and hands them to this function
	 * on the MAIN thread during its per-frame finalize step -- the actual
	 * GL upload this does can only ever run there. `pngPath` doubles as the
	 * FunkinCache/FlxG.bitmap cache key the caller should register the
	 * result under (see _loadInternal()'s own GL-upload code for why that
	 * doesn't happen automatically here).
	 */
	public static function loadAndTrack(pngPath:String, astcPath:String, bytes:haxe.io.Bytes):Null<BitmapData>
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

		if (width <= 0 || height <= 0 || width > 16384 || height > 16384)
		{
			Logger.log('AstcLoader: invalid dimensions ${width}x${height} parsed from $path (bytes.length=${bytes.length}) — corrupt/truncated file?', WARN);
			return null;
		}

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

		var astcTex = _uploadCompressed(gl, bytes, width, height, glFormat, path);
		if (astcTex == null) return null;

		// -----------------------------------------------------------------------
		// Wrap in an OpenFL RectangleTexture so BitmapData.fromTexture() works.
		// createRectangleTexture allocates a throw-away placeholder GL texture;
		// we delete it immediately and inject our ASTC texture instead.
		// If either call throws (OOM, invalid context), clean up the GL handle
		// before propagating so it doesn't leak.
		// -----------------------------------------------------------------------
		try
		{
			var rectTex:RectangleTexture = context3D.createRectangleTexture(width, height, Context3DTextureFormat.BGRA, false);
			gl.deleteTexture(rectTex.__textureID); // free the placeholder
			rectTex.__textureID = astcTex;         // inject ASTC texture
			var bitmap = BitmapData.fromTexture(rectTex);
			return {bitmap: bitmap, rectTex: rectTex, width: width, height: height, glFormat: glFormat};
		}
		catch (e:Dynamic)
		{
			gl.deleteTexture(astcTex);
			Logger.log('AstcLoader: failed to wrap GL texture in $path — $e', WARN);
			return null;
		}
	}

	/**
	 * Uploads the ASTC payload (bytes after the 16-byte header) to a new GL
	 * texture with the given compressed format and returns the texture object,
	 * or null on GL error.
	 */
	static function _uploadCompressed(gl:Dynamic, bytes:haxe.io.Bytes, width:Int, height:Int, glFormat:Int, path:String):Dynamic
	{
		var imgLen:Int = bytes.length - HEADER_SIZE;
		// Zero-copy view: UInt8Array.fromBytes wraps the existing haxe.io.Bytes (ArrayBuffer
		// is an abstract over Bytes, so no allocation) and initBuffer assigns the reference
		// directly — the payload starts at HEADER_SIZE so no offset math needed in GL.
		var imgData = UInt8Array.fromBytes(bytes, HEADER_SIZE, imgLen);

		var astcTex = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, astcTex);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		while (gl.getError() != 0) {} // drain any pre-existing errors so the check below is unambiguous
		// gl is Dynamic (context3D.gl, not the statically-typed lime.graphics.opengl.GL),
		// so a wrong argument count here compiles fine and only fails at runtime as a driver-
		// level GL error -- lime.graphics.opengl.GL.compressedTexImage2D's real signature is
		// (target, level, internalformat, width, height, border, imageSize, data); this was
		// missing imageSize entirely, silently shifting/dropping args at the native call.
		gl.compressedTexImage2D(gl.TEXTURE_2D, 0, glFormat, width, height, 0, imgLen, imgData);
		gl.bindTexture(gl.TEXTURE_2D, null);

		var glErr:Int = gl.getError();
		if (glErr != 0)
		{
			gl.deleteTexture(astcTex);
			Logger.log('AstcLoader: GL error 0x${StringTools.hex(glErr, 4)} uploading $path (${width}x${height}, glFormat=0x${StringTools.hex(glFormat, 4)}, imgLen=$imgLen)', WARN);
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
			// If the graphic is no longer in FlxG.bitmap the sprite that owned it was
			// destroyed without going through FunkinCache.removeFromCache (e.g.
			// FlxAnimateSpritemapCollection.destroySpritemaps calls FlxG.bitmap.remove
			// directly). There is nothing left to restore — skip the GPU upload and
			// evict this entry so _recovery stays lean. FunkinCache will finish its own
			// cleanup on the next clearUnusedMemory call.
			if (!FlxG.bitmap.checkCache(pngPath))
			{
				toRemove.push(pngPath);
				continue;
			}

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
					// Convert to absolute path on Android (matching tryLoad() behavior)
					var loadPath = funkin.FunkinAssets.androidStoragePath(entry.astcPath);
					
					if (sys.FileSystem.exists(loadPath))
						bytes = sys.io.File.getBytes(loadPath);
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

			var freshTex = _uploadCompressed(gl, bytes, entry.width, entry.height, entry.glFormat, entry.astcPath);
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

		// Same context-restore pass also re-primes gpuCaching's regular
		// bitmaps -- separate loop since these were never tracked via the
		// ASTC/RectangleTexture path above and don't need context3D at all
		// (see _restoreGpuCachedBitmap()).
		var gpuRestored = 0;
		var gpuFailed = 0;
		var gpuToRemove:Array<String> = [];

		for (key => bitmap in _gpuCachedBitmaps)
		{
			// Same "sprite destroyed outside FunkinCache.removeFromCache()"
			// case as the ASTC loop above -- nothing left to restore.
			if (!FlxG.bitmap.checkCache(key))
			{
				gpuToRemove.push(key);
				continue;
			}

			if (_restoreGpuCachedBitmap(key, bitmap))
				gpuRestored++;
			else
			{
				gpuToRemove.push(key);
				gpuFailed++;
			}
		}

		for (key in gpuToRemove)
			_gpuCachedBitmaps.remove(key);

		if (gpuRestored > 0 || gpuFailed > 0)
			Logger.log('AstcLoader: gpuCaching context restore — $gpuRestored bitmap(s) re-primed, $gpuFailed failed', WARN);
	}

	/**
	 * Re-decodes the original asset at `key` and hands its fresh pixel data
	 * to the SAME BitmapData object already tracked for that key -- same
	 * object identity, so every FlxGraphic/sprite already holding a
	 * reference to it picks up the change automatically, no need to touch
	 * them individually.
	 *
	 * Unlike _restoreFromPng() (which manually recreates and patches a GL
	 * texture handle because ASTC BitmapDatas are GPU-only with no `image`
	 * to fall back on), this bitmap DOES still have its own texture
	 * management -- BitmapData.getTexture() already re-uploads on its own
	 * whenever `image` is non-null and the context changed. Explicitly
	 * clearing the stale texture fields forces that recreate-and-upload path
	 * to run on the very next draw instead of relying on its own
	 * __textureContext check to notice on its own.
	 */
	static function _restoreGpuCachedBitmap(key:String, bitmap:BitmapData):Bool
	{
		var fresh:Null<BitmapData> = null;
		try
		{
			// Filesystem first (external storage / mods, absolute path),
			// then OflAssets for APK-bundled assets.  Uses androidStoragePath()
			// so mod overrides on external storage are found before falling
			// through to the bundled APK copy.
			var gpuLoadPath = funkin.FunkinAssets.androidStoragePath(key);
			if (sys.FileSystem.exists(gpuLoadPath))
				fresh = BitmapData.fromFile(gpuLoadPath);
			else if (OflAssets.exists(key))
				// useCache=false: always decode fresh, never the cached
				// copy -- it may be this exact same disposed bitmap.
				fresh = OflAssets.getBitmapData(key, false);
		}
		catch (e:Dynamic) {}

		if (fresh == null || fresh.image == null)
		{
			Logger.log('AstcLoader: gpuCaching restore failed for $key — source unreadable', WARN);
			return false;
		}

		bitmap.image = fresh.image;
		bitmap.__isValid = true;
		bitmap.__texture = null;
		bitmap.__textureContext = null;
		bitmap.__textureVersion = -1;

		return true;
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
			// Filesystem first (external storage / mods, absolute path),
			// then OflAssets for APK-bundled assets.  Uses androidStoragePath()
			// so mod overrides on external storage are found before falling
			// through to the bundled APK copy.
			var pngLoadPath = funkin.FunkinAssets.androidStoragePath(pngPath);
			if (sys.FileSystem.exists(pngLoadPath))
				pngBitmap = BitmapData.fromFile(pngLoadPath);
			else if (OflAssets.exists(pngPath))
				// useCache=false: always decode fresh — the cached copy may have had disposeImage() called on it
				pngBitmap = OflAssets.getBitmapData(pngPath, false);
		}
		catch (e:Dynamic) {}

		if (pngBitmap == null)
		{
			Logger.log('AstcLoader: PNG fallback failed for $pngPath — file not found', WARN);
			return false;
		}

		if (pngBitmap.width != entry.width || pngBitmap.height != entry.height)
			Logger.log('AstcLoader: PNG fallback size mismatch for $pngPath — PNG ${pngBitmap.width}x${pngBitmap.height}, ASTC was ${entry.width}x${entry.height}', WARN);

		// Upload PNG pixels via OpenFL's standard path (format conversion handled
		// internally) into a temporary RectangleTexture, then steal its GL handle.
		var gl = context3D.gl;
		var tempTex:RectangleTexture = context3D.createRectangleTexture(
			pngBitmap.width, pngBitmap.height, Context3DTextureFormat.BGRA, false);
		tempTex.uploadFromBitmapData(pngBitmap);

		var uploadErr:Int = gl.getError();
		if (uploadErr != 0)
		{
			Logger.log('AstcLoader: PNG fallback upload error 0x${StringTools.hex(uploadErr, 4)} for $pngPath', WARN);
			tempTex.dispose();
			pngBitmap.dispose();
			return false;
		}

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
