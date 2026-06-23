package funkin.states.options;

#if mobile

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import openfl.display.BitmapData;

/** One configurable row. Read/written straight through ClientPrefs by `id`. */
typedef MobileOpt =
{
	id:String,        // 'haptic' | 'nav' | 'game' | 'layout' | 'hitboxAlpha' | 'padAlpha'
	kind:String,      // 'bool' | 'string' | 'percent'
	label:String,
	desc:String,
	?choices:Array<String>, // display strings (string kind)
	?stored:Array<String>   // values saved to ClientPrefs (string kind)
}

/** A single tap zone drawn on the preview canvas. */
typedef PreviewZone =
{
	spr:FlxSprite,
	label:FlxText,
	colorIdx:Int,
	pressed:Bool,
	curA:Float
}

/**
 * Dedicated mobile-controls screen.
 *
 * Independent of the generic options list (opened from its own OptionsState
 * button, like the Editor / DLC manager). Shows a live, interactive preview
 * canvas of the chosen control scheme on the left and an adaptive option list
 * on the right — the available options change with the selected gameplay input.
 *
 * Navigation:
 *   UP / DOWN    — move selection
 *   LEFT / RIGHT — change the selected value
 *   ACCEPT       — toggle (bool options)
 *   BACK         — close
 * Touch:
 *   tap a row        — select it
 *   tap ◄ / ►        — change the selected value
 *   tap a preview zone — "test" it (lights up, fires haptic feedback)
 */
class MobileSettingsSubState extends MusicBeatSubstate
{
	// ── Preview canvas (a mini game screen, ~16:9) ───────────────────────────
	static final CANVAS_X:Float = 60;
	static final CANVAS_Y:Float = 84;
	static final CANVAS_W:Int   = 512;
	static final CANVAS_H:Int   = 288;

	// ── Options column ───────────────────────────────────────────────────────
	static final OPT_X:Float  = 648;
	static final OPT_Y0:Float = 104;
	static final OPT_H:Float  = 60;
	static final OPT_W:Int    = 560;
	static final MAX_OPT:Int  = 6;

	// L D U R — matches MobileHitbox / MobileVirtualPad colours.
	static final ZONE_COLORS = [0xFFFF00FF, 0xFF00FFFF, 0xFF00FF00, 0xFFFF0000];
	static final ZONE_LABELS = ["LEFT", "DOWN", "UP", "RIGHT"];

	// ── UI: preview ──────────────────────────────────────────────────────────
	var _canvasBg:FlxSprite;
	var _modeText:FlxText;
	var _zones:Array<PreviewZone> = [];

	// ── UI: options (fixed pool, updated in place) ───────────────────────────
	var _rowHi:Array<FlxSprite>    = [];
	var _rowLabel:Array<FlxText>   = [];
	var _rowValue:Array<FlxText>   = [];
	var _rowLeft:Array<FlxText>    = [];
	var _rowRight:Array<FlxText>   = [];
	var _descText:FlxText;

	// ── State ────────────────────────────────────────────────────────────────
	var _opts:Array<MobileOpt> = [];
	var _sel:Int = 0;

	var _demoTimer:Float = 0.0;
	var _demoIdx:Int = 0;
	var _touchingZone:Bool = false;

	// ── Lifecycle ──────────────────────────────────────────────────────────────

	public function new()
	{
		super();
	}

