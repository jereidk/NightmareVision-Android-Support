var bothSing:Bool = false;
var twoSing:Bool = false;
public var cargoDark:FlxSprite;
public var lightoverlayDK:FlxSprite;
public var mainoverlayDK:FlxSprite;
var cargoAirship:FlxSprite;
/*
	There is a bug where the first note played in a changed section will be the
	other character that sang last time. I do not know how to fix this yet.


	Post-note: I manually moved all of the events 10ms to the left in the .json
	
	heh. new eve nts order fixes this.
 */
var ext = 'stages/airship/double-kill/';
public var yellow:Character;
public var isBfGhost:Bool = false;
var mandoSing:Bool = false;

function onLoad()
{
	var bg:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image(ext + 'cargo'));
	bg.antialiasing = true;
	bg.scale.set(2, 2);
	bg.updateHitbox();
	bg.scrollFactor.set(1, 1);
	bg.active = false;
	add(bg);
	
	cargoDark = new FlxSprite(-1000, -1000).makeScaledGraphic(FlxG.width * 3, FlxG.height * 3, FlxColor.BLACK);
	cargoDark.antialiasing = true;
	cargoDark.scrollFactor.set(0, 0);
	cargoDark.alpha = 0.001;
	add(cargoDark);
}

function goodNoteHit(note)
{
	if (mandoSing) characterSing(yellow, note);
}

function onBeatHit()
{
	if (yellow != null) yellow.onBeatHit(curBeat);
}

function onCreatePost()
{
	isBfGhost = boyfriend.getFlag('ghost');
	
	if (isBfGhost)
	{
		mandoSing = true;
		
		yellow = new Character(3100, 650, 'yellow-ghost', true);
		yellow.alpha = 0.001;
		startCharacterPos(yellow);
		
		add(yellow);
	}
	
	mainoverlayDK = new FlxSprite(1000, 350).loadGraphic(Paths.image(ext + 'newoverlay1'));
	mainoverlayDK.scale.set(1.8, 1.6);
	mainoverlayDK.updateHitbox();
	mainoverlayDK.alpha = .51;
	mainoverlayDK.blend = BlendMode.SUBTRACT;
	add(mainoverlayDK);
	
	lightoverlayDK = new FlxSprite(1000, 350).loadGraphic(Paths.image(ext + 'newoverlay2'));
	lightoverlayDK.scale.set(1.8, 1.6);
	lightoverlayDK.updateHitbox();
	lightoverlayDK.alpha = 0.60;
	lightoverlayDK.blend = BlendMode.ADD;
	add(lightoverlayDK);
}

function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case 'Legacy': // I fucked up but i dont wanna go back and fix all the events i put down
			switch (value1) // orbyy do not pull this line of code on me ever again i will kill you
			{
				case 'black':
					camCurTarget = game.gf;
				case 'not black':
					camCurTarget = null;
			}
		case 'Opponent Two':
			twoSing = Std.int(value1) == 1;
			if (!bothSing) refreshDoubleKillIcon();
		case 'Both Opponents':
			bothSing = Std.int(value1) == 1;
			playHUD.iconP2.changeIcon(bothSing ? 'double-kill' : (twoSing ? 'black' : 'white'));
	}
}

function refreshDoubleKillIcon()
{
	if (hasColor) scoreTxt.color = (twoSing ? gf : dad).healthColour;
	playHUD.healthBar.setColors((twoSing ? gf : dad).healthColour, boyfriend.healthColour);
	playHUD.iconP2.changeIcon(twoSing ? 'black' : 'white');
}

function opponentNoteHitPre(note)
{
	if (note.noteType == 'Opponent 2 Sing')
	{
		note.owner = gf;
	}
	else if (bothSing || note.noteType == 'Both Opponents Sing')
	{
		// TODO: despite doing the same fraeking thing, note.singers isnt playing gohst animations  ?!?!
		characterSing(dad, note);
		characterSing(gf, note);
		note.noAnimation = true;
	}
	else if (twoSing)
	{
		note.owner = gf;
	}
}
