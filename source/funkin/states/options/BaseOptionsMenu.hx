package funkin.states.options;

import flixel.FlxObject;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxRect;

import funkin.objects.*;
import funkin.objects.menu.ScrollBar;
import funkin.backend.MusicBeatSubstate;

class BaseOptionsMenu extends MusicBeatSubstate
{
	public var curOption:Option = null;
	public var curSelected:Int = 0;
	public var lastHovered:Int = 0;
	public var optionsArray:Array<Option>;
	
	public var grpOptions:FlxTypedGroup<FlxText>;
	public var checkboxGroup:FlxTypedGroup<CheckboxThingie>;
	public var addGroup:FlxTypedGroup<AddBox>;
	public var grpTexts:FlxTypedGroup<FlxText>;
	
	public var boyfriend:Character = null;
	public var descBox:FlxSprite;
	public var descText:FlxText;
	
	public var title:String;
	public var rpcTitle:String;
	public var titleObject:FlxText;
	
	var panelX:Float = 480;
	var optionStartY:Float = 155;
	var optionSpacing:Float = 30;
	
	final maxVisibleOptions:Int = 11;
	var topBound:Float = 150;
	var bottomBound:Float = 650;
	var optionsUnderlay:FlxSprite;
	var optionsScrollBar:ScrollBar;
	var optionsUnderlayBaseY:Float = 0;
	var useOptionOverflow:Bool = false;
	var scrollTargetY:Float = 0;
	var currentScrollY:Float = 0;
	var mouseControlActive:Bool = true;
	var hoveredOption:Int = -1;
	var mouseHeldDirection:Int = 0;
	
	public var autoScroll:Bool = true;
	
	public function new()
	{
		super();
		
		if (title == null) title = 'Options';
		if (rpcTitle == null) rpcTitle = 'Options Menu';
		
		DiscordClient.changePresence(rpcTitle);
		
		initStateScript('Options');
		scriptGroup.set('this', this);
		scriptGroup.set('title', title);
		
		bgColor = 0x00000000;
		
		useOptionOverflow = (optionsArray.length > maxVisibleOptions);
		if (useOptionOverflow)
		{
			topBound = optionStartY - 5;
			bottomBound = optionStartY + (optionSpacing * maxVisibleOptions) + 5;
		}
		else
		{
			topBound = 150;
			bottomBound = 650;
		}
		
		var underlayRows:Int = optionsArray.length;
		optionsUnderlayBaseY = optionStartY - 5;
		optionsUnderlay = new FlxSprite(panelX, optionsUnderlayBaseY).makeGraphic(676, Std.int((optionSpacing * underlayRows)) + 5, FlxColor.BLACK);
		optionsUnderlay.alpha = 0.5;
		add(optionsUnderlay);
		
		optionsScrollBar = new ScrollBar(panelX - 16, topBound, 8, Std.int(bottomBound - topBound), 0xFF2C3F3F, 0xFFFFFFFF);
		optionsScrollBar.minThumbHeight = 48;
		optionsScrollBar.setMetrics(maxVisibleOptions, optionsArray.length);
		optionsScrollBar.onScroll.add(function(scroll:Float, _) currentScrollY = (scroll * getMinScroll()));
		optionsScrollBar.onInteract.add(function() autoScroll = false);
		add(optionsScrollBar);
		
		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);
		
		grpTexts = new FlxTypedGroup<FlxText>();
		add(grpTexts);
		
		checkboxGroup = new FlxTypedGroup<CheckboxThingie>();
		add(checkboxGroup);
		
		addGroup = new FlxTypedGroup<AddBox>();
		add(addGroup);
		
		titleObject = new FlxText(panelX, 112, 700, Lang.str('opt_category_$title'));
		titleObject.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleObject.y += Math.round((titleObject.size - titleObject.height) * .5);
		titleObject.borderSize = 2;
		titleObject.antialiasing = ClientPrefs.globalAntialiasing;
		add(titleObject);
		
		descText = new FlxText(468, 580, 710, 'hello');
		descText.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.offset.y = Math.round((descText.height - descText.size) * .5);
		descText.scrollFactor.set();
		descText.borderSize = 1.5;
		descText.antialiasing = ClientPrefs.globalAntialiasing;
		descText.text = '';
		add(descText);
		
