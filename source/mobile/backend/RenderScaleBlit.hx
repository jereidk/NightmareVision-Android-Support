package mobile.backend;

#if (android && cpp)
import openfl.display3D.Context3D;
import openfl.events.Event;
import lime.utils.Float32Array;
import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * Manual full-screen stretch-blit to finish what RenderScale.hx starts.
 *
 * window.scale correctly shrinks OpenFL's own backbuffer AND viewport in
 * sync (see RenderScale.hx) -- Context3D genuinely renders the scene at
 * the reduced resolution, complete and correctly proportioned. What's
 * missing is the last step: whatever native code moves
 * context3D.__backBufferTexture onto the real window surface does not
 * stretch a smaller-than-window buffer -- it shows up as-is, pixel for
 * pixel, in a corner of the screen with black filling the rest.
 *
 * This reuses DynamicResolution's own proven fullscreen-quad blit
 * technique (same shader, same Y-flip -- OpenGLRenderer selects
 * __projectionFlipped whenever renderTarget == null, i.e. exactly when
 * rendering into the primary backbuffer, the same FBO-vs-window
 * convention DRS's captured texture already has to compensate for) to
 * draw context3D.__backBufferTexture directly onto the real default
 * framebuffer at the window's true physical size, every frame RenderScale
 * is active.
 *
 * Architecture hookup -- Application.hx render() override, right after
 * super.render(context):
 *   if (RenderScale.currentScale < 0.999) RenderScaleBlit.blit();
 */
@:nullSafety(Off)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.textures.TextureBase)
class RenderScaleBlit
{
	static var _gl:Dynamic       = null;
	static var _blitProg:Dynamic = null;
	static var _quadVBO:Dynamic  = null;
	static var _posLoc:Int       = -1;
	static var _uvLoc:Int        = -1;
	static var _texLoc:Int       = -1;
	static var _initialized:Bool = false;

	/** Call once from Init.hx to register context-loss recovery. */
	public static function init():Void
	{
		FlxG.stage.stage3Ds[0].addEventListener(Event.CONTEXT3D_CREATE, _onContextCreate);
	}

	/**
	 * Draws context3D's current backbuffer texture to the real screen as a
	 * fullscreen quad, stretched to the window's true physical size.
	 */
	public static function blit():Void
	{
		try
		{
			final ctx:Null<Context3D> = FlxG.stage.context3D;
			if (ctx == null) return;

			final tex = ctx.__backBufferTexture;
			if (tex == null) return;

			if (!_initialized) _tryCreateGL(ctx.gl);
			if (!_initialized) return;

			final gl = _gl;
			// window.width/height are NOT touched by RenderScale (only
			// window.scale is) -- this is the same untouched full physical
			// size DynamicResolution already uses for its own (confirmed
			// working) fullscreen blit.
			final winW = Std.int(FlxG.stage.window.width);
			final winH = Std.int(FlxG.stage.window.height);

			gl.bindFramebuffer(gl.FRAMEBUFFER, null);
			gl.viewport(0, 0, winW, winH);
			gl.disable(gl.DEPTH_TEST);
			gl.disable(gl.BLEND);

			gl.useProgram(_blitProg);
			gl.activeTexture(gl.TEXTURE0);
			gl.bindTexture(gl.TEXTURE_2D, tex.__textureID);
			gl.uniform1i(_texLoc, 0);

			gl.bindBuffer(gl.ARRAY_BUFFER, _quadVBO);
			gl.enableVertexAttribArray(_posLoc);
			gl.vertexAttribPointer(_posLoc, 2, gl.FLOAT, false, 16, 0);
			gl.enableVertexAttribArray(_uvLoc);
			gl.vertexAttribPointer(_uvLoc, 2, gl.FLOAT, false, 16, 8);
			gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

			// Restore expected GL state for the next frame's normal rendering.
			gl.disableVertexAttribArray(_posLoc);
			gl.disableVertexAttribArray(_uvLoc);
			gl.bindBuffer(gl.ARRAY_BUFFER, null);
			gl.bindTexture(gl.TEXTURE_2D, null);
			gl.useProgram(null);
			gl.enable(gl.BLEND);
			gl.flush(); // ensure commands reach the GPU before eglSwapBuffers
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScaleBlit] blit failed: $e', WARN);
		}
	}

	static function _onContextCreate(_:Dynamic):Void
	{
		_destroyGL();
	}

	static function _tryCreateGL(gl:Dynamic):Void
	{
		if (gl == null) return;
		_gl = gl;
		_createGL();
	}

	static function _createGL():Void
	{
		final gl = _gl;
		try
		{
			// Same blit shader as DynamicResolution.hx, including the Y-flip:
			// content rendered into an FBO (renderTarget == null selects
			// OpenGLRenderer's __projectionFlipped) is stored bottom-up same
			// as DRS's glCopyTexImage2D capture, so it needs the identical
			// correction to read right-side-up.
			final vsrc:String = "attribute vec2 aPos;"
				+ "attribute vec2 aUV;"
				+ "varying vec2 vUV;"
				+ "void main(){"
				+ "  vUV = aUV;"
				+ "  gl_Position = vec4(aPos, 0.0, 1.0);"
				+ "}";
			final fsrc:String = "precision mediump float;"
				+ "uniform sampler2D uTex;"
				+ "varying vec2 vUV;"
				+ "void main(){"
				+ "  gl_FragColor = texture2D(uTex, vec2(vUV.x, 1.0 - vUV.y));"
				+ "}";

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
			_uvLoc = gl.getAttribLocation(_blitProg, "aUV");
			_texLoc = gl.getUniformLocation(_blitProg, "uTex");

			// Triangle strip, NDC coordinates, UV (0-1):
			// bottom-left, bottom-right, top-left, top-right
			final verts = new Float32Array([
				-1.0, -1.0, 0.0, 0.0,
				1.0, -1.0, 1.0, 0.0,
				-1.0, 1.0, 0.0, 1.0,
				1.0, 1.0, 1.0, 1.0,
			]);

			_quadVBO = gl.createBuffer();
			gl.bindBuffer(gl.ARRAY_BUFFER, _quadVBO);
			gl.bufferData(gl.ARRAY_BUFFER, verts, gl.STATIC_DRAW);
			gl.bindBuffer(gl.ARRAY_BUFFER, null);

			_initialized = true;
			Logger.log('[RenderScaleBlit] GL blit ready', NOTICE);
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScaleBlit] GL init failed: $e', WARN);
			_destroyGL();
		}
	}

	static function _destroyGL():Void
	{
		if (_gl == null)
		{
			_initialized = false;
			return;
		}
		final gl = _gl;
		try
		{
			if (_blitProg != null) gl.deleteProgram(_blitProg);
		}
		catch (_:Dynamic) {}
		try
		{
			if (_quadVBO != null) gl.deleteBuffer(_quadVBO);
		}
		catch (_:Dynamic) {}
		_blitProg = null;
		_quadVBO = null;
		_initialized = false;
	}
}
#end
