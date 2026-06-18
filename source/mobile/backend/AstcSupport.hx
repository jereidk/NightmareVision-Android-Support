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

	public static var isSupported(get, never):Bool;

	static inline function get_isSupported():Bool
	{
		if (_isSupported == null) check();
		return _isSupported == true;
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
		Logger.log('ASTC texture compression: ${_isSupported == true ? "supported" : "not supported"}', NOTICE);
		#else
		_isSupported = false;
		#end
	}
}
