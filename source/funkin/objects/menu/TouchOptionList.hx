package funkin.objects.menu;

import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxSprite;

import funkin.states.options.Option;
import funkin.input.Controls;
import funkin.data.ClientPrefs;

/**
 * Reusable, touch-first option list: one `Array<Option>` (the same data model
 * `BaseOptionsMenu`/its substates already used) rendered as big, tappable rows
 * instead of small text + tiny far-away checkbox/arrow sprites.
 *
 * Interaction:
 *   D-pad/keyboard: UP/DOWN move selection (skipping 'label' rows), LEFT/RIGHT
 *   adjust the value (hold to repeat, same math BaseOptionsMenu used), ACCEPT
 *   toggles bools / presses buttons.
 *   Touch: tap a row to select it; tap its left/right half to adjust (bools
 *   toggle on any tap); drag anywhere in the list to scroll -- resolved on
 *   release via a drag-distance threshold so a drag never also fires a tap.
 *
 * Owns its own scroll animation and description text; the owning state just
 * positions this group and calls `setOptions()` when the active category
 * changes -- swapping datasets doesn't require rebuilding the row pool.
 */
class TouchOptionList extends FlxTypedGroup<FlxSprite>
{
	public static inline var ROW_H:Float = 56;

	public var optionsArray:Array<Option> = [];
	public var curSelected(default, null):Int = 0;

	/**
	 * Fired when the user actively moves the selection (keyboard nav or a
	 * touch tap) -- NOT when `setOptions()` just repopulated the list with a
	 * fresh dataset. Screens that hand D-pad focus back and forth between
	 * this list and their own UI (e.g. a tab bar above it) use this specific
	 * signal to know a real interaction happened, as opposed to `setOptions()`
	 * merely resetting the selection back to the first row.
	 */
	public var onSelect:Option->Void;
	/** Fired whenever the selected option's description should be shown/refreshed -- both on a real onSelect and after setOptions(). */
	public var onDatasetChanged:Option->Void;
	/** Fired after any option's value changes (selection, toggle, adjust, or reset-all). */
	public var onChange:Void->Void;

	/**
	 * Gate for D-pad/keyboard input only -- touch taps always work regardless
	 * (there's no "focus" concept for a direct tap). Owning screens that also
	 * have their own keyboard-navigable UI (e.g. a tab bar above this list)
	 * toggle this to hand D-pad control back and forth between the two.
	 */
	public var keyboardEnabled:Bool = true;

	public var listX(get, never):Float;
	inline function get_listX():Float return x0;

	public var listWidth(get, never):Float;
	inline function get_listWidth():Float return w;

	var x0:Float;
	var y0:Float;
	var w:Float;
	var maxVisible:Int;

	var _rowHiBorder:Array<FlxSprite> = [];
	var _rowHi:Array<FlxSprite> = [];
	var _rowAccent:Array<FlxSprite> = [];
	var _rowLabel:Array<FlxText> = [];
	var _rowSectionRule:Array<FlxSprite> = [];
	var _rowValue:Array<FlxText> = [];
	// A real checkbox sprite (menu/options/impastacheckbox, the same asset
	// CheckboxThingie/GameplayChangersSubstate already use elsewhere) for
	// 'bool' rows instead of plain "ON"/"OFF" text -- swapped in over
	// _rowValue for that row, same pooled-by-slot approach as everything else.
	var _rowCheckbox:Array<FlxSprite> = [];
	var _rowLeft:Array<FlxText> = [];
	var _rowLeftBg:Array<FlxSprite> = [];
	var _rowRight:Array<FlxText> = [];
	var _rowRightBg:Array<FlxSprite> = [];

	// Reserved strip at the row's right edge for the ◄/► adjust buttons --
	// value text stops short of it, and it in turn stops short of the
	// scrollbar (x0+w+10) instead of the two crowding each other.
	static inline var ARROW_W:Float = 46;
	static inline var ARROW_GAP:Float = 10;
	static inline var ARROW_EDGE_MARGIN:Float = 16;

	var _selVisual:Float = 0;
	var _scrollOffset:Float = 0; // in rows
	var _scrollOffsetVisual:Float = 0;

	var _scrollBar:ScrollBar;

	var mouseControlActive:Bool = true;
	var hoveredRow:Int = -1;

	var holdTime:Float = 0;
	var holdValue:Float = 0;
	var nextAccept:Int = 5;

	static inline var DRAG_THRESHOLD_Y:Float = 12;
	var _touchDragging:Bool = false;
	var _touchIsScroll:Bool = false;
	var _touchStartY:Float = 0;
	var _touchStartScrollOffset:Float = 0;

