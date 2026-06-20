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

		var option = new Option(Lang.str('opt_navinput', 'Navigation Input'),
			Lang.str('opt_navinput_desc', 'How you interact with menus and UI.\nTouch uses native screen taps — no overlay needed.\nVirtual Pad shows on-screen directional buttons.'),
			'navInputMode', 'string', 'Touch',
			[Lang.str('choice_navinput_touch', 'Touch'), Lang.str('choice_navinput_pad', 'Virtual Pad')],
			['Touch', 'Virtual Pad']);
		addOption(option);

		var option = new Option(Lang.str('opt_gameinput', 'Gameplay Input'),
			Lang.str('opt_gameinput_desc', 'How you hit notes in-game.\nHitbox splits the screen into four tap zones.\nVirtual Pad shows an on-screen D-pad.'),
			'gameInputMode', 'string', 'Hitbox',
			[Lang.str('choice_gameinput_hitbox', 'Hitbox'), Lang.str('choice_gameinput_pad', 'Virtual Pad')],
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
