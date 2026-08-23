import funkin.data.ClientPrefs;

var ext:String = 'stages/skeld/jads/';

function onLoad()
{
	var bg:FlxSprite = new FlxSprite(-595, -195).loadGraphic(Paths.image(ext + 'O2Background'));
	
	var fans = new FlxSprite(-166.25, 68.45);
	fans.frames = Paths.getSparrowAtlas(ext + 'fansss');
	fans.animation.addByPrefix('bop', 'fansss instance 1', 24, true);
	fans.animation.play('bop');
	
	var piss:FlxSprite = new FlxSprite(-453.9, 310.2).loadGraphic(Paths.image(ext + 'switch'));
	
	add(bg);
	add(fans);
	add(piss);
}

function onCreatePost()
{
	camSpecialThing([600, 440], [1150, 440]);
}

function onSongStart() onStepHit(); // fuk you
public var woo_party:Int = 0;
function onEndSong() woo_party = 0;

function onStepHit()
{
	modchart(curStep);
	
	if (curStep % 4 > 0) return;
	
	switch (woo_party)
	{
		case 1:
			bump(0.008, 0.008);
			
		case 2:
			bump(0.016, 0.016);
			
		case 3:
			bump(0.008, 0.016);
			
		case 4:
			bump(0.02, 0.02);
			
			if (ClientPrefs.flashing)
			{
				camGame.stopFade();
				camGame.flash(FlxColor.WHITE, 5);
				camGame._fxFlashAlpha = .1;
			}
	}
}

function bump(game:Float, hud:Float)
{
	if (!ClientPrefs.camZooms) return;
	
	camGame.zoom += game;
	camHUD.zoom += hud;
}