		for (i in 0...optionsArray.length)
		{
			final optionY:Float = (optionStartY + (optionSpacing * i));
			
			var optionText:FlxText = new FlxText(panelX + 5, optionY, -1, optionsArray[i].name);
			optionText.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionText.borderSize = 1;
			optionText.ID = i;
			grpOptions.add(optionText);
			
			if (optionsArray[i].type == 'bool')
			{
				var checkbox:CheckboxThingie = new CheckboxThingie(1118, optionY, optionsArray[i].getValue() == true);
				checkbox.sprTracker = optionText;
				checkbox.ID = i;
				checkboxGroup.add(checkbox);
			}
			else if (optionsArray[i].type != 'button' && optionsArray[i].type != 'label')
			{
				var valueText:FlxText = new FlxText(panelX, optionText.y, 608, '' + optionsArray[i].getValue());
				
				// Old Color from updog: 0xFF62E0CF
				valueText.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				valueText.borderSize = 1;
				valueText.ID = i;
				grpTexts.add(valueText);
				optionsArray[i].setChild(valueText);
				
				var leftBox:AddBox = new AddBox(1118 - 30, optionY, false);
				leftBox.sprTracker = optionText;
				leftBox.ID = i;
				addGroup.add(leftBox);
				
				var rightBox:AddBox = new AddBox(1118, optionY, true);
				rightBox.sprTracker = optionText;
				rightBox.ID = i;
				addGroup.add(rightBox);
			}
			
			if (optionsArray[i].showBoyfriend && boyfriend == null)
			{
				reloadBoyfriend();
			}
			updateTextFrom(optionsArray[i]);
		}
		
		changeSelection();
		reloadCheckboxes();
		refreshOptionVisuals();
		
