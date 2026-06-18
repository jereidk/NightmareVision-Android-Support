package funkin.states;

import funkin.backend.macro.GitMacro;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxBackdrop;
import flixel.input.keyboard.FlxKey;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;

import funkin.data.*;
import funkin.data.CosmicubeData;
import funkin.data.GameFlags;
import funkin.objects.menu.AmongControls;
import funkin.utils.ProgressionUtil;
import funkin.states.options.*;
import funkin.states.*;
import funkin.states.editors.MasterEditorMenu;

class MainMenuState extends MusicBeatState
{
	public static var fromTitle:Bool = false;
	
	var lockMovement:Bool = false;
	var mouseMode:Bool = false;
	
	static var curMenuItem:Int = 0;
	static var lastSmallBtn:Int = 3;
	var menuButtons:Array<FlxSprite> = [];
	var menuLabels:Array<FlxText> = [];
	var menuLabelBaseSizes:Array<Int> = [];
	var menuLabelYOffsets:Array<Float> = [];
	var menuIcons:Array<FunkinSprite> = [];
	var menuIconOrigX:Array<Float> = [];
	var menuIconTweens:Array<FlxTween> = [];
	
	var redMenu:FlxSprite;
	var greenMenu:FlxSprite;
	var logo:FlxSprite;
	
	var starFG:FlxBackdrop;
	var starBG:FlxBackdrop;
	
	var panelIntroItems:Array<FlxSprite> = [];
	var introActive:Bool = false;
	var introTimer:Float = 0;
	
	var menuShinies:Array<FlxSprite> = [];
	
	static final BIG_LABEL_KEYS = ['storymode', 'freeplay', 'cosmi'];
	static final SMALL_LABEL_KEYS = ['options', 'awards'];
	static final ICON_PREFIXES = ['Red and Green instance 1', 'Cone instance 1', 'Polus instance 1', 'Gear instance 1', 'Trophy instance 1'];
	static final MENU_LABEL_MIN_SIZE:Int = 12;
	
