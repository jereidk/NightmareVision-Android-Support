package funkin.states;

import flixel.addons.display.FlxBackdrop;
import flixel.addons.transition.FlxTransitionableState;
import flixel.tweens.FlxTween.FlxTweenType;
import flixel.util.typeLimit.NextState;

import funkin.data.CharacterData.CharacterParser;
import funkin.objects.HealthIcon;

/**
 * Sits between picking a song and PlayState.create() actually running.
 * Flixel's switchState() calls the target state's create() synchronously
 * (see FlxGame.switchState()) -- no frame renders while it's working, so
 * a loading screen can't show LIVE progress through that block without
 * splitting create() into resumable steps. This is the "safe minimal"
 * version instead: show something real (opponent, song, a tip) for at
 * least MIN_SHOW_TIME using the same starfield/vignette/fonts as the
 * main menu, THEN trigger the real switch -- so the freeze is
 * bookended by an on-theme loading screen instead of a static wipe.
 */
class LoadingState extends MusicBeatState
{
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
		glow.y = 120;
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
			icon.setGraphicSize(300, 300);
			icon.updateHitbox();
			icon.antialiasing = ClientPrefs.globalAntialiasing;
			icon.screenCenter(X);
			icon.x -= 330;
			icon.y = 150;
			icon.scrollFactor.set();
			add(icon);

			FlxTween.tween(icon.scale, {x: icon.scale.x * 1.08, y: icon.scale.y * 1.08}, 0.6,
				{type: PINGPONG, ease: FlxEase.sineInOut});
		}

		var loadingLabel = new FlxText(0, 150, FlxG.width, Lang.str('loading_title', 'Loading'), 60);
		loadingLabel.setFormat(Paths.font('vcr.ttf'), 60, ACCENT, CENTER, OUTLINE, FlxColor.BLACK);
		loadingLabel.scrollFactor.set();
		add(loadingLabel);

		var titleText = new FlxText(0, loadingLabel.y + 80, FlxG.width, songName, 150);
		titleText.setFormat(Paths.font('AmaticSC-Bold.ttf'), 150, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 5;
		titleText.scrollFactor.set();
		add(titleText);

		FlxTween.tween(titleText.scale, {x: 1.04, y: 1.04}, 0.9, {type: PINGPONG, ease: FlxEase.sineInOut});

		var tipEntry = FlxG.random.getObject(TitleState.funFacts);
		var tip:String = (tipEntry != null) ? Lang.str(tipEntry.key, tipEntry.fallback) : '';
		var tipText = new FlxText(100, FlxG.height - 140, FlxG.width - 200, tip, 26);
		tipText.setFormat(Paths.font('vcr.ttf'), 26, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		tipText.borderSize = 2;
		tipText.scrollFactor.set();
		add(tipText);

		super.create();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		shownTime += elapsed;
		if (!switching && shownTime >= MIN_SHOW_TIME)
		{
			switching = true;

			// MusicBeatState.startOutro() (triggered by FlxG.switchState())
			// normally opens a SwipeTransition substate first and only
			// switches once its 0.48s tween finishes -- but that substate's
			// `gradientFill` is a fully OPAQUE black sprite added the instant
			// it's created, not something that fades in, so the screen goes
			// solid black immediately, well before PlayState.create() (the
			// actual multi-second blocking load this whole state exists to
			// hide) even starts. Since no frame renders during that
			// synchronous create() call, that solid black frame is what
			// stays on screen for the entire real load -- this state's own
			// tip/icon visuals were already gone by then, defeating the
			// point. Skipping this one transition leaves this state's last
			// drawn frame on screen (frozen, but on-theme) for the whole
			// load instead; PlayState's own entrance wipe (a separate flag,
			// untouched here) still plays normally once it's actually built.
			FlxTransitionableState.skipNextTransIn = true;

			FlxG.switchState(nextState);
		}
	}
}
