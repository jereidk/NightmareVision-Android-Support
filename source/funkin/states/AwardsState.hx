package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;

import funkin.states.*;
import funkin.utils.*;
import funkin.data.*;

using Lambda;

import flixel.util.FlxGradient;

import funkin.game.shaders.ColorSwap;
import funkin.input.TurboControl;

import flixel.math.FlxRandom;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.util.FlxStringUtil;
import flixel.addons.text.FlxTypeText;
import flixel.util.FlxTimer;
import flixel.util.FlxAxes;
import flixel.addons.display.FlxBackdrop;
import flixel.util.FlxSpriteUtil;

typedef Achievement =
{
	var name:String;
	var hidden:Bool;
	var ?icon:String;
	var ?displayName:String;
	var ?displayHint:String;
	var ?displayDesc:String;
}

class AwardsState extends AmongUIState
{
	var achievements:Array<Achievement> = [];
	var nameText:FlxText;
	var infoText:FlxText;
	var completionText:FlxText;
	var playTimeText:FlxText;
	var achArray:Array<FlxSprite>;
	var curSel:Int = 0;
	var hoveredMouseSel:Int = -1;
	var mouseControlActive:Bool = true;
	var completion = ProgressionUtil.calculateCompletion();
	
	var turboGroup:TurboControlGroup;
	var controlDOWN:TurboControl = TurboControl.fromControl('ui_down');
	var controlUP:TurboControl = TurboControl.fromControl('ui_up');
	var controlLEFT:TurboControl = TurboControl.fromControl('ui_left');
	var controlRIGHT:TurboControl = TurboControl.fromControl('ui_right');
	
	final columnsPerRow:Int = 7;
	
	function loadAchievements()
	{
		achievements = [];
		for (award in GameFlags.getAwards())
		{
			achievements.push(
				{
					name: award.id,
					icon: award.icon,
					displayName: award.title,
					displayHint: award.hint,
					displayDesc: award.desc,
					hidden: award.hidden
				});
		}
		
		if (achievements.length <= 0)
		{
			achievements = [
				{
					name: 'week1',
					hidden: false
				},
				{
					name: 'week2',
					hidden: false
				},
				{
					name: 'week3',
					hidden: false
				}
			];
		}
	}
	