	override function create()
	{
		Mods.currentModDirectory = null;
		
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus");
		#end
		Lang.reloadLangFile();
		
		persistentUpdate = persistentDraw = true;
		
		if (ClientPrefs.finaleState == ACTIVE) FunkinSound.playMusic(Paths.music('finaleMenu'), 0);
		else if (FlxG.sound.music == null) FunkinSound.playMusic(Paths.music('freakyMenu'), 0);
		
		initStateScript();
		
		starFG = new FlxBackdrop(Paths.image('menu/common/starFG'));
		add(starFG);
		
		starBG = new FlxBackdrop(Paths.image('menu/common/starBG'));
		add(starBG);
		
		logo = new FlxSprite(0, -5);
		logo.frames = Paths.getSparrowAtlas('logoBumpin');
		logo.animation.addByPrefix('bump', 'logo bumpin', 24, false);
		logo.antialiasing = true;
		logo.scale.set(0.5, 0.5);
		logo.updateHitbox();
		logo.screenCenter(X);
		logo.x += 20;
		
		add(logo);
		
		buildPanel();
		
		var redTargetX:Float = 630;
		var greenTargetX:Float = -225;
		
		redMenu = new FlxSprite(redTargetX, 70);
		redMenu.frames = Paths.getSparrowAtlas('menu/main/redmenu');
		redMenu.animation.addByPrefix('idle', 'idle', 24, false);
		redMenu.animation.addByPrefix('select', 'confirm', 24, false);
		redMenu.animation.play('idle');
		
		greenMenu = new FlxSprite(greenTargetX, 100);
		greenMenu.frames = Paths.getSparrowAtlas('menu/main/greenmenu');
		greenMenu.animation.addByPrefix('idle', 'idle', 24, false);
		greenMenu.animation.addByPrefix('select', 'confirm', 24, false);
		greenMenu.animation.play('idle');
		
		if (ClientPrefs.finaleState != ACTIVE)
		{
			add(redMenu);
			add(greenMenu);
		}
		
		var glow = new FlxSprite().loadGraphic(Paths.image(ClientPrefs.finaleState == ACTIVE ? 'menu/main/glowEVIL' : 'menu/main/glow'));
		glow.scale.set(1.1, 1.1);
		glow.updateHitbox();
		glow.screenCenter();
		glow.blend = ADD;
		add(glow);
		
		var vignette = new FlxSprite().loadGraphic(Paths.image('menu/main/vignette'));
		vignette.scrollFactor.set();
		vignette.active = false;
		add(vignette);
		
		if (ClientPrefs.finaleState == ACTIVE)
		{
			for (icon in menuIcons)
				icon.visible = false;
				
			refreshMenuLabelLayout();
			menuLabels[0].color = 0xFFFF0000;
			
			menuButtons[0].animation.addByPrefix('idle', 'Big_buttonEVIL instance 1', 24, true);
			menuButtons[0].animation.play('idle');
			menuButtons[0].updateHitbox();
			menuButtons[0].screenCenter(X);
			menuButtons[0].y -= 15;
		}
		
		final rtl:Bool = Lang.hasSpecial('rightToLeft');
		
		var versionShit = new FlxText(rtl ? 12 : 0, FlxG.width - 24, 0, 'VS Impostor Legacy ${Main.LEGACY_VERSION}', 16);
		#if debug
		versionShit.text += ' (${GitMacro.getGitCommitHash()})';
		#end
		versionShit.scrollFactor.set();
		versionShit.setFormat(Paths.font('vcr.ttf', false), 16, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(versionShit);
		
		var bottomControls:AmongControls = new AmongControls([
			['arrow', 'select'],
			['enter', 'conf']
		], false);
		add(bottomControls);
		
		Conductor.bpm = 102;
		Conductor.bpmChangeMap.resize(0);
		
		FlxG.mouse.visible = true;
		
		super.create();
		
		if (fromTitle)
		{
			redMenu.x = FlxG.width + 120;
			greenMenu.x = -greenMenu.width - 120;
			FlxTween.tween(redMenu, {x: redTargetX}, 1.2, {ease: FlxEase.expoOut});
			FlxTween.tween(greenMenu, {x: greenTargetX}, 1.2, {ease: FlxEase.expoOut});
			playPanelIntro();
			fromTitle = false;
		}
		
		updateMenuSelection();
		
		var shinies:Int = ProgressionUtil.getShinies();
		for (i => shiny in menuShinies) shiny.visible = (i < shinies);
		
		scriptGroup.call('onCreatePost', []);
	}
	
	var backpanel:FlxSprite;
	
	function buildPanel()
	{
		final ext:String = 'menu/main/';
		final r:Float = (1280 / 1920);
		
		backpanel = new FlxSprite(0, 350, Paths.image('${ext}tablet'));
		backpanel.scale.set(r, r);
		backpanel.updateHitbox();
		backpanel.screenCenter(X);
		add(backpanel);
		
		panelIntroItems.push(backpanel);
		
		var buttonY:Float = (backpanel.y + 28);
		for (i in 0...BIG_LABEL_KEYS.length)
		{
			var btn = new FlxSprite(0, buttonY);
			btn.frames = Paths.getSparrowAtlas('${ext}new buttons and stuff');
			btn.animation.addByPrefix('idle', 'Big button instance 1', 24, false);
			btn.animation.play('idle');
			btn.animation.pause();
			btn.scale.set(r, r);
			btn.updateHitbox();
			btn.screenCenter(X);
			add(btn);
			menuButtons.push(btn);
			panelIntroItems.push(btn);
			
			buttonY += (btn.height + 8);
			
			var lbl = new FlxText(btn.x + 16, 0, btn.width - 32, Lang.str(BIG_LABEL_KEYS[i]), 24);
			lbl.setFormat(Paths.font('vcr.ttf'), 28, 0xFF0F332F, RIGHT);
			lbl.y = Math.round(btn.y + (btn.height - lbl.height) * 0.5 + 4);
			add(lbl);
			menuLabels.push(lbl);
			menuLabelBaseSizes.push(28);
			menuLabelYOffsets.push(4);
			panelIntroItems.push(lbl);
		}
		
		for (i in 0...SMALL_LABEL_KEYS.length)
		{
			var btn = new FlxSprite(0, buttonY);
			btn.frames = Paths.getSparrowAtlas('${ext}new buttons and stuff');
			btn.animation.addByPrefix('idle', 'Small Button instance 1', 24, false);
			btn.animation.play('idle');
			btn.animation.pause();
			btn.scale.set(r, r);
			btn.updateHitbox();
			btn.x = Math.round(i == 0 ? backpanel.x + 28 : backpanel.x + backpanel.width - btn.width - 28);
			add(btn);
			menuButtons.push(btn);
			panelIntroItems.push(btn);
			
			var lbl = new FlxText(btn.x + 16, 0, btn.width - 32, Lang.str(SMALL_LABEL_KEYS[i]), 22);
			lbl.setFormat(Paths.font('vcr.ttf'), 18, 0xFF0F332F, RIGHT);
			lbl.y = Math.round(btn.y + (btn.height - lbl.height) * 0.5 + 3);
			add(lbl);
			menuLabels.push(lbl);
			menuLabelBaseSizes.push(18);
			menuLabelYOffsets.push(3);
			panelIntroItems.push(lbl);
		}
		
		final shinies:Int = 5;
		for (i in 0...shinies)
		{
			var shiny = new FlxSprite();
			shiny.frames = Paths.getSparrowAtlas('${ext}shiny');
			shiny.animation.addByPrefix('idle', 'Symbol 21 instance 1', 24, true);
			shiny.animation.play('idle');
			shiny.visible = false;
			shiny.scale.set(.75, .75);
			shiny.updateHitbox();
			shiny.setPosition(Math.round(FlxMath.remapToRange(i, 0, shinies - 1, backpanel.x + 28, backpanel.x + backpanel.width - shiny.width - 28)),
				Math.round(backpanel.y + backpanel.height - shiny.height - 28));
			add(shiny);
			menuShinies.push(shiny);
			panelIntroItems.push(shiny);
		}
		
		for (i in 0...menuButtons.length)
		{
			var btn = menuButtons[i];
			var icon = new FunkinSprite().loadAtlas('${ext}new buttons and stuff');
			icon.animation.addByPrefix('idle', ICON_PREFIXES[i], 24, false);
			icon.animation.play('idle');
			icon.scale.set(r, r);
			icon.updateHitbox();
			icon.x = btn.x + 10;
			icon.y = btn.y + (btn.height - icon.height) * 0.5;
			icon.origin.x = (btn.width * .5 - 10);
			icon.offset.x = (icon.origin.x * (1 - r));
			add(icon);
			menuIcons.push(icon);
			menuIconOrigX.push(icon.x);
			menuIconTweens.push(null);
			panelIntroItems.push(icon);
		}
		
		refreshMenuLabelLayout();
	}
	
	function refreshMenuLabelLayout()
	{
		for (i in 0...menuLabels.length)
			fitMenuLabel(i);
	}
	
	function fitMenuLabel(i:Int)
	{
		var btn = menuButtons[i];
		var lbl = menuLabels[i];
		var icon = menuIcons[i];
		
		var leftBound:Float = btn.x + 8;
		if (icon != null && icon.visible) leftBound = Math.max(leftBound, icon.x + icon.width + 8);
		var rightBound:Float = btn.x + btn.width - 8;
		
		lbl.x = Math.round(leftBound + 4);
		lbl.fieldWidth = Math.max(8, Math.round(rightBound - lbl.x - 4));
		
		var size:Int = menuLabelBaseSizes[i];
		lbl.setFormat(Paths.font('vcr.ttf'), size, lbl.color, RIGHT);
		lbl.textField.wordWrap = false;
		lbl.textField.multiline = false;
		
		while (size > MENU_LABEL_MIN_SIZE && lbl.textField != null && lbl.textField.textWidth > lbl.fieldWidth)
		{
			size--;
			lbl.setFormat(Paths.font('vcr.ttf'), size, lbl.color, RIGHT);
			lbl.textField.wordWrap = false;
			lbl.textField.multiline = false;
		}
		
		lbl.y = Math.round(btn.y + (btn.height - lbl.height) * 0.5 + menuLabelYOffsets[i]);
	}
	
	function playPanelIntro()
	{
		introActive = true;
		introTimer = 0.6;
		for (item in panelIntroItems)
		{
			var targetY = item.y;
			item.y += 220;
			FlxTween.tween(item, {y: targetY}, 1.2, {ease: FlxEase.expoOut});
		}
	}
	
	function updateMenuSelection()
	{
		var isFinale = ClientPrefs.finaleState == ACTIVE;
		for (i in 0...menuButtons.length)
		{
			if (isFinale && i == 0)
			{
				menuLabels[0].color = (curMenuItem == 0) ? FlxColor.WHITE : 0xFFFF0000;
			}
			else
			{
				menuButtons[i].animation.curAnim.curFrame = (i == curMenuItem) ? 1 : 0;
			}
			if (menuIconTweens[i] != null)
			{
				menuIconTweens[i].cancel();
				menuIconTweens[i] = null;
			}
			
			if (i < 3)
			{
				if (menuIconTweens[i] != null) menuIconTweens[i].cancel();
				
				menuIconTweens[i] = FlxTween.tween(menuIcons[i].spriteOffset, {x: (i == curMenuItem ? 15 : 0)}, 0.15, {ease: FlxEase.quadOut});
			}
		}
	}
	
	override function beatHit()
	{
		super.beatHit();
		
		if (redMenu?.animation.name != 'select') redMenu.animation.play('idle', true);
		if (greenMenu?.animation.name != 'select') greenMenu.animation.play('idle', true);
	}
	
	function select()
	{
		if (lockMovement) return;
		lockMovement = true;
		
		redMenu.animation.play('select');
		greenMenu.animation.play('select');
		
		for (item in [menuButtons[curMenuItem], menuLabels[curMenuItem], menuIcons[curMenuItem]])
		{
			item.scale.scale(.9);
			FlxTween.tween(item.scale, {x: item.scale.x * 1.05, y: item.scale.y * 1.05}, .2, {ease: FlxEase.circOut});
		}
		
		FlxG.sound.play(Paths.sound('confirmMenu'));
		
		FlxTween.tween(starFG, {y: starFG.y + 2000}, 1.8, {ease: FlxEase.sineIn, startDelay: .6});
		FlxTween.tween(starBG, {y: starBG.y + 1500}, 1.8, {ease: FlxEase.sineIn, startDelay: .6});
		FlxTween.tween(redMenu, {y: redMenu.y + 750}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		FlxTween.tween(greenMenu, {y: greenMenu.y + 750}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		FlxTween.tween(logo, {y: logo.y + 1000}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		for (item in panelIntroItems)
			FlxTween.tween(item, {y: item.y + 1000}, 1.2, {ease: FlxEase.quadInOut, startDelay: .6});
		FlxTimer.wait(1, switchToSelection);
	}
	
	function switchToSelection()
	{
		switch (curMenuItem)
		{
			case 0:
				FlxG.switchState(new StoryMenuState());
			case 1:
				FlxG.switchState(new FreeplayState());
			case 2:
				FlxG.switchState(new CosmicubeSelectState());
			case 3:
				FlxG.switchState(new OptionsState());
			case 4:
				FlxG.switchState(new AwardsState());
		}
	}
	
	override function update(elapsed:Float)
	{
		if (FlxG.sound.music != null)
		{
			if (FlxG.sound.music.volume < 0.8) FlxG.sound.music.volume += 0.5 * elapsed;
			Conductor.songPosition = FlxG.sound.music.time;
		}
		
		starBG.x -= 4.5 * elapsed;
		starFG.x -= 9 * elapsed;
		
		if (FlxG.keys.justPressed.SEVEN) FlxG.switchState(new MasterEditorMenu());
		
		if (FlxG.keys.firstJustPressed() != FlxKey.NONE) mouseMode = false;
		if (FlxG.mouse.justMoved) mouseMode = true;
		
		if (!lockMovement && !introActive && mouseMode)
		{
			for (i in 0...menuButtons.length)
			{
				if (FlxG.mouse.overlaps(menuButtons[i]))
				{
					if (curMenuItem != i)
					{
						curMenuItem = i;
						updateMenuSelection();
					}
					if (FlxG.mouse.justPressed) select();
					break;
				}
			}
		}
		
		if (introActive)
		{
			introTimer -= elapsed;
			if (introTimer <= 0) introActive = false;
		}
		
		if (!lockMovement && !introActive)
		{
			var moved = false;
			if (controls.UI_UP_P)
			{
				final prev = curMenuItem;
				if (curMenuItem >= 3)
				{
					lastSmallBtn = curMenuItem;
					curMenuItem = 2;
				}
				else if (curMenuItem > 0) curMenuItem--;
				
				moved = curMenuItem != prev;
			}
			else if (controls.UI_DOWN_P)
			{
				final prev = curMenuItem;
				
				if (curMenuItem == 2) curMenuItem = lastSmallBtn;
				else if (curMenuItem < 2) curMenuItem++;
				
				moved = curMenuItem != prev;
			}
			else if (controls.UI_LEFT_P && curMenuItem == 4)
			{
				curMenuItem = 3;
				moved = true;
			}
			else if (controls.UI_RIGHT_P && curMenuItem == 3)
			{
				curMenuItem = 4;
				moved = true;
			}
			if (moved)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
				updateMenuSelection();
			}
			if (controls.ACCEPT) select();
		}
		
		super.update(elapsed);
		
		scriptGroup.call('onUpdatePost', [elapsed]);
	}
}
