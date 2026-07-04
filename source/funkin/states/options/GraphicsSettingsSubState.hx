package funkin.states.options;

import funkin.data.ClientPrefs.VsyncMode;

import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;

import funkin.backend.DebugDisplay;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	var presetOption:Option;
	var gpuCachingOption:Option;
	var lowQualityOption:Option;
	var shadersOption:Option;
	var aaOption:Option;

	public function new()
	{
		title = 'graphics';
		rpcTitle = 'Graphics Settings Menu'; // for Discord Rich Presence

		presetOption = new Option(Lang.str('opt_perfpreset', 'Performance Preset'),
			Lang.str('opt_perfpreset_desc',
				'Quickly apply a quality profile.\nLow boosts performance, High enables everything.\nCustom lets you configure each setting individually.'),
			'performancePreset', 'string', 'Custom',
			[Lang.str('choice_preset_low', 'Low'), Lang.str('choice_preset_medium', 'Medium'), Lang.str('choice_preset_high', 'High'), Lang.str('choice_generic_custom', 'Custom')],
			['Low', 'Medium', 'High', 'Custom']);
		presetOption.onChange = onChangePreset;
		addOption(presetOption);

		gpuCachingOption = new Option(Lang.str('opt_gpucaching', 'GPU Caching'),
			#if android
			Lang.str('opt_gpucaching_desc_android',
				'[EXPERIMENTAL — ANDROID]\nFrees RAM after uploading textures to the GPU.\nWARNING: If the app is minimized or a call comes in,\nthe OpenGL context is lost and textures may appear\nblank until the game is restarted.\nDisabled by default. Enable only if you know the risk.'),
			#else
			Lang.str('opt_gpucaching_desc', 'If checked, GPU caching will be enabled.'),
			#end
			'gpuCaching', 'bool', false);
		gpuCachingOption.onChange = markCustomPreset;
		addOption(gpuCachingOption);

		lowQualityOption = new Option(Lang.str('opt_lowquality', 'Low Quality'),
			Lang.str('opt_lowquality_desc', 'If checked, disables some background details,\ndecreases loading times and improves performance.'),
			'lowQuality', 'bool', false);
		lowQualityOption.onChange = markCustomPreset;
		addOption(lowQualityOption);

		shadersOption = new Option(Lang.str('opt_shaders', 'Shaders'), Lang.str('opt_shaders_desc', 'If checked, shaders will be enabled across the mod'), 'shaders', 'bool', true);
		shadersOption.onChange = markCustomPreset;
		addOption(shadersOption);

		aaOption = new Option(Lang.str('opt_antialiasing', 'Anti-Aliasing'),
			Lang.str('opt_antialiasing_desc', 'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.'), 'globalAntialiasing', 'bool', true);
		aaOption.onChange = () -> { onChangeAntiAliasing(); markCustomPreset(); };
		addOption(aaOption);

		var option:Option = new Option(Lang.str('opt_debugdisplaytype', 'Debug Display Type'),
			Lang.str('opt_debugdisplaytype_desc',
				'Handles what type of information to display in the top left of your screen.\nSimple shows FPS & Memory. Advanced adds debug info.\nDisabled hides it entirely.'),
			'fpsDisplayType', 'string', 'Simple',
			[Lang.str('choice_debug_simple', 'Simple'), Lang.str('choice_debug_advanced', 'Advanced'), Lang.str('choice_debug_memory', 'Memory'), Lang.str('choice_generic_disabled', 'Disabled')],
			['Simple', 'Advanced', 'Memory', 'Disabled']);
		addOption(option);

		var option:Option = new Option(Lang.str('opt_fpsrgb', 'Animate FPS Color (RGB)'),
			Lang.str('opt_fpsrgb_desc', 'Cycles the FPS counter color through the rainbow.\nWorks with both Simple and Advanced display modes.'),
			'fpsRGB', 'bool', false);
		addOption(option);

		var option:Option = new Option(Lang.str('opt_framerate', 'Framerate'), Lang.str('opt_framerate_desc', "Pretty self explanatory, isn't it?"), 'framerate', 'int', 60);
		addOption(option);

		option.minValue = 60;
		option.maxValue = 240;
		option.displayFormat = '%v FPS';
		option.onChange = onChangeFramerate;

		var option:Option = new Option(Lang.str('opt_unlockedFramerate', 'Unlocked Framerate'), Lang.str('opt_unlockedFramerate_desc', "Pretty self explanatory, isn't it?"), 'unlockedFramerate',
			'bool', false);
		addOption(option);
		option.onChange = onChangeFramerate;

		var option:Option = new Option(Lang.str('opt_vsyncMode', 'VSync Mode'), Lang.str('opt_vsyncMode_desc', "Syncs the games Fps to your monitors refresh rate to prevent screen tearing"),
			'vsyncMode', 'string', 'Off', [Lang.str('choice_generic_disabled', 'Disabled'), Lang.str('choice_generic_enabled', 'Enabled'), Lang.str('choice_vsync_adaptive', 'Adaptive')],
			['Off', 'On', 'Adaptive']);
		addOption(option);
		option.onChange = () -> ClientPrefs.updateVsyncMode();

		#if android
		var option:Option = new Option(Lang.str('opt_drs', 'Dynamic Resolution (DRS)'),
			Lang.str('opt_drs_desc',
				'Auto-drops render rate to ~30fps when the game falls below 30fps,\nkeeping gameplay logic at full speed.\nDisable if you prefer consistent frame pacing at all times.'),
			'drsEnabled', 'bool', true);
		option.onChange = markCustomPreset;
		addOption(option);
		#end

		super();
	}

	function onChangePreset()
	{
		switch (ClientPrefs.performancePreset)
		{
			case 'Low':
				ClientPrefs.gpuCaching = false;
				ClientPrefs.lowQuality = true;
				ClientPrefs.shaders = false;
				ClientPrefs.globalAntialiasing = false;
				#if android ClientPrefs.drsEnabled = true; #end
			case 'Medium':
				#if !android ClientPrefs.gpuCaching = true; #end
				ClientPrefs.lowQuality = false;
				ClientPrefs.shaders = false;
				ClientPrefs.globalAntialiasing = true;
				#if android ClientPrefs.drsEnabled = true; #end
			case 'High':
				#if !android ClientPrefs.gpuCaching = true; #end
				ClientPrefs.lowQuality = false;
				ClientPrefs.shaders = true;
				ClientPrefs.globalAntialiasing = true;
				#if android ClientPrefs.drsEnabled = false; #end
			default: // Custom — leave individual settings unchanged
		}
		onChangeAntiAliasing();
		reloadCheckboxes();
	}

	function markCustomPreset()
	{
		if (ClientPrefs.performancePreset == 'Custom') return;
		ClientPrefs.performancePreset = 'Custom';
		presetOption.curOption = presetOption.storedValues.indexOf('Custom');
		updateTextFrom(presetOption);
	}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			if (sprite != null && (sprite is FlxSprite) && !(sprite is FlxText))
			{
				(cast sprite : FlxSprite).antialiasing = ClientPrefs.globalAntialiasing;
			}
		}

		FlxSprite.defaultAntialiasing = ClientPrefs.globalAntialiasing;
	}

	function onChangeFramerate()
	{
		ClientPrefs.changeFps(ClientPrefs.framerate);
	}
}
