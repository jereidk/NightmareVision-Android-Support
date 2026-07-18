package funkin.states.options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.util.FlxColor;

import funkin.backend.MusicBeatSubstate;
import funkin.game.shaders.*;
import funkin.objects.*;

class NotesSubState extends MusicBeatSubstate
{
	private static var curSelected:Int = 0;
	private static var typeSelected:Int = 0;
	
	private var grpNumbers:FlxTypedGroup<Alphabet>;
	private var grpNotes:FlxTypedGroup<FlxSprite>;
	// RGB palette per note -- the same coloring path gameplay uses (white note
	// sprite recolored by an RGBShader), so the preview actually matches what
	// falls in-game. Was an HSLColorSwap array over frames named purple0/blue0/
	// green0/red0, which the VSlice note-assets update renamed out of existence
	// (left/down/up/right note now), leaving the preview notes blank.
	private var paletteArray:Array<funkin.game.shaders.RGBShader.RGBPalette> = [];
	var curValue:Float = 0;
	var holdTime:Float = 0;
	var nextAccept:Int = 5;
	
	var blackBG:FlxSprite;
	var hsbText:Alphabet;
	
	// blackBG spans posX-25 to posX-25+870=1075+X, i.e. symmetric ~205px
	// margins on the 1280 canvas — centered, not edge-anchored, so shifted by
	// half the 'expand'-mode cutout (like CosmicubeSelectState's cards).
	var posX = 230 + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x * 0.5;
	
	public function new()
	{
		super();
		
		initStateScript('NotesSubState');
		scriptGroup.set('this', this);
		
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFFea71fd;
		// Same fixed 1286x730 background as CreditsState — screenCenter() alone
		// just leaves black bars on both sides on a wide 'expand'-mode screen.
		// Stretch first (gated on gameCutoutSize.x, untouched in 'fit' mode).
		if (funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x > 0)
		{
			bg.setGraphicSize(Std.int(bg.width + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x), Std.int(bg.height));
			bg.updateHitbox();
		}
		bg.screenCenter();
		add(bg);
		
		blackBG = new FlxSprite(posX - 25).makeGraphic(870, 200, FlxColor.BLACK);
		blackBG.alpha = 0.4;
		add(blackBG);
		
		grpNotes = new FlxTypedGroup<FlxSprite>();
		add(grpNotes);
		grpNumbers = new FlxTypedGroup<Alphabet>();
		add(grpNumbers);
		
		for (i in 0...ClientPrefs.arrowHSV.length)
		{
			var yPos:Float = (165 * i) + 35;
			for (j in 0...3)
			{
				var optionText:Alphabet = new Alphabet(0, yPos + 60, Std.string(ClientPrefs.arrowHSV[i][j]), true);
				optionText.x = posX + (225 * j) + 250;
				grpNumbers.add(optionText);
			}
			
			var note:FlxSprite = new FlxSprite(posX, yPos);
			note.frames = Paths.getSparrowAtlas('NOTE_assets');
			// VSlice note frames: one white note per direction. Index order
			// matches arrowHSV / funkin.utils.NoteUtil.defaultColors (0=left 1=down 2=up
			// 3=right).
			var dirs:Array<String> = ['left note', 'down note', 'up note', 'right note'];
			note.animation.addByPrefix('idle', dirs[i], 24, true);
			note.animation.play('idle');
			grpNotes.add(note);

			var palette = new funkin.game.shaders.RGBShader.RGBPalette();
			note.shader = palette.shader;
			paletteArray.push(palette);
			_applyNoteColor(i);
		}
		
		hsbText = new Alphabet(0, 0, "Hue    Saturation  Luminosity", false, false, 0, 0.65);
		hsbText.x = posX + 240;
		add(hsbText);
		
		changeSelection();
		
		scriptGroup.set('curSelected', curSelected);
		scriptGroup.set('typeSelected', typeSelected);
		scriptGroup.set('grpNumbers', grpNumbers);
		scriptGroup.set('grpNotes', grpNotes);
		scriptGroup.set('paletteArray', paletteArray);
		scriptGroup.set('curValue', curValue);
		scriptGroup.set('holdTime', holdTime);
		scriptGroup.set('nextAccept', nextAccept);
		scriptGroup.set('blackBG', blackBG);
		scriptGroup.set('hsbText', hsbText);
		scriptGroup.set('posX', posX);
		scriptGroup.set('bg', bg);
		scriptGroup.call('onCreatePost', []);

		#if mobile
		controls.isInSubstate = true;
		// forceShow: true -- unlike the list-based options screens, every
		// interaction here (selection, value adjustment) is D-pad/button
		// driven with no touch-tap equivalent, so a 'Touch' nav mode user
		// would otherwise have no way to use this screen at all.
		addVirtualPad(LEFT_FULL, A_B_C, true);
		addVirtualPadCamera();
		#end
	}

	var changingNote:Bool = false;
	
