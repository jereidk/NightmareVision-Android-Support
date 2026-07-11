package funkin.objects.menu;

import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxSprite;

import funkin.states.options.Option;
import funkin.input.Controls;

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

	/** Fired whenever the selected option's description should be shown/refreshed. */
	public var onSelect:Option->Void;
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

	var _rowHi:Array<FlxSprite> = [];
	var _rowLabel:Array<FlxText> = [];
	var _rowValue:Array<FlxText> = [];
	var _rowLeft:Array<FlxText> = [];
	var _rowRight:Array<FlxText> = [];

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

		for (i in 0...maxVisible)
		{
			final rowY = y0 + i * ROW_H;

			final hi = new FlxSprite(x0 - 6, rowY - 3).makeGraphic(Std.int(w + 12), Std.int(ROW_H - 6), 0xFF3A3A4A);
			hi.alpha = 0;
			add(hi);
			_rowHi.push(hi);

			final lbl = new FlxText(x0 + 20, rowY + 8, w * 0.55, '');
			lbl.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			add(lbl);
			_rowLabel.push(lbl);

			final val = new FlxText(x0 + w * 0.55, rowY + 8, w * 0.45 - 90, '');
			val.setFormat(Paths.font('vcr.ttf'), 20, 0xFFFFD700, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			add(val);
			_rowValue.push(val);

			final lA = new FlxText(x0 + w - 68, rowY + 6, 44, '◄');
			lA.setFormat(Paths.font('vcr.ttf'), 24, 0xFF00D9FF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lA.borderSize = 1.5;
			add(lA);
			_rowLeft.push(lA);

			final rA = new FlxText(x0 + w - 24, rowY + 6, 44, '►');
			rA.setFormat(Paths.font('vcr.ttf'), 24, 0xFF00D9FF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			rA.borderSize = 1.5;
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
		if (onSelect != null && curSelected >= 0 && curSelected < opts.length) onSelect(opts[curSelected]);
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
		if (curSelected == idx) return;

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

			if (curSelected != optIndex) select(optIndex);

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

			_rowHi[i].y = show ? y0 + i * ROW_H - 3 : -9999;
			_rowHi[i].alpha = selected ? 0.9 : (hovered ? 0.4 : 0);
			if (selected) _rowHi[i].y = highlightY;

			_rowLabel[i].visible = show;
			_rowValue[i].visible = show && opt.type != 'label';
			_rowLeft[i].visible = show && isAdjustable(opt);
			_rowRight[i].visible = show && isAdjustable(opt);

			if (!show) continue;

			_rowLabel[i].y = y0 + i * ROW_H + 8;
			_rowValue[i].y = _rowLabel[i].y;
			_rowLeft[i].y = y0 + i * ROW_H + 6;
			_rowRight[i].y = _rowLeft[i].y;

			final isLabel = (opt.type == 'label');
			_rowLabel[i].text = opt.name;
			_rowLabel[i].color = isLabel ? 0xFFAAAAAA : (selected ? 0xFFFFE066 : FlxColor.WHITE);
			_rowLabel[i].size = isLabel ? 20 : 22;

			if (isLabel) continue;

			_rowValue[i].text = displayValue(opt);
			_rowValue[i].color = selected ? 0xFFFFE066 : 0xFFCCCCCC;

			final arrowColor = selected ? 0xFF00FFFF : 0xFF6699CC;
			_rowLeft[i].color = arrowColor;
			_rowRight[i].color = arrowColor;
		}

		_scrollBar.visible = optionsArray.length > maxVisible;
	}

	inline function isAdjustable(opt:Option):Bool
		return opt.type == 'int' || opt.type == 'float' || opt.type == 'percent' || opt.type == 'string';
}
