package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.group.FlxGroup;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.addons.display.FlxBackdrop;

import funkin.data.WeekData;
import funkin.objects.Alphabet;
import funkin.FunkinAssets;

@:nullSafety
class TitleState extends MusicBeatState
{
	public static var initialized:Bool = false;
	public static var closedState:Bool = false;
	
	// For a potential loading screen but i dont think its necessary
	// key = Lang.hx lookup (see lang/english.json's loading_tip_* entries),
	// fallback = the original English text, used if a language file doesn't
	// have (or hasn't yet translated) that key -- see LoadingState's use of
	// Lang.str(key, fallback) for why this needs both instead of just text.
	// songs = if set, this tip is a reference/spoiler for a specific song and
	// should ONLY be picked while loading exactly that song (matched against
	// SONG.song, e.g. "Double Kill") -- LoadingState filters on this. Omitted
	// entirely (null) means the tip is generic and always eligible.
	public static var funFacts:Array<{key:String, fallback:String, ?songs:Array<String>}> = [
		{key: 'loading_tip_beans', fallback: 'You need at least 4,870 beans to unlock every song.'}, // its true, general
		{key: 'loading_tip_doublekill', fallback: 'Despite its\' name, Double Kill only features one kill.', songs: ['Double Kill']},
		{key: 'loading_tip_blackimpostor', fallback: 'I\'m the black impostor! I am gonna kill you!', songs: ['Defeat']},
		{key: 'loading_tip_airship', fallback: 'The Airship contains many wacky trinkets in i! Try the teleporter today!',
			songs: ['Titular', 'Greatest Plan', 'Reinforcements', 'Armed']}, // HENRY week
		{key: 'loading_tip_torture', fallback: '"Why don\'t we begin?"', songs: ['Torture']},
		{key: 'loading_tip_shapeshifter', fallback: 'The shapeshifter\'s name is Monotone.', songs: ['Identity Crisis']}, // doc
		{key: 'loading_tip_doubletrouble', fallback: '"Impostor Trouble? Now it is double."', songs: ['Double Trouble']},
		{key: 'loading_tip_tomongus', fallback: 'Beat the Tomongus week to unlock a new song!',
			songs: ['Sussy Bussy', 'Rivals', 'Chewmate']}, // week10
		{key: 'loading_tip_keep', fallback: 'I don\'t want to get rid of this'} // general
	];
	
	var skippedIntro:Bool = false;
	var transitioning:Bool = false;
	
	var introEndingText:Array<String> = ['VS', 'IMPOSTOR', 'LEGACY'];
	var randomIntroText:Array<String> = [];
	
	// objects
	var starFG:Null<FlxSprite> = null;
	var starBG:Null<FlxSprite> = null;
	var textGroup:Null<FlxGroup> = null;
	var ngSpr:Null<FlxSprite> = null;
	var logo:Null<FlxSprite> = null;
	var titleText:Null<FlxSprite> = null;
	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	public static function init():Void
	{
		FunkinAssets.cache.clearStoredMemory();
		FunkinAssets.cache.clearUnusedMemory();
		
		// for some reason the plugin scripts dont run sometimes when first loaded. oh well
		funkin.scripting.PluginsManager.prepareSignals();
		funkin.scripting.PluginsManager.populate();

	}
	
	override public function create():Void
	{
		_bitmapSnapshotAtCreate = FunkinAssets.cache.snapshotBitmapKeys();

		if (FlxG.save.data.photosensitive == null && !FlashingState.leftState)
		{
			CoolUtil.setTransSkip();
			FlxG.switchState(FlashingState.new);
			
			return super.create();
		}
		
		if (ClientPrefs.finaleState == COMPLETE)
		{
			if (!ProgressionUtil.songIsClear('finale'))
			{
				ClientPrefs.finaleState = ACTIVE; // failsafe for a realy specific case
			}
			else if (!ClientPrefs.doubletrouble)
			{
				ClientPrefs.doubletrouble = true;
			}
		}
		
		init();
		
		randomIntroText = FlxG.random.getObject(getIntroText());
		
		initStateScript();
		
		startIntro();
		
		super.create();
		
		#if ASSET_REDIRECT
		if (Paths.fileExists('images/cursor.png'))
			FlxG.mouse.load(openfl.display.BitmapData.fromFile(Paths.getPath('images/cursor.png')));
		#else
		FlxG.mouse.load('assets/images/cursor.png');
		#end
		
		persistentUpdate = true;
		
		FlxG.mouse.visible = #if mobile false #else true #end;
	}

