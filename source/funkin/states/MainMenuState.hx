package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxBackdrop;
import flixel.input.keyboard.FlxKey;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;

import openfl.display.BitmapData;

import funkin.data.*;
import funkin.data.CosmicubeData;
import funkin.data.GameFlags;
import funkin.objects.menu.AmongControls;
import funkin.utils.ProgressionUtil;
import funkin.utils.CoolUtil;
import funkin.states.options.*;
import funkin.states.*;
import funkin.states.editors.MasterEditorMenu;

class MainMenuState extends MusicBeatState
{
	public static var fromTitle:Bool = false;
	
	var lockMovement:Bool = false;
	var mouseMode:Bool = #if mobile ClientPrefs.navInputMode == 'Touch' #else false #end;
	
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

	static final YT_CHANNEL_URL:String = 'https://youtube.com/@jere-idk?si=zqgS9D-dDx8IWmJ_';

	var ytGlow:FlxSprite;
	var ytIcon:FlxSprite;
	var portCreditText:FlxText;
	
	override function create()
	{
		Mods.currentModDirectory = null;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus");
		#end
		Lang.reloadLangFile();

		// Free previous state's assets before loading new ones. Must run before any
		// Paths.image/getSparrowAtlas calls so that shared assets (starFG, starBG, logo)
		// are revived from cache instead of reloaded, preventing double-allocation.
		FunkinAssets.cache.clearStoredMemory();
		FunkinAssets.cache.clearUnusedMemory();

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

		buildPortCredit();

		#if !mobile
		var bottomControls:AmongControls = new AmongControls([
			['arrow', 'select'],
			['enter', 'conf']
		], false);
		add(bottomControls);
		#end

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

		#if mobile
		addVirtualPad(LEFT_FULL, A_B);
		addVirtualPadCamera();
		#end
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
	
	/**
	 * Small YouTube-styled icon + "Android Port By Jere" credit, centered at
	 * the bottom of the menu (replaces the old left-aligned port/version text).
	 * Tapping the icon opens the channel in the browser.
	 */
	function buildPortCredit():Void
	{
		final iconSize:Int = 52;
		final iconY:Float  = FlxG.height - 104;
		final textY:Float  = FlxG.height - 42;

		ytGlow = new FlxSprite(0, 0).loadGraphic(_glowBitmap(iconSize + 28, 0xFFFF0000));
		ytGlow.screenCenter(X);
		ytGlow.y = iconY - 14;
		ytGlow.scrollFactor.set();
		ytGlow.blend = ADD;
		add(ytGlow);

		ytIcon = new FlxSprite(0, iconY).loadGraphic(_youtubeIconBitmap(iconSize));
		ytIcon.screenCenter(X);
		ytIcon.y = iconY;
		ytIcon.scrollFactor.set();
		add(ytIcon);

		portCreditText = new FlxText(0, textY, FlxG.width, 'Android Port By Jere', 20);
		portCreditText.alignment = 'center';
		portCreditText.setFormat(Paths.font('vcr.ttf', false), 20, 0xFF6CFF7A, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		portCreditText.borderSize = 2;
		portCreditText.scrollFactor.set();
		add(portCreditText);

		// Gentle breathing pulse on the icon + its glow so the whole thing feels
		// a little alive instead of a static credit line.
		FlxTween.tween(ytIcon, {"scale.x": 1.08, "scale.y": 1.08}, 1.1,
			{ease: FlxEase.quadInOut, type: PINGPONG});
		FlxTween.tween(ytGlow, {alpha: 0.35}, 1.1, {ease: FlxEase.quadInOut, type: PINGPONG});
	}

	/** Simple YouTube-style badge: a red rounded square with a white play triangle. */
	function _youtubeIconBitmap(size:Int):BitmapData
	{
		var bmp = new BitmapData(size, size, true, 0x00000000);
		final r = Std.int(size * 0.28);
		final red = 0xFFFF0000;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				var inside = true;

				if (px < r && py < r)
				{
					final dx = r - px, dy = r - py;
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px >= size - r && py < r)
				{
					final dx = px - (size - r - 1), dy = r - py;
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px < r && py >= size - r)
				{
					final dx = r - px, dy = py - (size - r - 1);
					if (dx * dx + dy * dy > r * r) inside = false;
				}
				else if (px >= size - r && py >= size - r)
				{
					final dx = px - (size - r - 1), dy = py - (size - r - 1);
					if (dx * dx + dy * dy > r * r) inside = false;
				}

				if (inside) bmp.setPixel32(px, py, red);
			}
		}

		// White play triangle, pointing right, roughly centered.
		final cy:Float    = size * 0.5;
		final triW:Float  = size * 0.34;
		final triH:Float  = size * 0.4;
		final baseX:Float = size * 0.5 - triW * 0.42;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				final t = (px - baseX) / triW;
				if (t < 0 || t > 1) continue;
				final halfH = (triH * 0.5) * (1 - t);
				if (Math.abs(py - cy) <= halfH) bmp.setPixel32(px, py, 0xFFFFFFFF);
			}
		}

		return bmp;
	}

	/** Soft radial glow, used as an ambient halo behind the YouTube icon. */
	function _glowBitmap(size:Int, color:Int):BitmapData
	{
		var bmp = new BitmapData(size, size, true, 0x00000000);
		final radius:Float = size * 0.5;
		final cx:Float = radius, cy:Float = radius;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				final dx = px - cx, dy = py - cy;
				final dist = Math.sqrt(dx * dx + dy * dy);
				if (dist <= radius)
				{
					final alpha = Std.int((1.0 - dist / radius) * 130);
					bmp.setPixel32(px, py, (color & 0x00FFFFFF) | (alpha << 24));
				}
			}
		}

		return bmp;
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

		if (ytIcon != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(ytIcon))
		{
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
			CoolUtil.browserLoad(YT_CHANNEL_URL);
		}

		if (FlxG.keys.justPressed.SEVEN) FlxG.switchState(new MasterEditorMenu());
		
		#if !mobile
		// Desktop: allow switching between keyboard and mouse
		if (FlxG.keys.firstJustPressed() != FlxKey.NONE) mouseMode = false;
		if (FlxG.mouse.justMoved) mouseMode = true;
		#end
		
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
			#if android
			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				FlxG.switchState(TitleState.new);
			}
			#end
		}

		super.update(elapsed);
		
		scriptGroup.call('onUpdatePost', [elapsed]);
	}
}
