// while this CAN be apart of NotesSubState
// fuck you
package funkin.states.options;

import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;

import funkin.objects.*;
import funkin.states.substates.*;
import funkin.game.shaders.*;
import funkin.backend.MusicBeatSubstate;

class QuantNotesSubState extends MusicBeatSubstate
{
	private static var curSelected:Int = 0;
	private static var typeSelected:Int = 0;
	
	private var grpNumbers:FlxTypedGroup<Alphabet>;
	private var grpNotes:FlxTypedGroup<FlxSprite>;
	private var grpQuants:FlxTypedGroup<AttachedAlphabet>;
	private var shaderArray:Array<HSLColorSwap> = [];
	var curValue:Float = 0;
	var holdTime:Float = 0;
	var nextAccept:Int = 5;
	
	var blackBG:FlxSprite;
	var hsbText:Alphabet;
	
	// Same symmetric-margin panel as NotesSubState.posX — shifted by half the
	// 'expand'-mode cutout to stay centered.
	var posX = 230 + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x * 0.5;
	
	public static var defaults:Array<Array<Int>> = [
		[0, -20, 0], // 4th
		[-130, -20, 0], // 8th
		[-80, -20, 0], // 12th
		[128, -30, 0], // 16th
		[-120, -70, -35], // 20th
		[-80, -20, 0], // 24th
		[50, -20, 0], // 32nd
		[-80, -20, 0], // 48th
		[160, -15, 0], // 64th
		[-120, -70, -35], // 96th
		[-120, -70, -35] // 192nd
	];
	public static var quantizations:Array<String> = [
		"4th", "8th", "12th", "16th", "20th", "24th", "32nd", "48th", "64th", "96th", "192nd"
	];
	
