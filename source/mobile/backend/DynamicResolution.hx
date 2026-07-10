package mobile.backend;

#if (android && cpp)
import openfl.display3D.Context3D;
import openfl.events.Event;
import lime.utils.Float32Array;
import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * True GPU-level DRS via temporal frame caching.
 *
 * When active, every other OpenFL GL render pass is SKIPPED entirely.
 * Instead the last fully rendered frame (stored via glCopyTexImage2D) is
 * blitted back to the back buffer as a fullscreen quad.
 *
 * Result: GL rasterisation drops to ~30fps, but Flixel game logic
 * (input, positions, draw-stack fills) continues at full 60fps tick rate.
 *
 * Architecture hookup — Application.hx render() override:
 *   shouldSkipRender() == true  → reuseLastFrame(); return;
 *   shouldSkipRender() == false → super.render(); saveCurrentFrame();
 *
 * Context loss: CONTEXT3D_CREATE re-initialises all GL objects.
 * GL handle is the same context3D.gl Dynamic used by AstcLoader.
 */
@:nullSafety(Off)
@:access(openfl.display3D.Context3D)
class DynamicResolution
{
	public static var active(default, null):Bool = false;

	static var _gl:Dynamic         = null;
	static var _storageTex:Dynamic = null;  // holds last rendered frame pixels
	static var _blitProg:Dynamic   = null;  // fullscreen-quad GLSL program
	static var _quadVBO:Dynamic    = null;  // 4 vertices: pos.xy + uv.xy
	static var _winW:Int           = 0;
	static var _winH:Int           = 0;
	static var _posLoc:Int         = -1;
	static var _uvLoc:Int          = -1;
	static var _texLoc:Int         = -1;
	static var _initialized:Bool   = false;
	static var _skipToggle:Bool    = false; // alternates each shouldSkipRender call

	// ── Public API ────────────────────────────────────────────────────────────

	/** Call once from Init.hx to register context-loss recovery. */
	public static function init():Void
	{
		FlxG.stage.stage3Ds[0].addEventListener(Event.CONTEXT3D_CREATE, _onContextCreate);
	}

	public static function setActive(value:Bool):Void
	{
		if (active == value) return;
		active = value;
		_skipToggle = false;
		if (active)
		{
			if (!_initialized) _tryCreateGL();
			Logger.log('[DRS] frame-cache on', NOTICE);
		}
		else
		{
			Logger.log('[DRS] frame-cache off', NOTICE);
		}
	}

	/**
	 * Called from Application.render() before super.render().
	 * Returns true when this frame should be skipped (reuse stored frame).
	 */
	public static function shouldSkipRender():Bool
	{
		if (!active || !_initialized || _storageTex == null) return false;
		_skipToggle = !_skipToggle;
		return _skipToggle; // true on every other frame
	}

	/**
	 * Draws the stored texture to the default back buffer as a fullscreen quad.
	 * Call when shouldSkipRender() returned true, instead of super.render().
	 */
	public static function reuseLastFrame():Void
	{
		if (_gl == null || _storageTex == null || _blitProg == null) return;
		final gl = _gl;

		gl.bindFramebuffer(gl.FRAMEBUFFER, null);
		gl.viewport(0, 0, _winW, _winH);
		gl.disable(gl.DEPTH_TEST);
		gl.disable(gl.BLEND);

		gl.useProgram(_blitProg);
		gl.activeTexture(gl.TEXTURE0);
		gl.bindTexture(gl.TEXTURE_2D, _storageTex);
		gl.uniform1i(_texLoc, 0);

		gl.bindBuffer(gl.ARRAY_BUFFER, _quadVBO);
		gl.enableVertexAttribArray(_posLoc);
		gl.vertexAttribPointer(_posLoc, 2, gl.FLOAT, false, 16, 0);
		gl.enableVertexAttribArray(_uvLoc);
		gl.vertexAttribPointer(_uvLoc, 2, gl.FLOAT, false, 16, 8);
		gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

		// Restore expected GL state for next render
		gl.disableVertexAttribArray(_posLoc);
		gl.disableVertexAttribArray(_uvLoc);
		gl.bindBuffer(gl.ARRAY_BUFFER, null);
		gl.bindTexture(gl.TEXTURE_2D, null);
		gl.useProgram(null);
		gl.enable(gl.BLEND);
		gl.flush(); // ensure commands reach GPU before eglSwapBuffers
	}

