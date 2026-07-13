package mobile.backend;

#if (android && cpp)
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.RectangleTexture;
import openfl.events.Event;
import lime.utils.Float32Array;
import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * Manual render-to-texture + full-screen stretch-blit to finish what
 * RenderScale.hx starts.
 *
 * window.scale correctly shrinks OpenFL's own viewport AND
 * Context3D.backBufferWidth/Height in sync (see RenderScale.hx) -- but a
 * live device log proved the actual mechanism is NOT "render into a
 * smaller offscreen backbuffer texture, then stretch it onto the window":
 * Context3D.configureBackBuffer() only ever creates a __backBufferTexture
 * when __stage3D != null (an embedded 3D layer). The PRIMARY context this
 * game actually renders through is created with stage3D=null
 * (Stage.hx: `new Context3D(this)`), so for our case configureBackBuffer()
 * only updates the backBufferWidth/backBufferHeight bookkeeping fields --
 * __backBufferTexture stays null forever, confirmed directly via
 * "[RenderScaleBlit] __backBufferTexture is null" in a real device log.
 *
 * That means Flixel's normal rendering, with its now-correctly-shrunk
 * viewport, draws DIRECTLY into a sub-rectangle of the REAL window
 * framebuffer (framebuffer 0) -- there was never a separate smaller buffer
 * to stretch. That's exactly why every attempt so far produced the same
 * "small box, black borders" result at every scale tested (100/95/90/85%,
 * confirmed via screenshots showing the black border grow proportionally
 * with how far below 100% the scale is): the scene was always being drawn
 * correctly, just directly onto an unstretched corner of the real screen.
 *
 * Fix: don't rely on Context3D's (nonexistent, for us) backbuffer texture.
 * Create our OWN correctly-sized RectangleTexture + FBO, and redirect
 * Context3D's internal "primary framebuffer" pointer at it for the
 * duration of one frame's rendering (Context3D.__bindGLFramebuffer()'s own
 * caching logic picks up any mismatch and rebinds automatically -- no
 * different from OpenFL's own render-to-texture support elsewhere in the
 * engine, just done through the private field directly since there's no
 * public API for "make the *default* target a texture"). Then, after
 * Flixel finishes drawing into it, blit that texture onto the real
 * framebuffer 0 stretched to the window's true physical size, using the
 * same fullscreen-quad technique DynamicResolution.hx already uses for
 * its own (unrelated) purpose.
 *
 * Architecture hookup -- Application.hx render() override:
 *   RenderScaleBlit.beginFrame();  // before super.render(context)
 *   super.render(context);
 *   RenderScaleBlit.endFrame();    // after super.render(context)
 */
@:nullSafety(Off)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D._internal.Context3DState)
class RenderScaleBlit
{
	static var _gl:Dynamic = null;

	// Our own render target -- an OpenFL-managed RectangleTexture (reuses
	// its existing, cross-device-tested depth/stencil renderbuffer setup
	// instead of hand-rolling one) that Flixel's normal rendering gets
	// redirected into for one frame.
	static var _tex:RectangleTexture = null;
	static var _fbo:Dynamic          = null;
	static var _fboW:Int             = 0;
	static var _fboH:Int             = 0;

	static var _blitProg:Dynamic = null;
	static var _quadVBO:Dynamic  = null;
	static var _posLoc:Int       = -1;
	static var _uvLoc:Int        = -1;
	static var _texLoc:Int       = -1;
	static var _shaderReady:Bool = false;

	// Keyed rather than a single flag -- a per-frame call site would spam
	// dozens of identical lines a second, but each DISTINCT thing worth
	// knowing (a specific failure reason, or the one-time success
	// confirmation) should still get its own one-shot report instead of
	// only the very first message of the whole session ever winning.
	static var _diagKeys:Map<String, Bool> = [];

	// Periodic (not one-shot) counters -- the flicker/teleport symptom
	// reported after the one-shot logs all showed clean success suggests an
	// INTERMITTENT failure (some frames redirect correctly, some don't) or a
	// genuinely unstable backbuffer size frame-to-frame, neither of which a
	// log that only ever fires once could ever catch.
	static var _periodBeginOK:Int    = 0;
	static var _periodBeginFail:Int  = 0;
	static var _periodEndOK:Int      = 0;
	static var _periodEndFail:Int    = 0;
	static var _periodFrames:Int     = 0;
	static var _periodLastW:Int      = -1;
	static var _periodLastH:Int      = -1;
	static var _periodSizeChanges:Int = 0;
	static inline final PERIOD_FRAMES = 90; // ~1.5s at 60fps

