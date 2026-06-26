package funkin.states.options;

import funkin.backend.MusicBeatSubstate;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxPoint;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.input.touch.FlxTouch;

import mobile.controls.MobileVirtualPad;
import mobile.backend.flixel.FlxButton;
import mobile.backend.flixel.input.FlxMobileInputID;
import mobile.controls.MobileDPadMode;
import mobile.controls.MobileActionMode;
import mobile.utils.MobileNavUtil;
import funkin.data.ClientPrefs;
import funkin.Paths;

/**
 * Substate for customizing Virtual Pad button positions.
 * Shows the 4 direction buttons and allows dragging them to new positions.
 */
class VirtualPadCustomizerSubState extends MusicBeatSubstate
{
	static final DIR_NAMES = ['LEFT', 'DOWN', 'UP', 'RIGHT'];
	static final DIR_COLORS = [0xFF00FF, 0x00FFFF, 0x00FF00, 0xFF0000];

	var bg:FlxSprite;
	var dragButtons:Array<DragButton> = [];
	var saveBtn:FlxSprite;
	var resetBtn:FlxSprite;
	var dragIdx:Int = -1;
	var offsetX:Float = 0;
	var offsetY:Float = 0;

	override function create()
	{
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 0, 200));
		add(bg);

		var title = new FlxText(0, 20, FlxG.width, 'CUSTOMIZE VIRTUAL PAD');
		title.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		add(title);

		var hint = new FlxText(0, FlxG.height - 80, FlxG.width, 'Drag the buttons to reposition them  ·  B to save & exit');
		hint.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.fromRGB(180, 180, 180), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(hint);

		// Create draggable buttons
		for (i in 0...4)
		{
			var pos = ClientPrefs.customPadPositions[i];
			if (pos[0] < 0 || pos[1] < 0)
			{
				pos = _defaultPos(i);
				ClientPrefs.customPadPositions[i] = pos;
			}

			var btn = new DragButton(pos[0], pos[1], DIR_NAMES[i], DIR_COLORS[i]);
			add(btn);
			dragButtons.push(btn);
		}

		// Save & Reset buttons
		saveBtn = _makeButton(FlxG.width / 2 - 180, FlxG.height - 50, 'SAVE & EXIT', 0xFF4488FF);
		resetBtn = _makeButton(FlxG.width / 2 + 20, FlxG.height - 50, 'RESET', 0xFFCC4444);
		add(saveBtn);
		add(resetBtn);

		super.create();

		#if mobile
		addVirtualPad(NONE, A_B);
		addVirtualPadCamera();
		#end
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Handle dragging
		if (FlxG.mouse.justPressed || _anyTouchJustPressed())
		{
			var mx = _getPointerX();
			var my = _getPointerY();
			for (i in 0...dragButtons.length)
			{
				var btn = dragButtons[i];
				if (mx >= btn.x && mx <= btn.x + btn.width &&
					my >= btn.y && my <= btn.y + btn.height)
				{
					dragIdx = i;
					offsetX = mx - btn.x;
					offsetY = my - btn.y;
					break;
				}
			}
		}

		if (dragIdx >= 0 && (FlxG.mouse.pressed || _anyTouchPressed()))
		{
			var mx = _getPointerX();
			var my = _getPointerY();

			dragButtons[dragIdx].x = mx - offsetX;
			dragButtons[dragIdx].y = my - offsetY;
		}

		if (dragIdx >= 0 && (FlxG.mouse.justReleased || _anyTouchJustReleased()))
		{
			// Save new position
			var btn = dragButtons[dragIdx];
			ClientPrefs.customPadPositions[dragIdx] = [btn.x, btn.y];
			dragIdx = -1;
		}

		// Button interactions
		if (FlxG.mouse.justPressed || _anyTouchJustPressed())
		{
			var mx = _getPointerX();
			var my = _getPointerY();

			if (_overlaps(saveBtn, mx, my))
			{
				_saveAndExit();
			}
			else if (_overlaps(resetBtn, mx, my))
			{
				_resetPositions();
			}
		}

		if (controls.BACK)
		{
			_saveAndExit();
		}
	}

	function _getPointerX():Float
	{
		#if mobile
		if (MobileNavUtil.allowPointerNav() && FlxG.touches.list.length > 0)
			return FlxG.touches.list[0].x;
		#end
		return FlxG.mouse.x;
	}
	
	function _getPointerY():Float
	{
		#if mobile
		if (MobileNavUtil.allowPointerNav() && FlxG.touches.list.length > 0)
			return FlxG.touches.list[0].y;
		#end
		return FlxG.mouse.y;
	}
	
	function _anyTouchJustPressed():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justPressed) return true;
		return false;
	}

	function _anyTouchPressed():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.pressed) return true;
		return false;
	}

	function _anyTouchJustReleased():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justReleased) return true;
		return false;
	}

	function _overlaps(spr:FlxSprite, mx:Float, my:Float):Bool
	{
		return mx >= spr.x && mx <= spr.x + spr.width && my >= spr.y && my <= spr.y + spr.height;
	}

	function _defaultPos(i:Int):Array<Float>
	{
		var safe = mobile.backend.ScreenUtil.safeArea();
		var safeLeft = Std.int(safe.left);
		var baseY = FlxG.height - Std.int(safe.bottom);
		return switch (i)
		{
			case 0: [safeLeft + 20, baseY - 220];
			case 1: [safeLeft + 140, baseY - 140];
			case 2: [safeLeft + 140, baseY - 300];
			case 3: [safeLeft + 260, baseY - 220];
			default: [0, 0];
		};
	}

	function _makeButton(x:Float, y:Float, text:String, color:Int):FlxSprite
	{
		var spr = new FlxSprite(x, y).makeGraphic(150, 36, color);
		var txt = new FlxText(x, y + 6, 150, text);
		txt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER);
		add(txt);
		return spr;
	}

	function _saveAndExit():Void
	{
		ClientPrefs.saveSettings();
		close();
	}

	function _resetPositions():Void
	{
		for (i in 0...4)
		{
			var pos = _defaultPos(i);
			ClientPrefs.customPadPositions[i] = pos;
			dragButtons[i].x = pos[0];
			dragButtons[i].y = pos[1];
		}
	}
}

class DragButton extends FlxSpriteGroup
{
	public var label:FlxText;
	public var bg:FlxSprite;

	public function new(x:Float, y:Float, text:String, color:Int)
	{
		super(x, y);

		bg = new FlxSprite().makeGraphic(80, 80, color);
		bg.alpha = 0.7;
		add(bg);

		label = new FlxText(0, 24, 80, text);
		label.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, CENTER);
		add(label);
	}
}
