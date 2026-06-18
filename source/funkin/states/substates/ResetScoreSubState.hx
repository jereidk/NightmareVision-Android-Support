package funkin.states.substates;

import funkin.backend.Difficulty;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;

import funkin.data.*;
import funkin.states.*;
import funkin.objects.*;
import funkin.backend.MusicBeatSubstate;

using StringTools;

class ResetScoreSubState extends MusicBeatSubstate
{
	var bg:FlxSprite;
	var alphabetArray:Array<Alphabet> = [];
	var yesButton:FlxSprite;
	var noButton:FlxSprite;
	var yesIcon:HealthIcon;
	var noIcon:HealthIcon;
	var onYes:Bool = false;
	var yesText:FlxText;
	var noText:FlxText;
	var titleText:FlxText;
	var otherTitleText:FlxText;
	var bgThing:FlxSprite;
	var menuBackButton:FlxSprite;
	var bottomControls:funkin.objects.menu.AmongControls;
	var mouseMode:Bool = false;
	
	var song:String;
	var difficulty:Int;
	var week:Int;
	
	var lockMovement:Bool = false;
	
	final uiTweenOffsetY:Float = 120;
	
	// Week -1 = Freeplay
	public function new(song:String, difficulty:Int, character:String, week:Int = -1) // todo update  the UIIIIIIIII
	{
		camera = CameraUtil.lastCamera;
		
		this.song = song;
		this.difficulty = difficulty;
		this.week = week;
		
		super();
		
		var name:String = song;
		if (week > -1)
		{
			name = WeekData.weeksLoaded.get(WeekData.weeksList[week]).weekName;
		}
		name += (difficulty == 1 ? '' : ' (' + Difficulty.difficulties[difficulty] + ')');
		
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		
		bgThing = new FlxSprite(0, 0, Paths.image('menu/freeplay/resetPrompt'));
		bgThing.screenCenter();
		bgThing.alpha = 1;
		add(bgThing);
		
		otherTitleText = new FlxText(340, 205, 0, Lang.str('reset_score', 'Reset Highscore'), 50);
		otherTitleText.setFormat(Paths.font('AmaticSC-Bold.ttf'), 50, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		otherTitleText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		add(otherTitleText);
		
		var titlePadding:Float = 72;
		titleText = new FlxText(bgThing.x + titlePadding, 320, bgThing.width - (titlePadding * 2), Lang.str('reset_score_question', 'Clear highscore for @')
			.replace('@', name), 32);
		titleText.setFormat(Paths.font('liber.ttf'), 30, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		titleText.wordWrap = true;
		titleText.alpha = 1;
		add(titleText);
		
		menuBackButton = new FlxSprite(bgThing.x + bgThing.width - 5, bgThing.y + 5).loadGraphic(Paths.image('menu/common/menuBack'));
		menuBackButton.x -= menuBackButton.width;
		add(menuBackButton);
		
		yesText = new FlxText(0, titleText.y + 150, 0, Lang.str('choice_generic_yes'), 36);
		yesText.setFormat(Paths.font('liber.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		yesText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		yesButton = new FlxSprite(0, 0, Paths.image('menu/freeplay/resetyesbutton'));
		yesButton.scrollFactor.set();
		add(yesButton);
		add(yesText);
		noText = new FlxText(0, titleText.y + 150, 0, Lang.str('choice_generic_no'), 36);
		noText.setFormat(Paths.font('liber.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		noText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		noButton = new FlxSprite(0, 0, Paths.image('menu/freeplay/resetnobutton'));
		noButton.scrollFactor.set();
		add(noButton);
		add(noText);
		if (week == -1)
		{
			yesIcon = new HealthIcon(character);
			yesIcon.updateHitbox();
			yesIcon.animation.curAnim.curFrame = 1;
			yesIcon.scale.set(0.55, 0.55);
			yesIcon.updateHitbox();
			yesIcon.alpha = 1;
			add(yesIcon);
			
			noIcon = new HealthIcon(character);
			noIcon.updateHitbox();
			noIcon.animation.curAnim.curFrame = 0;
			noIcon.scale.set(0.55, 0.55);
			noIcon.updateHitbox();
			noIcon.alpha = 1;
			add(noIcon);
		}
		
		var buttonY:Float = bgThing.y + bgThing.height - 92;
		var buttonPadding:Float = 56;
		
		yesButton.x = bgThing.x + buttonPadding;
		yesButton.y = buttonY;
		noButton.x = bgThing.x + bgThing.width - noButton.width - buttonPadding;
		noButton.y = buttonY;
		
		yesText.x = yesButton.x + (yesButton.width - yesText.width) * 0.5;
		yesText.y = yesButton.y + (yesButton.height - yesText.height) * 0.5;
		noText.x = noButton.x + (noButton.width - noText.width) * 0.5;
		noText.y = noButton.y + (noButton.height - noText.height) * 0.5;
		
		if (week == -1)
		{
			yesIcon.x = yesText.x - yesIcon.width - 25;
			yesIcon.y = yesText.y + (yesText.size - yesIcon.height) * 0.5 - 30;
			noIcon.x = noText.x - noIcon.width - 25;
			noIcon.y = noText.y + (noText.size - noIcon.height) * 0.5 - 30;
		}
		updateOptions();
		
		for (member in members) // siiigh
		{
			if (member is flixel.FlxObject)
			{
				var member:flixel.FlxObject = cast member;
				member.setPosition(Math.round(member.x), Math.round(member.y));
			}
		}
		
		bottomControls = new funkin.objects.menu.AmongControls([
			['arrow', 'select'], // select
			['enter', 'conf'], // conf
			['esc', 'back'] // back
		], false);
		add(bottomControls);
		
		FlxTween.tween(bg, {alpha: .72}, .35, {ease: FlxEase.circOut});
		
		for (obj in members)
		{
			if (obj == bg || obj == bottomControls || !Std.isOfType(obj, FlxSprite)) continue;
			
			var sprite:FlxSprite = cast obj;
			var alpha:Float = sprite.alpha;
			sprite.alpha = 0;
			sprite.y += uiTweenOffsetY;
			FlxTween.tween(sprite, {y: sprite.y - uiTweenOffsetY, alpha: alpha}, .35, {ease: FlxEase.circOut});
		}
		
		new FlxTimer().start(.35, function(_) lockMovement = false);
	}
	
	override function update(elapsed:Float)
	{
		for (i in 0...alphabetArray.length)
		{
			var spr = alphabetArray[i];
			spr.alpha += elapsed * 2.5;
		}
		
		if (!lockMovement)
		{
			if (FlxG.mouse.justPressed)
			{
				mouseMode = true;
				var mousePos = FlxG.mouse.getWorldPosition();
				
				if (menuBackButton.overlapsPoint(mousePos))
				{
					FlxG.sound.play(Paths.sound('cancelMenu'), 1);
					closeTween();
				}
				else if (yesButton.overlapsPoint(mousePos))
				{
					if (onYes)
					{
						confirmChoice();
					}
					else
					{
						onYes = true;
						FlxG.sound.play(Paths.sound('scrollMenu'), 1);
						updateOptions();
					}
				}
				else if (noButton.overlapsPoint(mousePos))
				{
					if (!onYes)
					{
						confirmChoice();
					}
					else
					{
						onYes = false;
						FlxG.sound.play(Paths.sound('scrollMenu'), 1);
						updateOptions();
					}
				}
			}
			
			if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
			{
				mouseMode = false;
				FlxG.sound.play(Paths.sound('scrollMenu'), 1);
				onYes = !onYes;
				updateOptions();
			}
			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'), 1);
				closeTween();
			}
			else if (controls.ACCEPT)
			{
				if (!mouseMode)
				{
					confirmChoice();
				}
			}
		}
		
		super.update(elapsed);
	}
	
	public function closeTween():Void
	{
		if (lockMovement) return;
		lockMovement = true;
		
		FlxTween.cancelTweensOf(bg);
		FlxTween.tween(bg, {alpha: 0}, .28, {ease: FlxEase.circIn});
		
		for (obj in members)
		{
			if (obj == bg || obj == bottomControls || !Std.isOfType(obj, FlxSprite)) continue;
			
			var sprite:FlxSprite = cast obj;
			FlxTween.cancelTweensOf(sprite);
			FlxTween.tween(sprite, {y: sprite.y + uiTweenOffsetY, alpha: 0}, .28, {ease: FlxEase.circIn});
		}
		
		new FlxTimer().start(.28, function(_) close());
	}
	
	function confirmChoice()
	{
		if (onYes)
		{
			if (week == -1)
			{
				Highscore.resetSong(song, difficulty);
			}
			else
			{
				Highscore.resetWeek(WeekData.weeksList[week], difficulty);
			}
			
			close();
		}
		else
		{
			closeTween();
		}
		
		FlxG.sound.play(Paths.sound('cancelMenu'), .5);
	}
	
	function updateOptions()
	{
		var alphas:Array<Float> = [0.6, 1.25];
		var confirmInt:Int = onYes ? 1 : 0;
		
		yesText.alpha = alphas[confirmInt];
		noText.alpha = alphas[1 - confirmInt];
		if (week == -1)
		{
			yesIcon.visible = onYes;
			noIcon.visible = !onYes;
		}
	}
}