	/** Call once from Init.hx to register context-loss recovery. */
	public static function init():Void
	{
		FlxG.stage.stage3Ds[0].addEventListener(Event.CONTEXT3D_CREATE, _onContextCreate);
	}

	/**
	 * Redirects Flixel's normal rendering into our own offscreen texture
	 * instead of the real window. Call right before super.render(context).
	 */
	public static function beginFrame():Void
	{
		try
		{
			final ctx:Null<Context3D> = FlxG.stage.context3D;
			if (ctx == null)
			{
				_periodBeginFail++;
				_diagOnce('begin_ctxnull', '[RenderScaleBlit] context3D is null, skipping');
				return;
			}
			if (_gl == null) _gl = ctx.gl;
			if (_gl == null)
			{
				_periodBeginFail++;
				_diagOnce('begin_glnull', '[RenderScaleBlit] context3D.gl is null, skipping');
				return;
			}

			final w = ctx.backBufferWidth;
			final h = ctx.backBufferHeight;
			if (w <= 0 || h <= 0)
			{
				_periodBeginFail++;
				_diagOnce('begin_zerosize', '[RenderScaleBlit] backBufferWidth/Height is ${w}x${h}, skipping');
				return;
			}

			if (w != _periodLastW || h != _periodLastH)
			{
				if (_periodLastW >= 0) _periodSizeChanges++;
				_periodLastW = w;
				_periodLastH = h;
			}

			if (_tex == null || _fboW != w || _fboH != h) _createTarget(ctx, w, h);
			if (_fbo == null)
			{
				_periodBeginFail++;
				_diagOnce('begin_nofbo', '[RenderScaleBlit] no offscreen target available, skipping (see earlier target-creation log)');
				return;
			}

			if (!_shaderReady) _createBlitShader();

			ctx.__state.__primaryGLFramebuffer = _fbo;
			_periodBeginOK++;
			_diagOnce('begin_ok', '[RenderScaleBlit] beginFrame redirecting to offscreen target ${w}x${h}');
		}
		catch (e:Dynamic)
		{
			_periodBeginFail++;
			_diagOnce('begin_exn', '[RenderScaleBlit] beginFrame failed: $e');
		}
	}

	/**
	 * Draws our offscreen texture to the real screen as a fullscreen quad,
	 * stretched to the window's true physical size. Call right after
	 * super.render(context).
	 */
	public static function endFrame():Void
	{
		try
		{
			final ctx:Null<Context3D> = FlxG.stage.context3D;
			if (ctx == null || _gl == null || _tex == null || !_shaderReady)
			{
				_periodEndFail++;
				_diagOnce('end_notready',
					'[RenderScaleBlit] endFrame skipped -- ctx=${ctx != null} gl=${_gl != null} tex=${_tex != null} shader=${_shaderReady}');
				_reportPeriodIfDue();
				return;
			}

			final gl = _gl;
			// window.width/height are NOT touched by RenderScale (only
			// window.scale is) -- the untouched full physical window size.
			final winW = Std.int(FlxG.stage.window.width);
			final winH = Std.int(FlxG.stage.window.height);

			// Go through Context3D's own bind wrapper (not a raw
			// gl.bindFramebuffer call) so its internal __currentGLFramebuffer
			// cache stays in sync -- otherwise the NEXT frame's beginFrame()
			// could see a stale cache entry that matches our FBO handle and
			// wrongly skip rebinding, leaving Flixel drawing straight to the
			// real screen instead of back into our offscreen texture.
			ctx.__bindGLFramebuffer(null);
			gl.viewport(0, 0, winW, winH);
			gl.disable(gl.DEPTH_TEST);
			gl.disable(gl.BLEND);

			gl.useProgram(_blitProg);
			gl.activeTexture(gl.TEXTURE0);
			gl.bindTexture(gl.TEXTURE_2D, @:privateAccess _tex.__textureID);
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

			_periodEndOK++;
			_diagOnce('end_ok', '[RenderScaleBlit] blit executed OK (offscreen=${_fboW}x${_fboH} -> window=${winW}x${winH})');
		}
		catch (e:Dynamic)
		{
			_periodEndFail++;
			_diagOnce('end_exn', '[RenderScaleBlit] endFrame failed: $e');
		}

		_reportPeriodIfDue();
	}

