package funkin.states.options;

import funkin.data.ClientPrefs.VsyncMode;

/**
 * Builds the "Graphics" category's option list. Pure data -- no screen of its
 * own anymore (see TouchOptionList.hx / the unified OptionsState.hx that owns
 * the actual tab bar + list).
 */
class GraphicsOptions
{
	/**
	 * @param onAntialiasingChanged Optional hook so the hosting screen can
	 * live-refresh antialiasing on whatever sprites it currently has on
	 * screen -- this class has no display list of its own to do that itself.
	 */
	public static function build(?onAntialiasingChanged:Void->Void):Array<Option>
	{
		final opts:Array<Option> = [];

		final presetOption = new Option(Lang.str('opt_perfpreset', 'Performance Preset'),
			Lang.str('opt_perfpreset_desc',
				'Quickly apply a quality profile.\nLow boosts performance, High enables everything.\nCustom lets you configure each setting individually.'),
			'performancePreset', 'string', 'Custom',
			[Lang.str('choice_preset_low', 'Low'), Lang.str('choice_preset_medium', 'Medium'), Lang.str('choice_preset_high', 'High'), Lang.str('choice_generic_custom', 'Custom')],
			['Low', 'Medium', 'High', 'Custom']);
		opts.push(presetOption);

		function markCustomPreset()
		{
			if (ClientPrefs.performancePreset == 'Custom') return;
			ClientPrefs.performancePreset = 'Custom';
			presetOption.curOption = presetOption.storedValues.indexOf('Custom');
		}

		function onChangeAntiAliasing()
		{
			FlxSprite.defaultAntialiasing = ClientPrefs.globalAntialiasing;
			if (onAntialiasingChanged != null) onAntialiasingChanged();
		}

		presetOption.onChange = () -> {
			switch (ClientPrefs.performancePreset)
			{
				case 'Low':
					ClientPrefs.gpuCaching = false;
					ClientPrefs.lowQuality = true;
					ClientPrefs.shaders = false;
					ClientPrefs.globalAntialiasing = false;
				case 'Medium':
					#if !android ClientPrefs.gpuCaching = true; #end
					ClientPrefs.lowQuality = false;
					ClientPrefs.shaders = false;
					ClientPrefs.globalAntialiasing = true;
				case 'High':
					#if !android ClientPrefs.gpuCaching = true; #end
					ClientPrefs.lowQuality = false;
					ClientPrefs.shaders = true;
					ClientPrefs.globalAntialiasing = true;
				default: // Custom -- leave individual settings unchanged
			}
			onChangeAntiAliasing();
		};

		final gpuCachingOption = new Option(Lang.str('opt_gpucaching', 'GPU Caching'),
			#if android
			Lang.str('opt_gpucaching_desc_android',
				'[EXPERIMENTAL — ANDROID]\nFrees RAM after uploading textures to the GPU.\nIf the app is minimized or a call comes in, the OpenGL context is lost -- affected textures are automatically re-uploaded when you return, but this recovery is untested on real hardware.\nDisabled by default. Enable only if you don\'t mind the risk.'),
			#else
			Lang.str('opt_gpucaching_desc', 'If checked, GPU caching will be enabled.'),
			#end
			'gpuCaching', 'bool', false);
		gpuCachingOption.onChange = markCustomPreset;
		opts.push(gpuCachingOption);

		final lowQualityOption = new Option(Lang.str('opt_lowquality', 'Low Quality'),
			Lang.str('opt_lowquality_desc', 'If checked, disables some background details,\ndecreases loading times and improves performance.'),
			'lowQuality', 'bool', false);
		lowQualityOption.onChange = markCustomPreset;
		opts.push(lowQualityOption);

		final shadersOption = new Option(Lang.str('opt_shaders', 'Shaders'), Lang.str('opt_shaders_desc', 'If checked, shaders will be enabled across the mod'), 'shaders', 'bool', true);
		shadersOption.onChange = markCustomPreset;
		opts.push(shadersOption);

		final aaOption = new Option(Lang.str('opt_antialiasing', 'Anti-Aliasing'),
			Lang.str('opt_antialiasing_desc', 'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.'), 'globalAntialiasing', 'bool', true);
		aaOption.onChange = () -> { onChangeAntiAliasing(); markCustomPreset(); };
		opts.push(aaOption);

		opts.push(new Option(Lang.str('opt_debugdisplaytype', 'Debug Display Type'),
			Lang.str('opt_debugdisplaytype_desc',
				'Handles what type of information to display in the top left of your screen.\nSimple shows FPS & Memory. Advanced adds debug info.\nDisabled hides it entirely.'),
			'fpsDisplayType', 'string', 'Simple',
			[Lang.str('choice_debug_simple', 'Simple'), Lang.str('choice_debug_advanced', 'Advanced'), Lang.str('choice_debug_memory', 'Memory'), Lang.str('choice_generic_disabled', 'Disabled')],
			['Simple', 'Advanced', 'Memory', 'Disabled']));

		opts.push(new Option(Lang.str('opt_fpsrgb', 'Animate FPS Color (RGB)'),
			Lang.str('opt_fpsrgb_desc', 'Cycles the FPS counter color through the rainbow.\nWorks with both Simple and Advanced display modes.'),
			'fpsRGB', 'bool', false));

		final framerateOption = new Option(Lang.str('opt_framerate', 'Framerate'), Lang.str('opt_framerate_desc', "Pretty self explanatory, isn't it?"), 'framerate', 'int', 60);
		framerateOption.minValue = 60;
		framerateOption.maxValue = 240;
		framerateOption.displayFormat = '%v FPS';
		framerateOption.onChange = onChangeFramerate;
		opts.push(framerateOption);

		final unlockedFramerateOption = new Option(Lang.str('opt_unlockedFramerate', 'Unlocked Framerate'), Lang.str('opt_unlockedFramerate_desc', "Pretty self explanatory, isn't it?"),
			'unlockedFramerate', 'bool', false);
		unlockedFramerateOption.onChange = onChangeFramerate;
		opts.push(unlockedFramerateOption);

		final vsyncOption = new Option(Lang.str('opt_vsyncMode', 'VSync Mode'), Lang.str('opt_vsyncMode_desc', "Syncs the games Fps to your monitors refresh rate to prevent screen tearing"),
			'vsyncMode', 'string', 'Off', [Lang.str('choice_generic_disabled', 'Disabled'), Lang.str('choice_generic_enabled', 'Enabled'), Lang.str('choice_vsync_adaptive', 'Adaptive')],
			['Off', 'On', 'Adaptive']);
		vsyncOption.onChange = () -> ClientPrefs.updateVsyncMode();
		opts.push(vsyncOption);

		#if android
		final drsOption = new Option(Lang.str('opt_drs', 'Dynamic Resolution (DRS)'),
			Lang.str('opt_drs_desc',
				'Auto-drops render rate to ~30fps when the game falls below 30fps,\nkeeping gameplay logic at full speed.\nDisable if you prefer consistent frame pacing at all times.'),
			'drsEnabled', 'bool', false);
		drsOption.onChange = markCustomPreset;
		opts.push(drsOption);

		// The four options below tune DRS without needing a new build -- useful
		// while we're still figuring out the right thresholds for real devices.
		final drsActivate = new Option(Lang.str('opt_drsActivate', 'DRS Activate FPS'),
			Lang.str('opt_drsActivate_desc', 'DRS turns on once the average fps drops below this.'),
			'drsActivateFps', 'int', 30);
		drsActivate.minValue = 15;
		drsActivate.maxValue = 55;
		drsActivate.displayFormat = 'below %v FPS';
		opts.push(drsActivate);

		final drsDeactivate = new Option(Lang.str('opt_drsDeactivate', 'DRS Deactivate FPS'),
			Lang.str('opt_drsDeactivate_desc', 'DRS turns back off once the average fps rises above this.\nKeep this higher than the Activate value or DRS won\'t turn off.'),
			'drsDeactivateFps', 'int', 50);
		drsDeactivate.minValue = 20;
		drsDeactivate.maxValue = 60;
		drsDeactivate.displayFormat = 'above %v FPS';
		opts.push(drsDeactivate);

		final drsMinActive = new Option(Lang.str('opt_drsMinActive', 'DRS Minimum Active Time'),
			Lang.str('opt_drsMinActive_desc', 'Once DRS turns on, it stays on for at least this long,\neven if fps recovers sooner — prevents rapid on/off flickering.'),
			'drsMinActiveSeconds', 'float', 1.5);
		drsMinActive.minValue = 0.5;
		drsMinActive.maxValue = 5;
		drsMinActive.displayFormat = '%v s';
		opts.push(drsMinActive);

		opts.push(new Option(Lang.str('opt_drsForceOn', 'DRS Force Always On'),
			Lang.str('opt_drsForceOn_desc',
				'[DEBUG] Keeps DRS on for the whole song regardless of framerate,\nignoring the Activate/Deactivate/Minimum settings above.\nUse to test whether DRS itself helps, separate from tuning when it triggers.'),
			'drsForceAlwaysOn', 'bool', false));

		// Different mechanism from DRS above: DRS skips whole frames, this shrinks
		// every real frame via Android's hardware surface scaler (near-zero extra
		// GPU cost, confirmed via on-device Perfetto traces to be the actual
		// bottleneck — GPU fill-rate, not CPU/script/note-count). Applies live so
		// you can feel the difference immediately.
		final renderScaleOption = new Option(Lang.str('opt_renderScale', 'Render Scale'),
			Lang.str('opt_renderScale_desc',
				'Renders the game at a lower internal resolution and lets the\ndisplay scale it up — cheaper for the GPU on every single frame.\nLower = faster but softer image. 100% = native, no change.'),
			'renderScale', 'percent', 1.0);
		renderScaleOption.minValue = 0.5;
		renderScaleOption.maxValue = 1.0;
		renderScaleOption.changeValue = 0.05;
		renderScaleOption.onChange = () -> mobile.backend.RenderScale.apply(ClientPrefs.renderScale);
		opts.push(renderScaleOption);
		#end

		return opts;
	}

	public static function onChangeFramerate():Void
	{
		ClientPrefs.changeFps(ClientPrefs.framerate);
	}
}
