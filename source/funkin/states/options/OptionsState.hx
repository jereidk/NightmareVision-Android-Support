package funkin.states.options;

import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;

import funkin.data.*;
import funkin.states.*;
import funkin.objects.*;
import funkin.objects.menu.AmongControls;

class OptionsState extends MusicBeatState
{
	public static var onPlayState:Bool = false;
	
	var options:Array<String> = [
		'controls',
		'adjustdelay',
		'language',
		'gameplay',
		'graphics',
		'visualsui',
		'misc',
		'credits'
	];
	
	var __openedOption:Null<String> = null;
	
	var optionTexts:FlxTypedGroup<FlxText>;
	
	private static var curSelected:Int = 0;
	public static var menuBG:FlxSprite;
	
	// For blocking everything
	var blockAllInput:Bool = false;
	
	var blockInput:Bool = false;
	var pendingSubstate:Null<String> = null;
	var titleText:FlxText;
	var versionText:FlxText;
	var artImage:FlxSprite;
	var optionsHeader:FlxText;
	var menuBackButton:FlxSprite;
	var mouseControlActive:Bool = true;
	var hoveredOption:Int = -1;
	
	static final OPTION_LABEL_BASE_SIZE:Int = 26;
	static final OPTION_LABEL_MIN_SIZE:Int = 14;
	static final OPTION_LABEL_MAX_LINES:Int = 2;
	
	function byeByeHomePanel(visible:Bool):Void
	{
		titleText.visible = visible;
		versionText.visible = visible;
		artImage.visible = visible;
	}
	
	// left panel button layout
	var buttonBaseX:Float = 95;
	var buttonBaseY:Float = 112;
	var buttonSpacing:Float = 65;
	
	var bottomControls:AmongControls;
	
	public function openSelectedSubstate(label:String)
	{
		if (label == 'adjustdelay')
		{
			FlxG.switchState(funkin.states.options.NoteOffsetState.new);
			return;
		}
		
		byeByeHomePanel(false);
		blockInput = true;
		
		scriptGroup.call('onOptionsSubmenu', [label]);
		
		switch (label)
		{
			case 'controls':
				final gamepad = FlxG.gamepads.getFirstActiveGamepad();
				openSubState(new funkin.states.options.ControlsSubState(gamepad != null ? Gamepad(gamepad.id) : Keys));
			case 'graphics':
				openSubState(new funkin.states.options.GraphicsSettingsSubState());
			case 'visualsui':
				openSubState(new funkin.states.options.VisualsUISubState());
			case 'gameplay':
				openSubState(new funkin.states.options.GameplaySettingsSubState());
			case 'language':
				openSubState(new funkin.states.options.LanguageSubState());
			case 'misc':
				openSubState(new funkin.states.options.MiscSubState());
			case 'credits':
				openSubState(new funkin.states.substates.CreditsRollSubState(true, resumeMenuMusic, resumeMenuMusic));
		}
		__openedOption = label;
		pendingSubstate = null;
	}
	
	function resumeMenuMusic():Void
	{
		FunkinSound.playMusic(Paths.music('freakyMenu'));
	}
	
