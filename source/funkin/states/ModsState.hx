package funkin.states;

import flixel.text.FlxText;

class ModsState extends MusicBeatState
{
	var modList = [];
	var curDir:Int = 0;
	var reset:Bool = false;
	
	var icon:FlxSprite;
	var name:FlxText;
	
	override function create()
	{
		modList = Mods.getModDirectories();
		
		name = new FlxText();
		name.setFormat(Paths.DEFAULT_FONT, 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		name.text = 'Test Mod';
		add(name);
		
		icon = new FlxSprite().loadGraphic(Paths.image('icon64'));
		add(icon);
		
		trace(Mods.getModDirectories());
		
		changeDir(0);
		
		super.create();
	}
	
	override function update(elapsed:Float)
	{
		if (controls.UI_UP_P) changeDir(-1);
		if (controls.UI_DOWN_P) changeDir(1);
		if (controls.ACCEPT) makeTopMod();
		if (controls.BACK)
		{
			if (reset)
			{
				TitleState.initialized = false;
				TitleState.closedState = false;
				FlxG.switchState(TitleState.new);
			}
			else FlxG.switchState(funkin.states.MainMenuState.new);
		}
	}
	
	function changeDir(change:Int = 0)
	{
		curDir += change;
		if (curDir > modList.length - 1) curDir = 0;
		if (curDir < 0) curDir = modList.length - 1;
		
		Mods.currentModDirectory = modList[curDir];
		
		name.text = Mods.getModName(modList[curDir]);
		name.screenCenter(X);
		name.y = 20;
		
		icon.loadGraphic(Paths.image(Mods.getModIcon(modList[curDir])));
		icon.screenCenter(X);
		icon.y = name.y + name.height + icon.height;
	}
	
	function makeTopMod()
	{
		reset = true;
		FunkinSound.play(Paths.sound('confirmMenu'));
		Mods.updateModList(modList[curDir]);
		Mods.loadTopMod();
		
		Logger.log('${modList[curDir]} is now prioritized');
	}
}
