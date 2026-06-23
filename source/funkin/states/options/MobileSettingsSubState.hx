package funkin.states.options;

#if mobile

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;

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