	override function create()
	{
		super.create();
		
		add(turboGroup = new TurboControlGroup());
		turboGroup.add(controlDOWN);
		turboGroup.add(controlUP);
		turboGroup.add(controlLEFT);
		turboGroup.add(controlRIGHT);
		
		FlxG.mouse.visible = true;
		
		backButton.setPosition(15, 15);
		add(backButton).revive();
		
		loadAchievements();
		
		achArray = [];
		var xAdd = 0;
		var yAdd = 0;
		for (i in 0...achievements.length)
		{
			final unlocked = ownAchievement(i);
			var iconName:String = achievements[i].icon ?? GameFlags.getAchievementIcon(achievements[i].name);
			if (!unlocked || !Paths.fileExists('images/awards/$iconName.png')) iconName = 'blank';
			var img:FlxSprite = new FlxSprite(85 + (xAdd * 165), 30 + (yAdd * 130)).loadGraphic(Paths.image('awards/$iconName'));
			img.setGraphicSize(120, 120);
			img.updateHitbox();
			img.ID = i;
			add(img);
			achArray.push(img);
			
			xAdd += 1;
			if (xAdd >= columnsPerRow)
			{
				xAdd = 0;
				yAdd += 1;
			}
		}
		var unlockedAwards:Int = GameFlags.getAwards().count((award) -> GameFlags.hasAchievement(award.id));
		
		#if DISCORD_ALLOWED
		// rich presence to show cool info stuff yay!
		DiscordClient.changePresence('Awards Menu (${unlockedAwards}/${achievements.length})', null); // Updating Discord Rich Presence
		#end
		
		var localizedAwardsFont:String = Lang.getFont('vcr.ttf');
		var isVcrFont:Bool = StringTools.startsWith((localizedAwardsFont ?? 'vcr.ttf').toLowerCase(), 'vcr');
		
		nameText = new FlxText(0, 540, 1280, 'name', 40);
		infoText = new FlxText(0, isVcrFont ? 580 : 600, 1280, 'bio', 25);
		completionText = new FlxText(10, 0, 0, '', 25);
		playTimeText = new FlxText(10, 0, 0, '', 25);
		var howManyText:FlxText = new FlxText(0, 700, 1250, 'ball', 25);
		howManyText.text = Lang.str('awards_counter').replace('@', '${unlockedAwards}/${achievements.length}');
		for (txt in [nameText, infoText, completionText, playTimeText, howManyText])
		{
			txt.setFormat(Paths.font("vcr.ttf"), txt.size, 0xFFFFFF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.borderSize = 2.5;
			txt.antialiasing = ClientPrefs.globalAntialiasing;
			add(txt);
		}
		completionText.alignment = LEFT;
		playTimeText.alignment = LEFT;
		playTimeText.y = (FlxG.height - playTimeText.height) - 9;
		completionText.y = playTimeText.y - completionText.height;
		howManyText.alignment = RIGHT;
		howManyText.y = (FlxG.height - howManyText.height) - 9;
		if (unlockedAwards >= achievements.length) howManyText.color = 0xFFFFE066;
		
		refreshCompletionText();
		refreshPlayTimeText();
		refreshSelection();
	}
	
	function refreshCompletionText():Void
	{
		var completionLabel:String = Lang.str('game_completion', 'Completion');
		var completionValue:String = '${Math.floor(completion.percent)}%';
		completionText.text = Lang.hasSpecial('rightToLeft') ? '$completionValue :$completionLabel' : '$completionLabel: $completionValue';
		completionText.color = completion.percent >= 100 ? 0xFFFFE066 : FlxColor.WHITE;
	}
	
	function refreshPlayTimeText():Void
	{
		var totalSeconds:Int = Math.floor(ClientPrefs.totalPlayTime);
		var hours:Int = Math.floor(totalSeconds / 3600);
		var minutes:Int = Math.floor((totalSeconds % 3600) / 60);
		var seconds:Int = totalSeconds % 60;
		var playTimeLabel:String = Lang.str('game_totalplaytime', 'Total Play Time');
		var playTimeValue:String = '${hours}h ${minutes}m ${seconds}s';
		playTimeText.text = Lang.hasSpecial('rightToLeft') ? '$playTimeValue :$playTimeLabel' : '$playTimeLabel: $playTimeValue';
	}
	
	function refreshSelection()
	{
		completion = ProgressionUtil.calculateCompletion();
		refreshCompletionText();
		refreshIconAlphas();
		
		final selected = achievements[curSel];
		final unlocked = ownAchievement(curSel);
		nameText.color = unlocked ? 0xFFFFE066 : FlxColor.WHITE;
		
		if (selected.hidden && !unlocked)
		{
			nameText.text = '???';
			infoText.text = Lang.str('AWARDS_SECRET');
		}
		else
		{
			nameText.text = Lang.str('AWARDNAME_${selected.name}', selected.displayName ?? selected.name);
			
			final awardDesc = Lang.str('AWARDBIO_${selected.name}', selected.displayDesc ?? '');
			var awardHint = Lang.str('AWARDHINT_${selected.name}', selected.displayHint ?? '');
			if (awardHint == null || awardHint.trim().length == 0) awardHint = selected.displayHint;
			if (awardHint == null || awardHint.trim().length == 0) awardHint = awardDesc;
			
			infoText.text = unlocked ? awardDesc : awardHint;
		}
	}
	
	function ownAchievement(i:Int):Bool
	{
		return GameFlags.hasAchievement(achievements[i].name);
	}
	
	function refreshIconAlphas():Void
	{
		for (icon in achArray)
		{
			icon.alpha = 0.6;
			if (icon.ID == hoveredMouseSel && icon.ID != curSel)
			{
				icon.alpha = 0.8;
			}
			if (icon.ID == curSel)
			{
				icon.alpha = 1;
			}
		}
	}
	
	function changeColumn(by:Int = 0):Void
	{
		final curRow:Int = Std.int(curSel / columnsPerRow);
		final maxColumn:Int = FlxMath.minInt(achievements.length - curRow * columnsPerRow, columnsPerRow);
		
		if (maxColumn <= 1) return;
		
		curSel = (FlxMath.wrap(curSel % columnsPerRow + by, 0, maxColumn - 1) + curRow * columnsPerRow);
		
		if (by != 0) FlxG.sound.play(Paths.sound('scrollMenu'));
		
		refreshSelection();
	}
	
	function changeRow(by:Int = 0):Void
	{
		final curColumn:Int = (curSel % columnsPerRow);
		final curRow:Int = Std.int(curSel / columnsPerRow);
		final maxRow:Int = (Math.floor(achievements.length / columnsPerRow) + (achievements.length % columnsPerRow <= curColumn ? 0 : 1));
		
		if (maxRow <= 1) return;
		
		final newRow = FlxMath.wrap(curRow + by, 0, maxRow - 1);
		
		curSel = (curColumn + newRow * columnsPerRow);
		
		if (by != 0) FlxG.sound.play(Paths.sound('scrollMenu'));
		
		refreshSelection();
	}
	
	function theMouseShit():Void
	{
		var newHovered:Int = -1;
		for (icon in achArray)
		{
			if (!FlxG.mouse.overlaps(icon)) continue;
			newHovered = icon.ID;
			if (FlxG.mouse.justPressed)
			{
				if (curSel != icon.ID)
				{
					curSel = icon.ID;
					refreshSelection();
				}
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			
			break;
		}
		
		if (hoveredMouseSel != newHovered)
		{
			hoveredMouseSel = newHovered;
			refreshIconAlphas();
		}
	}
	
	override function update(elapsed:Float)
	{
		refreshPlayTimeText();
		
		if (FlxG.mouse.justMoved)
		{
			mouseControlActive = true;
		}
		
		if (controlUP.PRESSED || controlDOWN.PRESSED || controlLEFT.PRESSED || controlRIGHT.PRESSED || controls.BACK)
		{
			mouseControlActive = false;
		}
		
		if (mouseControlActive)
		{
			theMouseShit();
		}
		else if (hoveredMouseSel != -1)
		{
			hoveredMouseSel = -1;
			refreshIconAlphas();
		}
		
		if (controlUP.PRESSED) changeRow(-1);
		if (controlDOWN.PRESSED) changeRow(1);
		if (controlLEFT.PRESSED) changeColumn(-1);
		if (controlRIGHT.PRESSED) changeColumn(1);
		
		super.update(elapsed);
	}
}