	function startIntro()
	{
		if (!initialized)
		{
			FunkinSound.playMusic(Paths.music('freakyMenu'), 0);
		}
		
		Conductor.bpm = 102;
		Conductor.bpmChangeMap.resize(0);
		
		if (isHardcodedState() && scriptGroup.call('onStartIntro') != ScriptConstants.STOP_FUNC)
		{
			starBG = new FlxBackdrop(Paths.image('menu/common/starBG'));
			starBG.alpha = 0.001;
			add(starBG);
			
			starFG = new FlxBackdrop(Paths.image('menu/common/starFG'));
			starFG.alpha = 0.001;
			add(starFG);
			
			logo = new FlxSprite(-150, -10).loadAtlasFrames(Paths.getAtlasFrames('logoBumpin'));
			logo.animation.addByPrefix('bump', 'logo bumpin', 24, false);
			logo.animation.play('bump');
			logo.screenCenter(X);
			add(logo);
			
			titleText = new FlxSprite(300, FlxG.height * 0.855).loadAtlasFrames(Paths.getAtlasFrames('menu/title/startText'));
			titleText.animation.addByPrefix('idle', "EnterIdle", 24, false);
			titleText.animation.addByPrefix('press', "EnterStart", 24, false);
			titleText.animation.play('idle');
			titleText.y -= 55;
			// x=300 was a hardcoded approximation of screenCenter() for this
			// sprite's ~650px frame width on the 1280 base canvas — same
			// screenCenter(X) convention logo/ngSpr already use below, so this
			// tracks live FlxG.width instead of staying fixed on a wide screen.
			titleText.screenCenter(X);
			
			logo.scale.set(0.84, 0.84);
			logo.updateHitbox();
			logo.screenCenter(X);
			logo.x += 20;
			
			add(titleText);
			
			textGroup = new FlxGroup();
			add(textGroup);
			
			ngSpr = new FlxSprite(0, FlxG.height * 0.52, Paths.image('menu/title/funkin'));
			add(ngSpr);
			ngSpr.visible = false;
			ngSpr.screenCenter(X);
			
			logo.alpha = 0.001;
			titleText.alpha = 0.001;
		}
		
		if (initialized)
		{
			skipIntro();
		}
		else
		{
			initialized = true;
			closedState = false;
		}
		
		scriptGroup.call('onCreatePost', []);
	}
	
	override function update(elapsed:Float)
	{
		if (FlxG.sound.music != null) Conductor.songPosition = FlxG.sound.music.time;
		if (starFG != null && starBG != null)
		{
			starBG.x = FlxMath.lerp(starBG.x, starBG.x - 0.5, elapsed * 9);
			starFG.x = FlxMath.lerp(starFG.x, starFG.x - 1, elapsed * 9);
		}
		
		if (!isHardcodedState())
		{
			super.update(elapsed);
			return;
		}
		
		// Always allow touch/click on TitleState for easy access
		var allowMousePress:Bool = true;
		#if mobile
		// TitleState should always accept touch, regardless of navInputMode setting
		allowMousePress = true;
		#end
		final pressedEnter:Bool = FlxG.gamepads.lastActive?.justPressed.START || FlxG.keys.justPressed.ENTER || controls.ACCEPT || (allowMousePress && FlxG.mouse.justPressed);
		
		if (!transitioning && skippedIntro)
		{
			if (pressedEnter && scriptGroup.call('onEnter', []) != ScriptConstants.STOP_FUNC)
			{
				FlxG.camera.flash(ClientPrefs.flashing ? FlxColor.WHITE : 0x4CFFFFFF, 1);
				transitioning = true;
				
				if (titleText != null)
				{
					titleText.animation.play('press');
					titleText.offset.set(278, 2);
				}
				
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
				
				FlxTimer.wait(1, () -> {
					MainMenuState.fromTitle = true;
					FlxG.switchState(MainMenuState.new);
					closedState = true;
				});
			}
		}
		
		if (pressedEnter && !skippedIntro)
		{
			skipIntro();
		}
		
		super.update(elapsed);
	}
	
