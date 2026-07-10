package funkin.states;

import flixel.addons.display.FlxBackdrop;
import flixel.tweens.FlxTweenType;
import flixel.util.typeLimit.NextState;

import funkin.objects.Pet;

/**
 * Sits between picking a song and PlayState.create() actually running.
 * Flixel's switchState() calls the target state's create() synchronously
 * (see FlxGame.switchState()) -- no frame renders while it's working, so
 * a loading screen can't show LIVE progress through that block without
 * splitting create() into resumable steps. This is the "safe minimal"
 * version instead: show something real (song name, a tip, a moving pet)
 * for at least MIN_SHOW_TIME using the same starfield/vignette/fonts as
 * the main menu, THEN trigger the real switch -- so the freeze is
 * bookended by an on-theme loading screen instead of a static wipe.
 */
class LoadingState extends MusicBeatState
{
	// Matches the mod's own Impostor/Among Us branding -- always something
	// to show even if the player has no pet equipped.
	static inline final DEFAULT_PET:String = 'minicrewmate';

	// Long enough that the screen never just flashes by, short enough it
	// doesn't feel like padding -- roughly two SwipeTransition beats.
	static inline final MIN_SHOW_TIME:Float = 1.1;

	var nextState:NextState;
	var shownTime:Float = 0;
	var switching:Bool = false;

	public static function loadAndSwitchState(nextState:NextState):Void
	{
		FlxG.switchState(() -> new LoadingState(nextState));
	}

	public function new(nextState:NextState)
	{
		super();
		this.nextState = nextState;
	}

	override function create():Void
	{
		persistentUpdate = persistentDraw = false;

		add(new FlxBackdrop(Paths.image('menu/common/starBG')));
		add(new FlxBackdrop(Paths.image('menu/common/starFG')));

		var vignette = new FlxSprite().loadGraphic(Paths.image('menu/main/vignette'));
		vignette.scrollFactor.set();
		vignette.active = false;
		if (FlxG.width > vignette.width)
		{
			vignette.scale.x *= FlxG.width / vignette.width;
			vignette.updateHitbox();
		}
		vignette.screenCenter();
		add(vignette);

		var songName:String = '';
		if (PlayState.SONG != null && PlayState.SONG.song != null && PlayState.SONG.song.length > 0)
			songName = PlayState.SONG.song.charAt(0).toUpperCase() + PlayState.SONG.song.substr(1);

		var titleText = new FlxText(0, 150, FlxG.width, Lang.str('loading_title', 'CARGANDO') + (songName.length > 0 ? '\n$songName' : ''), 56);
		titleText.setFormat(Paths.font('AmaticSC-Bold.ttf'), 56, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 3;
		titleText.scrollFactor.set();
		add(titleText);

		var tip:String = FlxG.random.getObject(TitleState.funFacts) ?? '';
		var tipText = new FlxText(100, FlxG.height - 140, FlxG.width - 200, tip, 26);
		tipText.setFormat(Paths.font('vcr.ttf'), 26, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		tipText.borderSize = 2;
		tipText.scrollFactor.set();
		add(tipText);

		var petId:String = (ClientPrefs.pet != null && ClientPrefs.pet.length > 0) ? ClientPrefs.pet : DEFAULT_PET;
		var pet:Pet = new Pet(0, 0, petId);
		if (pet.isAnimNull())
		{
			// Whatever pet.json this ID pointed to failed to load (bad ID,
			// missing assets, etc.) -- fall back to the always-bundled
			// default rather than showing a blank/broken sprite.
			pet.destroy();
			pet = new Pet(0, 0, DEFAULT_PET);
		}
		pet.scale.set(1.6, 1.6);
		pet.updateHitbox();
		pet.screenCenter(X);
		pet.y = FlxG.height - 250;
		pet.scrollFactor.set();
		pet.dance();
		add(pet);

		FlxTween.tween(pet, {x: pet.x - 140}, 1.4, {type: PINGPONG, ease: FlxEase.quadInOut});

		super.create();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		shownTime += elapsed;
		if (!switching && shownTime >= MIN_SHOW_TIME)
		{
			switching = true;
			FlxG.switchState(nextState);
		}
	}
}
