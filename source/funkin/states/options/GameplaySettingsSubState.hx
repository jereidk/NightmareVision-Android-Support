package funkin.states.options;

import flixel.FlxG;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'gameplay';
		rpcTitle = 'Gameplay Settings Menu'; // for Discord Rich Presence
		
		// I'd suggest using "Downscroll" as an example for making your own option since it is the simplest here
		var option:Option = new Option(Lang.str('opt_downscroll', 'Downscroll'), // Name
			Lang.str('opt_downscroll_desc', 'If checked, notes go Down instead of Up, simple enough.'), // Description
			'downScroll', // Save data variable name
			'bool', // Variable type
			false); // Default value
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_middlescroll', 'Middlescroll'), // Name
			Lang.str('opt_middlescroll_desc', "it dcroll middle"), 'middleScroll', 'bool', false);
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_ghosttapping', 'Ghost Tapping'),
			Lang.str('opt_ghosttapping_desc', "If checked, you won't get misses from pressing keys\nwhile there are no notes able to be hit."), 'ghostTapping', 'bool', true);
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_disableresetbutton', 'Disable Reset Button'), Lang.str('opt_disableresetbutton_desc', "If checked, pressing Reset won't do anything."),
			'noReset', 'bool', false);
		addOption(option);
		
		var option:Option = new Option(Lang.str('opt_hitsoundvolume', 'Hitsound Volume'), Lang.str('opt_hitsoundvolume_desc', 'stupdi ass description bro'), 'hitsoundVolume',
			'percent', 0);
		addOption(option);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;
		
		super();
	}
	
	function onChangeHitsoundVolume()
	{
		FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.hitsoundVolume);
	}
}
