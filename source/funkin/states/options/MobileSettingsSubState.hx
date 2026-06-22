package funkin.states.options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;

/**
 * Mobile settings panel with a live control-layout preview on the left side.
 *
 * Preview area: x 10–462  (left panel, never overlaps the options at x≥480)
 * Options area: x 480+    (BaseOptionsMenu default)
 */
class MobileSettingsSubState extends BaseOptionsMenu
{
	// ─── Preview state ────────────────────────────────────────────────────────
	static final PREV_X:Float  = 14;
	static final PREV_Y:Float  = 106;
	static final PREV_W:Int    = 448;
	static final PREV_H:Int    = 400;

	static final ZONE_ALPHA:Float = 0.72;

	static final COLORS = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000]; // L D U R
	static final LABELS = ["LEFT",   "DOWN",   "UP",    "RIGHT" ];

	var _prevTitle:FlxText;
	var _prevScreen:FlxSprite;
	var _prevModeText:FlxText;
	var _prevZones:Array<FlxSprite>   = [];
	var _prevZoneLabels:Array<FlxText> = [];

	// Saved option references so we can attach onChange.
	var _gameInputOpt:Option;
	var _hitboxLayoutOpt:Option;

	// ──────────────────────────────────────────────────────────────────────────

	public function new()
	{
		title    = 'mobile';
		rpcTitle = 'Mobile Settings Menu';

		// ── Options ──────────────────────────────────────────────────────────

		addOption(new Option(
			Lang.str('opt_haptic', 'Haptic Feedback'),
			Lang.str('opt_haptic_desc', 'Vibrates briefly on each note hit.\nOnly fires when you are in control (not bot play).'),
			'hapticFeedback', 'bool', true));

		addOption(new Option(
			Lang.str('opt_navinput', 'Navigation Input'),
			Lang.str('opt_navinput_desc', 'How you interact with menus and UI.\nTouch uses native screen taps — no overlay needed.\nVirtual Pad shows on-screen directional buttons.'),
			'navInputMode', 'string', 'Touch',
			[Lang.str('choice_navinput_touch', 'Touch'), Lang.str('choice_navinput_pad', 'Virtual Pad')],
			['Touch', 'Virtual Pad']));

		_gameInputOpt = new Option(
			Lang.str('opt_gameinput', 'Gameplay Input'),
			Lang.str('opt_gameinput_desc', 'How you hit notes in-game.\nHitbox splits the screen into tap zones.\nVirtual Pad shows an on-screen D-pad.'),
			'gameInputMode', 'string', 'Hitbox',
			[Lang.str('choice_gameinput_hitbox', 'Hitbox'), Lang.str('choice_gameinput_pad', 'Virtual Pad')],
			['Hitbox', 'Virtual Pad']);
		addOption(_gameInputOpt);

		_hitboxLayoutOpt = new Option(
			Lang.str('opt_hitboxlayout', 'Hitbox Layout'),
			Lang.str('opt_hitboxlayout_desc', 'Arrangement of the tap zones when using Hitbox mode.\nFour Lanes: four equal columns across the full screen.\nTwo Thumb: 2×2 grid — left thumb covers LEFT and DOWN, right thumb covers UP and RIGHT.'),
			'hitboxLayout', 'string', 'Four Lanes',
			[Lang.str('choice_hitboxlayout_4l', 'Four Lanes'), Lang.str('choice_hitboxlayout_2t', 'Two Thumb')],
			['Four Lanes', 'Two Thumb']);
		addOption(_hitboxLayoutOpt);

		addOption(new Option(
			Lang.str('opt_hitboxalpha', 'Hitbox Opacity'),
			Lang.str('opt_hitboxalpha_desc', 'How visible the hitbox zones appear when pressed.\nTakes effect the next time you enter a song.'),
			'hitboxAlpha', 'percent', 0.2));

		addOption(new Option(
			Lang.str('opt_padopacity', 'Pad Opacity'),
			Lang.str('opt_padopacity_desc', 'How visible the virtual pad buttons appear.\nTakes effect the next time you enter a song.'),
			'virtualPadAlpha', 'percent', 0.5));

		// ── Build base UI ─────────────────────────────────────────────────────
		super();

		// ── Wire up live-preview callbacks ────────────────────────────────────
		_gameInputOpt.onChange    = () -> _rebuildPreview();
		_hitboxLayoutOpt.onChange = () -> _rebuildPreview();

		// ── Build the preview panel on the left side ─────────────────────────
		_buildPreviewShell();
		_rebuildPreview();
	}

	// ─── Preview shell (created once) ─────────────────────────────────────────

	function _buildPreviewShell():Void
	{
		_prevTitle = new FlxText(PREV_X, 88, PREV_W, Lang.str('preview_controls_title', 'CONTROL LAYOUT'));
		_prevTitle.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, FlxTextAlign.CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_prevTitle.borderSize = 1.5;
		_prevTitle.antialiasing = ClientPrefs.globalAntialiasing;
		add(_prevTitle);

		// Dark screen background — zones will be drawn on top of this.
		_prevScreen = new FlxSprite(PREV_X, PREV_Y).makeGraphic(PREV_W, PREV_H, 0xFF0A0A0A);
		_prevScreen.alpha = 0.82;
		add(_prevScreen);

		_prevModeText = new FlxText(PREV_X, PREV_Y + PREV_H + 6, PREV_W, '');
		_prevModeText.setFormat(Paths.font('vcr.ttf'), 16, 0xFFCCCCCC, FlxTextAlign.CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_prevModeText.borderSize = 1;
		_prevModeText.antialiasing = ClientPrefs.globalAntialiasing;
		add(_prevModeText);
	}

	// ─── Zone rebuild ──────────────────────────────────────────────────────────

	function _rebuildPreview():Void
	{
		_clearZones();

		if (ClientPrefs.gameInputMode == 'Virtual Pad')
			_buildVirtualPadPreview();
		else if (ClientPrefs.hitboxLayout == 'Two Thumb')
			_buildTwoThumbPreview();
		else
			_buildFourLanesPreview();

		// Update mode label.
		_prevModeText.text = ClientPrefs.gameInputMode == 'Virtual Pad'
			? Lang.str('preview_mode_vpad', 'Virtual Pad')
			: 'Hitbox  ·  ' + ClientPrefs.hitboxLayout;
	}

	// ─── Hitbox: Four Lanes ────────────────────────────────────────────────────

	function _buildFourLanesPreview():Void
	{
		final colW = PREV_W / 4;
		final positions = [
			for (i in 0...4)
				{x: PREV_X + i * colW, y: PREV_Y, w: colW, h: PREV_H, ci: i}
		];
		_spawnZones(positions, "fourLanes");
	}

	// ─── Hitbox: Two Thumb ─────────────────────────────────────────────────────

	function _buildTwoThumbPreview():Void
	{
		final hw = PREV_W / 2;
		final hh = PREV_H / 2;
		// Same mapping as MobileHitbox: TOP-LEFT=LEFT, BOT-LEFT=DOWN, TOP-RIGHT=UP, BOT-RIGHT=RIGHT
		final positions = [
			{x: PREV_X,      y: PREV_Y,      w: hw, h: hh, ci: 0}, // LEFT
			{x: PREV_X,      y: PREV_Y + hh, w: hw, h: hh, ci: 1}, // DOWN
			{x: PREV_X + hw, y: PREV_Y,      w: hw, h: hh, ci: 2}, // UP
			{x: PREV_X + hw, y: PREV_Y + hh, w: hw, h: hh, ci: 3}, // RIGHT
		];
		_spawnZones(positions, "twoThumb");
	}

	// ─── Virtual Pad preview ───────────────────────────────────────────────────

	function _buildVirtualPadPreview():Void
	{
		final cx  = PREV_X + PREV_W / 2;
		final cy  = PREV_Y + PREV_H / 2;
		final btn = 76;  // button square size
		final gap = 84;  // distance from center to button center

		final positions = [
			{x: cx - btn / 2, y: cy - gap - btn / 2, ci: 2}, // UP   (green)
			{x: cx - btn / 2, y: cy + gap - btn / 2, ci: 1}, // DOWN (cyan)
			{x: cx - gap - btn / 2, y: cy - btn / 2, ci: 0}, // LEFT (magenta)
			{x: cx + gap - btn / 2, y: cy - btn / 2, ci: 3}, // RIGHT (red)
		];

		for (p in positions)
		{
			_addZone(p.x, p.y, btn, btn, p.ci);
		}

		// Cross lines between buttons to suggest a D-pad.
		var hLine = new FlxSprite(cx - gap - btn / 2, cy - 2).makeGraphic(
			Std.int(gap * 2 + btn), 4, 0xFF333333);
		hLine.alpha = 0.6;
		hLine.scrollFactor.set();
		add(hLine);
		_prevZones.push(hLine);

		var vLine = new FlxSprite(cx - 2, cy - gap - btn / 2).makeGraphic(
			4, Std.int(gap * 2 + btn), 0xFF333333);
		vLine.alpha = 0.6;
		vLine.scrollFactor.set();
		add(vLine);
		_prevZones.push(vLine);
	}

	// ─── Helpers ───────────────────────────────────────────────────────────────

	function _spawnZones(positions:Array<{x:Float, y:Float, w:Float, h:Float, ci:Int}>, ?layoutKey:String):Void
	{
		for (p in positions)
			_addZone(p.x, p.y, p.w, p.h, p.ci);
	}

	function _addZone(x:Float, y:Float, w:Float, h:Float, colorIndex:Int):Void
	{
		final color:FlxColor = COLORS[colorIndex];
		final label:String   = LABELS[colorIndex];

		var zone = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h),
			(color & 0x00FFFFFF) | 0xBB000000);
		zone.color       = color;
		zone.alpha       = ZONE_ALPHA;
		zone.scrollFactor.set();
		add(zone);
		_prevZones.push(zone);

		// Divider line on the right edge (except last in a row/column).
		var divider = new FlxSprite(x + w - 1, y).makeGraphic(2, Std.int(h), 0xFF000000);
		divider.alpha = 0.5;
		divider.scrollFactor.set();
		add(divider);
		_prevZones.push(divider);

		var lbl = new FlxText(x, y + h / 2 - 10, w, label);
		lbl.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, FlxTextAlign.CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		lbl.borderSize    = 1.5;
		lbl.antialiasing  = ClientPrefs.globalAntialiasing;
		lbl.scrollFactor.set();
		add(lbl);
		_prevZoneLabels.push(lbl);
	}

	function _clearZones():Void
	{
		for (z in _prevZones)
		{
			remove(z, true);
			z.destroy();
		}
		_prevZones.resize(0);

		for (l in _prevZoneLabels)
		{
			remove(l, true);
			l.destroy();
		}
		_prevZoneLabels.resize(0);
	}

	override function destroy():Void
	{
		_clearZones();
		super.destroy();
	}
}
