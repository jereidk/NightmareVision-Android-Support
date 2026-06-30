package extensions.flixel;

import flixel.addons.ui.FlxUIAssets;
import flixel.addons.ui.FlxUIButton;
import flixel.addons.ui.FlxUIDropDownMenu;
import flixel.addons.ui.FlxUI9SliceSprite;
import flixel.addons.ui.StrNameLabel;
import flixel.ui.FlxButton;

/*
	The differences are the following:
	* Support to scrolling up/down with mouse wheel or arrow keys
	* THe default drop direction is "Down" instead of "Automatic"

 */
class FlxUIDropDownMenuEx extends FlxUIDropDownMenu
{
	var template:FlxUIButton;
	var listInitialized:Bool = false;
	var currentScroll:Int = 0; // Handles the scrolling

	public var canScroll:Bool = true;
	
	public function new(X:Float = 0, Y:Float = 0, DataList:Array<StrNameLabel>, ?Callback:String->Void, ?Header:FlxUIDropDownHeader, ?DropPanel:FlxUI9SliceSprite, ?ButtonList:Array<FlxUIButton>,
			?UIControlCallback:Bool->FlxUIDropDownMenu->Void)
	{
		super(X, Y, DataList, Callback, Header, DropPanel, ButtonList, UIControlCallback);
		dropDirection = Down;
	}
	
	override function updateButtonPositions():Void
	{
		var buttonHeight = header.background.height;
		dropPanel.y = header.background.y;
		if (dropsUp()) dropPanel.y -= getPanelHeight();
		else dropPanel.y += buttonHeight;
		
		var offset = dropPanel.y;
		for (i in 0...currentScroll)
		{ // Hides buttons that goes before the current scroll
			var button:FlxUIButton = list[i];
			if (button != null)
			{
				button.y = -99999;
			}
		}
		for (i in currentScroll...list.length)
		{
			var button:FlxUIButton = list[i];
			if (button != null)
			{
				button.y = offset;
				offset += buttonHeight;
			}
		}
	}
	
	override function makeListButton(i:Int, Label:String, Name:String):FlxUIButton
	{
		var t:FlxUIButton = new FlxUIButton(0, 0, Label, false, true);
		t.broadcastToFlxUI = false;
		t.name = Name;
		t.x = 1;
		return t;
	}

	function makeTemplateListButton():FlxUIButton
	{
		var t:FlxUIButton = new FlxUIButton(0, 0, '', false, true);

		@:privateAccess t._no_graphic = false;
		t.loadGraphicSlice9([FlxUIAssets.IMG_INVIS, FlxUIAssets.IMG_HILIGHT, FlxUIAssets.IMG_HILIGHT], Std.int(header.background.width),
			Std.int(header.background.height), [[1, 1, 3, 3], [1, 1, 3, 3], [1, 1, 3, 3]], FlxUI9SliceSprite.TILE_NONE);
		t.labelOffsets[PRESSED].y -= 1; // turn off the 1-pixel depress on click
		t.up_color = FlxColor.BLACK;
		t.over_color = FlxColor.WHITE;
		t.down_color = FlxColor.WHITE;

		t.resize(header.background.width - 2, header.background.height - 1);
		t.label.alignment = 'left';
		t.autoCenterLabel();
		for (offset in t.labelOffsets) offset.x += 2;

		return t;
	}

	inline function initList():Void
	{
		listInitialized = true;

		for (i => button in list)
		{
			button.onUp.callback = onClickItem.bind(i);
			template ??= makeTemplateListButton();

			@:privateAccess
			{
				button.tile = template.tile;
				button.resize_ratio = template.resize_ratio;
				button._src_w = template._src_w;
				button._src_h = template._src_h;
				button._no_graphic = template._no_graphic;
				button._slice9_arrays = template._slice9_arrays;
				button._slice9_assets = template._slice9_assets;
				button._frame_indeces = flixel.addons.ui.U.copy_shallow_arr_i(template._frame_indeces);
				button._centerLabelOffset = template._centerLabelOffset?.clone();
			}

			button.resize(template.width, template.height);
			button.copyStyle(cast template);
			button.label.color = button.up_color;
		}
	}

	public override function setData(datalyst:Array<StrNameLabel>):Void
	{
		super.setData(datalyst);
		listInitialized = false;
	}

	override function checkClickOff()
	{
		if (dropPanel.visible)
		{
			if (list.length > 1 && canScroll)
			{
				if (FlxG.mouse.wheel > 0 || FlxG.keys.justPressed.UP)
				{
					// Go up
					--currentScroll;
					if (currentScroll < 0) currentScroll = 0;
					updateButtonPositions();
				}
				else if (FlxG.mouse.wheel < 0 || FlxG.keys.justPressed.DOWN)
				{
					// Go down
					currentScroll++;
					if (currentScroll >= list.length) currentScroll = list.length - 1;
					updateButtonPositions();
				}
			}
			
			if (FlxG.mouse.justPressed && !FlxG.mouse.overlaps(this, getDefaultCamera()))
			{
				showList(false);
			}
		}
	}
	
	override function showList(b:Bool)
	{
		if (b && !listInitialized)
		{
			initList();
		}

		for (button in list)
		{
			button.visible = b;
			button.active = b;
		}

		dropPanel.visible = b;

		flixel.addons.ui.FlxUI.forceFocus(b, this); // avoid overlaps

		if (currentScroll != 0)
		{
			currentScroll = 0;
			updateButtonPositions();
		}
	}
}