	public function new()
	{
		super();
		
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menus/menuDesat'));
		bg.color = 0xFFea71fd;
		// Same fixed 1286x730 background as CreditsState/NotesSubState —
		// stretch first (gated on gameCutoutSize.x) so screenCenter() covers
		// the full width instead of leaving black bars on both sides.
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
		grpQuants = new FlxTypedGroup<AttachedAlphabet>();
		add(grpQuants);
		grpNumbers = new FlxTypedGroup<Alphabet>();
		add(grpNumbers);
		
		for (i in 0...ClientPrefs.quantHSV.length)
		{
			var yPos:Float = (165 * i) + 35;
			for (j in 0...3)
			{
				var optionText:Alphabet = new Alphabet(0, yPos + 60, Std.string(ClientPrefs.quantHSV[i][j]), true);
				optionText.x = posX + (225 * j) + 250;
				grpNumbers.add(optionText);
			}
			
			var note:FlxSprite = new FlxSprite(posX, yPos);
			note.frames = Paths.getSparrowAtlas('QUANTNOTE_assets');
			
			var txt:AttachedAlphabet = new AttachedAlphabet(quantizations[i], 0, 0, true);
			txt.sprTracker = note;
			txt.copyAlpha = true;
			add(txt);
			var animations:Array<String> = ['purple0', 'blue0', 'green0', 'red0'];
			note.animation.addByPrefix('idle', animations[i % 4]);
			note.animation.play('idle');
			grpNotes.add(note);
			
			var newShader:HSLColorSwap = new HSLColorSwap();
			note.shader = newShader.shader;
			newShader.hue = ClientPrefs.quantHSV[i][0] / 360;
			newShader.saturation = ClientPrefs.quantHSV[i][1] / 100;
			newShader.lightness = ClientPrefs.quantHSV[i][2] / 100;
			shaderArray.push(newShader);
		}
		
		hsbText = new Alphabet(0, 0, "Hue    Saturation  Luminosity", false, false, 0, 0.65);
		hsbText.x = posX + 240;
		add(hsbText);
		
		changeSelection();

		#if mobile
		controls.isInSubstate = true;
		// forceShow: true -- same reasoning as NotesSubState: no touch-tap
		// equivalent exists here, so a 'Touch' nav mode user needs the pad
		// to interact with this screen at all.
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
		
		for (i in 0...grpNotes.length)
		{
			var yIndex = i;
			var item = grpNotes.members[i];
			if (curSelected > 2) yIndex -= curSelected - 2;
			
			// FlxMath.getElapsedLerp() instead of a raw "0.4 * (elapsed / (1/120))"
			// scale -- that naive version has no ceiling, so a lag spike
			// (elapsed well past a 120fps frame) pushed the ratio past 1.0 and
			// overshot the target position instead of just closing the gap
			// faster. getElapsedLerp() asymptotically approaches 1.0 for any
			// elapsed, same framerate-independent-smoothing pattern already
			// used elsewhere (TouchOptionList, MobileSettingsSubState). 0.65
			// picked to match the old formula's speed at a normal framerate.
			var lerpVal:Float = FlxMath.getElapsedLerp(0.65, elapsed);
			
			var yPos:Float = (165 * yIndex) + 35;
			
			item.y = FlxMath.lerp(item.y, yPos, lerpVal);
			if (i == curSelected)
			{
				hsbText.y = FlxMath.lerp(hsbText.y, yPos - 70, lerpVal);
				blackBG.y = FlxMath.lerp(blackBG.y, yPos - 20, lerpVal);
			}
		}
		
		for (i in 0...grpNumbers.length)
		{
			var item = grpNumbers.members[i];
			item.y = grpNotes.members[Math.floor(i / 3)].y + 60;
		}
		
		super.update(elapsed);
	}
	
	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0) curSelected = ClientPrefs.quantHSV.length - 1;
		if (curSelected >= ClientPrefs.quantHSV.length) curSelected = 0;
		
		curValue = ClientPrefs.quantHSV[curSelected][typeSelected];
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
			}
		}
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}
	
	function changeType(change:Int = 0)
	{
		typeSelected += change;
		if (typeSelected < 0) typeSelected = 2;
		if (typeSelected > 2) typeSelected = 0;
		
		curValue = ClientPrefs.quantHSV[curSelected][typeSelected];
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
	
	function resetValue(selected:Int, type:Int)
	{
		// Was unconditional on ClientPrefs.quants while updateValue() (the
		// manual arrow-key edit path) isn't -- Reset silently no-opped the
		// actual value whenever quants were toggled off, while still lying
		// about it below (see the other two fixes in this function).
		curValue = defaults[selected][type];
		ClientPrefs.quantHSV[selected][type] = defaults[selected][type];
		switch (type)
		{
			// Was missing the /360 and /100 normalization updateValue() uses
			// for the exact same fields -- fed the shader raw degree/percent
			// values (e.g. -120) instead of the 0..1 range it expects,
			// scrambling the note's color on reset.
			case 0:
				shaderArray[selected].hue = defaults[selected][type] / 360;
			case 1:
				shaderArray[selected].saturation = defaults[selected][type] / 100;
			case 2:
				shaderArray[selected].lightness = defaults[selected][type] / 100;
		}

		var item = grpNumbers.members[(selected * 3) + type];
		// Was hardcoded '0' -- correct for NotesSubState (whose defaults are
		// always 0) but QuantNotesSubState's defaults are mostly nonzero, so
		// this displayed a false "0" no matter what the reset value actually was.
		item.changeText(Std.string(defaults[selected][type]));
		item.offset.x = (40 * (item.lettersArray.length - 1)) / 2;
		if (defaults[selected][type] < 0) item.offset.x += 10;
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
		ClientPrefs.quantHSV[curSelected][typeSelected] = roundedValue;
		
		switch (typeSelected)
		{
			case 0:
				shaderArray[curSelected].hue = roundedValue / 360;
			case 1:
				shaderArray[curSelected].saturation = roundedValue / 100;
			case 2:
				shaderArray[curSelected].lightness = roundedValue / 100;
		}
		
		var item = grpNumbers.members[(curSelected * 3) + typeSelected];
		item.changeText(Std.string(roundedValue));
		item.offset.x = (40 * (item.lettersArray.length - 1)) / 2;
		if (roundedValue < 0) item.offset.x += 10;
	}
}
