package mobile.backend;

import funkin.backend.Logger;

#if (android && cpp)
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.ASTCTexture;
import openfl.display3D.textures.RectangleTexture;
import openfl.display3D.textures.TextureBase;
import openfl.Assets as OflAssets;
import openfl.Assets;
import openfl.events.Event;
#end

/**
 * Loads raw ASTC texture files into OpenFL BitmapData backed by a GPU-side
 * compressed texture, via Context3D.createASTCTexture() -- the same public
 * API openfl.utils.Assets.getBitmapData() already uses internally (see
 * openfl/utils/Assets.hx) to transparently load every APK-bundled ASTC-only
 * asset in this game. That existing path only ever checks Lime's compiled
 * asset manifest (LimeAssets.exists/getBytes), so it can never see loose
 * files added after the APK was built -- e.g. downloaded song DLC extracted
 * onto external storage. This class exists purely to cover THAT gap: same
 * upload mechanism, external storage (and APK) checked directly instead.
 *
 * Previously this class hand-rolled its own GL texture upload against
 * FlxG.stage.stage3Ds[0].context3D -- a *separate* Stage3D object nothing
 * in this codebase ever calls requestContext3D() on, so that context3D was
 * permanently null and this loader never actually uploaded a single texture
 * in any shipped build (every asset silently fell through past it). Fixed
 * by routing through openfl.Lib.current.stage.context3D instead -- the
 * main Stage's own Context3D, already created unconditionally by OpenFL's
 * renderer setup (openfl/display/Stage.hx) and already what the native
 * Assets.getBitmapData() ASTC path above uses -- and letting
 * createASTCTexture() do its own (already-correct) header parsing/GL
 * upload instead of reimplementing it by hand.
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
 * listener (still on FlxG.stage.stage3Ds[0] -- confirmed in openfl/display/
 * Stage.hx's __onLimeRenderContextRestored() that EVERY registered Stage3D,
 * including ones that never called requestContext3D(), gets its
 * __restoreContext() -- and therefore this event -- fired on a genuine
 * render-context restore) that re-uploads every tracked ASTC texture,
 * patching the existing ASTCTexture's GL handle in-place so all live
 * BitmapData instances automatically see fresh GPU data.
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
	// restoration can skip the disk re-read for small/medium textures.
	// At ASTC 8×8 this covers textures up to ~1024×1024.
	// Larger spritemaps re-read from disk on restore (lower RAM overhead vs.
	// occasional resume stutter is the accepted tradeoff).

	#if (android && cpp)
	// Keyed by PNG path (= FunkinCache cache key).
	static var _recovery:Map<String, {
		astcPath:      String,
		astcTex:       ASTCTexture,
		width:         Int,
		height:        Int,
		isPngFallback: Bool,
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

		// External storage (extracted APK assets, DLC overrides) takes priority.
		if (sys.FileSystem.exists(astcPath))
		{

			try
			{
				var bytes = sys.io.File.getBytes(astcPath);

				return loadAndTrack(pngPath, astcPath, bytes);
			}
			catch (e:Dynamic)
			{

				Logger.log('AstcLoader: failed to read $astcPath — $e', WARN);
				return null;
			}
		}

		// Bundled APK asset — allows shipping pre-compressed ASTC inside the APK.
		if (OflAssets.exists(astcPath) || Assets.exists(astcPath))
		{
			var bytes = OflAssets.getBytes(astcPath);
			if (bytes != null) {
				return loadAndTrack(pngPath, astcPath, bytes);
			}
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

			_recovery.set(pngPath, {
				astcPath:      astcPath,
				astcTex:       result.astcTex,
				width:         result.width,
				height:        result.height,
				isPngFallback: false,
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
	 * Uploads the ASTC bytes to the GPU via Context3D.createASTCTexture() --
	 * the same public OpenFL API openfl.utils.Assets.getBitmapData() already
	 * uses for every APK-bundled ASTC asset -- and wraps the result in a
	 * BitmapData. createASTCTexture() does its own header parsing/validation
	 * and GL upload internally (see openfl/display3D/textures/ASTCTexture.hx),
	 * so there is no manual magic-byte/block-size parsing or raw GL call here
	 * to get wrong.
	 */
	static function _loadInternal(path:String, bytes:haxe.io.Bytes):Null<{bitmap:BitmapData, astcTex:ASTCTexture, width:Int, height:Int}>
	{
		// The main Stage's own Context3D -- created unconditionally by OpenFL's
		// renderer setup (openfl/display/Stage.hx), NOT the separate
		// FlxG.stage.stage3Ds[0] Stage3D this loader used to (and never
		// successfully did, since nothing ever requests it).
		var context3D:Null<Context3D> = openfl.Lib.current.stage.context3D;
		if (context3D == null) return null;

		try
		{
			var astcTex = context3D.createASTCTexture(bytes);
			var bitmap = BitmapData.fromTexture(astcTex);
			return {bitmap: bitmap, astcTex: astcTex, width: astcTex.__width, height: astcTex.__height};
		}
		catch (e:Dynamic)
		{
			Logger.log('AstcLoader: createASTCTexture failed for $path — $e', WARN);
			return null;
		}
	}

	/**
	 * Called when the Stage3D context is created or recreated after context loss.
	 * (FlxG.stage.stage3Ds[0]'s CONTEXT3D_CREATE still fires here even though
	 * nothing ever calls requestContext3D() on it -- see this class's own doc
	 * comment. What actually matters for a real re-upload is the MAIN Stage's
	 * context3D below, which gets replaced with a brand-new Context3D instance
	 * by OpenFL on every real context loss/restore cycle.)
	 *
	 * For each tracked texture:
	 *   • isPngFallback == false (ASTC mode): re-reads from disk/APK. On missing
	 *     file, falls through to PNG fallback.
	 *   • isPngFallback == true: re-uploads from the original PNG.
	 *
	 * On the initial CONTEXT3D_CREATE (before any ASTC textures are loaded) the
	 * recovery map is empty and this function returns immediately.
	 */
	static function _onContextRestored(_:Dynamic):Void
	{
		var context3D:Null<Context3D> = openfl.Lib.current.stage.context3D;
		if (context3D == null) return;

		var restored = 0;
		var failed = 0;
		var toRemove:Array<String> = [];

		// pngPath (the map key) is the original PNG asset path, which doubles as
		// the FunkinCache cache key. This loop is synchronous: small textures skip
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
			if (entry.isPngFallback)
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

			// ASTC mode: re-read from disk/APK on every restore.
			var bytes:Null<haxe.io.Bytes> = null;
			try
			{
				if (sys.FileSystem.exists(entry.astcPath))
					bytes = sys.io.File.getBytes(entry.astcPath);
				else if (OflAssets.exists(entry.astcPath))
					bytes = OflAssets.getBytes(entry.astcPath);
			}
			catch (e:Dynamic) {}

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

			// The old __textureID is a dead handle after context loss; the driver
			// already freed all GPU resources. Build a fresh ASTCTexture against
			// the (also fresh) context3D purely to get a new, valid GL handle,
			// then steal it into the ORIGINAL entry.astcTex object -- the live
			// BitmapData's __texture already permanently references that same
			// object, so patching its __textureID in place is all that's needed
			// for the renderer to pick up the new handle on the next draw.
			try
			{
				var freshTex = context3D.createASTCTexture(bytes);
				entry.astcTex.__textureID = freshTex.__textureID;
				freshTex.__textureID = 0; // orphan wrapper -- ownership moved to entry.astcTex
				restored++;
			}
			catch (e:Dynamic)
			{
				// GL upload error (driver-side failure). PNG fallback won't help
				// since the context itself may be in a bad state. Skip and log.
				Logger.log('AstcLoader: context restore upload failed for ${entry.astcPath} — $e', WARN);
				failed++;
			}
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
			// Mirrors _restoreFromPng(): filesystem first (external storage /
			// mods, absolute path), then OflAssets for APK-bundled assets.
			if (sys.FileSystem.exists(key))
				fresh = BitmapData.fromFile(key);
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
	 * transfers the GL handle to entry.astcTex (still a valid TextureBase to
	 * patch in place -- the live BitmapData's __texture already permanently
	 * references that same object). Sets the temporary wrapper's __textureID
	 * to 0 so any future cleanup call on it is a harmless no-op
	 * (gl.deleteTexture(0) is defined as a no-op by the GL spec).
	 *
	 * Permanently marks the entry as PNG mode (isPngFallback = true) so all
	 * subsequent context-restore cycles also re-upload from PNG without
	 * retrying the ASTC.
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
		tempTex.__textureID = 0; // orphan wrapper — handle ownership moves to entry.astcTex
		entry.astcTex.__textureID = handle;
		pngBitmap.dispose();

		// Mark entry as PNG mode for all future context-restore cycles.
		entry.isPngFallback = true;

		Logger.log('AstcLoader: PNG fallback succeeded for $pngPath', WARN);
		return true;
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
