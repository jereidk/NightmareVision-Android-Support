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

	var ytRing:FlxSprite;
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

		// Designed for the 1280-wide base canvas, hanging off the right edge.
		// 'expand' mode's extra width (see FunkinRatioScaleMode.gameCutoutSize)
		// only ever opens up to the right of that design (origin stays at 0,0),
		// so without this offset red stays pinned at its base-resolution X while
		// the screen grows around it, sliding it from "off the right edge" to
		// "in the middle". greenMenu sits off-screen to the LEFT, where expand
		// never reveals extra space, so it needs no such adjustment.
		var redTargetX:Float = 630 + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;
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
		// Source image is exactly 1280x720 — on a device wide enough that
		// 'expand' screen fit grows FlxG.width past that, stretch to cover the
		// extra width instead of leaving an uncovered gap on either side.
		if (FlxG.width > glow.width)
		{
			glow.scale.x *= FlxG.width / glow.width;
			glow.updateHitbox();
		}
		glow.screenCenter();
		glow.blend = ADD;
		add(glow);

		var vignette = new FlxSprite().loadGraphic(Paths.image('menu/main/vignette'));
		vignette.scrollFactor.set();
		vignette.active = false;
		// Was never centered even at the base resolution (sat at (0,0) covering
		// only the left 1280px) — stretch and center so wide 'expand' screens
		// don't end up with the vignette darkening only one side of the screen.
		if (FlxG.width > vignette.width)
		{
			vignette.setGraphicSize(FlxG.width, Std.int(vignette.height));
			vignette.updateHitbox();
		}
		vignette.screenCenter();
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
		final iconSize:Int = 44;
		final iconX:Float  = 18;
		final iconY:Float  = 16;
		final ringColor:Int = 0xFF6CFF7A;

		// Ring sits a touch larger than the avatar and behind it, like a
		// colored profile-picture border.
		ytRing = new FlxSprite(iconX - 3, iconY - 3).loadGraphic(_ringBitmap(iconSize + 6, ringColor, 3));
		ytRing.scrollFactor.set();
		add(ytRing);

		ytIcon = new FlxSprite(iconX, iconY).loadGraphic(_circleMask(Paths.image('menu/main/ytChannelIcon').bitmap, iconSize));
		ytIcon.scrollFactor.set();
		add(ytIcon);

		portCreditText = new FlxText(iconX + iconSize + 12, iconY + (iconSize - 22) * 0.5, 300, 'Android Port By Jere', 18);
		portCreditText.alignment = 'left';
		portCreditText.setFormat(Paths.font('vcr.ttf', false), 18, ringColor, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		portCreditText.borderSize = 1.5;
		portCreditText.scrollFactor.set();
		add(portCreditText);

		// Gentle breathing pulse so the corner credit feels a little alive.
		FlxTween.tween(ytIcon, {"scale.x": 1.08, "scale.y": 1.08}, 1.1,
			{ease: FlxEase.quadInOut, type: PINGPONG});
		FlxTween.tween(ytRing, {"scale.x": 1.08, "scale.y": 1.08}, 1.1,
			{ease: FlxEase.quadInOut, type: PINGPONG});
	}

	/**
	 * Scales `source` to fit an size×size square and clips it to a circle
	 * (per-pixel alpha cutoff outside the radius) — same procedural masking
	 * approach used elsewhere this session, applied to a real image instead
	 * of a solid fill.
	 */
	function _circleMask(source:BitmapData, size:Int):BitmapData
	{
		var scaled = new BitmapData(size, size, true, 0x00000000);
		var matrix = new openfl.geom.Matrix();
		matrix.scale(size / source.width, size / source.height);
		scaled.draw(source, matrix, null, null, null, true);

		final radius:Float = size * 0.5;
		final cx:Float = radius, cy:Float = radius;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				final dx = px - cx, dy = py - cy;
				if (dx * dx + dy * dy > radius * radius) scaled.setPixel32(px, py, 0x00000000);
			}
		}

		return scaled;
	}

	/** Thin colored ring (annulus), used as a border behind the circular avatar. */
	function _ringBitmap(size:Int, color:Int, thickness:Float):BitmapData
	{
		var bmp = new BitmapData(size, size, true, 0x00000000);
		final outerR:Float = size * 0.5;
		final innerR:Float = outerR - thickness;
		final cx:Float = outerR, cy:Float = outerR;

		for (px in 0...size)
		{
			for (py in 0...size)
			{
				final dx = px - cx, dy = py - cy;
				final dist = Math.sqrt(dx * dx + dy * dy);
				if (dist <= outerR && dist >= innerR) bmp.setPixel32(px, py, color);
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
