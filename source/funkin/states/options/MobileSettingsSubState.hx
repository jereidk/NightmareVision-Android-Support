package funkin.states.options;

#if mobile

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.math.FlxRect;

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

/** A single tap zone drawn on the preview canvas (a framed tile). */
typedef PreviewZone =
{
	border:FlxSprite,
	fill:FlxSprite,
	label:FlxText,
	colorIdx:Int,
	pressed:Bool,
	curA:Float
}

/**
 * Dedicated mobile-controls screen.
 *
 * Independent of the generic options list (opened from its own OptionsState
 * button, like the Editor / DLC manager). A live, interactive preview canvas
 * of the chosen control scheme sits on the left; an adaptive option list with
 * inline controls (toggle pills, draggable opacity sliders) sits on the right.
 *
 * Navigation:
 *   UP / DOWN    — move selection
 *   LEFT / RIGHT — change the selected value
 *   ACCEPT       — toggle (bool options)
 *   RESET        — restore mobile defaults
 *   BACK         — close
 * Touch:
 *   tap a row          — select it
 *   tap ◄ / ►          — nudge the value
 *   drag a slider      — set opacity directly
 *   tap a preview zone — "test" it (lights up, fires haptic feedback)
 */
class MobileSettingsSubState extends MusicBeatSubstate
{
	// ── Preview canvas (a mini game screen, ~16:9) ───────────────────────────
	static final CANVAS_X:Float = 60;
	static final CANVAS_Y:Float = 92;
	static final CANVAS_W:Int   = 512;
	static final CANVAS_H:Int   = 276; // bezel ends at ~374, just clear of the on-screen pad
	static final ZONE_GAP:Int   = 4; // inset of the coloured fill inside its tile

	// ── Options column ───────────────────────────────────────────────────────
	static final OPT_X:Float  = 648;
	static final OPT_Y0:Float = 116;
	static final OPT_H:Float  = 60;
	static final OPT_W:Int    = 560;
	static final MAX_OPT:Int  = 6;

	// Inline control box (slider / pill / value) on the right of each row.
	static final ARROW_W:Int = 34;
	static final CTRL_W:Int  = 140;

	// L D U R — matches MobileHitbox / MobileVirtualPad colours.
	static final ZONE_COLORS = [0xFFFF00FF, 0xFF00FFFF, 0xFF00FF00, 0xFFFF0000];
	static final ZONE_LABELS = ["LEFT", "DOWN", "UP", "RIGHT"];

	static final ACCENT:Int   = 0xFF45D7FF;
	static final SEL_COLOR:Int = 0xFFFFE066;

	// ── UI: preview ──────────────────────────────────────────────────────────
	var _canvasFrame:FlxSprite;
	var _canvasBg:FlxSprite;
	var _modeText:FlxText;
	var _zones:Array<PreviewZone> = [];

	// ── UI: options (fixed pool, updated in place) ───────────────────────────
	var _selBar:FlxSprite;
	var _selAccent:FlxSprite;
	var _rowLabel:Array<FlxText>   = [];
	var _rowValue:Array<FlxText>   = [];
	var _rowLeft:Array<FlxText>    = [];
	var _rowRight:Array<FlxText>   = [];
	var _rowTrack:Array<FlxSprite> = [];
	var _rowFill:Array<FlxSprite>  = [];
	var _rowFillRect:Array<FlxRect> = [];
	var _rowPill:Array<FlxSprite>  = [];
	var _descText:FlxText;

	// ── State ────────────────────────────────────────────────────────────────
	var _opts:Array<MobileOpt> = [];
	var _sel:Int = 0;
	var _selY:Float = OPT_Y0;
	var _time:Float = 0.0;

	var _demoTimer:Float = 0.0;
	var _demoIdx:Int = 0;
	var _touchingZone:Bool = false;
	var _dragging:Bool = false;

	// ── Derived geometry ───────────────────────────────────────────────────────
	inline function rightArrowX():Float return OPT_X + OPT_W - 36;
	inline function ctrlX():Float        return rightArrowX() - 8 - CTRL_W;
	inline function leftArrowX():Float   return ctrlX() - 8 - ARROW_W;

	// ── Lifecycle ──────────────────────────────────────────────────────────────

	public function new()
	{
		super();
	}