	override function create()
	{
		// Dim the menu behind us.
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 8, 210));
		add(bg);

		var titleTxt = new FlxText(0, 18, FlxG.width, Lang.str('opt_category_mobile', 'MOBILE CONTROLS').toUpperCase());
		titleTxt.setFormat(Paths.font('vcr.ttf'), 38, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleTxt.borderSize = 2;
		add(titleTxt);

		// Caption above the canvas (kept clear of the canvas so zones never cover it).
		_modeText = new FlxText(CANVAS_X, 58, CANVAS_W, '');
		_modeText.setFormat(Paths.font('vcr.ttf'), 18, 0xFFFFE066, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_modeText.borderSize = 1.5;
		add(_modeText);

		// Canvas background — zones are drawn on top of this.
		_canvasBg = new FlxSprite(CANVAS_X, CANVAS_Y).makeGraphic(CANVAS_W, CANVAS_H, 0xFF0A0A12);
		_canvasBg.alpha = 0.9;
		add(_canvasBg);

		// Options row pool.
		for (i in 0...MAX_OPT)
		{
			final rowY = OPT_Y0 + i * OPT_H;

			var hi = new FlxSprite(OPT_X, rowY).makeGraphic(OPT_W, Std.int(OPT_H - 6), FlxColor.fromRGB(255, 230, 60, 38));
			hi.visible = false;
			_rowHi.push(hi);
			add(hi);

			var lbl = new FlxText(OPT_X + 14, rowY + 8, OPT_W - 200, '');
			lbl.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.visible = false;
			_rowLabel.push(lbl);
			add(lbl);

			var lA = new FlxText(OPT_X + OPT_W - 168, rowY + 8, 40, '◄');
			lA.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.fromRGB(120, 200, 255), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lA.borderSize = 1;
			lA.visible = false;
			_rowLeft.push(lA);
			add(lA);

			var v = new FlxText(OPT_X + OPT_W - 158, rowY + 8, 140, '');
			v.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			v.borderSize = 1.5;
			v.visible = false;
			_rowValue.push(v);
			add(v);

			var rA = new FlxText(OPT_X + OPT_W - 36, rowY + 8, 40, '►');
			rA.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.fromRGB(120, 200, 255), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			rA.borderSize = 1;
			rA.visible = false;
			_rowRight.push(rA);
			add(rA);
		}

		_descText = new FlxText(OPT_X, OPT_Y0 + MAX_OPT * OPT_H + 6, OPT_W, '');
		_descText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(190, 190, 190), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_descText.borderSize = 1;
		add(_descText);

		var help = new FlxText(340, FlxG.height - 60, 600,
			Lang.str('mobile_controls_help', '◄ ►  change   ·   tap a zone to test   ·   B  back'));
		help.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(140, 140, 140), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		help.borderSize = 1;
		add(help);

		super.create();

		#if mobile
		addVirtualPad(LEFT_FULL, A_B);
		addVirtualPadCamera();
		#end

		_rebuildOptions();
		_rebuildPreview();
		_updateRows();
	}

	// ── Update ───────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		_updatePreview(elapsed);

		if (controls.BACK)
		{
			FunkinSound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		_handleInput();
		#if mobile
		_handleTouch();
		#end
	}

	// ── Input ────────────────────────────────────────────────────────────────

	function _handleInput():Void
	{
		if (_opts.length == 0) return;

		if (controls.UI_UP_P)
		{
			_sel = (_sel <= 0) ? _opts.length - 1 : _sel - 1;
			FunkinSound.play(Paths.sound('hover'), 0.5);
			_updateRows();
		}
		if (controls.UI_DOWN_P)
		{
			_sel = (_sel >= _opts.length - 1) ? 0 : _sel + 1;
			FunkinSound.play(Paths.sound('hover'), 0.5);
			_updateRows();
		}

		if (controls.UI_LEFT_P)  _changeSelected(-1);
		if (controls.UI_RIGHT_P) _changeSelected(1);

		if (controls.ACCEPT)
		{
			final opt = _opts[_sel];
			if (opt != null && opt.kind == 'bool') _changeSelected(1);
		}
	}

	#if mobile
	function _handleTouch():Void
	{
		if (!FlxG.mouse.justPressed) return;

		final mx = FlxG.mouse.x;
		final my = FlxG.mouse.y;

		// Preview zones — "test" tap.
		for (i in 0..._zones.length)
		{
			if (FlxG.mouse.overlaps(_zones[i].spr))
			{
				_zones[i].pressed = true;
				if (ClientPrefs.hapticFeedback) mobile.backend.AndroidUtils.vibrate(12);
				FunkinSound.play(Paths.sound('hover'), 0.4);
				return;
			}
		}

		// Option rows.
		for (i in 0..._opts.length)
		{
			if (i >= MAX_OPT) break;

			if (_rowLeft[i].visible && FlxG.mouse.overlaps(_rowLeft[i]))
			{
				if (_sel != i) { _sel = i; _updateRows(); }
				_changeSelected(-1);
				return;
			}
			if (_rowRight[i].visible && FlxG.mouse.overlaps(_rowRight[i]))
			{
				if (_sel != i) { _sel = i; _updateRows(); }
				_changeSelected(1);
				return;
			}

			final rowY = OPT_Y0 + i * OPT_H;
			if (mx >= OPT_X && mx <= OPT_X + OPT_W && my >= rowY && my < rowY + OPT_H)
			{
				if (_sel != i)
				{
					_sel = i;
					FunkinSound.play(Paths.sound('hover'), 0.5);
					_updateRows();
				}
				else if (_opts[i].kind == 'bool')
				{
					_changeSelected(1);
				}
				return;
			}
		}
	}
	#end

	function _changeSelected(dir:Int):Void
	{
		if (dir == 0) return;
		final opt = _opts[_sel];
		if (opt == null) return;

		switch (opt.kind)
		{
			case 'bool':
				_setBool(opt.id, !_getBool(opt.id));

			case 'string':
				if (opt.stored != null)
				{
					var idx = opt.stored.indexOf(_getStr(opt.id));
					idx += dir;
					if (idx < 0) idx = opt.stored.length - 1;
					if (idx >= opt.stored.length) idx = 0;
					_setStr(opt.id, opt.stored[idx]);
				}

			case 'percent':
				var v = _getFloat(opt.id) + dir * 0.05;
				v = FlxMath.bound(v, 0, 1);
				v = Math.round(v * 100) / 100;
				_setFloat(opt.id, v);
		}

		FunkinSound.play(Paths.sound('scrollMenu'));

		// Layout / input changes alter both the visible options and the preview.
		if (opt.id == 'game')
		{
			_rebuildOptions();
			_rebuildPreview();
		}
		else if (opt.id == 'layout')
		{
			_rebuildPreview();
		}

		_updateRows();
	}

	// ── ClientPrefs accessors ──────────────────────────────────────────────────

	function _getStr(id:String):String
		return switch (id)
		{
			case 'nav':    ClientPrefs.navInputMode;
			case 'game':   ClientPrefs.gameInputMode;
			case 'layout': ClientPrefs.hitboxLayout;
			case 'aspectRatio': ClientPrefs.aspectRatioMode;
			default: '';
		};

	function _setStr(id:String, v:String):Void
		switch (id)
		{
			case 'nav':    ClientPrefs.navInputMode = v;
			case 'game':   ClientPrefs.gameInputMode = v;
			case 'layout': ClientPrefs.hitboxLayout = v;
			case 'aspectRatio':
				ClientPrefs.aspectRatioMode = v;
				funkin.backend.FunkinRatioScaleMode.resetScaleMode();
		}

	function _getFloat(id:String):Float
		return switch (id)
		{
			case 'hitboxAlpha': ClientPrefs.hitboxAlpha;
			case 'padAlpha':    ClientPrefs.virtualPadAlpha;
			default: 0;
		};

	function _setFloat(id:String, v:Float):Void
		switch (id)
		{
			case 'hitboxAlpha': ClientPrefs.hitboxAlpha = v;
			case 'padAlpha':    ClientPrefs.virtualPadAlpha = v;
		}

	inline function _getBool(id:String):Bool return ClientPrefs.hapticFeedback;

	inline function _setBool(id:String, v:Bool):Void ClientPrefs.hapticFeedback = v;

	// ── Options model ──────────────────────────────────────────────────────────

	function _rebuildOptions():Void
	{
		_opts = [];

		_opts.push({
			id: 'haptic', kind: 'bool',
			label: Lang.str('opt_haptic', 'Haptic Feedback'),
			desc:  Lang.str('opt_haptic_desc', 'Vibrates briefly on each note hit.\nOnly fires when you are in control (not bot play).')
		});

		_opts.push({
			id: 'nav', kind: 'string',
			label: Lang.str('opt_navinput', 'Navigation Input'),
			desc:  Lang.str('opt_navinput_desc', 'How you interact with menus and UI.\nTouch uses native screen taps. Virtual Pad shows on-screen buttons.'),
			choices: [Lang.str('choice_navinput_touch', 'Touch'), Lang.str('choice_navinput_pad', 'Virtual Pad')],
			stored:  ['Touch', 'Virtual Pad']
		});

		_opts.push({
			id: 'game', kind: 'string',
			label: Lang.str('opt_gameinput', 'Gameplay Input'),
			desc:  Lang.str('opt_gameinput_desc', 'How you hit notes in-game.\nHitbox: split-screen zones. Virtual Pad: D-pad buttons. Tap Notes: touch notes directly.'),
			choices: [Lang.str('choice_gameinput_hitbox', 'Hitbox'), Lang.str('choice_gameinput_pad', 'Virtual Pad'), Lang.str('choice_gameinput_tapnotes', 'Tap Notes')],
			stored:  ['Hitbox', 'Virtual Pad', 'Tap Notes']
		});

		if (ClientPrefs.gameInputMode == 'Hitbox')
		{
			_opts.push({
				id: 'layout', kind: 'string',
				label: Lang.str('opt_hitboxlayout', 'Hitbox Layout'),
				desc:  Lang.str('opt_hitboxlayout_desc', 'Arrangement of the tap zones.\nFour Lanes: four columns. Two Thumb: 2×2 grid. DPad: circular buttons. Arrows: note-style arrows.'),
				choices: [Lang.str('choice_hitboxlayout_4l', 'Four Lanes'), Lang.str('choice_hitboxlayout_2t', 'Two Thumb'), Lang.str('choice_hitboxlayout_dpad', 'DPad'), Lang.str('choice_hitboxlayout_arrows', 'Arrows'), Lang.str('choice_hitboxlayout_triangle', 'Triangle')],
				stored:  ['Four Lanes', 'Two Thumb', 'DPad', 'Arrows', 'Triangle']
			});
			_opts.push({
				id: 'hitboxAlpha', kind: 'percent',
				label: Lang.str('opt_hitboxalpha', 'Hitbox Opacity'),
				desc:  Lang.str('opt_hitboxalpha_desc', 'How visible the hitbox zones appear when pressed.')
			});
		}
		else
		{
			_opts.push({
				id: 'padAlpha', kind: 'percent',
				label: Lang.str('opt_padopacity', 'Pad Opacity'),
				desc:  Lang.str('opt_padopacity_desc', 'How visible the virtual pad buttons appear.')
			});
		}

		#if mobile
		_opts.push({
			id: 'aspectRatio', kind: 'string',
			label: Lang.str('opt_aspectratio', 'Screen Fit'),
			desc:  Lang.str('opt_aspectratio_desc', 'How the game fills the screen.\nFit: keeps 16:9 with black bars. Stretch: fills screen (may distort).'),
			choices: [Lang.str('choice_aspect_fit', 'Fit (16:9)'), Lang.str('choice_aspect_stretch', 'Stretch')],
			stored:  ['fit', 'stretch']
		});
		#end

		if (_sel >= _opts.length) _sel = _opts.length - 1;
		if (_sel < 0) _sel = 0;
	}

	function _displayValue(opt:MobileOpt):String
	{
		return switch (opt.kind)
		{
			case 'bool':
				_getBool(opt.id) ? Lang.str('on', 'ON') : Lang.str('off', 'OFF');
			case 'percent':
				Std.int(Math.round(_getFloat(opt.id) * 100)) + '%';
			case 'string':
				if (opt.stored != null && opt.choices != null)
				{
					final idx = opt.stored.indexOf(_getStr(opt.id));
					(idx >= 0 && idx < opt.choices.length) ? opt.choices[idx] : _getStr(opt.id);
				}
				else _getStr(opt.id);
			default: '';
		};
	}

	function _updateRows():Void
	{
		for (i in 0...MAX_OPT)
		{
			final opt = (i < _opts.length) ? _opts[i] : null;
			final show = (opt != null);

			_rowHi[i].visible    = show && (i == _sel);
			_rowLabel[i].visible = show;
			_rowValue[i].visible = show;
			_rowLeft[i].visible  = show;
			_rowRight[i].visible = show;

			if (!show) continue;

			_rowLabel[i].text = opt.label;
			_rowLabel[i].color = (i == _sel) ? FlxColor.YELLOW : FlxColor.WHITE;
			_rowValue[i].text = _displayValue(opt);
			_rowValue[i].color = (i == _sel) ? FlxColor.YELLOW : FlxColor.fromRGB(210, 210, 210);
		}

		final sel = (_sel >= 0 && _sel < _opts.length) ? _opts[_sel] : null;
		_descText.text = (sel != null) ? sel.desc : '';
	}

	// ── Preview canvas ───────────────────────────────────────────────────────

	function _currentOpacity():Float
		return (ClientPrefs.gameInputMode == 'Hitbox') ? ClientPrefs.hitboxAlpha : ClientPrefs.virtualPadAlpha;

	inline function _idleAlpha():Float  return Math.max(_currentOpacity() * 0.35, 0.10);
	inline function _pressAlpha():Float return Math.max(_currentOpacity(), 0.22);

	function _clearZones():Void
	{
		for (z in _zones)
		{
			remove(z.spr, true);
			z.spr.destroy();
			remove(z.label, true);
			z.label.destroy();
		}
		_zones.resize(0);
	}

	function _rebuildPreview():Void
	{
		_clearZones();

		if (ClientPrefs.gameInputMode == 'Virtual Pad')
		{
			_buildPadPreview();
			_modeText.text = Lang.str('preview_mode_vpad', 'Virtual Pad');
		}
		else if (ClientPrefs.gameInputMode == 'Tap Notes')
		{
			// No visual zones for tap notes - just touch the notes directly
			_modeText.text = Lang.str('preview_mode_tapnotes', 'Tap Notes');
		}
		else if (ClientPrefs.hitboxLayout == 'Two Thumb')
		{
			_buildTwoThumbPreview();
			_modeText.text = 'Hitbox  ·  ' + Lang.str('choice_hitboxlayout_2t', 'Two Thumb');
		}
		else if (ClientPrefs.hitboxLayout == 'DPad')
		{
			_buildDPadPreview();
			_modeText.text = 'Hitbox  ·  ' + Lang.str('choice_hitboxlayout_dpad', 'DPad');
		}
		else if (ClientPrefs.hitboxLayout == 'Arrows')
		{
			_buildArrowsPreview();
			_modeText.text = 'Hitbox  ·  ' + Lang.str('choice_hitboxlayout_arrows', 'Arrows');
		}
		else if (ClientPrefs.hitboxLayout == 'Triangle')
		{
			_buildTrianglePreview();
			_modeText.text = 'Hitbox  ·  ' + Lang.str('choice_hitboxlayout_triangle', 'Triangle');
		}
		else
		{
			_buildFourLanesPreview();
			_modeText.text = 'Hitbox  ·  ' + Lang.str('choice_hitboxlayout_4l', 'Four Lanes');
		}

		_demoIdx = 0;
		_demoTimer = 0.0;
	}

	function _buildFourLanesPreview():Void
	{
		final colW = CANVAS_W / 4;
		for (i in 0...4)
			_addZone(CANVAS_X + i * colW, CANVAS_Y, colW, CANVAS_H, i);
	}

	function _buildTwoThumbPreview():Void
	{
		final hw = CANVAS_W / 2;
		final hh = CANVAS_H / 2;
		// TL = LEFT, BL = DOWN, TR = UP, BR = RIGHT (matches MobileHitbox).
		_addZone(CANVAS_X,      CANVAS_Y,      hw, hh, 0);
		_addZone(CANVAS_X,      CANVAS_Y + hh, hw, hh, 1);
		_addZone(CANVAS_X + hw, CANVAS_Y,      hw, hh, 2);
		_addZone(CANVAS_X + hw, CANVAS_Y + hh, hw, hh, 3);
	}

	/**
	 * Builds a circular DPad preview with two zones of 4 circular buttons each.
	 */
	function _buildDPadPreview():Void
	{
		final cx = CANVAS_X + CANVAS_W / 2;
		final cy = CANVAS_Y + CANVAS_H / 2;
		final radius = 30.0;
		final zoneRadius = 20.0;

		// Left zone: LEFT(π) and DOWN(π/2)
		_addZoneCircle(cx - CANVAS_W / 4 + Math.cos(Math.PI) * zoneRadius, cy + Math.sin(Math.PI) * zoneRadius, radius, 0);
		_addZoneCircle(cx - CANVAS_W / 4 + Math.cos(Math.PI / 2) * zoneRadius, cy + Math.sin(Math.PI / 2) * zoneRadius, radius, 1);

		// Right zone: UP(1.5π) and RIGHT(0)
		_addZoneCircle(cx + CANVAS_W / 4 + Math.cos(Math.PI * 1.5) * zoneRadius, cy + Math.sin(Math.PI * 1.5) * zoneRadius, radius, 2);
		_addZoneCircle(cx + CANVAS_W / 4 + Math.cos(0) * zoneRadius, cy + Math.sin(0) * zoneRadius, radius, 3);
	}

	/**
	 * Adds a circular zone preview element.
	 * Uses FlxSprite with circular bitmap since _preview.graphics is not available.
	 */
	function _addZoneCircle(X:Float, Y:Float, radius:Float, colorIndex:Int):Void
	{
		var color = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000][colorIndex];
		var diameter = Std.int(radius * 2);

		// Create a circular bitmap
		var bitmap = new BitmapData(diameter, diameter, true, 0x00000000);
		var cx = Std.int(radius);
		var cy = Std.int(radius);

		for (px in 0...diameter)
		{
			for (py in 0...diameter)
			{
				var dx = px - cx;
				var dy = py - cy;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist <= radius)
				{
					bitmap.setPixel32(px, py, (color & 0x00FFFFFF) | 0x88000000);
				}
			}
		}

		var spr = new FlxSprite(X - radius, Y - radius).loadGraphic(bitmap);
		spr.alpha = _idleAlpha();
		add(spr);

		_zones.push({spr: spr, label: null, colorIdx: colorIndex, pressed: false, curA: _idleAlpha()});
	}

	/**
	 * Builds a preview showing arrow buttons at the bottom of the canvas.
	 */
	function _buildArrowsPreview():Void
	{
		final arrowW = 40.0;
		final arrowH = 30.0;
		final spacing = 15.0;
		final totalW = (arrowW + spacing) * 4 - spacing;
		final startX = CANVAS_X + (CANVAS_W - totalW) / 2;
		final y = CANVAS_Y + CANVAS_H - arrowH * 2;

		// Draw 4 arrow rectangles in order: LEFT, DOWN, UP, RIGHT
		var colors = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000];
		for (i in 0...4)
		{
			var x = startX + i * (arrowW + spacing);
			_addZone(x, y, arrowW, arrowH, i);
		}
	}

	/**
	 * Builds a preview showing triangle buttons in two zones.
	 */
	function _buildTrianglePreview():Void
	{
		// Two zones: left (LEFT+DOWN) and right (UP+RIGHT)
		var zoneHalf:Float = CANVAS_W / 2;

		// Left zone: tall bar LEFT + bottom square DOWN
		var leftBarW:Float = zoneHalf / 2;
		var squareSize:Float = zoneHalf / 2;
		var squareH:Float = CANVAS_H / 2;

		// LEFT bar (full height, left portion)
		_addZone(CANVAS_X, CANVAS_Y, leftBarW, CANVAS_H, 0);

		// DOWN square (bottom half, right portion of left zone)
		_addZone(CANVAS_X + leftBarW, CANVAS_Y + squareH, squareSize, squareH, 1);

		// Right zone: top square UP + tall bar RIGHT
		// UP square (top half, left portion of right zone)
		_addZone(CANVAS_X + zoneHalf, CANVAS_Y, squareSize, squareH, 2);

		// RIGHT bar (full height, right portion)
		_addZone(CANVAS_X + zoneHalf + squareSize, CANVAS_Y, leftBarW, CANVAS_H, 3);
	}

	function _buildPadPreview():Void
	{
		// Scale the real LEFT_FULL layout (game coords) into the canvas.
		final sx = CANVAS_W / FlxG.width;
		final sy = CANVAS_H / FlxG.height;
		final bw = 134 * sx;
		final bh = 134 * sy;

		inline function place(gx:Float, gy:Float, ci:Int)
			_addZone(CANVAS_X + gx * sx, CANVAS_Y + gy * sy, bw, bh, ci);

		place(105, FlxG.height - 345, 2); // UP
		place(0,   FlxG.height - 243, 0); // LEFT
		place(207, FlxG.height - 243, 3); // RIGHT
		place(105, FlxG.height - 135, 1); // DOWN
	}

	function _addZone(x:Float, y:Float, w:Float, h:Float, colorIdx:Int):Void
	{
		var spr = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.WHITE);
		spr.color = ZONE_COLORS[colorIdx];
		spr.alpha = _idleAlpha();
		add(spr);

		var lbl = new FlxText(x, y + h / 2 - 11, w, ZONE_LABELS[colorIdx]);
		lbl.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		lbl.borderSize = 1.5;
		add(lbl);

		_zones.push({spr: spr, label: lbl, colorIdx: colorIdx, pressed: false, curA: _idleAlpha()});
	}

	function _updatePreview(elapsed:Float):Void
	{
		if (_zones.length == 0) return;

		// Hold-to-test: a zone stays lit while the screen is held over it.
		_touchingZone = false;
		#if mobile
		if (FlxG.mouse.pressed)
		{
			for (z in _zones)
			{
				if (FlxG.mouse.overlaps(z.spr)) { z.pressed = true; _touchingZone = true; }
				else z.pressed = false;
			}
		}
		else
		{
			for (z in _zones) z.pressed = false;
		}
		#end

		// Idle "demo" shimmer so the preview feels alive when untouched.
		if (!_touchingZone)
		{
			_demoTimer += elapsed;
			if (_demoTimer >= 0.65)
			{
				_demoTimer = 0.0;
				_demoIdx = (_demoIdx + 1) % _zones.length;
			}
			for (i in 0..._zones.length)
				_zones[i].pressed = (i == _demoIdx);
		}

		final pressA = _pressAlpha();
		final idleA  = _idleAlpha();
		for (z in _zones)
		{
			final target = z.pressed ? pressA : idleA;
			z.curA = FlxMath.lerp(z.curA, target, FlxMath.bound(elapsed * 10, 0, 1));
			z.spr.alpha = z.curA;
		}
	}

	// ── Cleanup ──────────────────────────────────────────────────────────────

	override function close():Void
	{
		#if mobile
		removeVirtualPad();
		#end
		super.close();
	}

	override function destroy():Void
	{
		_clearZones();
		super.destroy();
	}
}

#end