		scriptGroup.set('grpOptions', grpOptions);
		scriptGroup.set('grpTexts', grpTexts);
		scriptGroup.set('checkboxGroup', checkboxGroup);
		scriptGroup.set('titleText', titleObject);
		scriptGroup.set('descText', descText);
		scriptGroup.call('onCreatePost', []);
	}
	
	public function addOption(option:Option)
	{
		if (optionsArray == null || optionsArray.length < 1) optionsArray = [];
		optionsArray.push(option);
	}
	
	var nextAccept:Int = 5;
	var holdTime:Float = 0;
	var holdValue:Float = 0;
	
	function bindToPanel(spr:FlxSprite)
	{
		if (spr.clipRect == null) spr.clipRect = new FlxRect(0, 0, spr.width, spr.height);
		
		var clipTop:Float = Math.max(0, topBound - spr.y);
		var clipBottom:Float = Math.max(0, (spr.y + spr.height) - bottomBound);
		var clipHeight:Float = spr.height - clipTop - clipBottom;
		if (clipHeight < 0) clipHeight = 0;
		
		spr.clipRect.set(0, clipTop, spr.width, clipHeight);
		spr.clipRect = spr.clipRect;
	}
	
	function getCheckboxById(id:Int):CheckboxThingie
	{
		for (checkbox in checkboxGroup)
		{
			if (checkbox.ID == id) return checkbox;
		}
		return null;
	}
	
	function getAddboxID(id:Int):AddBox
	{
		for (checkbox in addGroup)
		{
			if (checkbox.ID == id) return checkbox;
		}
		return null;
	}
	
	function getHoveredAddbox():AddBox
	{
		for (box in addGroup)
		{
			if (box.y < topBound || box.y + box.height > bottomBound) continue;
			if (FlxG.mouse.overlaps(box)) return box;
		}
		return null;
	}
	
	function refreshOptionVisuals()
	{
		for (item in grpOptions.members)
		{
			item.alpha = 0.6;
			item.color = FlxColor.WHITE;
			if (item.ID == hoveredOption && item.ID != curSelected)
			{
				item.alpha = 1;
			}
			if (item.ID == curSelected)
			{
				item.alpha = 1;
				item.color = 0xFFFFE066;
			}
		}
		for (text in grpTexts)
		{
			text.alpha = (text.ID == curSelected || text.ID == hoveredOption) ? 1 : 0.6;
		}
		for (checkbox in checkboxGroup)
		{
			checkbox.alpha = 1;
		}
		for (box in addGroup)
		{
			box.alpha = 1;
		}
	}
	
	function selectOption(id:Int)
	{
		autoScroll = true;
		
		curSelected = lastHovered = id;
		curOption = optionsArray[curSelected];
		descText.text = curOption.description;
		Lang.arabicTextFix(descText);
		descText.y = 630 - descText.height;
		if (boyfriend != null)
		{
			boyfriend.visible = curOption.showBoyfriend;
		}
		
		var selectedBaseY = optionStartY + (optionSpacing * curSelected);
		if (useOptionOverflow)
		{
			if (curSelected < maxVisibleOptions)
			{
				scrollTargetY = 0;
			}
			else
			{
				scrollTargetY = -optionSpacing * (curSelected - (maxVisibleOptions - 1));
			}
		}
		else
		{
			var visibleCenter = (topBound + bottomBound) / 2;
			scrollTargetY = visibleCenter - selectedBaseY - optionSpacing / 2;
			if (scrollTargetY > 0) scrollTargetY = 0;
		}
		
		scrollTargetY = Math.max(scrollTargetY, getMinScroll());
		
		refreshOptionVisuals();
	}
	
	function toggleCurrentBool()
	{
		FlxG.sound.play(Paths.sound('hover'), 0.5);
		curOption.setValue((curOption.getValue() == true) ? false : true);
		curOption.change();
		reloadCheckboxes();
	}
	
	function getMinScroll():Float
	{
		final listEndY = (optionStartY + (optionSpacing * optionsArray.length));
		
		return Math.min(bottomBound - listEndY, 0);
	}
	
	override function update(elapsed:Float)
	{
		// scroll lerp
		if (autoScroll)
		{
			final scrollPad:Float = 32;
			final optionY:Float = (lastHovered * optionSpacing);
			
			var targetY:Float = currentScrollY;
			
			targetY = Math.min(targetY, -optionY - optionSpacing + (bottomBound - topBound) - scrollPad);
			targetY = Math.max(targetY, -optionY + scrollPad);
			targetY = FlxMath.bound(targetY, getMinScroll(), 0);
			
			currentScrollY = MathUtil.fpsLerp(currentScrollY, targetY, .16);
		}
		
		if (optionsScrollBar != null)
		{
			optionsScrollBar.visible = false;
			
			if (useOptionOverflow && getMinScroll() < 0) {
				optionsScrollBar.visible = true;
				
				if (autoScroll) optionsScrollBar.setProgress(FlxMath.bound(currentScrollY / getMinScroll(), 0, 1));
			}
		}
		
		if (optionsUnderlay != null)
		{
			optionsUnderlay.y = optionsUnderlayBaseY + currentScrollY;
			
			if (useOptionOverflow)
			{
				bindToPanel(optionsUnderlay);
			}
			else if (optionsUnderlay.clipRect != null)
			{
				optionsUnderlay.clipRect.set(0, 0, optionsUnderlay.width, optionsUnderlay.height);
				optionsUnderlay.clipRect = optionsUnderlay.clipRect;
			}
		}
		
		for (item in grpOptions.members)
		{
			var baseY = optionStartY + (optionSpacing * item.ID);
			item.y = baseY + currentScrollY + Math.round((optionSpacing - item.height) * .5);
			bindToPanel(item);
		}
		for (text in grpTexts)
		{
			var baseY = optionStartY + (optionSpacing * text.ID);
			text.y = baseY + currentScrollY + Math.round((optionSpacing - text.height) * .5);
			bindToPanel(text);
		}
		for (cb in checkboxGroup)
		{
			var baseY = optionStartY + (optionSpacing * cb.ID);
			cb.y = baseY + currentScrollY - 2;
			bindToPanel(cb);
		}
		for (box in addGroup)
		{
			var baseY = optionStartY + (optionSpacing * box.ID);
			box.y = baseY + currentScrollY - 2;
			bindToPanel(box);
		}
		hoveredOption = -1;
		var mouseDirectionPressed:Int = 0;
		var mouseDirectionReleased:Int = 0;
		
		if (FlxG.mouse.justPressed)
		{
			var hoveredBox = getHoveredAddbox();
			if (hoveredBox != null)
			{
				mouseHeldDirection = (hoveredBox.animation.curAnim?.name == 'left') ? -1 : 1;
				mouseDirectionPressed = mouseHeldDirection;
				selectOption(hoveredBox.ID);
			}
		}
		if (!FlxG.mouse.pressed && mouseHeldDirection != 0)
		{
			mouseDirectionReleased = mouseHeldDirection;
			mouseHeldDirection = 0;
		}
		if (FlxG.mouse.justMoved || FlxG.mouse.justPressed)
		{
			mouseControlActive = true;
		}
		if (controls.UI_UP_P || controls.UI_DOWN_P || controls.UI_LEFT_P || controls.UI_RIGHT_P || controls.ACCEPT || controls.BACK || controls.RESET)
		{
			mouseControlActive = false;
			mouseHeldDirection = 0;
		}
		
		var uiLeft:Bool = controls.UI_LEFT || mouseHeldDirection < 0;
		var uiRight:Bool = controls.UI_RIGHT || mouseHeldDirection > 0;
		var uiLeftPressed:Bool = controls.UI_LEFT_P || mouseDirectionPressed < 0;
		var uiRightPressed:Bool = controls.UI_RIGHT_P || mouseDirectionPressed > 0;
		var uiLeftReleased:Bool = controls.UI_LEFT_R || mouseDirectionReleased < 0;
		var uiRightReleased:Bool = controls.UI_RIGHT_R || mouseDirectionReleased > 0;
		if (controls.UI_UP_P)
		{
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			changeSelection(1);
		}
		
		if (mouseControlActive)
		{
			for (item in grpOptions.members)
			{
				if (item.y + item.height < topBound || item.y > bottomBound) continue;
				
				if (!isOverOptionBounds(item, getCheckboxById(item.ID)) && !isOverOptionBounds(item, getAddboxID(item.ID))) continue;
				
				autoScroll = true;
				
				lastHovered = hoveredOption = item.ID;
				
				var hoveringCheckbox = (getCheckboxById(item.ID) != null && FlxG.mouse.overlaps(getCheckboxById(item.ID)));
				
				if (FlxG.mouse.justPressed && nextAccept <= 0)
				{
					if (item.ID != curSelected)
					{
						selectOption(item.ID);
						FlxG.sound.play(Paths.sound('hover'), 0.5);
					}
					if (curOption.type == 'bool' && hoveringCheckbox)
					{
						toggleCurrentBool();
					}
					else if (curOption.type == 'button') curOption.callback();
				}
				break;
			}
		}
		else hoveredOption = -1;
		refreshOptionVisuals();
		
		if (controls.BACK)
		{
			close();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
		
		if (nextAccept <= 0)
		{
			if (curOption.type == 'bool')
			{
				if (controls.ACCEPT)
				{
					toggleCurrentBool();
				}
			}
			else if (curOption.type == 'button')
			{
				if (controls.ACCEPT) curOption.callback();
			}
			else if (curOption.type != 'label')
			{
				if (uiLeft || uiRight)
				{
					var pressed = (uiLeftPressed || uiRightPressed);
					if (holdTime > 0.5 || pressed)
					{
						final decrease:Bool = (uiLeft && !uiRightPressed);
						
						if (pressed)
						{
							var add:Dynamic = null;
							if (curOption.type != 'string')
							{
								add = decrease ? -curOption.changeValue : curOption.changeValue;
							}
							
							switch (curOption.type)
							{
								case 'int' | 'float' | 'percent':
									holdValue = curOption.getValue() + add;
									if (holdValue < curOption.minValue) holdValue = curOption.minValue;
									else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;
									
									switch (curOption.type)
									{
										case 'int':
											holdValue = Math.round(holdValue);
											curOption.setValue(holdValue);
											
										case 'float' | 'percent':
											holdValue = FlxMath.roundDecimal(holdValue, curOption.decimals);
											curOption.setValue(holdValue);
									}
									
								case 'string':
									var num:Int = curOption.curOption; // lol
									if (uiLeftPressed) --num;
									else num++;
									
									if (num < 0)
									{
										num = curOption.options.length - 1;
									}
									else if (num >= curOption.options.length)
									{
										num = 0;
									}
									
									curOption.curOption = num;
									// Use storedValues if available, otherwise use display strings
									var valueToStore:String = (curOption.storedValues != null) ? curOption.storedValues[num] : curOption.options[num];
									curOption.setValue(valueToStore);
									reloadCheckboxes();
									// trace(curOption.options[num]);
							}
							updateTextFrom(curOption);
							curOption.change();
							FlxG.sound.play(Paths.sound('hover'), 0.5);
						}
						else if (curOption.type != 'string')
						{
							holdValue += curOption.scrollSpeed * elapsed * (decrease ? -1 : 1);
							if (holdValue < curOption.minValue) holdValue = curOption.minValue;
							else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;
							
							switch (curOption.type)
							{
								case 'int':
									curOption.setValue(Math.round(holdValue));
									
								case 'float' | 'percent':
									curOption.setValue(FlxMath.roundDecimal(holdValue, curOption.decimals));
							}
							updateTextFrom(curOption);
							reloadCheckboxes();
							curOption.change();
						}
					}
					
					if (uiLeftPressed || uiRightPressed) clearHold();
					else if (curOption.type != 'string') holdTime += elapsed;
				}
			}
			
			if (controls.RESET)
			{
				for (i in 0...optionsArray.length)
				{
					var leOption:Option = optionsArray[i];
					if (leOption.type != 'button' && leOption.type != 'label')
					{
						leOption.setValue(leOption.defaultValue);
						if (leOption.type != 'bool')
						{
							if (leOption.type == 'string')
							{
								if (leOption.storedValues != null)
								{
									leOption.curOption = leOption.storedValues.indexOf(leOption.getValue());
								}
								else
								{
									leOption.curOption = leOption.options.indexOf(leOption.getValue());
								}
							}
							updateTextFrom(leOption);
						}
						leOption.change();
					}
				}
				FlxG.sound.play(Paths.sound('cancelMenu'));
				reloadCheckboxes();
			}
		}
		
		if (boyfriend != null && boyfriend.animation.curAnim?.finished)
		{
			boyfriend.dance();
		}
		
		if (nextAccept > 0)
		{
			nextAccept -= 1;
		}
		super.update(elapsed);
	}
	
	function isOverOptionBounds(opt1:FlxObject, opt2:FlxObject)
	{
		if (opt1 == null || opt2 == null) return false;
		
		final minX = Math.min(opt1.x, opt2.x);
		final maxX = Math.max(opt1.x + opt1.width, opt2.x + opt2.width);
		
		final minY = Math.min(opt1.y, opt2.y);
		final maxY = Math.max(opt1.y + opt1.height, opt2.y + opt2.height);
		
		return (FlxG.mouse.x >= minX && FlxG.mouse.x <= maxX && FlxG.mouse.y >= minY && FlxG.mouse.y <= maxY);
	}
	
	function updateTextFrom(option:Option)
	{
		var val:Dynamic = option.getValue();
		if (option.type == 'percent') val *= 100;
		
		var formatted:String;
		if (option.type == 'string')
		{
			formatted = (option.curOption >= 0 && option.curOption < option.options.length) ? option.options[option.curOption] : Std.string(val);
		}
		else
		{
			formatted = option.displayFormat.replace('%v', Std.string(val)).replace('%d', Std.string(option.defaultValue));
		}
		
		var idx = optionsArray.indexOf(option);
		if (idx < 0) return;
		for (t in grpTexts)
		{
			if (t.ID == idx)
			{
				t.text = formatted;
				break;
			}
		}
	}
	
	function clearHold()
	{
		if (holdTime > 0.5)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		holdTime = 0;
	}
	
	function changeSelection(change:Int = 0, silent:Bool = false)
	{
		curSelected += change;
		if (curSelected < 0) curSelected = optionsArray.length - 1;
		if (curSelected >= optionsArray.length) curSelected = 0;
		selectOption(curSelected);
		
		if (change != 0 && !silent) FlxG.sound.play(Paths.sound('scrollMenu'));
	}
	
	public function reloadBoyfriend()
	{
		var wasVisible:Bool = false;
		if (boyfriend != null)
		{
			wasVisible = boyfriend.visible;
			boyfriend.kill();
			remove(boyfriend);
			boyfriend.destroy();
		}
		
		boyfriend = new Character(840, 170, 'bf', true);
		boyfriend.setGraphicSize(Std.int(boyfriend.width * 0.75));
		boyfriend.updateHitbox();
		boyfriend.dance();
		insert(1, boyfriend);
		boyfriend.visible = wasVisible;
	}
	
	function reloadCheckboxes()
	{
		for (checkbox in checkboxGroup)
		{
			checkbox.daValue = (optionsArray[checkbox.ID].getValue() == true);
		}
	}
}