	/**
	 * Every ~1.5s, reports how many of the last PERIOD_FRAMES begin/end
	 * calls actually succeeded, and how many times the backbuffer size
	 * itself changed mid-period. A 100%-success period with a stable size
	 * would rule out an intermittent redirect failure as the cause of the
	 * reported flicker/teleport symptom -- pointing instead at something
	 * outside what this file can see (e.g. double/triple-buffer swap-chain
	 * timing). Frequent size changes during a period the user isn't
	 * actively dragging the slider would itself be a red flag.
	 */
	static function _reportPeriodIfDue():Void
	{
		_periodFrames++;
		if (_periodFrames < PERIOD_FRAMES) return;

		Logger.log('[RenderScaleBlit] last ${_periodFrames}f: begin ${_periodBeginOK}ok/${_periodBeginFail}fail, '
			+ 'end ${_periodEndOK}ok/${_periodEndFail}fail, sizeChanges=$_periodSizeChanges, '
			+ 'currentSize=${_periodLastW}x${_periodLastH}', NOTICE, true);

		_periodFrames = 0;
		_periodBeginOK = 0;
		_periodBeginFail = 0;
		_periodEndOK = 0;
		_periodEndFail = 0;
		_periodSizeChanges = 0;
	}

	static function _createTarget(ctx:Context3D, w:Int, h:Int):Void
	{
		// Not rate-limited like the per-frame diagnostics above -- this only
		// runs when the render scale setting actually changes size, so it's
		// rare, and every distinct size the user tries during a session is
		// worth its own line rather than only the first ever logged.
		try
		{
			if (_tex != null)
			{
				_tex.dispose();
				_tex = null;
				_fbo = null;
			}

			_tex = ctx.createRectangleTexture(w, h, Context3DTextureFormat.BGRA, true);
			_fbo = @:privateAccess _tex.__getGLFramebuffer(true, 0, 0);
			_fboW = w;
			_fboH = h;

			// FBO completeness is checked with glCheckFramebufferStatus, not
			// exceptions -- a bad depth/stencil combo on some GPU could leave
			// this incomplete and every draw into it silently a no-op, with
			// nothing above ever throwing to explain why the screen stays
			// black. The raw bind here doesn't need to be undone: beginFrame()
			// sets Context3DState.__primaryGLFramebuffer right after this
			// returns, and its mismatch-vs-__currentGLFramebuffer check (see
			// endFrame()'s comment on the same mechanism) forces a proper
			// rebind through Context3D's own wrapper before anything draws.
			final gl = _gl;
			gl.bindFramebuffer(gl.FRAMEBUFFER, _fbo);
			final status:Int = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
			final complete = (status == gl.FRAMEBUFFER_COMPLETE);
			Logger.log('[RenderScaleBlit] created offscreen target ${w}x${h}, '
				+ 'FBO status=$status (${complete ? "COMPLETE" : "INCOMPLETE"})', NOTICE, !complete);

			if (!complete)
			{
				_tex.dispose();
				_tex = null;
				_fbo = null;
				_fboW = 0;
				_fboH = 0;
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('[RenderScaleBlit] offscreen target creation failed for ${w}x${h}: $e', NOTICE, true);
			_tex = null;
			_fbo = null;
			_fboW = 0;
			_fboH = 0;
		}
	}

	static function _onContextCreate(_:Dynamic):Void
	{
		_gl = null;
		_tex = null;
		_fbo = null;
		_fboW = 0;
		_fboH = 0;
		_blitProg = null;
		_quadVBO = null;
		_shaderReady = false;
	}

	static function _createBlitShader():Void
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

			_shaderReady = true;
			Logger.log('[RenderScaleBlit] blit shader ready (posLoc=$_posLoc uvLoc=$_uvLoc texLoc=$_texLoc)', NOTICE, _posLoc < 0 || _uvLoc < 0 || _texLoc < 0);
		}
		catch (e:Dynamic)
		{
			_diagOnce('shader_exn', '[RenderScaleBlit] blit shader creation failed: $e');
			_shaderReady = false;
		}
	}

	/**
	 * Logs a message once per distinct `key` (both to file and as an
	 * in-game toast), so a per-frame call site doesn't spam it every frame
	 * while still surfacing every different thing that happens over a
	 * session (not just whichever one happened first).
	 */
	static function _diagOnce(key:String, msg:String):Void
	{
		if (_diagKeys.exists(key)) return;
		_diagKeys.set(key, true);
		Logger.log(msg, NOTICE, true);
	}
}
#end
