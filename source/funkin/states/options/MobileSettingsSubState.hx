package funkin.states.options;

#if mobile

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.graphics.frames.FlxTileFrames;
import openfl.display.BitmapData;

/** One configurable row. Read/written straight through ClientPrefs by `id`. */
typedef MobileOpt =
{
	id:String,        // 'haptic' | 'nav' | 'game' | 'layout' | 'hitboxAlpha' | 'padAlpha' | 'openDataFolder'
	kind:String,      // 'bool' | 'string' | 'percent' | 'button'
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
	static final CANVAS_X:Float = 50;
	static final CANVAS_Y:Float = 120;
	static final CANVAS_W:Int   = 500;
	static final CANVAS_H:Int   = 280;

	// ── Options column ───────────────────────────────────────────────────────
	static final OPT_X:Float  = 600;
	static final OPT_Y0:Float = 120;
	static final OPT_H:Float  = 54;
	static final OPT_W:Int    = 580;
	static final MAX_OPT:Int  = 6;

	// L D U R — matches MobileHitbox / MobileVirtualPad colours (improved).
	static final ZONE_COLORS = [0xFFFF6B9D, 0xFF00D9FF, 0xFF00FF88, 0xFFFFB84D];
	static final ZONE_LABELS = ["LEFT", "DOWN", "UP", "RIGHT"];

	// Color palette for modern FNF style
	static final COLOR_HIGHLIGHT:Int = 0xFFFFD700;
	static final COLOR_SELECTED:Int  = 0xFFFFA500;
	static final COLOR_TEXT:Int      = 0xFFFFFFFF;
	static final COLOR_DESC:Int      = 0xFFB0B0B0;
	static final COLOR_BG:Int        = 0xFF0A0A14;

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
	var _descBg:FlxSprite;
	var _scrollBar:FlxSprite;
	var _scrollThumb:FlxSprite;
	var _helpText:FlxText;
	var _backBtn:FlxSprite;
	var _backBtnLabel:FlxText;

	// ── State ────────────────────────────────────────────────────────────────
	var _opts:Array<MobileOpt> = [];
	var _sel:Int = 0;
	var _selVisual:Float = 0.0; // Smoothly follows _sel
	var _scrollOffset:Float = 0.0; // Target scroll offset
	var _scrollOffsetVisual:Float = 0.0; // Smoothly follows _scrollOffset

	var _demoTimer:Float = 0.0;
	var _demoIdx:Int = 0;
	var _touchingZone:Bool = false;

	// Animation state
	var _enterAlpha:Float = 0.0;
	var _enterComplete:Bool = false;

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

		// Header bar behind the title.
		var topBar = new FlxSprite(0, 0);
		topBar.loadGraphic(Paths.image('menu/common/topBar'));
		topBar.setGraphicSize(FlxG.width, 90);
		topBar.updateHitbox();
		topBar.antialiasing = ClientPrefs.globalAntialiasing;
		add(topBar);

		var titleTxt = new FlxText(0, 10, FlxG.width, Lang.str('opt_category_mobile', 'MOBILE CONTROLS').toUpperCase());
		titleTxt.setFormat(Paths.font('AmaticSC-Bold.ttf'), 50, COLOR_HIGHLIGHT, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleTxt.borderSize = 2;
		titleTxt.antialiasing = ClientPrefs.globalAntialiasing;
		add(titleTxt);

		// Caption above the canvas (placed between header bar and canvas)
		_modeText = new FlxText(CANVAS_X, 92, CANVAS_W, '');
		_modeText.setFormat(Paths.font('vcr.ttf'), 18, 0xFFFFB84D, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_modeText.borderSize = 1.5;
		_modeText.antialiasing = ClientPrefs.globalAntialiasing;
		add(_modeText);

		// Canvas background — star field scaled to preview area.
		_canvasBg = new FlxSprite(CANVAS_X, CANVAS_Y);
		_canvasBg.loadGraphic(Paths.image('menu/common/starFG'));
		_canvasBg.setGraphicSize(CANVAS_W, CANVAS_H);
		_canvasBg.updateHitbox();
		_canvasBg.alpha = 0.95;
		_canvasBg.antialiasing = ClientPrefs.globalAntialiasing;
		add(_canvasBg);

		// Options row pool with improved styling
		for (i in 0...MAX_OPT)
		{
			final rowY = OPT_Y0 + i * OPT_H;

			// Highlight background for selected row
			var hi = new FlxSprite(OPT_X - 6, rowY - 2);
			hi.loadGraphic(Paths.image('menu/freeplay/card'));
			hi.setGraphicSize(OPT_W + 12, Std.int(OPT_H - 4));
			hi.updateHitbox();
			hi.antialiasing = ClientPrefs.globalAntialiasing;
			hi.visible = false;
			_rowHi.push(hi);
			add(hi);

			// Option label
			var lbl = new FlxText(OPT_X + 16, rowY + 6, OPT_W - 275, '');
			lbl.setFormat(Paths.font('vcr.ttf'), 24, COLOR_TEXT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.visible = false;
			_rowLabel.push(lbl);
			add(lbl);

			// Left arrow  (must be added AFTER value so it draws on top)
			// Value display (centre of the right block)
			var v = new FlxText(OPT_X + OPT_W - 192, rowY + 6, 134, '');
			v.setFormat(Paths.font('vcr.ttf'), 22, 0xFFFFD700, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			v.borderSize = 1.5;
			v.visible = false;
			_rowValue.push(v);
			add(v);

			// Left arrow — drawn after value so it renders on top if widths ever shift
			var lA = new FlxText(OPT_X + OPT_W - 248, rowY + 4, 52, '◄');
			lA.setFormat(Paths.font('vcr.ttf'), 26, 0xFF00D9FF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lA.borderSize = 1.5;
			lA.visible = false;
			_rowLeft.push(lA);
			add(lA);

			// Right arrow
			var rA = new FlxText(OPT_X + OPT_W - 56, rowY + 4, 52, '►');
			rA.setFormat(Paths.font('vcr.ttf'), 26, 0xFF00D9FF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			rA.borderSize = 1.5;
			rA.visible = false;
			_rowRight.push(rA);
			add(rA);
		}

		// Description text with better styling and background
		_descBg = new FlxSprite(OPT_X - 6, OPT_Y0 + MAX_OPT * OPT_H + 4);
		_descBg.makeGraphic(OPT_W + 12, 70, 0x88000000);
		_descBg.antialiasing = ClientPrefs.globalAntialiasing;
		add(_descBg);

		_descText = new FlxText(OPT_X + 8, OPT_Y0 + MAX_OPT * OPT_H + 8, OPT_W - 16, '');
		_descText.setFormat(Paths.font('vcr.ttf'), 17, COLOR_DESC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_descText.borderSize = 1.2;
		_descText.wordWrap = true;
		add(_descText);

		// Scrollbar (only visible when there are more options than fit on screen)
		final scrollBarX = OPT_X + OPT_W + 8;
		final scrollBarH = MAX_OPT * OPT_H;
		_scrollBar = new FlxSprite(scrollBarX, OPT_Y0);
		_scrollBar.makeGraphic(8, Std.int(scrollBarH), 0x33FFFFFF);
		add(_scrollBar);

		_scrollThumb = new FlxSprite(scrollBarX, OPT_Y0);
		_scrollThumb.makeGraphic(8, 40, 0xAAFFFFFF);
		add(_scrollThumb);

		// Help text at bottom (updated dynamically by _updateNavModeUI)
		_helpText = new FlxText(0, FlxG.height - 48, FlxG.width, '');
		_helpText.setFormat(Paths.font('vcr.ttf'), 17, 0xFF909090, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_helpText.borderSize = 1.3;
		add(_helpText);

		// Touch-mode back button — only visible when navInputMode is Touch.
		final backBtnY:Float = OPT_Y0 + MAX_OPT * OPT_H + 80;
		_backBtn = new FlxSprite(OPT_X, backBtnY);
		_backBtn.loadGraphic(Paths.image('menu/freeplay/card'));
		_backBtn.setGraphicSize(160, 42);
		_backBtn.updateHitbox();
		_backBtn.antialiasing = ClientPrefs.globalAntialiasing;
		_backBtn.color = 0xFF334455;
		add(_backBtn);
		_backBtnLabel = new FlxText(OPT_X, backBtnY + 9, 160, '◄  BACK');
		_backBtnLabel.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_backBtnLabel.borderSize = 1.5;
		_backBtnLabel.antialiasing = ClientPrefs.globalAntialiasing;
		add(_backBtnLabel);

		super.create();

		#if mobile
		if (ClientPrefs.navInputMode == 'Virtual Pad')
		{
			addVirtualPad(LEFT_FULL, A_B);
			addVirtualPadCamera();
		}
		#end

		_rebuildOptions();
		_rebuildPreview();
		_updateRows();
		_updateNavModeUI();
	}

	// ── Update ───────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Smooth fade-in entrance
		if (!_enterComplete)
		{
			_enterAlpha = FlxMath.lerp(_enterAlpha, 1.0, elapsed * 4);
			if (_enterAlpha > 0.95)
				_enterComplete = true;

			for (i in 0...members.length)
			{
				var spr = Std.downcast(members[i], FlxSprite);
				if (spr != null)
					spr.alpha = _enterAlpha;
			}
		}

		// Smooth selection animation
		_selVisual = FlxMath.lerp(_selVisual, _sel, elapsed * 8);
		_scrollOffsetVisual = FlxMath.lerp(_scrollOffsetVisual, _scrollOffset, elapsed * 10);

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
			_updateScrollOffset();
			_updateRows();
		}
		if (controls.UI_DOWN_P)
		{
			_sel = (_sel >= _opts.length - 1) ? 0 : _sel + 1;
			FunkinSound.play(Paths.sound('hover'), 0.5);
			_updateScrollOffset();
			_updateRows();
		}

		if (controls.UI_LEFT_P)  _changeSelected(-1);
		if (controls.UI_RIGHT_P) _changeSelected(1);

		if (controls.ACCEPT)
		{
			final opt = _opts[_sel];
			if (opt != null && opt.kind == 'bool') _changeSelected(1);
			else if (opt != null && opt.kind == 'customize' && opt.id == 'vpadCustomize')
				openSubState(new funkin.states.options.VirtualPadCustomizerSubState());
		}
	}

	/** Update scroll offset so selected option stays visible */
	function _updateScrollOffset():Void
	{
		if (_opts.length <= MAX_OPT)
		{
			_scrollOffset = 0;
			return;
		}

		final maxScroll:Float = (_opts.length - MAX_OPT) * OPT_H;

		// Scroll down enough to show the selected item at the bottom
		final minForSel:Float = (_sel - MAX_OPT + 1) * OPT_H;
		// Scroll up enough to show the selected item at the top
		final maxForSel:Float = _sel * OPT_H;

		if (_scrollOffset < minForSel)
			_scrollOffset = minForSel;
		else if (_scrollOffset > maxForSel)
			_scrollOffset = maxForSel;

		// Clamp to valid scroll range
		if (_scrollOffset < 0) _scrollOffset = 0;
		if (_scrollOffset > maxScroll) _scrollOffset = maxScroll;
	}

	#if mobile
	function _handleTouch():Void
	{
		if (!FlxG.mouse.justPressed) return;

		final mx = FlxG.mouse.x;
		final my = FlxG.mouse.y;

		// Touch-mode back button
		if (_backBtn.visible && FlxG.mouse.overlaps(_backBtn))
		{
			FunkinSound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		// Preview zones — always tappable regardless of nav mode.
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

		// Option rows — Virtual Pad navigates via controls.*, not raw touch.
		if (ClientPrefs.navInputMode == 'Virtual Pad') return;

		// Use the full row as a touch target.
		// Left half of the row → ◄ (change left); right half → ► (change right).
		// Bool options toggle on any tap. The ◄ ► sprites are visual only.
		final topIndex = Std.int(_scrollOffsetVisual / OPT_H);
		for (i in 0...MAX_OPT)
		{
			final optIndex = topIndex + i;
			if (optIndex >= _opts.length) break;

			final rowY = OPT_Y0 + i * OPT_H;
			if (!(mx >= OPT_X && mx <= OPT_X + OPT_W && my >= rowY && my < rowY + OPT_H))
				continue;

			if (_sel != optIndex)
			{
				_sel = optIndex;
				FunkinSound.play(Paths.sound('hover'), 0.5);
				_updateScrollOffset();
				_updateRows();
			}

			final opt = _opts[optIndex];
			if (opt.kind == 'bool')
				_changeSelected(1);
			else if (mx < OPT_X + OPT_W * 0.5)
				_changeSelected(-1);
			else
				_changeSelected(1);

			return;
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

			case 'button' | 'customize':
				// Buttons and customize options are triggered on selection, not on direction change
		}

		FunkinSound.play(Paths.sound('scrollMenu'));

		// Layout / input changes alter both the visible options and the preview.
		if (opt.id == 'nav')
		{
			#if mobile
			removeVirtualPad();
			if (ClientPrefs.navInputMode == 'Virtual Pad')
			{
				addVirtualPad(LEFT_FULL, A_B);
				addVirtualPadCamera();
			}
			_updateNavModeUI();
			#end
		}
		else if (opt.id == 'game')
		{
			_rebuildOptions();
			_rebuildPreview();
		}
		else if (opt.id == 'layout')
		{
			_rebuildPreview();
		}
		else if (opt.id == 'vpadLayout')
		{
			_rebuildOptions();
		}
		else if (opt.id == 'vpadCustomize')
		{
			openSubState(new funkin.states.options.VirtualPadCustomizerSubState());
		}
		else if (opt.id == 'openDataFolder')
		{
			mobile.backend.AndroidUtils.openDataFolder();
		}

		_updateRows();
	}

	/** Show/hide touch-mode back button and update help text to match current nav input mode. */
	function _updateNavModeUI():Void
	{
		final touchMode = (ClientPrefs.navInputMode == 'Touch');
		_backBtn.visible      = touchMode;
		_backBtnLabel.visible = touchMode;
		_helpText.text = touchMode
			? Lang.str('mobile_controls_help_touch', 'tap a zone to test it   ·   BACK to exit')
			: Lang.str('mobile_controls_help', '◄ ►  change   ·   tap a zone to test it   ·   B  back');
	}

	// ── ClientPrefs accessors ──────────────────────────────────────────────────

	function _getStr(id:String):String
		return switch (id)
		{
			case 'nav':    ClientPrefs.navInputMode;
			case 'game':   ClientPrefs.gameInputMode;
			case 'layout': ClientPrefs.hitboxLayout;
			case 'vpadLayout': ClientPrefs.virtualPadLayout;
			case 'noteLayout': ClientPrefs.noteLayout;
			case 'aspectRatio': ClientPrefs.aspectRatioMode;
			default: '';
		};

	function _setStr(id:String, v:String):Void
		switch (id)
		{
			case 'nav':    ClientPrefs.navInputMode = v;
			case 'game':   ClientPrefs.gameInputMode = v;
			case 'layout': ClientPrefs.hitboxLayout = v;
			case 'vpadLayout': ClientPrefs.virtualPadLayout = v;
			case 'noteLayout': ClientPrefs.noteLayout = v;
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
			id: 'nav', kind: 'string',
			label: '≡ ' + Lang.str('opt_navinput', 'Navigation Input'),
			desc:  Lang.str('opt_navinput_desc', 'How you interact with menus and UI.\nTouch uses native screen taps. Virtual Pad shows on-screen buttons.'),
			choices: [Lang.str('choice_navinput_touch', 'Touch'), Lang.str('choice_navinput_pad', 'Virtual Pad')],
			stored:  ['Touch', 'Virtual Pad']
		});

		_opts.push({
			id: 'game', kind: 'string',
			label: '◆ ' + Lang.str('opt_gameinput', 'Gameplay Input'),
			desc:  Lang.str('opt_gameinput_desc', 'How you hit notes in-game.\nHitbox: split-screen zones. Virtual Pad: D-pad buttons. VSlice controls: tap the notes directly (requires VSlice Note Layout).'),
			choices: [Lang.str('choice_gameinput_hitbox', 'Hitbox'), Lang.str('choice_gameinput_pad', 'Virtual Pad'), Lang.str('choice_gameinput_vslice', 'VSlice controls')],
			stored:  ['Hitbox', 'Virtual Pad', 'VSlice controls']
		});

		_opts.push({
			id: 'noteLayout', kind: 'string',
			label: '◈ ' + Lang.str('opt_notelayout', 'Note Layout'),
			desc:  Lang.str('opt_notelayout_desc', 'Visual arrangement of notes.\nNormal: standard FNF layout.\nVSlice: centered, wider spacing, bigger arrows.'),
			choices: [Lang.str('choice_notelayout_normal', 'Normal'), Lang.str('choice_notelayout_vslice', 'VSlice')],
			stored:  ['Normal', 'VSlice']
		});

		if (ClientPrefs.gameInputMode == 'Hitbox')
		{
			_opts.push({
				id: 'layout', kind: 'string',
				label: '◇ ' + Lang.str('opt_hitboxlayout', 'Hitbox Layout'),
				desc:  Lang.str('opt_hitboxlayout_desc', 'Arrangement of the tap zones.\nFour Lanes: four columns. Two Thumb: 2×2 grid. DPad: circular buttons. Arrows: note-style arrows.'),
				choices: [Lang.str('choice_hitboxlayout_4l', 'Four Lanes'), Lang.str('choice_hitboxlayout_2t', 'Two Thumb'), Lang.str('choice_hitboxlayout_dpad', 'DPad'), Lang.str('choice_hitboxlayout_arrows', 'Arrows'), Lang.str('choice_hitboxlayout_triangle', 'Triangle')],
				stored:  ['Four Lanes', 'Two Thumb', 'DPad', 'Arrows', 'Triangle']
			});
			_opts.push({
				id: 'hitboxAlpha', kind: 'percent',
				label: '◉ ' + Lang.str('opt_hitboxalpha', 'Hitbox Opacity'),
				desc:  Lang.str('opt_hitboxalpha_desc', 'How visible the hitbox zones appear when pressed.')
			});
		}
		else if (ClientPrefs.gameInputMode == 'Virtual Pad')
		{
			_opts.push({
				id: 'padAlpha', kind: 'percent',
				label: '◉ ' + Lang.str('opt_padopacity', 'Pad Opacity'),
				desc:  Lang.str('opt_padopacity_desc', 'How visible the virtual pad buttons appear.')
			});

			_opts.push({
				id: 'vpadLayout', kind: 'string',
				label: '✦ ' + Lang.str('opt_vpadlayout', 'Pad Layout'),
				desc:  Lang.str('opt_vpadlayout_desc', 'Arrangement of the virtual pad buttons.\nLeftFull: left side diamond. RightFull: right side diamond. Custom: user-defined positions.'),
				choices: [Lang.str('choice_vpad_leftfull', 'Left Side'), Lang.str('choice_vpad_rightfull', 'Right Side'), Lang.str('choice_vpad_custom', 'Custom')],
				stored:  ['LeftFull', 'RightFull', 'Custom']
			});

			if (ClientPrefs.virtualPadLayout == 'Custom')
			{
				_opts.push({
					id: 'vpadCustomize', kind: 'customize',
					label: '⚙ ' + Lang.str('opt_vpadcustomize', 'Customize Pad'),
					desc:  Lang.str('opt_vpadcustomize_desc', 'Open the pad customizer to drag buttons to new positions.')
				});
			}
		}
		// VSlice controls: no pad/hitbox specific options here

		#if mobile
		_opts.push({
			id: 'aspectRatio', kind: 'string',
			label: '▭ ' + Lang.str('opt_aspectratio', 'Screen Fit'),
			desc:  Lang.str('opt_aspectratio_desc', 'How the game fills the screen.\nFit: keeps 16:9 with black bars. Stretch: fills screen (may distort). Expand: shows more of the background on wide screens, no distortion.'),
                        choices: [Lang.str('choice_aspect_fit', 'Fit (16:9)'), Lang.str('choice_aspect_stretch', 'Stretch'), Lang.str('choice_aspect_expand', 'Expand')],
                        stored:  ['fit', 'stretch', 'expand']
		});

		_opts.push({
			id: 'openDataFolder', kind: 'button',
			label: '📁 ' + Lang.str('opt_opendatafolder', 'Open Data Folder'),
			desc:  Lang.str('opt_opendatafolder_desc', 'Opens the game data folder in your file manager.\nUse this to install mods or access save files.')
		});
		#end

		if (_sel >= _opts.length) _sel = _opts.length - 1;
		if (_sel < 0) _sel = 0;
		_scrollOffset = 0;
		_scrollOffsetVisual = 0;
	}

	function _displayValue(opt:MobileOpt):String
	{
		return switch (opt.kind)
		{
			case 'bool':
				_getBool(opt.id) ? '[✓ ON]' : '[  OFF  ]';
			case 'percent':
				var pct = Std.int(Math.round(_getFloat(opt.id) * 100));
				var filled = Std.int(pct / 10);
				var bar = '[';
				for (i in 0...filled) bar += '█';
				for (i in filled...10) bar += '░';
				bar += '] ' + pct + '%';
				bar;
			case 'string':
				if (opt.stored != null && opt.choices != null)
				{
					final idx = opt.stored.indexOf(_getStr(opt.id));
					(idx >= 0 && idx < opt.choices.length) ? opt.choices[idx] : _getStr(opt.id);
				}
				else _getStr(opt.id);
			case 'button':
				'[  ▶  ]';
			default: '';
		};
	}

	function _updateRows():Void
	{
		// Calculate which option index is at the top of the visible area (use visual for smooth scroll)
		final topIndex = Std.int(_scrollOffsetVisual / OPT_H);

		// Position highlight smoothly (accounting for scroll)
		final highlightY = OPT_Y0 + (_selVisual - topIndex) * OPT_H - 2;

		for (i in 0...MAX_OPT)
		{
			// Map visual row index to option array index
			final optIndex = topIndex + i;
			final opt = (optIndex < _opts.length) ? _opts[optIndex] : null;
			final show = (opt != null);
			final selected = show && (optIndex == _sel);

			// Set visibility and position together — reading _rowHi[i].visible
			// here would still reflect *last* frame's mapping (rows are reused
			// slots that get remapped to different option indices as the list
			// scrolls), which made the highlight lag a frame behind or freeze
			// on the wrong row while scrolling.
			_rowHi[i].visible = selected;
			if (selected) _rowHi[i].y = highlightY;
			_rowLabel[i].visible = show;
			_rowValue[i].visible = show;
			_rowLeft[i].visible  = show;
			_rowRight[i].visible = show;

			if (!show) continue;

			_rowLabel[i].text = opt.label;
			_rowLabel[i].color = selected ? COLOR_HIGHLIGHT : COLOR_TEXT;
			_rowValue[i].text = _displayValue(opt);
			_rowValue[i].color = selected ? COLOR_HIGHLIGHT : 0xFFCCCCCC;

			// Selection visual feedback
			if (selected)
			{
				_rowLeft[i].color = 0xFF00FFFF;
				_rowRight[i].color = 0xFF00FFFF;
			}
			else
			{
				_rowLeft[i].color = 0xFF6699CC;
				_rowRight[i].color = 0xFF6699CC;
			}
		}

		final sel = (_sel >= 0 && _sel < _opts.length) ? _opts[_sel] : null;
		_descText.text = (sel != null) ? sel.desc : '';

		// Update scrollbar visibility and thumb position
		final needsScroll = _opts.length > MAX_OPT;
		_scrollBar.visible = needsScroll;
		_scrollThumb.visible = needsScroll;

		if (needsScroll)
		{
			// Position thumb based on scroll offset
			final maxScroll = (_opts.length - MAX_OPT) * OPT_H;
			final thumbRange = MAX_OPT * OPT_H - 40;
			final thumbY = OPT_Y0 + (_scrollOffsetVisual / maxScroll) * thumbRange;
			_scrollThumb.y = thumbY;
		}

		// Show/hide description based on scroll position
		if (_descBg != null && _descText != null)
		{
			final descAreaTop = OPT_Y0 + MAX_OPT * OPT_H;
			final scrollDelta = _scrollOffsetVisual;
			final descVisible = scrollDelta < OPT_H; // Show desc if not scrolled too far
			_descBg.visible = descVisible;
			_descText.visible = descVisible;
		}
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
			if (z.label != null)
			{
				remove(z.label, true);
				z.label.destroy();
			}
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
		else if (ClientPrefs.gameInputMode == 'VSlice controls')
		{
			_buildArrowsPreview();
			_modeText.text = Lang.str('preview_mode_vslice', 'VSlice controls');
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
	 * Adds a circular zone preview element with improved visual feedback.
	 */
	function _addZoneCircle(X:Float, Y:Float, radius:Float, colorIndex:Int):Void
	{
		var color = ZONE_COLORS[colorIndex];
		var diameter = Std.int(radius * 2);

		var cacheKey = 'zone_circle_${colorIndex}_${diameter}';
		var graphic = FlxG.bitmap.get(cacheKey);
		if (graphic == null)
		{
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
						var alpha = Std.int((1.0 - (dist / radius)) * 200);
						bitmap.setPixel32(px, py, (color & 0x00FFFFFF) | (alpha << 24));
					}
				}
			}

			graphic = FlxG.bitmap.add(bitmap, false, cacheKey);
		}

		var spr = new FlxSprite(X - radius, Y - radius);
		spr.loadGraphic(graphic);
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

		// colorIdx → asset name: 0=left, 1=down, 2=up, 3=right
		final btnNames = ['left', 'down', 'up', 'right'];

		inline function place(gx:Float, gy:Float, ci:Int)
			_addPadButtonZone(CANVAS_X + gx * sx, CANVAS_Y + gy * sy, bw, bh, btnNames[ci], ci);

		place(105, FlxG.height - 345, 2); // UP
		place(0,   FlxG.height - 243, 0); // LEFT
		place(207, FlxG.height - 243, 3); // RIGHT
		place(105, FlxG.height - 135, 1); // DOWN
	}

	function _addPadButtonZone(x:Float, y:Float, w:Float, h:Float, graphicName:String, colorIdx:Int):Void
	{
		var graphic = FlxG.bitmap.add('assets/mobile/virtualpad/$graphicName.png');
		var frames  = FlxTileFrames.fromGraphic(graphic, FlxPoint.weak(Std.int(graphic.width / 3), graphic.height));

		var spr = new FlxSprite(x, y);
		spr.frames = frames;
		spr.animation.add('idle',    [0], 1, false);
		spr.animation.add('pressed', [2], 1, false);
		spr.animation.play('idle');
		spr.setGraphicSize(Std.int(w), Std.int(h));
		spr.updateHitbox();
		spr.color = ZONE_COLORS[colorIdx];
		spr.alpha = _idleAlpha();
		add(spr);

		_zones.push({spr: spr, label: null, colorIdx: colorIdx, pressed: false, curA: _idleAlpha()});
	}

	function _addZone(x:Float, y:Float, w:Float, h:Float, colorIdx:Int):Void
	{
		var spr = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.WHITE);
		spr.color = ZONE_COLORS[colorIdx];
		spr.alpha = _idleAlpha();
		add(spr);

		// Zone label with better styling
		var lbl = new FlxText(x + 2, y + h / 2 - 13, w - 4, ZONE_LABELS[colorIdx]);
		lbl.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		lbl.borderSize = 2;
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

		// Idle "demo" animation — zones pulse in sequence when untouched
		if (!_touchingZone)
		{
			_demoTimer += elapsed;
			if (_demoTimer >= 0.5)
			{
				_demoTimer = 0.0;
				_demoIdx = (_demoIdx + 1) % _zones.length;
			}
			for (i in 0..._zones.length)
				_zones[i].pressed = (i == _demoIdx);
		}

		// Smooth alpha transitions with easing
		final pressA = _pressAlpha();
		final idleA  = _idleAlpha();
		for (z in _zones)
		{
			final target = z.pressed ? pressA : idleA;
			z.curA = FlxMath.lerp(z.curA, target, FlxMath.bound(elapsed * 12, 0, 1));
			z.spr.alpha = z.curA;
			// Real pad button sprites (3-frame sheets): switch idle/pressed frame.
			if (z.spr.frames != null && z.spr.frames.numFrames > 1)
				z.spr.animation.play(z.pressed ? 'pressed' : 'idle');
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
