package mobile.backend;

import funkin.backend.Logger;

#if (android && cpp)
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.RectangleTexture;
import openfl.display3D.textures.TextureBase;
import lime.utils.UInt8Array;
#end

/**
 * Loads raw ASTC texture files (16-byte header + compressed blocks) into
 * OpenFL BitmapData backed by a GPU-side compressed texture.
 *
 * ASTC files are placed in a mirror folder: assets/astc/<same-path>.astc
 * alongside the original assets/…/foo.png.  The original PNGs are never
 * touched.  On devices that do not expose GL_KHR_texture_compression_astc_ldr
 * the loader returns null and the caller falls through to the PNG.
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

	/**
	 * Derives the ASTC path for a PNG path and attempts to load it.
	 * Returns null if ASTC is unsupported, the .astc file doesn't exist,
	 * or loading fails for any reason — caller should then load the PNG.
	 */
	public static function tryLoad(pngPath:String):Null<BitmapData>
	{
		#if (android && cpp)
		if (!AstcSupport.isSupported) return null;

		var astcPath = deriveAstcPath(pngPath);
		if (astcPath == null) return null;
		if (!sys.FileSystem.exists(astcPath)) return null;

		return load(astcPath);
		#else
		return null;
		#end
	}

	/**
	 * Loads an .astc file from the filesystem and returns a GPU-backed BitmapData.
	 * Only call this after confirming the file exists and ASTC is supported.
	 */
	public static function load(astcPath:String):Null<BitmapData>
	{
		#if (android && cpp)
		try
		{
			return loadInternal(astcPath);
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

	static function loadInternal(path:String):Null<BitmapData>
	{
		var bytes = sys.io.File.getBytes(path);
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
		var width:Int = bytes.get(7) | (bytes.get(8) << 8) | (bytes.get(9) << 16);
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

		// -----------------------------------------------------------------------
		// Upload ASTC payload to a new GL texture
		// -----------------------------------------------------------------------
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
			Logger.log('AstcLoader: GL error 0x${StringTools.hex(glErr, 4)} for $path', WARN);
			return null;
		}

		// -----------------------------------------------------------------------
		// Wrap in an OpenFL RectangleTexture so BitmapData.fromTexture() works.
		// createRectangleTexture allocates a throw-away placeholder GL texture;
		// we delete it immediately and inject our ASTC texture instead.
		// -----------------------------------------------------------------------
		var rectTex:RectangleTexture = context3D.createRectangleTexture(width, height, Context3DTextureFormat.BGRA, false);
		gl.deleteTexture(rectTex.__textureID); // free the placeholder
		rectTex.__textureID = astcTex; // inject ASTC texture

		var bitmap = BitmapData.fromTexture(rectTex);
		return bitmap;
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
	 *
	 *   assets/game/images/foo.png
	 *     → assets/astc/game/images/foo.astc
	 *
	 *   /sdcard/.ImpostorLegacy/assets/game/images/foo.png
	 *     → /sdcard/.ImpostorLegacy/assets/astc/game/images/foo.astc
	 */
	public static function deriveAstcPath(pngPath:String):Null<String>
	{
		if (!pngPath.endsWith('.png')) return null;

		var stem = pngPath.substr(0, pngPath.length - 4);

		// Full filesystem path: /prefix/assets/rest
		var idx = stem.indexOf('/assets/');
		if (idx >= 0)
			return stem.substring(0, idx) + '/assets/astc/' + stem.substring(idx + '/assets/'.length) + '.astc';

		// Relative path: assets/rest
		if (stem.startsWith('assets/'))
			return 'assets/astc/' + stem.substring('assets/'.length) + '.astc';

		return null;
	}

	#end // android && cpp
}
