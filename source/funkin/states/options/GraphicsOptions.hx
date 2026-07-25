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

		opts.push(new Option(Lang.str('opt_category_performance', 'Performance').toUpperCase(), '', '', 'label'));

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
					// Low-end profile: free per-state, lowest RAM footprint.
					ClientPrefs.cacheMode = 'Destructive';
				case 'Medium':
					ClientPrefs.gpuCaching = true;
					ClientPrefs.lowQuality = false;
					ClientPrefs.shaders = false;
					ClientPrefs.globalAntialiasing = true;
					ClientPrefs.cacheMode = 'Destructive';
				case 'High':
					ClientPrefs.gpuCaching = true;
					ClientPrefs.lowQuality = false;
					ClientPrefs.shaders = true;
					ClientPrefs.globalAntialiasing = true;
					// High-end profile: keep art resident for faster returns.
					ClientPrefs.cacheMode = 'Accumulative';
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

		// Part of the performance preset (Low/Medium -> Destructive, High ->
		// Accumulative), so changing it by hand drops the preset to Custom.
		final cacheModeOption = new Option(Lang.str('opt_cachemode', 'Cache Mode'),
			Lang.str('opt_cachemode_desc',
				'How loaded art is kept between screens.\nDestructive: free the art a screen loaded when you leave it — lowest RAM, best for low-end devices.\nAccumulative: keep everything loaded — faster returns and next-song loads, but RAM keeps growing. Best for high-end devices.'),
			'cacheMode', 'string', 'Destructive',
			[Lang.str('choice_cachemode_destructive', 'Destructive'), Lang.str('choice_cachemode_accumulative', 'Accumulative')],
			['Destructive', 'Accumulative']);
		cacheModeOption.onChange = markCustomPreset;
		opts.push(cacheModeOption);

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

		// Loading-time behaviour -- moved here from the "Misc" tab, where they
		// sat disconnected from every other performance-affecting setting.
		// Not wired into markCustomPreset(): the Low/Medium/High switch-case
		// above never sets either of these, so they're genuinely independent
		// of the preset (unlike everything above, which the preset controls),
		// not merely relocated.
		opts.push(new Option(Lang.str('opt_streamedsongfiles', 'Streamed Song files'),
			Lang.str('opt_streamedsongfiles_desc',
				'If checked, playable song files will be streamed via bytes instead of being loaded all at once. This heavily improves loading times, however it is EXTREMELY EXPERIMENTAL and prone to issues.'),
			'streamedMusic', 'bool', false));

		opts.push(new Option(Lang.str('opt_threadedpreload', 'Background Song Preload'),
			Lang.str('opt_threadedpreload_desc',
				'If checked, the loading screen decodes the next song\'s assets on a background thread while the bar animates. If unchecked, it just waits, and PlayState loads everything itself the plain, one-at-a-time way.'),
			'threadedPreload', 'bool', true));

		opts.push(new Option(Lang.str('opt_category_framerate', 'Framerate').toUpperCase(), '', '', 'label'));

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

		return opts;
	}

	public static function onChangeFramerate():Void
	{
		ClientPrefs.changeFps(ClientPrefs.framerate);
	}
}
