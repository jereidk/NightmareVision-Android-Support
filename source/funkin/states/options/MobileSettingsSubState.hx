package funkin.states.options;

class MobileSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'mobile';
		rpcTitle = 'Mobile Settings Menu';

		var option = new Option(Lang.str('opt_haptic', 'Haptic Feedback'),
			Lang.str('opt_haptic_desc', 'Vibrates briefly on each note hit.\nOnly fires when you are in control (not bot play).'),
			'hapticFeedback', 'bool', true);
		addOption(option);

		var option = new Option(Lang.str('opt_touchmode', 'Touch Input Mode'),
			Lang.str('opt_touchmode_desc', 'Hitbox splits the screen into four tap zones.\nVirtual Pad shows an on-screen D-pad in the corner.'),
			'touchInputMode', 'string', 'Hitbox',
			[Lang.str('choice_touchmode_hitbox', 'Hitbox'), Lang.str('choice_touchmode_pad', 'Virtual Pad')],
			['Hitbox', 'Virtual Pad']);
		addOption(option);

		var option = new Option(Lang.str('opt_hitboxalpha', 'Hitbox Opacity'),
			Lang.str('opt_hitboxalpha_desc', 'How visible the hitbox zones appear when pressed.\nTakes effect the next time you enter a song.'),
			'hitboxAlpha', 'percent', 0.2);
		addOption(option);

		var option = new Option(Lang.str('opt_padopacity', 'Pad Opacity'),
			Lang.str('opt_padopacity_desc', 'How visible the virtual pad buttons appear.\nTakes effect the next time you enter a song.'),
			'virtualPadAlpha', 'percent', 0.5);
		addOption(option);

		super();
	}
}