	override function update(elapsed:Float)
	{
		if (changingNote)
		{
			if (holdTime < 0.5)
			{
				if (controls.UI_LEFT_P)
				{
					updateValue(-1);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				else if (controls.UI_RIGHT_P)
				{
					updateValue(1);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				else if (controls.RESET #if mobile || virtualPad?.buttonC?.justPressed == true #end)
				{
					resetValue(curSelected, typeSelected);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				if (controls.UI_LEFT_R || controls.UI_RIGHT_R)
				{
					holdTime = 0;
				}
				else if (controls.UI_LEFT || controls.UI_RIGHT)
				{
					holdTime += elapsed;
				}
			}
			else
			{
				var add:Float = 90;
				switch (typeSelected)
				{
					case 1 | 2:
						add = 50;
				}
				if (controls.UI_LEFT)
				{
					updateValue(elapsed * -add);
				}
				else if (controls.UI_RIGHT)
				{
					updateValue(elapsed * add);
				}
				if (controls.UI_LEFT_R || controls.UI_RIGHT_R)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'));
					holdTime = 0;
				}
			}
		}
		else
		{
			if (controls.UI_UP_P)
			{
				changeSelection(-1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			if (controls.UI_DOWN_P)
			{
				changeSelection(1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			if (controls.UI_LEFT_P)
			{
				changeType(-1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			if (controls.UI_RIGHT_P)
			{
				changeType(1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			if (controls.RESET #if mobile || virtualPad?.buttonC?.justPressed == true #end)
			{
				for (i in 0...3)
				{
					resetValue(curSelected, i);
				}
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			if (controls.ACCEPT && nextAccept <= 0)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changingNote = true;
				holdTime = 0;
				for (i in 0...grpNumbers.length)
				{
					var item = grpNumbers.members[i];
					item.alpha = 0;
					if ((curSelected * 3) + typeSelected == i)
					{
						item.alpha = 1;
					}
				}
				for (i in 0...grpNotes.length)
				{
					var item = grpNotes.members[i];
					item.alpha = 0;
					if (curSelected == i)
					{
						item.alpha = 1;
					}
				}
				super.update(elapsed);
				return;
			}
		}
		
		if (controls.BACK || (changingNote && controls.ACCEPT))
		{
			if (!changingNote)
			{
				close();
			}
			else
			{
				changeSelection();
			}
			changingNote = false;
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
		
		if (nextAccept > 0)
		{
			nextAccept -= 1;
		}
		super.update(elapsed);
	}
	
	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0) curSelected = ClientPrefs.arrowHSV.length - 1;
		if (curSelected >= ClientPrefs.arrowHSV.length) curSelected = 0;
		
		curValue = ClientPrefs.arrowHSV[curSelected][typeSelected];
		updateValue();
		
		for (i in 0...grpNumbers.length)
		{
			var item = grpNumbers.members[i];
			item.alpha = 0.6;
			if ((curSelected * 3) + typeSelected == i)
			{
				item.alpha = 1;
			}
		}
		for (i in 0...grpNotes.length)
		{
			var item = grpNotes.members[i];
			item.alpha = 0.6;
			item.scale.set(0.75, 0.75);
			if (curSelected == i)
			{
				item.alpha = 1;
				item.scale.set(1, 1);
				hsbText.y = item.y - 70;
				blackBG.y = item.y - 20;
			}
		}
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}
	
	function changeType(change:Int = 0)
	{
		typeSelected += change;
		if (typeSelected < 0) typeSelected = 2;
		if (typeSelected > 2) typeSelected = 0;
		
		curValue = ClientPrefs.arrowHSV[curSelected][typeSelected];
		updateValue();
		
		for (i in 0...grpNumbers.length)
		{
			var item = grpNumbers.members[i];
			item.alpha = 0.6;
			if ((curSelected * 3) + typeSelected == i)
			{
				item.alpha = 1;
			}
		}
	}
	
	// Recolors note `i`'s preview exactly as gameplay does: shift that arrow's
	// base color trio by its current arrowHSV and push it to the RGB shader.
	function _applyNoteColor(i:Int)
	{
		if (i < 0 || i >= paletteArray.length) return;
		final shifted = funkin.utils.NoteUtil.applyHSVShift(funkin.utils.NoteUtil.defaultColors[i], ClientPrefs.arrowHSV[i]);
		paletteArray[i].setColors(funkin.utils.NoteUtil.colorToArray(shifted));
	}

	function resetValue(selected:Int, type:Int)
	{
		curValue = 0;
		ClientPrefs.arrowHSV[selected][type] = 0;
		_applyNoteColor(selected);

		var item = grpNumbers.members[(selected * 3) + type];
		item.changeText('0');
		item.offset.x = (40 * (item.lettersArray.length - 1)) / 2;
	}
	
	function updateValue(change:Float = 0)
	{
		curValue += change;
		var roundedValue:Int = Math.round(curValue);
		var max:Float = 180;
		switch (typeSelected)
		{
			case 1 | 2:
				max = 100;
		}
		
		if (roundedValue < -max)
		{
			curValue = -max;
		}
		else if (roundedValue > max)
		{
			curValue = max;
		}
		roundedValue = Math.round(curValue);
		ClientPrefs.arrowHSV[curSelected][typeSelected] = roundedValue;

		_applyNoteColor(curSelected);

		var item = grpNumbers.members[(curSelected * 3) + typeSelected];
		item.changeText(Std.string(roundedValue));
		item.offset.x = (40 * (item.lettersArray.length - 1)) / 2;
		if (roundedValue < 0) item.offset.x += 10;
	}
}
