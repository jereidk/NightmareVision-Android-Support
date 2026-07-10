package funkin.states;

import flixel.addons.display.FlxBackdrop;
import flixel.tweens.FlxTweenType;
import flixel.util.typeLimit.NextState;

import funkin.backend.Difficulty;
import funkin.data.CharacterData.CharacterParser;
import funkin.objects.HealthIcon;
import funkin.objects.Pet;

/**
 * Sits between picking a song and PlayState.create() actually running.
 * Flixel's switchState() calls the target state's create() synchronously
 * (see FlxGame.switchState()) -- no frame renders while it's working, so
 * a loading screen can't show LIVE progress through that block without
 * splitting create() into resumable steps. This is the "safe minimal"
 * version instead: show something real (opponent, song, difficulty, a
 * tip, a moving pet) for at least MIN_SHOW_TIME using the same
 * starfield/vignette/fonts as the main menu, THEN trigger the real
 * switch -- so the freeze is bookended by an on-theme loading screen
 * instead of a static wipe.
 */
class LoadingState extends MusicBeatState
{
	// Matches the mod's own Impostor/Among Us branding -- always something
	// to show even if the player has no pet equipped.
	static inline final DEFAULT_PET:String = 'minicrewmate';

	// Long enough that the screen never just flashes by, short enough it
	// doesn't feel like padding -- roughly two SwipeTransition beats.
	static inline final MIN_SHOW_TIME:Float = 1.1;

	static inline final ACCENT:FlxColor = 0xFFFF4444; // matches FreeplayCard's own selection accent

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

		// Soft warm highlight behind the title/icon cluster -- same additive
		// technique MainMenuState uses for its own glow, just scaled down and
		// tinted to sit behind a smaller area instead of covering the screen.
		var glow = new FlxSprite().loadGraphic(Paths.image('menu/main/glow'));
		glow.scale.set(0.55, 0.55);
		glow.updateHitbox();
		glow.color = ACCENT;
		glow.alpha = 0.55;
		glow.blend = ADD;
		glow.screenCenter(X);
		glow.y = 30;
		glow.scrollFactor.set();
		add(glow);

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

		var song = PlayState.SONG;

		var songName:String = '';
		if (song != null && song.song != null && song.song.length > 0)
			songName = song.song.charAt(0).toUpperCase() + song.song.substr(1);

		// Cheap metadata-only lookup (just parses the character JSON, no
		// atlas/sprite construction -- see Pet.hx's own use of this for the
		// same reason) so the icon matches what the HUD actually shows for
		// this opponent (e.g. "danger" character -> "black" icon), not just
		// whatever HealthIcon's own placeholder fallback would guess from
		// the raw character id.
		if (song != null && song.player2 != null && song.player2.length > 0)
		{
			var opponentInfo = CharacterParser.fetchInfoUnsafe(song.player2);
			var iconKey:String = opponentInfo?.healthicon ?? song.player2;

			var icon = new HealthIcon(iconKey, false);
			icon.setGraphicSize(90, 90);
			icon.updateHitbox();
			icon.antialiasing = ClientPrefs.globalAntialiasing;
			icon.screenCenter(X);
			icon.x -= 130;
			icon.y = 100;
			icon.scrollFactor.set();
			add(icon);

			FlxTween.tween(icon.scale, {x: icon.scale.x * 1.08, y: icon.scale.y * 1.08}, 0.6,
				{type: PINGPONG, ease: FlxEase.sineInOut});
		}

		var titleText = new FlxText(0, 118, FlxG.width, Lang.str('loading_title', 'CARGANDO') + (songName.length > 0 ? '\n$songName' : ''), 56);
		titleText.setFormat(Paths.font('AmaticSC-Bold.ttf'), 56, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 3;
		titleText.scrollFactor.set();
		add(titleText);

		FlxTween.tween(titleText.scale, {x: 1.04, y: 1.04}, 0.9, {type: PINGPONG, ease: FlxEase.sineInOut});

		if (song != null)
		{
			var diffName:String = Difficulty.difficulties[PlayState.storyMeta.difficulty] ?? '';
			if (diffName.length > 0)
			{
				var diffText = new FlxText(0, titleText.y + 92, FlxG.width, diffName.toUpperCase(), 26);
				diffText.setFormat(Paths.font('vcr.ttf'), 26, ACCENT, CENTER, OUTLINE, FlxColor.BLACK);
				diffText.scrollFactor.set();
				add(diffText);
			}
		}

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