	override function create()
	{
		// Dim the menu behind us.
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 10, 215));
		add(bg);

		_buildHeader();
		_buildCanvasShell();
		_buildOptionPool();

		_descText = new FlxText(OPT_X, OPT_Y0 + MAX_OPT * OPT_H + 4, OPT_W, '');
		_descText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(195, 195, 205), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_descText.borderSize = 1;
		add(_descText);

		var help = new FlxText(280, FlxG.height - 56, 720,
			Lang.str('mobile_controls_help', '◄ ►  change     drag a slider     tap a zone to test     RESET  defaults     B  back'));
		help.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(150, 150, 160), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		help.borderSize = 1;
		add(help);

		super.create();

		#if mobile
		addVirtualPad(LEFT_FULL, A_B);
		addVirtualPadCamera();
		#end

		_rebuildOptions();
		_rebuildPreview();
		_selY = OPT_Y0 + _sel * OPT_H;
		_updateRows();
	}

	function _buildHeader():Void
	{
		var titleTxt = new FlxText(0, 16, FlxG.width, Lang.str('opt_category_mobile', 'MOBILE CONTROLS').toUpperCase());
		titleTxt.setFormat(Paths.font('vcr.ttf'), 36, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleTxt.borderSize = 2;
		add(titleTxt);

		var underline = new FlxSprite(FlxG.width / 2 - 180, 54).makeGraphic(360, 4, ACCENT);
		underline.alpha = 0.9;
		add(underline);
	}

	function _buildCanvasShell():Void
	{
		// Caption above the canvas (kept clear so zones never cover it).
		_modeText = new FlxText(CANVAS_X, CANVAS_Y - 28, CANVAS_W, '');
		_modeText.setFormat(Paths.font('vcr.ttf'), 18, SEL_COLOR, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_modeText.borderSize = 1.5;
		add(_modeText);

		// Bezel + screen background — zones draw on top of these.
		_canvasFrame = new FlxSprite(CANVAS_X - 6, CANVAS_Y - 6).makeGraphic(CANVAS_W + 12, CANVAS_H + 12, FlxColor.fromRGB(60, 64, 86));
		_canvasFrame.alpha = 0.95;
		add(_canvasFrame);

		_canvasBg = new FlxSprite(CANVAS_X, CANVAS_Y).makeGraphic(CANVAS_W, CANVAS_H, 0xFF0A0A12);
		add(_canvasBg);
	}

	function _buildOptionPool():Void
	{
		// Gliding selection bar + left accent (positioned every frame).
		_selBar = new FlxSprite(OPT_X, OPT_Y0).makeGraphic(OPT_W, Std.int(OPT_H - 6), FlxColor.fromRGB(255, 230, 100, 30));
		add(_selBar);

		_selAccent = new FlxSprite(OPT_X, OPT_Y0).makeGraphic(5, Std.int(OPT_H - 14), SEL_COLOR);
		add(_selAccent);

		for (i in 0...MAX_OPT)
		{
			final rowY = OPT_Y0 + i * OPT_H;

			var lbl = new FlxText(OPT_X + 16, rowY + 16, Std.int(leftArrowX() - (OPT_X + 16) - 8), '');
			lbl.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.visible = false;
			_rowLabel.push(lbl);
			add(lbl);

			var lA = new FlxText(leftArrowX(), rowY + 14, ARROW_W, '◄');
			lA.setFormat(Paths.font('vcr.ttf'), 26, ACCENT, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lA.borderSize = 1;
			lA.visible = false;
			_rowLeft.push(lA);
			add(lA);

			// Slider track + fill (percent rows) and toggle pill (bool rows).
			var track = new FlxSprite(ctrlX(), rowY + (OPT_H - 18) / 2).makeGraphic(CTRL_W, 18, FlxColor.fromRGB(42, 42, 54));
			track.visible = false;
			_rowTrack.push(track);
			add(track);

			var fill = new FlxSprite(ctrlX(), rowY + (OPT_H - 18) / 2).makeGraphic(CTRL_W, 18, ACCENT);
			fill.visible = false;
			_rowFill.push(fill);
			_rowFillRect.push(new FlxRect(0, 0, CTRL_W, 18));
			add(fill);

			var pill = new FlxSprite(ctrlX(), rowY + (OPT_H - 28) / 2).makeGraphic(CTRL_W, 28, FlxColor.fromRGB(85, 85, 96));
			pill.visible = false;
			_rowPill.push(pill);
			add(pill);

			var v = new FlxText(ctrlX(), rowY + 16, CTRL_W, '');
			v.setFormat(Paths.font('vcr.ttf'), 21, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			v.borderSize = 1.5;
			v.visible = false;
			_rowValue.push(v);
			add(v);

			var rA = new FlxText(rightArrowX(), rowY + 14, ARROW_W, '►');
			rA.setFormat(Paths.font('vcr.ttf'), 26, ACCENT, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			rA.borderSize = 1;
			rA.visible = false;
			_rowRight.push(rA);
			add(rA);
		}
	}

	// ── Update ───────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		_time += elapsed;
		_updatePreview(elapsed);
		_updateSelectionVisuals(elapsed);

		if (controls.BACK)
		{
			FunkinSound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		if (controls.RESET)
		{
			_resetDefaults();
			return;
		}

		#if mobile
		if (_handleSliderDrag()) return;
		#end

		_handleInput();
		#if mobile
		_handleTouch();
		#end
	}

	/** Glides the selection bar/accent to the active row and pulses the cues. */
	function _updateSelectionVisuals(elapsed:Float):Void
	{
		final targetY = OPT_Y0 + _sel * OPT_H;
		_selY = FlxMath.lerp(_selY, targetY, FlxMath.bound(elapsed * 14, 0, 1));

		final visible = (_opts.length > 0);
		_selBar.visible = _selAccent.visible = visible;
		_selBar.y = _selY + 3;
		_selAccent.y = _selY + 7;

		final pulse = 0.5 + 0.5 * Math.sin(_time * 6.0);
		_selAccent.alpha = 0.55 + 0.45 * pulse;

		// Pulse the arrows of the selected row only.
		for (i in 0...MAX_OPT)
		{
			final isSel = (i == _sel);
			final a = isSel ? (0.55 + 0.45 * pulse) : 0.55;
			if (_rowLeft[i].visible)  _rowLeft[i].alpha  = a;
			if (_rowRight[i].visible) _rowRight[i].alpha = a;
		}
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
	/** Lets the player drag the opacity slider of the selected percent row. */
	function _handleSliderDrag():Bool
	{
		if (_sel < 0 || _sel >= _opts.length || _sel >= MAX_OPT) { _dragging = false; return false; }
		final opt = _opts[_sel];
		if (opt == null || opt.kind != 'percent') { _dragging = false; return false; }

		final rowY = OPT_Y0 + _sel * OPT_H;
		final inTrack = FlxG.mouse.x >= ctrlX() - 6 && FlxG.mouse.x <= ctrlX() + CTRL_W + 6
			&& FlxG.mouse.y >= rowY && FlxG.mouse.y <= rowY + OPT_H;

		if (FlxG.mouse.justPressed && inTrack) _dragging = true;
		if (!FlxG.mouse.pressed) _dragging = false;

		if (_dragging)
		{
			var frac = (FlxG.mouse.x - ctrlX()) / CTRL_W;
			frac = FlxMath.bound(frac, 0, 1);
			_setFloat(opt.id, Math.round(frac * 100) / 100);
			_updateRows();
			return true;
		}
		return false;
	}

	function _handleTouch():Void
	{
		if (!FlxG.mouse.justPressed) return;

		// Preview zones — "test" tap.
		for (i in 0..._zones.length)
		{
			if (FlxG.mouse.overlaps(_zones[i].fill))
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
			if (FlxG.mouse.x >= OPT_X && FlxG.mouse.x <= OPT_X + OPT_W && FlxG.mouse.y >= rowY && FlxG.mouse.y < rowY + OPT_H)
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
				final nv = !_getBool(opt.id);
				_setBool(opt.id, nv);
				// Buzz once so the player feels what they just enabled.
				if (opt.id == 'haptic' && nv) mobile.backend.AndroidUtils.vibrate(20);

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

	function _resetDefaults():Void
	{
		ClientPrefs.hapticFeedback = true;
		ClientPrefs.navInputMode   = 'Touch';
		ClientPrefs.gameInputMode  = 'Hitbox';
		ClientPrefs.hitboxLayout   = 'Four Lanes';
		ClientPrefs.hitboxAlpha    = 0.2;
		ClientPrefs.virtualPadAlpha = 0.5;

		_rebuildOptions();
		_rebuildPreview();
		_updateRows();

		FunkinSound.play(Paths.sound('cancelMenu'));
		if (ClientPrefs.hapticFeedback) mobile.backend.AndroidUtils.vibrate(20);
	}

	// ── ClientPrefs accessors ──────────────────────────────────────────────────

	function _getStr(id:String):String
		return switch (id)
		{
			case 'nav':    ClientPrefs.navInputMode;
			case 'game':   ClientPrefs.gameInputMode;
			case 'layout': ClientPrefs.hitboxLayout;
			default: '';
		};

	function _setStr(id:String, v:String):Void
		switch (id)
		{
			case 'nav':    ClientPrefs.navInputMode = v;
			case 'game':   ClientPrefs.gameInputMode = v;
			case 'layout': ClientPrefs.hitboxLayout = v;
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
			desc:  Lang.str('opt_gameinput_desc', 'How you hit notes in-game.\nHitbox splits the screen into tap zones. Virtual Pad shows an on-screen D-pad.'),
			choices: [Lang.str('choice_gameinput_hitbox', 'Hitbox'), Lang.str('choice_gameinput_pad', 'Virtual Pad')],
			stored:  ['Hitbox', 'Virtual Pad']
		});

		if (ClientPrefs.gameInputMode == 'Hitbox')
		{
			_opts.push({
				id: 'layout', kind: 'string',
				label: Lang.str('opt_hitboxlayout', 'Hitbox Layout'),
				desc:  Lang.str('opt_hitboxlayout_desc', 'Arrangement of the tap zones.\nFour Lanes: four columns. Two Thumb: 2×2 grid for two-thumb play.'),
				choices: [Lang.str('choice_hitboxlayout_4l', 'Four Lanes'), Lang.str('choice_hitboxlayout_2t', 'Two Thumb')],
				stored:  ['Four Lanes', 'Two Thumb']
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
			final isSel = show && (i == _sel);

			_rowLabel[i].visible = show;
			_rowValue[i].visible = show;
			_rowLeft[i].visible  = show;
			_rowRight[i].visible = show;

			final isPercent = show && opt.kind == 'percent';
			final isBool    = show && opt.kind == 'bool';

			_rowTrack[i].visible = isPercent;
			_rowFill[i].visible  = isPercent;
			_rowPill[i].visible  = isBool;

			if (!show) continue;

			_rowLabel[i].text  = opt.label;
			_rowLabel[i].color = isSel ? SEL_COLOR : FlxColor.WHITE;
			_rowLabel[i].alpha = isSel ? 1 : 0.7;

			_rowValue[i].text  = _displayValue(opt);
			_rowValue[i].alpha = isSel ? 1 : 0.85;

			if (isPercent)
			{
				final frac = FlxMath.bound(_getFloat(opt.id), 0, 1);
				_rowFillRect[i].set(0, 0, frac * CTRL_W, 18);
				_rowFill[i].clipRect = _rowFillRect[i];
				_rowFill[i].color = isSel ? ACCENT : FlxColor.fromRGB(90, 150, 180);
				_rowValue[i].color = FlxColor.WHITE;
			}
			else if (isBool)
			{
				final on = _getBool(opt.id);
				_rowPill[i].color = on ? FlxColor.fromRGB(63, 203, 110) : FlxColor.fromRGB(85, 85, 96);
				_rowValue[i].color = FlxColor.WHITE;
			}
			else
			{
				_rowValue[i].color = isSel ? SEL_COLOR : FlxColor.fromRGB(210, 210, 210);
			}
		}

		final sel = (_sel >= 0 && _sel < _opts.length) ? _opts[_sel] : null;
		_descText.text = (sel != null) ? sel.desc : '';
	}

	// ── Preview canvas ───────────────────────────────────────────────────────

	function _currentOpacity():Float
		return (ClientPrefs.gameInputMode == 'Hitbox') ? ClientPrefs.hitboxAlpha : ClientPrefs.virtualPadAlpha;

	inline function _idleAlpha():Float  return Math.max(_currentOpacity() * 0.35, 0.12);
	inline function _pressAlpha():Float return Math.max(_currentOpacity(), 0.30);

	function _clearZones():Void
	{
		for (z in _zones)
		{
			remove(z.border, true); z.border.destroy();
			remove(z.fill, true);   z.fill.destroy();
			remove(z.label, true);  z.label.destroy();
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
		else if (ClientPrefs.hitboxLayout == 'Two Thumb')
		{
			_buildTwoThumbPreview();
			_modeText.text = 'Hitbox  ·  ' + Lang.str('choice_hitboxlayout_2t', 'Two Thumb');
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
		final col = ZONE_COLORS[colorIdx];

		// Border tile (constant, so the layout always reads even at low opacity).
		var border = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.WHITE);
		border.color = col;
		border.alpha = 0.32;
		add(border);

		// Inset coloured fill (animated with the opacity setting / presses).
		final fx = x + ZONE_GAP, fy = y + ZONE_GAP;
		final fw = Std.int(Math.max(1, w - ZONE_GAP * 2));
		final fh = Std.int(Math.max(1, h - ZONE_GAP * 2));
		var fill = new FlxSprite(fx, fy).makeGraphic(fw, fh, FlxColor.WHITE);
		fill.color = col;
		fill.alpha = _idleAlpha();
		add(fill);

		var lbl = new FlxText(x, y + h / 2 - 11, w, ZONE_LABELS[colorIdx]);
		lbl.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		lbl.borderSize = 1.5;
		add(lbl);

		_zones.push({border: border, fill: fill, label: lbl, colorIdx: colorIdx, pressed: false, curA: _idleAlpha()});
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
				if (FlxG.mouse.overlaps(z.fill)) { z.pressed = true; _touchingZone = true; }
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
			if (_demoTimer >= 0.6)
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
			z.fill.alpha = z.curA;
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