	var controls(get, never):Controls;
	inline function get_controls():Controls return Controls.instance;

	public function new(x:Float, y:Float, width:Float, maxVisible:Int)
	{
		super();

		x0 = x;
		y0 = y;
		w = width;
		this.maxVisible = maxVisible;

		final rA_x = x0 + w - ARROW_EDGE_MARGIN - ARROW_W;
		final lA_x = rA_x - ARROW_GAP - ARROW_W;
		final valueRight = lA_x - 14;
		final valueLeft = x0 + w * 0.55;

		for (i in 0...maxVisible)
		{
			final rowY = y0 + i * ROW_H;

			// Border sits behind the fill, 2px larger on every side, so only a
			// thin bright ring shows around the selected row instead of a flat
			// single-tone block.
			final hiBorder = new FlxSprite(x0 - 8, rowY - 5).makeGraphic(Std.int(w + 16), Std.int(ROW_H - 2), 0xFFFFD700);
			hiBorder.alpha = 0;
			add(hiBorder);
			_rowHiBorder.push(hiBorder);

			final hi = new FlxSprite(x0 - 6, rowY - 3).makeGraphic(Std.int(w + 12), Std.int(ROW_H - 6), 0xFF3A3A50);
			hi.alpha = 0;
			add(hi);
			_rowHi.push(hi);

			final accent = new FlxSprite(x0 - 6, rowY - 3).makeGraphic(5, Std.int(ROW_H - 6), 0xFFFFD700);
			accent.alpha = 0;
			add(accent);
			_rowAccent.push(accent);

			final rule = new FlxSprite(x0, rowY + ROW_H - 6).makeGraphic(Std.int(w), 2, 0xFF555570);
			rule.visible = false;
			add(rule);
			_rowSectionRule.push(rule);

			final lbl = new FlxText(x0 + 20, rowY + 8, w * 0.55 - 20, '');
			lbl.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			add(lbl);
			_rowLabel.push(lbl);

			final val = new FlxText(valueLeft, rowY + 8, valueRight - valueLeft, '');
			val.setFormat(Paths.font('vcr.ttf'), 20, 0xFFFFD700, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			add(val);
			_rowValue.push(val);

			final chk = new FlxSprite().loadGraphic(Paths.image('menu/options/impastacheckbox'), true, 30, 30);
			chk.animation.add('unchecked', [0], 24, false);
			chk.animation.add('checked', [1], 24, false);
			chk.antialiasing = ClientPrefs.globalAntialiasing;
			chk.setGraphicSize(0, Std.int(ROW_H - 22));
			chk.updateHitbox();
			chk.visible = false;
			add(chk);
			_rowCheckbox.push(chk);

			// White base so runtime `.color` tinting (selected/unselected in
			// refreshRows()) actually produces that exact color, instead of
			// multiplying against a pre-baked non-white makeGraphic() fill.
			final lBg = new FlxSprite(lA_x - 3, rowY + 4).makeGraphic(Std.int(ARROW_W + 6), Std.int(ROW_H - 14), FlxColor.WHITE);
			lBg.color = 0xFF2E2E44;
			add(lBg);
			_rowLeftBg.push(lBg);

			final lA = new FlxText(lA_x, rowY + 6, ARROW_W, '◄');
			lA.setFormat(Paths.font('vcr.ttf'), 26, 0xFF3DE0FF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lA.borderSize = 2;
			add(lA);
			_rowLeft.push(lA);

			final rBg = new FlxSprite(rA_x - 3, rowY + 4).makeGraphic(Std.int(ARROW_W + 6), Std.int(ROW_H - 14), FlxColor.WHITE);
			rBg.color = 0xFF2E2E44;
			add(rBg);
			_rowRightBg.push(rBg);

			final rA = new FlxText(rA_x, rowY + 6, ARROW_W, '►');
			rA.setFormat(Paths.font('vcr.ttf'), 26, 0xFF3DE0FF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			rA.borderSize = 2;
			add(rA);
			_rowRight.push(rA);
		}

		_scrollBar = new ScrollBar(x0 + w + 10, y0, 8, Std.int(maxVisible * ROW_H), 0xFF2C3F3F, 0xFFFFFFFF);
		_scrollBar.minThumbHeight = 40;
		_scrollBar.onScroll.add((scroll, _) -> _scrollOffset = scroll * getMaxScrollRows());
		add(_scrollBar);
	}

	public function setOptions(opts:Array<Option>):Void
	{
		optionsArray = opts;
		curSelected = firstSelectable();
		_selVisual = curSelected;
		_scrollOffset = 0;
		_scrollOffsetVisual = 0;
		_scrollBar.setMetrics(maxVisible, opts.length);
		if (onDatasetChanged != null && curSelected >= 0 && curSelected < opts.length) onDatasetChanged(opts[curSelected]);
	}

	function firstSelectable():Int
	{
		for (i in 0...optionsArray.length)
			if (optionsArray[i].type != 'label') return i;
		return 0;
	}

	function getMaxScrollRows():Float
	{
		return Math.max(0, optionsArray.length - maxVisible);
	}

	function moveSelection(dir:Int):Void
	{
		if (optionsArray.length == 0) return;

		var idx = curSelected;
		var guard = 0;
		do
		{
			idx += dir;
			if (idx < 0) idx = optionsArray.length - 1;
			if (idx >= optionsArray.length) idx = 0;
			guard++;
		}
		while (optionsArray[idx].type == 'label' && guard <= optionsArray.length);

		select(idx);
	}

	function select(idx:Int):Void
	{
		if (idx < 0 || idx >= optionsArray.length || optionsArray[idx].type == 'label') return;
		if (curSelected == idx)
		{
			// Already the selected row -- still a real interaction (e.g. a
			// tap landed on the row that's already selected), so the owning
			// screen still needs to know to hand this list keyboard focus.
			if (onSelect != null) onSelect(optionsArray[curSelected]);
			return;
		}

		curSelected = idx;
		FunkinSound.play(Paths.sound('hover'), 0.5);

		final maxScroll = getMaxScrollRows();
		if (curSelected < _scrollOffset) _scrollOffset = curSelected;
		else if (curSelected > _scrollOffset + maxVisible - 1) _scrollOffset = curSelected - maxVisible + 1;
		_scrollOffset = FlxMath.bound(_scrollOffset, 0, maxScroll);

		if (onSelect != null) onSelect(optionsArray[curSelected]);
	}

	function adjustValue(dir:Int, held:Bool):Void
	{
		if (optionsArray.length == 0) return;
		final opt = optionsArray[curSelected];
		if (opt == null) return;

		switch (opt.type)
		{
			case 'string':
				if (held) return; // discrete only, matches the original menu's behaviour
				var num:Int = opt.curOption;
				num += dir;
				if (num < 0) num = opt.options.length - 1;
				else if (num >= opt.options.length) num = 0;
				opt.curOption = num;
				final valueToStore:String = (opt.storedValues != null) ? opt.storedValues[num] : opt.options[num];
				opt.setValue(valueToStore);

			case 'int' | 'float' | 'percent':
				if (held)
				{
					holdValue += opt.scrollSpeed * FlxG.elapsed * dir;
					holdValue = FlxMath.bound(holdValue, opt.minValue, opt.maxValue);
					opt.setValue(opt.type == 'int' ? Math.round(holdValue) : FlxMath.roundDecimal(holdValue, opt.decimals));
				}
				else
				{
					final add:Dynamic = dir * opt.changeValue;
					holdValue = opt.getValue() + add;
					holdValue = FlxMath.bound(holdValue, opt.minValue, opt.maxValue);
					opt.setValue(opt.type == 'int' ? Math.round(holdValue) : FlxMath.roundDecimal(holdValue, opt.decimals));
				}

			case 'bool':
				if (!held) opt.setValue(!(opt.getValue() == true));

			case 'button':
				if (!held && opt.callback != null) opt.callback();
		}

		if (!held) FunkinSound.play(Paths.sound(opt.type == 'string' || opt.type == 'int' || opt.type == 'float' || opt.type == 'percent' ? 'scrollMenu' : 'hover'), 0.5);
		opt.change();
		if (onChange != null) onChange();
	}

	public function resetAllToDefault():Void
	{
		for (opt in optionsArray)
		{
			if (opt.type == 'button' || opt.type == 'label') continue;
			opt.setValue(opt.defaultValue);
			if (opt.type == 'string')
			{
				opt.curOption = (opt.storedValues != null) ? opt.storedValues.indexOf(opt.getValue()) : opt.options.indexOf(opt.getValue());
			}
			opt.change();
		}
		FunkinSound.play(Paths.sound('cancelMenu'));
		if (onChange != null) onChange();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		_selVisual = MathUtil.fpsLerp(_selVisual, curSelected, .2);
		if (_touchIsScroll)
			_scrollOffsetVisual = _scrollOffset;
		else
			_scrollOffsetVisual = MathUtil.fpsLerp(_scrollOffsetVisual, _scrollOffset, .25);

		if (keyboardEnabled) handleInput(elapsed);
		#if mobile
		handleTouch();
		#end

		refreshRows();

		if (nextAccept > 0) nextAccept--;
	}

	function handleInput(elapsed:Float):Void
	{
		if (controls.UI_UP_P) moveSelection(-1);
		if (controls.UI_DOWN_P) moveSelection(1);

		if (nextAccept > 0) return;

		final opt = (curSelected >= 0 && curSelected < optionsArray.length) ? optionsArray[curSelected] : null;
		if (opt == null) return;

		final uiLeft = controls.UI_LEFT;
		final uiRight = controls.UI_RIGHT;
		final leftPressed = controls.UI_LEFT_P;
		final rightPressed = controls.UI_RIGHT_P;

		if (opt.type == 'bool')
		{
			if (controls.ACCEPT) adjustValue(1, false);
		}
		else if (opt.type == 'button')
		{
			if (controls.ACCEPT) adjustValue(1, false);
		}
		else if (uiLeft || uiRight)
		{
			final dir = uiLeft && !rightPressed ? -1 : 1;
			final justPressed = leftPressed || rightPressed;

			if (justPressed) { adjustValue(dir, false); holdTime = 0; }
			else if (opt.type != 'string' && holdTime > 0.5) adjustValue(dir, true);

			if (justPressed) holdTime = 0; else holdTime += elapsed;
		}
		else
		{
			holdTime = 0;
		}

		if (controls.RESET) resetAllToDefault();
	}

	#if mobile
	function handleTouch():Void
	{
		updateTouchDrag();

		var allowMouseInput:Bool = true;
		#if mobile
		allowMouseInput = mobile.utils.MobileNavUtil.allowPointerNav();
		#end
		if (!allowMouseInput) { mouseControlActive = false; hoveredRow = -1; return; }

		if (FlxG.mouse.justMoved || FlxG.mouse.justPressed) mouseControlActive = true;

		hoveredRow = -1;
		if (mouseControlActive)
		{
			final topIndex = Std.int(_scrollOffset);
			for (i in 0...maxVisible)
			{
				final optIndex = topIndex + i;
				if (optIndex >= optionsArray.length) break;
				if (optionsArray[optIndex].type == 'label') continue;

				final rowY = y0 + i * ROW_H;
				if (FlxG.mouse.y < rowY || FlxG.mouse.y > rowY + ROW_H || FlxG.mouse.x < x0 - 6 || FlxG.mouse.x > x0 + w + 6) continue;

				hoveredRow = optIndex;
				break;
			}
		}

		if (!FlxG.mouse.justPressed) return;

		final withinList = (FlxG.mouse.x >= x0 - 6 && FlxG.mouse.x <= x0 + w + 6 && FlxG.mouse.y >= y0 && FlxG.mouse.y < y0 + maxVisible * ROW_H);
		if (withinList && optionsArray.length > maxVisible)
		{
			_touchDragging = true;
			_touchIsScroll = false;
			_touchStartY = FlxG.mouse.y;
			_touchStartScrollOffset = _scrollOffset;
			return;
		}

		resolveRowTap(FlxG.mouse.x, FlxG.mouse.y);
	}

	function updateTouchDrag():Void
	{
		if (!_touchDragging) return;

		if (FlxG.mouse.pressed)
		{
			final dy = FlxG.mouse.y - _touchStartY;
			if (!_touchIsScroll && Math.abs(dy) > DRAG_THRESHOLD_Y) _touchIsScroll = true;

			if (_touchIsScroll)
			{
				_scrollOffset = FlxMath.bound(_touchStartScrollOffset - dy / ROW_H, 0, getMaxScrollRows());
				_scrollBar.setProgress(getMaxScrollRows() > 0 ? _scrollOffset / getMaxScrollRows() : 0);
			}
			return;
		}

		_touchDragging = false;
		if (!_touchIsScroll) resolveRowTap(FlxG.mouse.x, FlxG.mouse.y);
	}

	function resolveRowTap(mx:Float, my:Float):Void
	{
		final topIndex = Std.int(_scrollOffset);
		for (i in 0...maxVisible)
		{
			final optIndex = topIndex + i;
			if (optIndex >= optionsArray.length) break;

			final opt = optionsArray[optIndex];
			if (opt.type == 'label') continue;

			final rowY = y0 + i * ROW_H;
			if (mx < x0 - 6 || mx > x0 + w + 6 || my < rowY || my >= rowY + ROW_H) continue;

			if (nextAccept > 0) return;

			select(optIndex);

			switch (opt.type)
			{
				case 'bool' | 'button':
					adjustValue(1, false);
				default:
					adjustValue(mx < x0 + w * 0.5 ? -1 : 1, false);
			}
			return;
		}
	}
	#end

	function displayValue(opt:Option):String
	{
		return switch (opt.type)
		{
			case 'bool': (opt.getValue() == true) ? 'ON' : 'OFF';
			case 'button': '▶';
			case 'label': '';
			case 'string':
				if (opt.storedValues != null)
				{
					final idx = opt.storedValues.indexOf(opt.getValue());
					(idx >= 0 && idx < opt.options.length) ? opt.options[idx] : Std.string(opt.getValue());
				}
				else Std.string(opt.getValue());
			default:
				var v:Dynamic = opt.getValue();
				if (opt.type == 'percent') v = Math.round((v : Float) * 100);
				opt.displayFormat.replace('%v', Std.string(v)).replace('%d', Std.string(opt.defaultValue));
		};
	}

	function refreshRows():Void
	{
		final topIndex = Std.int(_scrollOffset);
		final highlightY = y0 + (_selVisual - _scrollOffsetVisual) * ROW_H - 3;

		for (i in 0...maxVisible)
		{
			final optIndex = topIndex + i;
			final opt = (optIndex >= 0 && optIndex < optionsArray.length) ? optionsArray[optIndex] : null;
			final show = (opt != null);
			final selected = show && (optIndex == curSelected);
			final hovered = show && (optIndex == hoveredRow);

			final rowTopY = show ? y0 + i * ROW_H - 3 : -9999;
			_rowHi[i].y = rowTopY;
			_rowHi[i].alpha = selected ? 0.92 : (hovered ? 0.4 : 0);
			_rowHiBorder[i].y = rowTopY - 2;
			_rowHiBorder[i].alpha = selected ? 0.8 : 0;
			_rowAccent[i].y = rowTopY;
			_rowAccent[i].alpha = selected ? 1 : 0;
			if (selected)
			{
				_rowHi[i].y = highlightY;
				_rowHiBorder[i].y = highlightY - 2;
				_rowAccent[i].y = highlightY;
			}

			_rowLabel[i].visible = show;
			final isBool = show && opt.type == 'bool';
			_rowValue[i].visible = show && opt.type != 'label' && !isBool;
			_rowCheckbox[i].visible = isBool;
			final showArrows = show && isAdjustable(opt);
			_rowLeft[i].visible = showArrows;
			_rowRight[i].visible = showArrows;
			_rowLeftBg[i].visible = showArrows;
			_rowRightBg[i].visible = showArrows;
			_rowSectionRule[i].visible = show && opt.type == 'label' && opt.name != '';

			if (!show) continue;

			_rowLabel[i].y = y0 + i * ROW_H + 8;
			_rowValue[i].y = _rowLabel[i].y;
			_rowLeft[i].y = y0 + i * ROW_H + 6;
			_rowRight[i].y = _rowLeft[i].y;
			_rowLeftBg[i].y = y0 + i * ROW_H + 4;
			_rowRightBg[i].y = _rowLeftBg[i].y;
			_rowSectionRule[i].y = y0 + i * ROW_H + ROW_H - 8;

			final isLabel = (opt.type == 'label');
			_rowLabel[i].text = opt.name;
			_rowLabel[i].color = isLabel ? 0xFF7FD9E8 : (selected ? 0xFFFFE066 : FlxColor.WHITE);
			_rowLabel[i].size = isLabel ? 19 : 22;
			_rowLabel[i].bold = isLabel;

			if (isLabel) continue;

			_rowValue[i].text = displayValue(opt);
			_rowValue[i].color = selected ? 0xFFFFE066 : 0xFFCCCCCC;

			if (isBool)
			{
				final chk = _rowCheckbox[i];
				chk.x = _rowValue[i].x + _rowValue[i].fieldWidth - chk.width;
				chk.y = y0 + i * ROW_H + (ROW_H - chk.height) * 0.5;
				chk.alpha = selected ? 1 : 0.85;
				final wantAnim = (opt.getValue() == true) ? 'checked' : 'unchecked';
				if (chk.animation.name != wantAnim) chk.animation.play(wantAnim, true);
			}

			final arrowColor = selected ? 0xFF3DE0FF : 0xFF9FCBE8;
			_rowLeft[i].color = arrowColor;
			_rowRight[i].color = arrowColor;
			final bgColor = selected ? 0xFF3A4A5A : 0xFF2E2E44;
			_rowLeftBg[i].color = bgColor;
			_rowRightBg[i].color = bgColor;
		}

		_scrollBar.visible = optionsArray.length > maxVisible;
	}

	inline function isAdjustable(opt:Option):Bool
		return opt.type == 'int' || opt.type == 'float' || opt.type == 'percent' || opt.type == 'string';
}
