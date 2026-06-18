package funkin.states.options;

import funkin.data.ClientPrefs.VsyncMode;

import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;

import funkin.backend.DebugDisplay;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'graphics';
		rpcTitle = 'Graphics Settings Menu'; // for Discord Rich Presence
		
		var option:Option = new Option(Lang.str('opt_gpucaching', 'GPU Caching'), Lang.str('opt_gpucaching_desc', 'If checked, GPU caching will be enabled.'), 'gpuCaching', 'bool', false);
		addOption(option);
		
		// I'd suggest using "Low Quality" as an example for making your own option since it is the simplest here
		var option:Option = new Option(Lang.str('opt_lowquality', 'Low Quality'), // Name
			Lang.str('opt_lowquality_desc', 'If checked, disables some background details,\ndecreases loading times and improves performance.'), // Description
			'lowQuality', // Save data variable name
			'bool', // Variable type
			false); // Default value
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_shaders', 'Shaders'), Lang.str('opt_shaders_desc', 'If checked, shaders will be enabled across the mod'), 'shaders', 'bool', true);
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_antialiasing', 'Anti-Aliasing'),
			Lang.str('opt_antialiasing_desc', 'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.'), 'globalAntialiasing', 'bool', true);
		// option.showBoyfriend = true;
		option.onChange = onChangeAntiAliasing; // Changing onChange is only needed if you want to make a special interaction after it changes the value
		addOption(option);
		
		#if !mobile
		var option:Option = new Option(Lang.str('opt_debugdisplaytype', 'Debug Display Type'),
			Lang.str('opt_debugdisplaytype_desc',
				'Handles what type of information to display in the top left of your screen.\nSimple displays FPS & Memory, and advanced displays the same alongside debug information.\nDisabled disables the counter entirely.'),
			'fpsDisplayType', 'string', 'Simple', [Lang.str('choice_debug_simple', 'Simple'), Lang.str('choice_debug_advanced', 'Advanced'), Lang.str('choice_generic_disabled', 'Disabled')],
			['Simple', 'Advanced', 'Disabled']);
		addOption(option);
		#end
		
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
		
		super();
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
