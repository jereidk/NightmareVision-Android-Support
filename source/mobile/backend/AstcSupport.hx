package mobile.backend;

import funkin.backend.Logger;

#if (android && cpp)
import lime.graphics.opengl.GL;
#end

/**
 * Detects runtime ASTC texture compression support on the current device.
 * Call check() once during initialization; then read isSupported.
 */
class AstcSupport
{
	static var _isSupported:Null<Bool> = null;
	static var _maxTextureSize:Int     = 4096; // conservative default

	public static var isSupported(get, never):Bool;
	/** Maximum GL texture dimension reported by the device GPU. */
	public static var maxTextureSize(get, never):Int;

	static inline function get_isSupported():Bool
	{
		if (_isSupported == null) check();
		return _isSupported == true;
	}

	static inline function get_maxTextureSize():Int
	{
		if (_isSupported == null) check();
		return _maxTextureSize;
	}

	/**
	 * Probes the GL extension string for GL_KHR_texture_compression_astc_ldr.
	 * Safe to call multiple times — subsequent calls are no-ops.
	 * Must be called after the OpenGL context is initialized.
	 */
	public static function check():Void
	{
		if (_isSupported != null) return;

		#if (android && cpp)
		try
		{
			// 0x1F03 = GL_EXTENSIONS
			var ext:Null<String> = GL.getString(0x1F03);
			_isSupported = ext != null
				&& (ext.contains("GL_KHR_texture_compression_astc_ldr")
					|| ext.contains("GL_KHR_texture_compression_astc_hdr"));
		}
		catch (e:Dynamic)
		{
			_isSupported = false;
		}
		try
		{
			// 0x0D33 = GL_MAX_TEXTURE_SIZE
			final v:Int = GL.getParameter(0x0D33);
			if (v > 0) _maxTextureSize = v;
		}
		catch (_:Dynamic) {}
		Logger.log('ASTC texture compression: ${_isSupported == true ? "supported" : "not supported"}  |  GL_MAX_TEXTURE_SIZE: $_maxTextureSize px', NOTICE);
		#else
		_isSupported = false;
		#end
	}
}