	override function create()
	{
		DiscordClient.changePresence("Options Menu");
		
		initStateScript();
		persistentUpdate = true;
		
		if (isHardcodedState())
		{
			var ext:String = 'menu/options/';
			
			// scrolling stars
			var starsBG = new FlxBackdrop(Paths.image('menu/common/starBG'));
			starsBG.scrollFactor.set();
			starsBG.velocity.x = -4.5;
			starsBG.zIndex = -2;
			add(starsBG);
			
			var starsFG = new FlxBackdrop(Paths.image('menu/common/starFG'));
			starsFG.scrollFactor.set();
			starsFG.velocity.x = -9;
			starsFG.zIndex = -1;
			add(starsFG);
			
			var thingy:FlxSprite = new FlxSprite(50, 30).loadGraphic(Paths.image(ext + 'thingy'));
			thingy.antialiasing = ClientPrefs.globalAntialiasing;
			add(thingy);
			
			var optionsHeaderY:Float = 30 + (ClientPrefs.language == 'arabic' ? -20 : 0);
			optionsHeader = new FlxText(75, optionsHeaderY, 0, Lang.str('options'), 62);
			optionsHeader.setFormat(Paths.font('AmaticSC-Bold.ttf'), 50, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionsHeader.borderSize = 2;
			optionsHeader.antialiasing = ClientPrefs.globalAntialiasing;
			add(optionsHeader);
			
			menuBackButton = new FlxSprite(1100, 30).loadGraphic(Paths.image('menu/common/menuBack'));
			menuBackButton.antialiasing = ClientPrefs.globalAntialiasing;
			add(menuBackButton);
			
			// left panel options
			optionTexts = new FlxTypedGroup<FlxText>();
			add(optionTexts);
			
			for (i in 0...options.length)
			{
				var txt:FlxText = new FlxText(buttonBaseX, buttonBaseY + (buttonSpacing * i), 320, Lang.str('opt_category_' + options[i]));
				txt.setFormat(Paths.font("vcr.ttf"), OPTION_LABEL_BASE_SIZE, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				txt.borderSize = 2;
				txt.antialiasing = ClientPrefs.globalAntialiasing;
				@:privateAccess txt._defaultFormat.leading = -6;
				txt.ID = i;
				fitLeftOptionLabel(txt);
				optionTexts.add(txt);
			}
			
			// right panel stuff
			artImage = new FlxSprite(500, 275 + 100).loadGraphic(Paths.image(ext + 'art'));
			artImage.antialiasing = ClientPrefs.globalAntialiasing;
			artImage.y -= Math.round(artImage.height * .5);
			add(artImage);
			
			titleText = new FlxText(480, artImage.y, 700, 'VS IMPOSTOR: LEGACY');
			titleText.setFormat(Paths.font("vcr"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			titleText.y -= (titleText.height + 16);
			titleText.borderSize = 2;
			titleText.antialiasing = ClientPrefs.globalAntialiasing;
			add(titleText);
			
			versionText = new FlxText(480, artImage.y + artImage.height + 20, 700, Main.LEGACY_VERSION);
			versionText.setFormat(Paths.font("vcr"), 28, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			versionText.borderSize = 1.5;
			versionText.antialiasing = ClientPrefs.globalAntialiasing;
			add(versionText);
			
			bottomControls = new AmongControls([
				['arrow', 'select'], // select
				['enter', 'conf'], // conf
				['esc', 'back'] // back
			], true);
			bottomControls.zIndex = 12;
			add(bottomControls);
			
			changeSelection();
			refreshOptionFonts();
			byeByeHomePanel(true);
		}
		
		super.create();
		
		scriptGroup.call('onCreatePost', []);
	}
	
	override function closeSubState()
	{
		if (subState is funkin.backend.BaseTransitionState)
		{
			super.closeSubState();
			
			return;
		}
		
		__openedOption = null;
		blockInput = false;
		refreshOptionFonts();
		
		if (pendingSubstate == null) byeByeHomePanel(true);
		
		super.closeSubState();
	}
	
	override function destroy():Void
	{
		ClientPrefs.flush();
		ClientPrefs.reloadControls(); // lets just reload the controls here
		super.destroy();
	}
	
	/**
	 * Reloads everything that has to do with language
	**/
	function refreshOptionFonts()
	{
		optionsHeader.text = Lang.str('options');
		optionsHeader.font = Paths.font('AmaticSC-Bold.ttf');
		optionsHeader.y = (38 + Math.round((optionsHeader.size - optionsHeader.height) * .5));
		
		@:privateAccess bottomControls.refreshBar();
		
		for (txt in optionTexts.members)
		{
			txt.text = Lang.str('opt_category_' + options[txt.ID]);
			fitLeftOptionLabel(txt);
		}
		
		scriptGroup.call('onRefreshLang', []);
		refreshOptionVisuals();
	}
	
	function fitLeftOptionLabel(txt:FlxText):Void
	{
		var size:Int = OPTION_LABEL_BASE_SIZE;
		txt.fieldWidth = 300;
		txt.setFormat(Paths.font('vcr.ttf'), size, txt.color, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		txt.borderSize = 2;
		txt.textField.wordWrap = true;
		txt.textField.multiline = true;
		
		while (size > OPTION_LABEL_MIN_SIZE && txt.textField.numLines > OPTION_LABEL_MAX_LINES)
		{
			size--;
			txt.setFormat(Paths.font('vcr.ttf'), size, txt.color, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.borderSize = 2;
			txt.textField.wordWrap = true;
			txt.textField.multiline = true;
		}
		
		if (txt.textField.numLines > OPTION_LABEL_MAX_LINES)
		{
			var baseText:String = txt.text;
			while (baseText.length > 1 && txt.textField.numLines > OPTION_LABEL_MAX_LINES)
			{
				var cut:Int = baseText.lastIndexOf(' ');
				baseText = (cut > 0 ? baseText.substring(0, cut) : baseText.substring(0, baseText.length - 1));
				txt.text = baseText + '...';
			}
		}
		
		var slotY:Float = buttonBaseY + (buttonSpacing * txt.ID);
		txt.y = Math.round(slotY + Math.max(0, (buttonSpacing - txt.height) * 0.5));
	}
	
	function refreshOptionVisuals()
	{
		if (blockAllInput) return;
		for (txt in optionTexts.members)
		{
			txt.alpha = 1;
			txt.color = 0xFFC9C9C9;
			
			if (txt.ID == hoveredOption && txt.ID != curSelected)
			{
				txt.color = FlxColor.WHITE;
			}
			if (txt.ID == curSelected)
			{
				txt.color = 0xFFFFE066;
			}
		}
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		if (isHardcodedState())
		{
			hoveredOption = -1;
			
			if (FlxG.mouse.justMoved || FlxG.mouse.justPressed)
			{
				mouseControlActive = true;
			}
			if (controls.UI_UP_P || controls.UI_DOWN_P || controls.ACCEPT || controls.BACK)
			{
				mouseControlActive = false;
			}
			
			if (subState != null && subState is funkin.states.substates.CreditsRollSubState) mouseControlActive = false;
			
			if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(menuBackButton) && !blockAllInput)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				if (onPlayState)
				{
					FlxG.switchState(PlayState.new);
					FlxG.sound.music.volume = 0;
					onPlayState = false;
				}
				else FlxG.switchState(MainMenuState.new);
				return;
			}
			
			if (mouseControlActive && !blockAllInput)
			{
				// left bar mouse
				var themouseshit2 = FlxG.mouse;
				for (txt in optionTexts.members)
				{
					if (!themouseshit2.overlaps(txt)) continue;
					hoveredOption = txt.ID;
					if (themouseshit2.justPressed)
					{
						if (txt.ID != curSelected)
						{
							curSelected = txt.ID;
							changeSelection(0, true);
						}
						if (blockInput)
						{
							if (options[curSelected] == 'adjustdelay') FlxG.switchState(funkin.states.options.NoteOffsetState.new);
							else if (__openedOption != null && __openedOption != options[curSelected])
							{
								pendingSubstate = options[curSelected];
								refreshOptionFonts();
								openSelectedSubstate(options[curSelected]);
							}
						}
						else openSelectedSubstate(options[curSelected]);
					}
					break;
				}
			}
			
			refreshOptionVisuals();
			
			if (!blockInput && !blockAllInput)
			{
				if (controls.UI_UP_P) changeSelection(-1);
				if (controls.UI_DOWN_P) changeSelection(1);
				
				if (controls.BACK)
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					if (onPlayState)
					{
						FlxG.switchState(PlayState.new);
						FlxG.sound.music.volume = 0;
						onPlayState = false;
					}
					else FlxG.switchState(MainMenuState.new);
				}
				
				if (controls.ACCEPT)
				{
					openSelectedSubstate(options[curSelected]);
				}
			}
		}
	}
	
	function changeSelection(change:Int = 0, ?fromMouse:Bool = false)
	{
		curSelected += change;
		if (curSelected < 0) curSelected = options.length - 1;
		if (curSelected >= options.length) curSelected = 0;
		refreshOptionVisuals();
		
		var snd = fromMouse ? 'scrollMenu' : 'hover';
		FlxG.sound.play(Paths.sound(snd), fromMouse ? 1 : 0.5);
	}
}