	/**
	 * Copies the default back buffer into the storage texture.
	 * Call after super.render() on non-skipped frames.
	 * glCopyTexImage2D reads the current READ framebuffer (default = 0).
	 */
	public static function saveCurrentFrame():Void
	{
		if (_gl == null || _storageTex == null) return;
		final gl = _gl;
		gl.bindTexture(gl.TEXTURE_2D, _storageTex);
		// copyTexSubImage2D instead of copyTexImage2D: the storage was already
		// allocated at _createGL() (texImage2D with null data), so re-defining
		// level 0 every rendered frame made tiled-GPU drivers treat it as a
		// brand-new texture allocation + full pipeline resolve each time.
		// SubImage reuses the existing storage and only pays for the copy.
		// x=0, y=0 reads from bottom-left of the back buffer (GL convention)
		gl.copyTexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 0, 0, _winW, _winH);
		gl.bindTexture(gl.TEXTURE_2D, null);
	}

	// ── GL lifecycle ──────────────────────────────────────────────────────────

	static function _onContextCreate(_:Dynamic):Void
	{
		_destroyGL();
		if (active) _tryCreateGL();
	}

	static function _tryCreateGL():Void
	{
		final ctx:Null<Context3D> = FlxG.stage.stage3Ds[0].context3D;
		if (ctx == null) return;
		final gl:Dynamic = ctx.gl;
		if (gl == null) return;
		_gl   = gl;
		_winW = FlxG.stage.window.width;
		_winH = FlxG.stage.window.height;
		_createGL();
	}

	static function _createGL():Void
	{
		final gl = _gl;
		try
		{
			// ── Storage texture ────────────────────────────────────────────
			// Full device resolution — we store one complete rendered frame.
			_storageTex = gl.createTexture();
			gl.bindTexture(gl.TEXTURE_2D, _storageTex);
			gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, _winW, _winH, 0,
				gl.RGBA, gl.UNSIGNED_BYTE, null);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
			gl.bindTexture(gl.TEXTURE_2D, null);

			// ── Blit shader ────────────────────────────────────────────────
			// Y-flip in fragment shader: glCopyTexImage2D stores the framebuffer
			// with GL's bottom-up convention (row 0 = screen bottom), but OpenFL
			// renders top-down, so the stored content reads upside-down without
			// flipping the V coordinate.
			final vsrc:String =
				"attribute vec2 aPos;" +
				"attribute vec2 aUV;" +
				"varying vec2 vUV;" +
				"void main(){" +
				"  vUV = aUV;" +
				"  gl_Position = vec4(aPos, 0.0, 1.0);" +
				"}";
			final fsrc:String =
				"precision mediump float;" +
				"uniform sampler2D uTex;" +
				"varying vec2 vUV;" +
				"void main(){" +
				"  gl_FragColor = texture2D(uTex, vec2(vUV.x, 1.0 - vUV.y));" +
				"}";

			final vs = gl.createShader(gl.VERTEX_SHADER);
			gl.shaderSource(vs, vsrc);
			gl.compileShader(vs);
			final fs = gl.createShader(gl.FRAGMENT_SHADER);
			gl.shaderSource(fs, fsrc);
			gl.compileShader(fs);

			_blitProg = gl.createProgram();
			gl.attachShader(_blitProg, vs);
			gl.attachShader(_blitProg, fs);
			gl.linkProgram(_blitProg);
			gl.deleteShader(vs);
			gl.deleteShader(fs);

			_posLoc = gl.getAttribLocation(_blitProg, "aPos");
			_uvLoc  = gl.getAttribLocation(_blitProg, "aUV");
			_texLoc = gl.getUniformLocation(_blitProg, "uTex");

			// ── Fullscreen quad VBO ────────────────────────────────────────
			// Triangle strip, NDC coordinates, UV (0-1):
			// bottom-left, bottom-right, top-left, top-right
			final verts = new Float32Array([
				-1.0, -1.0,  0.0, 0.0,
				 1.0, -1.0,  1.0, 0.0,
				-1.0,  1.0,  0.0, 1.0,
				 1.0,  1.0,  1.0, 1.0,
			]);

			_quadVBO = gl.createBuffer();
			gl.bindBuffer(gl.ARRAY_BUFFER, _quadVBO);
			gl.bufferData(gl.ARRAY_BUFFER, verts, gl.STATIC_DRAW);
			gl.bindBuffer(gl.ARRAY_BUFFER, null);

			_initialized = true;
			Logger.log('[DRS] GL frame-cache ready (${_winW}×${_winH})', NOTICE);
		}
		catch (e:Dynamic)
		{
			Logger.log('[DRS] GL init failed: $e', WARN);
			_destroyGL();
		}
	}

	static function _destroyGL():Void
	{
		if (_gl == null) { _initialized = false; return; }
		final gl = _gl;
		try { if (_storageTex != null) gl.deleteTexture(_storageTex);  } catch (_:Dynamic) {}
		try { if (_blitProg   != null) gl.deleteProgram(_blitProg);    } catch (_:Dynamic) {}
		try { if (_quadVBO    != null) gl.deleteBuffer(_quadVBO);      } catch (_:Dynamic) {}
		_storageTex = null;
		_blitProg   = null;
		_quadVBO    = null;
		_initialized = false;
	}
}
#end