	function createCoolText(textArray:Array<String>, offset:Float = 0)
	{
		if (textGroup == null) return;
		
		for (i in 0...textArray.length)
		{
			final text:Alphabet = new Alphabet(0, 0, textArray[i], true);
			text.screenCenter(X);
			text.y += (i * 60) + 200 + offset;
			
			textGroup.add(text);
		}
	}
	
	function addMoreText(text:String, offset:Float = 0)
	{
		if (textGroup == null) return;
		
		final coolText:Alphabet = new Alphabet(0, 0, text, true);
		coolText.screenCenter(X);
		coolText.y += (textGroup.length * 60) + 200 + offset;
		textGroup.add(coolText);
	}
	
	function deleteCoolText()
	{
		if (textGroup != null && textGroup.members[0] != null)
		{
			for (i in 0...textGroup.length)
			{
				var txt = textGroup.members[0];
				textGroup.remove(txt, true);
				
				txt = FlxDestroyUtil.destroy(txt);
			}
		}
	}
	
	function getIntroText():Array<Array<String>>
	{
		if (!FunkinAssets.exists(Paths.txt('introText'))) return [];
		
		final fullText:String = FunkinAssets.getContent(Paths.txt('introText'));
		
		return [for (i in fullText.split('\n')) i.split('--')];
	}
	
	var sickBeats:Int = 0; // Basically curBeat but won't be skipped if you hold the tab or resize the screen
	
	override function beatHit()
	{
		super.beatHit();
		
		if (!closedState)
		{
			sickBeats++;
			scriptGroup.set('curBeat', sickBeats);
		}
		
		if (!isHardcodedState() || scriptGroup.call('onBeatHit', []) == ScriptConstants.STOP_FUNC) return;
		
		// just in case
		if (isHardcodedState())
		{
			if (logo != null)
			{
				logo.animation.play('bump', true);
			}
			
			if (!closedState)
			{
				switch (sickBeats)
				{
					case 1:
						FunkinSound.playMusic(Paths.music('freakyMenu'), 0);
						
						if (ClientPrefs.finaleState != ACTIVE) FlxG.sound.music.fadeIn(4, 0, 0.7);
					case 2:
						createCoolText(['MOTORFROG']);
					case 4:
						addMoreText('presents');
					case 5:
						deleteCoolText();
					case 6:
						createCoolText(['This is a mod to'], -60);
					case 8:
						addMoreText('This game right below lol', -60);
						if (ngSpr != null) ngSpr.visible = true;
					case 9:
						deleteCoolText();
						if (ngSpr != null) ngSpr.visible = false;
					case 10:
						if (randomIntroText[0] != null) createCoolText([randomIntroText[0]]);
					case 12:
						if (randomIntroText[1] != null) addMoreText(randomIntroText[1]);
					case 13:
						deleteCoolText();
					case 14:
						if (introEndingText[0] != null) addMoreText(introEndingText[0]);
					case 15:
						if (introEndingText[1] != null) addMoreText(introEndingText[1]);
					case 16:
						if (introEndingText[2] != null) addMoreText(introEndingText[2]);
					case 17:
						skipIntro();
				}
			}
		}
	}
	
	public function skipIntro():Void
	{
		if (scriptGroup.call('onSkipIntro', []) != ScriptConstants.STOP_FUNC && !skippedIntro)
		{
			ngSpr?.kill();
			textGroup?.kill();
			
			if (starFG != null && starBG != null)
			{
				starBG.alpha = 1;
				starFG.alpha = 1;
			}
			if (logo != null) logo.alpha = 1;
			if (titleText != null) titleText.alpha = 1;
			
			FlxG.camera.flash(FlxColor.WHITE, 4);
			
			skippedIntro = true;
		}
	}

	override function destroy():Void
	{
		super.destroy();

		if (_bitmapSnapshotAtCreate != null)
		{
			FunkinAssets.cache.disposeNewSince(_bitmapSnapshotAtCreate);
			_bitmapSnapshotAtCreate = null;
		}
	}
}
