package funkin.states;

import haxe.Timer;
import haxe.ds.Vector;

import openfl.events.KeyboardEvent;

import flixel.util.FlxDestroyUtil;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxSort;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.group.FlxSpriteGroup;
import flixel.input.keyboard.FlxKey;
import flixel.util.helpers.FlxBounds;
import flixel.group.FlxContainer.FlxTypedContainer;
import flixel.util.FlxStringUtil;

import funkin.input.InputSystem;
import funkin.input.InputEvent;
import funkin.objects.Character;
import funkin.backend.Difficulty;
import funkin.backend.SystemMonitor;
import funkin.game.RatingInfo;
import funkin.objects.note.*;
import funkin.objects.note.Note;
import funkin.game.huds.BaseHUD;
import funkin.scripts.*;
import funkin.data.Song;
import funkin.data.StageData;
import funkin.game.Rating;
import funkin.objects.*;
import funkin.data.*;
import funkin.states.*;
import funkin.states.substates.*;
import funkin.states.editors.*;
import funkin.game.modchart.*;
import funkin.game.StoryMeta;
import funkin.game.Countdown;
import funkin.game.marathon.*;
import funkin.objects.menu.AwardPopup;
import funkin.objects.menu.BeansPopup;
import funkin.audio.SyncedFlxSoundGroup;
#if VIDEOS_ALLOWED
import funkin.video.FunkinVideoSprite;
#end

class PlayState extends MusicBeatState
{
	public static var STRUM_X:Float = 42; // redundant
	public static var STRUM_X_MIDDLESCROLL:Float = -278; // redundant
	
	public static var meta:Null<Metadata> = null; // bad?
	
	public static var SONG:Null<Song> = null;
	
	public static var storyMeta:StoryMeta = new StoryMeta();
	
	public static var isStoryMode:Bool = false;
	public static var isChallenge:Bool = false;
	
	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	
	public static var isPixelStage:Bool = false;
	
	/**
	 * Static reference to the state. used for other classes to reference
	 */
	public static var instance:Null<PlayState> = null;
	
	/**
	 * Helper function to ready PlayState for conveniently.
	 * 
	 * will return null if done successfully. Otherwise, the exception will be returned.
	 */
	public static function prepareForSong(songName:String, difficulty:Int = 1, isStoryMode:Bool = false):Null<haxe.Exception>
	{
		try
		{
			PlayState.SONG = Chart.fromSong(songName, difficulty);
			PlayState.storyMeta.difficulty = difficulty;
			PlayState.isStoryMode = isStoryMode;
			
			return null;
		}
		catch (e)
		{
			// Logger.log('Failed to prepare for song.\nException $e', ERROR);
			return e;
		}
	}
	
	/**
	 * Multiplier to the game speed
	 */
	public var playbackRate(default, set):Float = 1;
	
	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if (generatedMusic) audio.pitch = value;
		
		if (!paused) FlxG.timeScale = value;
		Conductor.safeZoneOffset = (ClientPrefs.safeFrames / 60) * 1000 * value;
		
		playbackRate = value;
		#else
		playbackRate = 1;
		#end
		return playbackRate;
	}
	
	public var volumeMult(default, set):Float = 1;
	
	function set_volumeMult(value:Float):Float
	{
		audio.volume *= (value / volumeMult);
		
		return volumeMult = value;
	}
	
	public var modManager:ModManager;
	public var modifiersRegistered:Bool = false;
	public var generatedFields:Bool = false;
	public var holdSubdivisions:Int = 1;
	
	var speedChanges:Array<SpeedEvent> = [{}];
	
	public var currentSV:SpeedEvent = {};
	
	public var modchartObjects:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	
	public var variables:Map<String, Dynamic> = new Map();
	
	public static var marathonModifiers:Array<MaraModifier> = [];
	
	/**
	 * Disables automatic camera movements if enabled.
	 */
	public var isCameraOnForcedPos:Bool = false;
	
	public var cameraLerping:Bool = true;
	
	/**
	 * Container of all boyfriend characters used in the state
	 * 
	 * Exists for the `Change Character` event.
	 */
	public var boyfriendGroup:CharacterGroup;
	
	/**
	 * Container of all dad characters used in the state
	 * 
	 * Exists for the `Change Character` event.
	 */
	public var dadGroup:CharacterGroup;
	
	/**
	 * Container of all gf characters used in the state
	 * 
	 * Exists for the `Change Character` event.
	 */
	public var gfGroup:CharacterGroup;
	
	/**
		Reference to the current dad
	**/
	public var dad:Character;
	
	/**
		Reference to the current girlfriend
	**/
	public var gf:Character;
	
	/**
		Reference to the current girlfriend
	**/
	public var boyfriend:Character;
	
	/**
		scary
	**/
	public var pet:Pet;
	
	/**
		Reference to the player stage X position
	**/
	public var BF_X:Float = 770;
	
	/**
		Reference to the player stage Y position
	**/
	public var BF_Y:Float = 100;
	
	/**
		Reference to the opponent stage X position
	**/
	public var DAD_X:Float = 100;
	
	/**
		Reference to the opponent stage Y position
	**/
	public var DAD_Y:Float = 100;
	
	/**
		Reference to the girlfriend stage X position
	**/
	public var GF_X:Float = 400;
	
	/**
		Reference to the girlfriend stage Y position
	**/
	public var GF_Y:Float = 130;
	
	/**
		Reference to the pet stage X position
	**/
	public var PET_X:Float = 0;
	
	/**
		Reference to the pet stage Y position
	**/
	public var PET_Y:Float = 0;
	
	/**
	 * A container of where all sprites placed
	 */
	public var stage:Stage;
	
	public var songSpeedTween:Null<FlxTween> = null;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;
	
	public var spawnTime:Float = 3000;
	
	/**
	 * Specialized container for song audio
	 */
	public var audio:PlayableSong;
	
	public var notes:FlxTypedGroup<Note>;
	public var queueNotes:Array<QueueNote> = [];
	public var eventNotes:Array<EventNote> = [];
	// Index pointers so we advance by pointer rather than O(n) shift().
	var _noteSpawnIdx:Int = 0;
	var _eventSpawnIdx:Int = 0;

	// Pre-allocated arg arrays to avoid per-frame heap allocation for script calls.
	final _scriptUpdateArgs:Array<Dynamic> = [0.0];
	final _scriptMoveCamArgs:Array<Dynamic> = [''];
	final _scriptEmptyArgs:Array<Dynamic> = [];
	final _scriptScoreArgs:Array<Dynamic> = [false];
	final _scriptKeyArgs:Array<Dynamic> = [0];
	final _scriptNoteArgs:Array<Dynamic> = [null];
	final _scriptNoteTypeExcl:Array<String> = [''];
	final _scriptRatingArgs:Array<Dynamic> = [null, null];
	final _scriptEventArgs:Array<Dynamic> = ['', '', ''];
	final _scriptEventTriggerArgs:Array<Dynamic> = ['', ''];
	final _scriptCountdownArgs:Array<Dynamic> = [0];

	/**
	 * Target the game camera follows
	 */
	var camFollow:FlxObject;
	
	/**
	 * Previous cameras target. used in story mode for a more seamless transition
	 */
	static var prevCamFollow:Null<FlxObject> = null;
	
	/**
	 * List of FlxCameras that follow camFollow
	**/
	public var followingCams:Array<FlxCamera> = [];
	
	/**
	 * Container of all strumline underlays
	 */
	public var underlays:Null<FlxTypedGroup<LaneUnderlay>> = null;
	
	/**
	 * Container of all strumlines in use
	 */
	public var playFields:Null<FlxTypedGroup<PlayField>> = null;
	
	/**
	 * The oppononents Strum field
	 */
	public var opponentStrums(get, never):Null<PlayField>;
	
	function get_opponentStrums()
	{
		for (i in playFields?.members)
			if (i.ID == 1) return i;
		return playFields?.members[1];
	}
	
	/**
	 * The players Strum field
	 */
	public var playerStrums(get, never):Null<PlayField>;
	
	function get_playerStrums()
	{
		for (i in playFields?.members)
			if (i.ID == 0) return i;
		return playFields?.members[0];
	}
	
	// i dont understand the need to change the ids tbh
	function getFieldFromID(id:Int):Null<PlayField>
	{
		for (i in playFields?.members)
			if (i.ID == id) return i;
		return playFields?.members[id];
	}
	
	@:isVar public var strumLineNotes(get, null):Array<StrumNote>;
	
	@:noCompletion function get_strumLineNotes()
	{
		final notes:Array<StrumNote> = [];
		if (playFields != null && playFields.length != 0)
		{
			for (field in playFields.members)
			{
				for (sturm in field.members)
					notes.push(sturm);
			}
		}
		return notes;
	}
	
	/**
	 * The container that all notesplashes are held in
	 */
	public var grpNoteSplashes:FlxTypedContainer<NoteSplash>;
	
	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	
	var curSong:String = "";
	
	/**
	 * The minimum and max bound that health can be within
	 */
	public var healthBounds:FlxBounds<Float> = new FlxBounds(0.0, 2.0);
	
	@:isVar public var health(default, set):Float = 1;
	
	@:noCompletion function set_health(value:Float):Float
	{
		health = value;
		callHUDFunc(hud -> hud.onHealthChange(value));
		return value;
	}
	
	var songPercent:Float = 0;
	
	public var combo:Int = 0;
	public var missCombo:Int = 0;
	public var ratingsData:Array<Rating> = [
		new Rating('sick'),
		new Rating('good'),
		new Rating('bad'),
		new Rating('shit')
	];
	
	public var epics:Int = 0;
	public var sicks:Int = 0;
	public var goods:Int = 0;
	public var bads:Int = 0;
	public var shits:Int = 0;
	
	var generatedMusic:Bool = false;
	
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	
	var updateTime:Bool = true;
	
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;
	public static var startOnTime:Float = 0;
	
	// Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;
	public var pressMissDamage:Float = .05;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled(default, set):Bool = false;
	public var practiceMode:Bool = false;
	
	public var botplayTxt:FlxText;
	
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;
	
	public var defaultScoreAddition:Bool = true;
	
	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;
	
	public var defaultCamZoomAdd:Float = 0;

	#if android
	// 60 frames (~1s at full rate), not 10 — a 10-frame window let a single
	// spike (~200ms) push the average over the activate threshold for one
	// frame, then immediately fall back under the deactivate threshold the
	// next frame once that spike aged out of the ring, so DRS was measured
	// flapping on/off within the same second on a real device (see sysmon.log
	// [DRS] on/off pairs one second apart) instead of staying engaged through
	// a genuinely slow section.
	static inline final DRS_RING_SIZE:Int = 60;
	var _drsRing:Array<Float> = [for (_ in 0...DRS_RING_SIZE) 1 / 60];
	var _drsRingIdx:Int = 0;
	var _drsActive:Bool = false;
	// Minimum active duration is a second line of defense against flapping,
	// since even a 60-frame average can dip below the deactivate threshold
	// for a frame or two during a brief lull inside an overall slow section.
	// Both this and the activate/deactivate fps thresholds are exposed as
	// ClientPrefs (Graphics settings) so they can be retuned in-game without
	// a new build if the defaults turn out not to be right for a given device.
	var _drsActivatedAt:Float = 0.0;
	#end

	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	/**
	 * Default camera zoom the game will attempt to return to.
	 *
	 * set via the Stage json
	 */
	public var defaultCamZoom:Float = 1.05;
	
	/**
	 * Default `camHUD` zoom the game will attempt to return to.
	 */
	public var defaultHudZoom:Float = 1;
	
	public var beatsPerZoom:Int = 0;
	
	var totalBeat:Int = 0;
	var totalShake:Int = 0;
	var timeBeat:Float = 1;
	var gameZ:Float = 0.015;
	var hudZ:Float = 0.03;
	var gameShake:Float = 0.003;
	var hudShake:Float = 0.003;
	var shakeTime:Bool = false;
	
	public var inCutscene:Bool = false;
	public var ingameCutscene:Bool = false;
	
	public var genNotesBeforeCountdown:Bool = true;
	
	public var skipCountdown:Bool = false;
	public var countdownSounds:Bool = true;
	public var countdownDelay:Float = 0;
	
	/**
	 * The length of the music track in miliseconds
	 * 
	 * Used for discord RPC and the time bar.
	 * 
	 * Can be manually changed.
	 */
	public var songLength:Float = 0;
	
	public var boyfriendCameraOffset:Array<Float> = [0, 0];
	public var opponentCameraOffset:Array<Float> = [0, 0];
	public var girlfriendCameraOffset:Array<Float> = [0, 0];
	
	/**
	 * The shown description in the discord RPC.
	 * 
	 * Can be manually changed.
	 */
	var rpcDescription:String = '';
	
	/**
	 * The shown paused Description in the discord RPC.
	 * 
	 * Can be manually changed.
	 */
	var rpcPausedDescription:String = '';
	
	/**
	 * The shown song name in the discord RPC.
	 * 
	 * Can be manually changed.
	 */
	var rpcSongName:String = '';
	
	/**
	 * Pause character portrait overwrite variable
	**/
	public var pauseOverwrite(get, set):String;
	
	public var pauseOverride:String = '';

	#if mobile
	private var mobilePauseBtn:FlxSprite;
	#end

	/**
	 * Variable that determines whether PlayState will automatically handle Discord RPC.
	 *
	 * Useful for if you want custom Discord RPC messages and PlayState gets in the way.
	**/
	public var automatedDiscord:Bool = true;
	
	/**
	 * Group of general scripts.
	 */
	public var scripts:ScriptGroup;
	
	/**
	 * Group of note type scripts. these have some special functions for their use
	 */
	public var noteTypeScripts:ScriptGroup;
	
	/**
	 * Group of event scripts. these have some special functions for their use
	 */
	public var eventScripts:ScriptGroup;
	
	public var arrowSkins:Array<String> = [];
	
	// ????
	public var script_NOTEOffsets:Vector<FlxPoint>;
	public var script_STRUMOffsets:Vector<FlxPoint>;
	public var script_SUSTAINOffsets:Vector<FlxPoint>;
	public var script_SUSTAINENDOffsets:Vector<FlxPoint>;
	
	public var introSoundsSuffix:String = '';
	
	// Debug buttons
	var debugKeysChart:Array<FlxKey>;
	var debugKeysCharacter:Array<FlxKey>;
	
	/**
	 * once set to a target, the camera will only follow them.
	 */
	public var camCurTarget:Null<Character> = null;
	
	public var playHUD:Null<BaseHUD> = null;
	
	/**
	 * Called when the Song should start
	 * 
	 * Change this to set custom behavior
	 * 
	 * Generally though your custom callback Should end with `startCountdown` to start the song
	 */
	public var songStartCallback:Null<Void->Void> = null;
	
	/**
	 * Called when the Song should end
	 * 
	 * Change this to set custom behavior
	 */
	public var songEndCallback:Null<Void->Void> = null;
	
	/*
	 * Niche impostor song specific vars
	 */
	public static var attackCharacter:Int = 0; // who ur playing as in monotone attack
	public static var totalMisses:Int = 0;
	public static var missLimit:Bool = false;
	
	public var allowBFSkin:Bool;
	public var allowGFSkin:Bool;
	public var allowPet:Bool;
	
	public var input:InputSystem;

	public var focusPlayer:Null<Character> = null;

	var tauntCharacter(get, set):Null<Character>;
	inline function get_tauntCharacter():Null<Character> return focusPlayer;
	inline function set_tauntCharacter(v:Null<Character>):Null<Character> return focusPlayer = v;

	inline function get_pauseOverwrite():String return pauseOverride;
	
	inline function set_pauseOverwrite(v:String):String return pauseOverride = v;
	
	@:noCompletion public function set_cpuControlled(val:Bool):Bool
	{
		if (playFields != null && playFields.members.length != 0)
		{
			for (field in playFields.members)
			{
				if (field.isPlayer) field.autoPlayed = val;
			}
		}
		return (cpuControlled = val);
	}
	
	function applyStageData(file:Null<StageFile>):Void
	{
		if (file == null) return;
		
		defaultCamZoom = file.defaultZoom;
		FlxG.camera.zoom = file.defaultZoom;
		isPixelStage = file.isPixelStage;
		
		BF_X = (file.boyfriend != null && file.boyfriend.length > 0) ? file.boyfriend[0] : 500;
		BF_Y = (file.boyfriend != null && file.boyfriend.length > 1) ? file.boyfriend[1] : 100;
		
		GF_X = (file.girlfriend != null && file.girlfriend.length > 0) ? file.girlfriend[0] : 0;
		GF_Y = (file.girlfriend != null && file.girlfriend.length > 1) ? file.girlfriend[1] : 100;
		
		DAD_X = (file.opponent != null && file.opponent.length > 0) ? file.opponent[0] : -500;
		DAD_Y = (file.opponent != null && file.opponent.length > 1) ? file.opponent[1] : 100;
		
		PET_X = (file.pet != null && file.pet.length > 0) ? file.pet[0] : (BF_X + 370);
		PET_Y = (file.pet != null && file.pet.length > 1) ? file.pet[1] : (BF_Y + 849);
		
		if (file.camera_speed != null) cameraSpeed = file.camera_speed;
		
		boyfriendCameraOffset = file.camera_boyfriend ?? [0, 0];
		
		opponentCameraOffset = file.camera_opponent ?? [0, 0];
		
		girlfriendCameraOffset = file.camera_girlfriend ?? [0, 0];
		
		boyfriendGroup ??= new CharacterGroup(BF_X, BF_Y, BF);
		dadGroup ??= new CharacterGroup(DAD_X, DAD_Y, DAD);
		gfGroup ??= new CharacterGroup(GF_X, GF_Y, GF);
		
		pet ??= new Pet('');
		pet.setPosition(PET_X, PET_Y);
		
		boyfriendGroup.zIndex = (file.bfZIndex ?? 0);
		dadGroup.zIndex = (file.dadZIndex ?? 0);
		gfGroup.zIndex = (file.gfZIndex ?? 0);
		pet.zIndex = (file.petZIndex ?? boyfriendGroup.zIndex);
	}
	
	// null checking
	function callHUDFunc(hud:BaseHUD->Void):Void if (playHUD != null) hud(playHUD);
	
	override public function create():Void
	{
		trace('[PlayState] ===== CREATE START =====');
		FlxG.sound.music?.stop();

		_bitmapSnapshotAtCreate = FunkinAssets.cache.snapshotBitmapKeys();

		FunkinAssets.cache.clearStoredMemory();
		
		funkin.backend.DebugDisplay.addPlugin(() -> 'curStep: $curStep • curBeat: $curBeat • curSection: $curSection');
		
		skipCountdown = false;
		countdownSounds = true;
		
		instance = this;
		
		GameOverSubstate.resetVariables();
		
		scripts = new ScriptGroup(this);
		eventScripts = new ScriptGroup(this);
		noteTypeScripts = new ScriptGroup(this);
		
		debugKeysChart = ClientPrefs.copyKey(ClientPrefs.keyBinds.get('debug_1'));
		debugKeysCharacter = ClientPrefs.copyKey(ClientPrefs.keyBinds.get('debug_2'));
		PauseSubState.songName = 'breakfast'; // Reset to default
		
		songStartCallback = startCountdown;
		songEndCallback = endSong;
		
		// If u have kutty enabled
		if (ClientPrefs.useEpicRankings) ratingsData.unshift(new Rating('epic'));
		
		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain', 1);
		healthLoss = ClientPrefs.getGameplaySetting('healthloss', 1);
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill', false);
		practiceMode = ClientPrefs.getGameplaySetting('practice', false);
		cpuControlled = ClientPrefs.getGameplaySetting('botplay', false);
		
		camGame = FlxG.camera;
		camHUD = new FlxCamera();
		camOther = new FlxCamera();

		camHUD.bgColor = 0x0;
		camOther.bgColor = 0x0;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);

		grpNoteSplashes = new FlxTypedContainer<NoteSplash>();
		
		persistentUpdate = true;
		persistentDraw = true;
		
		SONG ??= Chart.fromPath(Paths.json('test/test'));
		
		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;
		
		arrowSkins = SONG.arrowSkins;
		
		// set up rpc stuff
		rpcDescription = isStoryMode == true ? 'Story Mode' : 'Freeplay';
		rpcPausedDescription = 'Paused - ' + rpcDescription;
		rpcSongName = SONG.song;
		
		scripts.set('isStoryMode', isStoryMode);
		scripts.set('attackCharacter', attackCharacter);
		
		if (SONG.stage == null || SONG.stage.length == 0) SONG.stage = 'stage';
		
		// Check for bf/gf skins
		// SOMEONE GOT THE CODE WRONG IM GONNA FUCKING KILL YOUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU YOU'RE GOING TO DIE
		// i think it was me... im so sorry.
		allowBFSkin = (!isStoryMode && (SONG.allowBFskin ?? true));
		allowGFSkin = (!isStoryMode && (SONG.allowGFskin ?? true));
		allowPet = (!isStoryMode && (SONG.allowPet ?? true));
		
		trace('[PlayState] Creating stage (${SONG.stage})...');
		stage = new Stage(SONG.stage);
		trace('[PlayState] Stage created, applying data...');
		applyStageData(stage.stageData);

		trace('[PlayState] Building stage...');
		stage.buildStage();
		trace('[PlayState] Stage built OK');
		
		if (stage.runScript(scripts))
		{
			scripts.addScript(stage.script);

			Logger.log('script: ' + stage.script.name + ' intialized');
		}

		// Stage's own background layers all exist by now (added during
		// buildStage()/the script's onLoad() above) — safe to sample one for
		// the 'expand'-mode edge-of-camera fill color. No-op outside 'expand'.
		stage.fillExpandModeBackdrop(camGame);

		if (isPixelStage) introSoundsSuffix = '-pixel';
		
		if (!ScriptConstants.stopping(scripts.call("onAddSpriteGroups")))
		{
			add(stage);
			stage.add(gfGroup);
			stage.add(dadGroup);
			stage.add(boyfriendGroup);
			stage.add(pet);
		}
		
		inline function addSongScripts(directory)
		{
			for (file in Paths.listAllFilesInDirectory(directory, LOOSE).filter(path -> FunkinScript.isHxFile(path)))
			{
				final scriptPath = FunkinScript.getPath(file);
				
				initFunkinScript(file);
			}
		}
		addSongScripts('scripts');
		
		var gfVersion:String = SONG.gfVersion;
		if (gfVersion == null || gfVersion.length < 1) SONG.gfVersion = gfVersion = 'gf';
		
		if (allowPet)
		{
			trace('[PlayState] Loading pet...');
			pet.loadPet(ClientPrefs.equipment.get('pet'));
			checkStageFlag(pet);
			startPetScript(pet);
			trace('[PlayState] Pet loaded OK');
		}

		if (!stage.stageData.hide_girlfriend)
		{
			trace('[PlayState] Creating girlfriend...');
			gf = new Character((allowGFSkin ? ClientPrefs.equipment.get('speakerSkin') : null) ?? gfVersion);
			trace('[PlayState] GF created, loading animations...');
			checkStageFlag(gf);
			gfGroup.addChar(gf);
			gfGroup.parent = gf;
			startCharacterScript(gf.curCharacter, gf);
			trace('[DEBUG] GF Created: visible=${gf.visible}, alpha=${gf.alpha}, x=${gf.x}, y=${gf.y}');
		}

		trace('[PlayState] Creating dad (${SONG.player2})...');
		dad = new Character(SONG.player2);
		trace('[PlayState] Dad created, loading animations...');
		checkStageFlag(dad);
		dadGroup.addChar(dad);
		dadGroup.parent = dad;
		startCharacterScript(dad.curCharacter, dad);
		trace('[PlayState] Dad OK');

		trace('[PlayState] Creating boyfriend...');
		boyfriend = new Character((allowBFSkin ? ClientPrefs.equipment.get('playerSkin') : null) ?? SONG.player1, true);
		trace('[PlayState] BF created, loading animations...');
		checkStageFlag(boyfriend);
		boyfriendGroup.addChar(boyfriend);
		boyfriendGroup.parent = boyfriend;
		startCharacterScript(boyfriend.curCharacter, boyfriend);
		trace('[PlayState] BF OK');
		
		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if (gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}
		else
		{
			camPos.set(opponentCameraOffset[0], opponentCameraOffset[1]);
			camPos.x += dad.getGraphicMidpoint().x + dad.cameraPosition[0];
			camPos.y += dad.getGraphicMidpoint().y + dad.cameraPosition[1];
		}
		
		if (dad.curCharacter.startsWith('gf'))
		{
			dad.setPosition(GF_X, GF_Y);
			if (gf != null) gf.visible = false;
		}
		
		Conductor.songPosition = -5000;
		
		underlays = new FlxTypedGroup<LaneUnderlay>();
		
		playFields = new FlxTypedGroup<PlayField>();
		add(playFields);
		
		notes = new FlxTypedGroup<Note>();
		add(notes);
		
		playHUD = new funkin.game.huds.PsychHUD(this);
		insert(members.indexOf(playFields), playHUD); // Data told me to do this
		playHUD.cameras = [camHUD];
		
		playHUD.insert(playHUD.underlayOrder, underlays);
		
		meta = Metadata.getSong();
		
		modManager = new ModManager(this);
		
		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();
		
		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		
		add(camFollow);
		
		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();
		
		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		
		botplayTxt = new FlxText(400, 55, FlxG.width - 800, "BOTPLAY", 32);
		botplayTxt.setFormat(Paths.DEFAULT_FONT, 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		
		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = cpuControlled;
		if (ClientPrefs.downScroll) botplayTxt.y = FlxG.height - botplayTxt.height - 55;
		add(botplayTxt);
		
		notes.cameras = [camHUD];
		playFields.cameras = [camHUD];
		botplayTxt.cameras = [camHUD];
		
		addSongScripts('songs/${Paths.sanitize(SONG.song)}/');
		addSongScripts('songs/${Paths.sanitize(SONG.song)}/scripts/');

		#if mobile
		addMobileControls(false, true);
		if (hitbox != null) hitbox.visible = false;
		if (virtualPad != null) virtualPad.visible = false;

		mobilePauseBtn = new FlxSprite();
		mobilePauseBtn.makeGraphic(55, 55, 0x88000000);
		mobilePauseBtn.x = FlxG.width - mobilePauseBtn.width - 5;
		mobilePauseBtn.y = 5;
		mobilePauseBtn.scrollFactor.set();
		mobilePauseBtn.cameras = [camHUD];
		add(mobilePauseBtn);

		var _pauseLabel = new FlxText(mobilePauseBtn.x, mobilePauseBtn.y + 9, Std.int(mobilePauseBtn.width), 'II', 26);
		_pauseLabel.setFormat(null, 26, FlxColor.WHITE, FlxTextAlign.CENTER);
		_pauseLabel.scrollFactor.set();
		_pauseLabel.cameras = [camHUD];
		add(_pauseLabel);
		#end

		scripts.call('preNoteGeneration', _scriptEmptyArgs);
		
		if (genNotesBeforeCountdown) generatePlayfields();
		generateSong(SONG.song);
		
		if (!ClientPrefs.opponentStrums || ClientPrefs.middleScroll)
		{
			for (playField in playFields)
			{
				if (playField.isPlayer)
				{
					if (ClientPrefs.middleScroll) modManager.setValue('opponentSwap', .5, playField.ID);
					
					continue;
				}
				
				playField.visible = false;
				
				modManager.setValue('alpha', 1, playField.ID);
			}
		}
		
		if (!ClientPrefs.opponentLaneUnderlay)
		{
			for (i => playField in playFields)
			{
				if (playField.isPlayer) continue;
				
				playField.underlay.kill();
			}
		}
		
		#if FLX_DEBUG
		FlxG.watch.addFunction('Conductor: ', () -> Conductor.songPosition);
		FlxG.watch.addFunction('SongTime: ', () -> FlxStringUtil.formatTime(Conductor.songPosition / 1000)
			+ ' / '
			+ FlxStringUtil.formatTime(audio.songLength / 1000));
			
		FlxG.watch.addFunction('curSec: ', () -> curSection);
		FlxG.watch.addFunction('curBeat: ', () -> curBeat);
		FlxG.watch.addFunction('curStep: ', () -> curStep);
		#end
		
		moveCameraSection();
		
		noteTypeMap?.clear();
		noteTypeMap = null;
		
		audio?.stop();
		
		startingSong = true;
		
		if (songStartCallback == null)
		{
			FlxG.log.error('songStartCallback is null! using default callback.');
			songStartCallback = startCountdown;
		}
		
		songStartCallback();
		
		RecalculateRating();
		updateScoreBar();
		
		if (ClientPrefs.hitsoundVolume > 0) Paths.sound('hitsound');
		Paths.sound('missnote1');
		Paths.sound('missnote2');
		Paths.sound('missnote3');
		Paths.music(Paths.sanitize('breakfast'));
		
		// Updating Discord Rich Presence.
		resetDiscordRPC();
		
		input = new InputSystem(controls);
		input.addEventListener(InputEvent.INPUT_PRESSED, onInputPress);
		input.addEventListener(InputEvent.INPUT_RELEASED, onInputRelease);
		
		Conductor.safeZoneOffset = (ClientPrefs.safeFrames / 60) * 1000;
		
		scripts.call('onCreatePost', _scriptEmptyArgs);

		callHUDFunc(hud -> hud.cachePopUpScore());

		trace('[PlayState] Calling super.create()...');
		super.create();
		trace('[PlayState] super.create() OK');

		FunkinAssets.cache.clearUnusedMemory();

		refreshZ(stage);
		trace('[PlayState] ===== CREATE END (success) =====');
	}
	
	function set_songSpeed(value:Float):Float
	{
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrotchet, 350 / songSpeed * playbackRate);
		return value;
	}
	
	public function addCharacterToList(newCharacter:String, type:Int):Void
	{
		final group = switch (type)
		{
			case 1:
				dadGroup;
			case 2:
				(gf != null ? gfGroup : dadGroup);
			default:
				boyfriendGroup;
		}
		
		final newCharacter = group.addToList(newCharacter);
		startCharacterScript(newCharacter.curCharacter, newCharacter);
	}
	
	function startCharacterScript(name:String, char:Character):Void
	{
		var hscriptPath = FunkinScript.getPath('data/characters/$name', LOOSE);
		if (!FunkinAssets.exists(hscriptPath, TEXT)) hscriptPath = FunkinScript.getPath('characters/$name', LOOSE);
		
		if (FunkinAssets.exists(hscriptPath, TEXT))
		{
			var script = initFunkinScript(hscriptPath, null, false);
			
			script?.set('parent', char);
			
			if (script?.exists('onLoad')) script.call('onLoad');
		}
	}
	
	function startPetScript(pet:Pet):Void
	{
		final name:String = pet.curPet;
		
		var hscriptPath = FunkinScript.getPath('data/pets/$name', LOOSE);
		if (!FunkinAssets.exists(hscriptPath, TEXT)) hscriptPath = FunkinScript.getPath('pets/$name', LOOSE);
		
		if (FunkinAssets.exists(hscriptPath, TEXT))
		{
			var script = initFunkinScript(hscriptPath, null, false);
			
			script?.set('parent', pet);
			
			if (script?.exists('onLoad')) script.call('onLoad');
		}
	}
	
	/**
	 * Creates a new `FunkinScript` from filepath and calls `onLoad`. Returns `null` if it couldnt be found
	 * @param name sets a custom name to the script
	 */
	public function initFunkinScript(filePath:String, ?name:String, autoOnLoad:Bool = true, unique:Bool = true):Null<FunkinScript>
	{
		var name:String = (name ?? filePath);
		
		if (scripts.exists(name))
		{
			if (!unique)
			{
				var c:Int = 1;
				
				while (scripts.exists('${name}_$c'))
					c++;
					
				name += '_$c';
			}
			else
			{
				return null;
			}
		}
		
		var script:FunkinScript = FunkinScript.fromFile(filePath, name, null, scripts.scriptShareables);
		if (script.__garbage)
		{
			script = FlxDestroyUtil.destroy(script);
			return null;
		}
		Logger.log('script: ' + filePath + ' intialized');
		if (autoOnLoad && script.exists('onLoad')) script.call('onLoad');
		scripts.addScript(script);
		return script;
	}
	
	public function getModchartObject(tag:String):Dynamic
	{
		if (variables.exists(tag)) return variables.get(tag);
		if (modchartObjects.exists(tag)) return modchartObjects.get(tag);
		return null;
	}
	
	function checkStageFlag(guy:IFlags):Void
	{
		var variants:Null<haxe.DynamicAccess<String>> = guy.getFlag('variants');
		if (variants == null) return;
		
		for (flag => variant in variants)
		{
			if (!stage.getFlag(flag) && (SONG.flags == null || !SONG.flags.get(flag))) continue;
			
			if (guy is Character)
			{
				cast(guy, Character).loadCharacter(variant);
			}
			else if (guy is Pet)
			{
				cast(guy, Pet).loadPet(variant);
			}
			
			return;
		}
	}
	
	function startCharacterPos(?char:Character, gfCheck:Bool = false):Void
	{
		if (char == null) return;
		
		if (gfCheck && char.curCharacter.startsWith('gf'))
		{ // IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}
	
	public function startVideo(name:String):Void
	{
		#if VIDEOS_ALLOWED
		final fileName = Paths.video(name);
		
		if (FunkinAssets.exists(fileName, BINARY))
		{
			inCutscene = true;
			var bg = new flixel.system.FlxBGSprite();
			bg.scrollFactor.set();
			bg.cameras = [camHUD];
			add(bg);
			
			var vid = new FlxVideo();
			FlxG.addChildBelowMouse(vid);
			vid.onEndReached.add(() -> {
				remove(bg);
				startAndEnd();
				
				FlxG.removeChild(vid);
				vid.dispose();
			});
			vid.load(fileName);
			vid.play();
			return;
		}
		else
		{
			FlxG.log.warn('Couldnt find video file: ' + fileName);
			startAndEnd();
		}
		#else
		startAndEnd();
		#end
	}
	
	inline function startAndEnd():Void
	{
		endingSong ? endSong() : startCountdown();
	}
	
	public function generatePlayfields()
	{
		if (generatedFields) return;
		
		if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

		Note.swagWidth = 160 * 0.7;
		// Plain, unscaled Funkin original VSlice values (STRUMLINE_SIZE=104, NOTE_SPACING=112,
		// scale 1.0) — no separate "match the touch hitbox" scale-up. On mobile the touch
		// hitbox instead tracks these exact receptor positions (see addMobileControls()),
		// so there's no fixed-size zone for the visuals to match in the first place.
		funkin.objects.note.StrumNote.spacingScale = 1.0;
		final _isVSlice = (ClientPrefs.noteLayout == 'VSlice');
		if (_isVSlice)
		{
			Note.swagWidth = funkin.objects.note.StrumNote.STRUMLINE_SIZE; // 104
			// Shared with MobileHitbox's VSLICE_MATCH layout so the touch zones it
			// builds (before these playfields even exist) land exactly here.
			modManager.vsliceBaseY = funkin.objects.note.StrumNote.getVSliceBaseY();
		}

		for (lane in 0...SONG.lanes)
		{
			final character = (lane == 1 ? dad : boyfriend);
			final isPlayer = (lane != 1);

			final auto = (lane != 0 || cpuControlled);

			// For VSlice, center the receptors on screen (getCenteredXPos already applies spacingScale)
			var baseX:Float = _isVSlice ? funkin.objects.note.StrumNote.getCenteredXPos(0) : 0;

			var strums = new PlayField(baseX, _isVSlice ? modManager.vsliceBaseY : 0, SONG.keys, character, isPlayer, auto, lane, arrowSkins[lane]);
			// strums.scale = NoteUtil.getSkinFromID(lane).scale;
			if (_isVSlice && lane == 0)
			{
				// noteScale defaults to 0.7 (our engine-wide default), leaving falling notes
				// visually smaller than the 104px VSlice receptor they're meant to match.
				strums._skin.receptorScale = 1.0;
				strums._skin.noteScale = 1.0;
			}
			scripts.call('preReceptorGeneration', [strums, lane]);
			strums.generateReceptors();
			strums.ID = lane;

			// In VSlice, only show player lanes (like Funkin original)
			// Opponent notes are hidden to avoid visual clutter
			if (_isVSlice && lane != 0)
			{
				strums.visible = false;
				strums.underlay.visible = false;
			}

			playFields.add(strums);
			underlays.add(strums.underlay);
			
			strums.onNoteHit.add((note, field) -> {
				#if android SystemMonitor.profBegin('hitFocus'); #end
				setFocusPlayerFromNote(note);
				#if android SystemMonitor.profEnd(); #end

				if (field.ID == 1) camZooming = true;

				#if android SystemMonitor.profBegin('hitAudioSfx'); #end
				if (field.playerControls || (!audio.splitVocals && !audio.trackSwap)) audio.hit();
				#if android SystemMonitor.profEnd(); #end

				if (field.playerControls && field.showRatings && !note.isSustainNote)
				{
					combo++;
					#if android SystemMonitor.profBegin('hitPopUp'); #end
					popUpScore(note);
					#if android SystemMonitor.profEnd(); #end
				}
			});
			strums.onNoteMiss.add((note, field) -> {
				setFocusPlayerFromNote(note);

				if (note.canMiss || !field.playerControls) return;
				
				audio.miss();
				if (instakillOnMiss) doDeathCheck(true);
				if (!practiceMode) songScore -= 10;
				
				totalPlayed++;
				songMisses++;
				breakCombo();
				
				if (songMisses > totalMisses && missLimit) doDeathCheck(true);
				
				RecalculateRating(true);
			});
			strums.onMissPress.add((key, field) -> {
				if (!field.playerControls) return;
				
				audio.miss();
				if (instakillOnMiss) doDeathCheck(true);
				if (!practiceMode) songScore -= 10;
				
				if (!endingSong) songMisses++;
				totalPlayed++;
				breakCombo();
				
				if (songMisses > totalMisses && missLimit) doDeathCheck(true);
				
				RecalculateRating();
			});
			
			strums.showRatings = true;
			strums.noteSplashes = (lane == 0);
			
			final splashGrp = strums.splashLayer;
			splashGrp.camera = camHUD;
			splashLayering.push(splashGrp);
			
			for (strum in strums) strum.alpha = 0;
		}
		
		modManager.receptors = [for (i in playFields) i.members];
		
		modManager.lanes = SONG.lanes;
		modManager.keys = SONG.keys;
		
		generatedFields = true;
		scripts.call('postReceptorGeneration');
		
		modManager.registerEssentialModifiers();
		modManager.registerDefaultModifiers();
		modManager.registerScriptedModifiers();
		modifiersRegistered = true;
		
		scripts.call('postModifierRegister');
	}
	
	var startTimer:FlxTimer = null;
	var finishTimer:FlxTimer = null;
	
	public var countdownReady:Null<FlxSprite> = null;
	public var countdownSet:Null<FlxSprite> = null;
	public var countdownGo:Null<FlxSprite> = null;
	
	public function startCountdown():Void
	{
		if (startedCountdown)
		{
			scripts.call('onStartCountdown', _scriptEmptyArgs);
			return;
		}

		// Debug: log GF state at countdown start
		trace('[DEBUG] startCountdown: gf=${gf != null}, visible=${gf?.visible}, alpha=${gf?.alpha}, gfGroup.visible=${gfGroup.visible}, stage.zIndex=${stage.zIndex}, gfGroup.zIndex=${gfGroup.zIndex}');

		// Log loaded scripts and enable per-call timing to track lag culprits
		ScriptGroup.timingEnabled = true;
		final scriptNames = scripts.members.map(s -> s.name);
		final ntNames    = noteTypeScripts.members.map(s -> s.name);
		final evNames    = eventScripts.members.map(s -> s.name);
		trace('[ScriptPerf] LOADED scripts(${scriptNames.length}): ${scriptNames.join(", ")}');
		trace('[ScriptPerf] LOADED noteTypeScripts(${ntNames.length}): ${ntNames.join(", ")}');
		trace('[ScriptPerf] LOADED eventScripts(${evNames.length}): ${evNames.join(", ")}');
		
		inCutscene = false;

		#if mobile
		if (hitbox != null) hitbox.visible = true;
		if (virtualPad != null) virtualPad.visible = true;
		#end

		#if android
		mobile.backend.AndroidUtils.keepScreenOn(true);
		mobile.backend.AndroidUtils.setGameplayState(true);
		#end

		if (!ScriptConstants.stopping(scripts.call('onStartCountdown')))
		{
			// if its not 0 we can assume this was manually triggered
			if (!genNotesBeforeCountdown) generatePlayfields();
			
			new FlxTimer().start(countdownDelay, (t:FlxTimer) -> {
				startedCountdown = true;
				Conductor.songPosition = 0;
				Conductor.songPosition -= Conductor.crotchet * 5;
				scripts.call('onCountdownStarted', _scriptEmptyArgs);
				
				for (playField in playFields) playField.fadeIn((isStoryMode && !seenCutscene) || skipArrowStartTween);
				
				var swagCounter:Int = 0;
				
				if (startOnTime < 0) startOnTime = 0;
				
				if (startOnTime > 0)
				{
					clearNotesBefore(startOnTime);
					setSongTime(startOnTime - 350);
					return;
				}
				else if (skipCountdown)
				{
					setSongTime(0);
					return;
				}
				
				startTimer = new FlxTimer().start(Conductor.crotchet / 1000, function(tmr:FlxTimer) {
					if (swagCounter < 4) handleBoppers(tmr.loopsLeft);
					
					var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
					introAssets.set('default', ['ready', 'set', 'go']);
					introAssets.set('pixel', ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel']);
					
					var introAlts:Array<String> = introAssets.get('default');
					var antialias:Bool = ClientPrefs.globalAntialiasing;
					if (isPixelStage)
					{
						introAlts = introAssets.get('pixel');
						antialias = false;
					}
					
					switch (swagCounter)
					{
						case 0:
							if (countdownSounds) FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						case 1:
							countdownReady = makeCountdownSprite(introAlts[0]);
							insert(members.indexOf(notes), countdownReady);
							
							if (countdownSounds) FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						case 2:
							countdownSet = makeCountdownSprite(introAlts[1]);
							insert(members.indexOf(notes), countdownSet);
							
							if (countdownSounds) FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						case 3:
							countdownGo = makeCountdownSprite(introAlts[2]);
							
							insert(members.indexOf(notes), countdownGo);
							
							if (countdownSounds) FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
							
						case 4:
					}
					
					_scriptCountdownArgs[0] = swagCounter;
					scripts.call('onCountdownTick', _scriptCountdownArgs);
					
					swagCounter += 1;
				}, 5);
			});
		}
	}
	
	function makeCountdownSprite(path:String):FlxSprite
	{
		final spr = new FlxSprite().loadGraphic(Paths.image(path));
		spr.scrollFactor.set();
		spr.updateHitbox();
		
		if (PlayState.isPixelStage) spr.setGraphicSize(Std.int(spr.width * daPixelZoom));
		spr.screenCenter();
		spr.antialiasing = isPixelStage ? false : ClientPrefs.globalAntialiasing;
		
		spr.cameras = [camHUD];
		
		FlxTween.tween(spr, {alpha: 0}, Conductor.crotchet / 1000,
			{
				ease: FlxEase.cubeInOut,
				onComplete: function(twn:FlxTween) {
					remove(spr);
					spr.destroy();
				}
			});
		return spr;
	}
	
	public function addBehindGF(obj:FlxObject):Void
	{
		insert(members.indexOf(gfGroup), obj);
	}
	
	public function addBehindBF(obj:FlxObject):Void
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	
	public function addBehindDad(obj:FlxObject):Void
	{
		insert(members.indexOf(dadGroup), obj);
	}
	
	inline function disposeNote(note:Note):Void
	{
		note.kill();
		note.garbage = true;
		// NOT removed from `notes` — a killed-but-still-a-member note is
		// exactly what notes.recycle()'s getFirstAvailable() looks for
		// (first member with exists == false). Splicing it out here used to
		// permanently discard it from the pool, so every single note spawn
		// fell through to `new Note()` instead of reusing one — the pool
		// never actually pooled anything. Left in place, the group settles
		// at roughly the song's peak concurrent note count and spawns after
		// that point are real reuses.
	}

	/**
	 * Pool reuse (see disposeNote()) means the pool only stops allocating
	 * once it's grown to the song's peak concurrent note count — until
	 * then, the first time a dense burst pushes past the previous
	 * high-water mark, that burst pays for `new Note()` on every note over
	 * the old peak, synchronously, mid-song (this is exactly what caused
	 * the fps=15 spike the very first time "Danger"'s densest section hit,
	 * jumping the pool from 26 to 58 notes in one frame).
	 *
	 * Chart data (queueNotes, already fully built and sorted by strumTime
	 * at this point) is enough to compute that peak up front via a
	 * sweep-line over each note's [spawn, dispose) lifetime — spawn at the
	 * same `strumTime - spawnOffset` threshold the real spawn loop uses,
	 * dispose at the same `strumTime + sustainLength + noteKillOffset`
	 * threshold notesLoop uses to kill late/finished notes. Creating that
	 * many Note objects now, during the loading transition before the
	 * countdown starts, pays the exact same construction cost somewhere
	 * that doesn't show up as an in-song stutter.
	 */
	function prewarmNotePool():Void
	{
		final spawnOffset:Float = (spawnTime / songSpeed);

		final edges:Array<{t:Float, delta:Int}> = [];

		inline function addInterval(qn:QueueNote):Void
		{
			edges.push({t: qn.strumTime - spawnOffset, delta: 1});
			edges.push({t: qn.strumTime + qn.sustainLength + noteKillOffset, delta: -1});
		}

		for (qn in queueNotes)
		{
			addInterval(qn);
			if (qn.tail != null) for (tail in qn.tail) addInterval(tail);
		}

		edges.sort((a, b) -> a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));

		var concurrent:Int = 0, peakConcurrent:Int = 0;
		for (e in edges)
		{
			concurrent += e.delta;
			if (concurrent > peakConcurrent) peakConcurrent = concurrent;
		}

		for (i in notes.length...peakConcurrent)
		{
			final n:Note = new Note();
			n.kill();
			notes.add(n);
		}
	}

	#if android
	/**
	 * Dev-only measurement, no effect on real gameplay: times how long
	 * constructing one `Note` for every note THE WHOLE CHART will ever
	 * need (heads + every sustain segment, not just prewarmNotePool()'s
	 * peak-concurrency count) actually takes on this device. That's the
	 * number a full build-everything-upfront migration (matching Psych
	 * Mobile's generateSong(), which builds a real Note per chart note
	 * before the countdown starts) would have to pay during loading.
	 * Built into a throwaway local array and destroyed right after, so
	 * `notes`/`queueNotes`/the real pool are never touched.
	 */
	function benchmarkFullNoteConstruction():Void
	{
		var total:Int = 0;
		for (qn in queueNotes)
		{
			total++;
			if (qn.tail != null) total += qn.tail.length;
		}

		final built:Array<Note> = [];
		final startStamp:Float = haxe.Timer.stamp();
		for (i in 0...total) built.push(new Note());
		final elapsedMs:Float = (haxe.Timer.stamp() - startStamp) * 1000;

		for (n in built) n.destroy();

		final perNoteMs:Float = (total > 0 ? elapsedMs / total : 0);
		Logger.log('[NoteBuildBenchmark] song=$curSong totalNotes=$total (heads+sustain segments) elapsed=${Std.int(elapsedMs)}ms avg=${perNoteMs}ms/note -- cost of a full build-everything-upfront migration during loading, for reference only');
	}
	#end

	public function clearNotesBefore(time:Float):Void
	{
		// Advance the index past notes that are before `time`; compact lazily.
		while (_noteSpawnIdx < queueNotes.length && queueNotes[_noteSpawnIdx].strumTime - 350 < time)
			_noteSpawnIdx++;
		if (_noteSpawnIdx > 0) { queueNotes.splice(0, _noteSpawnIdx); _noteSpawnIdx = 0; }
			
		var i:Int = (notes.length - 1);
		while (i >= 0)
		{
			var daNote:Note = notes.members[i];
			if (daNote.strumTime - 350 < time) disposeNote(daNote);
			
			--i;
		}
	}
	
	public function setSongTime(time:Float):Void
	{
		if (time < 0) time = 0;
		
		audio.pause();
		audio.time = time;
		#if FLX_PITCH audio.pitch = playbackRate; #end
		audio.play();
		
		audio.hit();
		
		Conductor.songPosition = time;
	}
	
	function startSong():Void
	{
		startingSong = false;

		#if android
		SystemMonitor.resetGameplayTimer();
		#end

		audio.inst.onComplete = finishSong.bind(false);
		
		#if FLX_PITCH
		audio.pitch = playbackRate;
		#end
		
		if (startOnTime > 0) setSongTime(startOnTime - 500);
		startOnTime = 0;
		
		songLength = audio.songLength;
		
		audio.volume = 1 * volumeMult;
		audio.play();
		
		if (paused) audio.pause();
		
		// Updating Discord Rich Presence (with Time Left)
		if (automatedDiscord) DiscordClient.changePresence(rpcDescription, rpcSongName, null, true, songLength);
		
		scripts.call('onSongStart', _scriptEmptyArgs);
		callHUDFunc(hud -> hud.onSongStart());
	}
	
	var noteTypeMap:Map<String, Bool> = new Map<String, Bool>();
	var eventsPushed:Array<String> = [];
	var noteTypesPushed:Array<String> = [];
	
	var _parsedEvents:Null<Array<EventNote>> = null;
	
	/**
	 * makes an event note (internal)
	 */
	inline function makeEv(time:Float, ev:String, v1:String, v2:String)
	{
		final ev:EventNote =
			{
				strumTime: time + ClientPrefs.noteOffset,
				event: ev,
				value1: v1,
				value2: v2
			};
		return ev;
	}
	
	/**
	 * returns all events from both the loaded chart and events json
	 * 
	 * these are not sorted
	 */
	function getEventsDirect():Array<EventNote>
	{
		if (_parsedEvents != null) return _parsedEvents;
		
		final events:Array<EventNote> = [];
		
		final songName:String = Paths.sanitize(SONG.song);
		
		var file:String = Paths.json('$songName/data/events');
		
		if (FunkinAssets.exists(file))
		{
			final eventsData:Array<Dynamic> = Chart.fromPath(file).events;
			
			for (event in eventsData) // Event Notes
			{
				for (i in 0...event[1].length)
				{
					events.push(makeEv(event[0], event[1][i][0], event[1][i][1], event[1][i][2]));
				}
			}
		}
		
		for (event in SONG.events) // Event Notes
		{
			for (i in 0...event[1].length)
				events.push(makeEv(event[0], event[1][i][0], event[1][i][1], event[1][i][2]));
		}
		
		return (_parsedEvents = events);
	}
	
	function generateSong(dataPath:String):Void
	{
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype', 'multiplicative');
		
		songSpeed = SONG.speed;
		
		switch (songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed', 1);
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed', 1);
		}
		
		final songData = SONG;
		Conductor.bpm = songData.bpm;
		
		curSong = songData.song;
		
		audio = new PlayableSong();
		audio.populate(SONG);
		audio.hit();
		add(audio);
		
		#if FLX_PITCH
		audio.pitch = playbackRate;
		#end
		
		audio.volume = 0;
		
		scripts.set('vocals', audio);
		scripts.set('inst', audio.inst);
		
		// layering for notesplash stuff
		for (i in splashLayering)
			add(i);
			
		final noteData:Array<SongSection> = songData.notes;
		
		// loads note types
		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var type:Dynamic = songNotes[3];
				if (!Std.isOfType(type, String)) type = ChartEditorState.noteTypeList[type];
				
				if (!noteTypeMap.exists(type)) noteTypeMap.set(type, true);
			}
		}
		
		for (type in noteTypeMap.keys())
		{
			if (!noteTypesPushed.contains(type))
			{
				var baseScriptFile = 'data/notetypes/$type';
				if (!FunkinAssets.exists(FunkinScript.getPath(baseScriptFile), TEXT)) baseScriptFile = 'notetypes/$type';
				
				final scriptFile = FunkinScript.getPath(baseScriptFile);
				
				if (FunkinAssets.exists(scriptFile, TEXT)) noteTypeScripts.addScript(initFunkinScript(scriptFile, type));
				
				noteTypesPushed.push(type);
			}
		}
		
		var events = getEventsDirect();
		
		#if debug
		var cpuTime = Sys.time();
		#end
		
		if (ClientPrefs.inDevMode)
		{
			var crotchet:Float = (60000 / SONG.bpm), time:Float = 0;
			var allNotes:Array<Array<Dynamic>> = [];
			var sectionTimes:Array<{start:Float, end:Float}> = [];
			
			for (i => section in noteData)
			{
				if (section.changeBPM) crotchet = (60000 / section.bpm);
				
				var minTime:Float = time;
				time += (crotchet * (section.sectionBeats ?? 4));
				sectionTimes.push({start: minTime, end: time});
				
				for (songNotes in section.sectionNotes)
				{
					songNotes.push(i);
					allNotes.push(songNotes);
				}
				
				section.sectionNotes.resize(0);
			}
			
			allNotes.sort(function(a, b) return (a[0] > b[0] ? 1 : -1));
			
			final killDifference:Float = 3;
			
			var lastNotes:Array<Array<Dynamic>> = [for (_ in 0...songData.keys) null];
			var i:Int = 0, dupes:Int = 0, fixed:Int = 0;
			
			while (i < allNotes.length)
			{
				var note = allNotes[i++];
				
				if (note[1] >= 0)
				{
					var lastNote = lastNotes[note[1]];
					if (lastNote != null && Math.abs(lastNote[0] - note[0]) < killDifference)
					{
						dupes++;
						continue;
					}
					
					lastNotes[note[1]] = note;
				}
				
				var time:Float = (note[0] + 5);
				var oldSection:Int = note.pop();
				var trueSection:Int = Lambda.findIndex(sectionTimes, (section:{start:Float, end:Float}) -> (time >= section.start && time < section.end));
				
				if (trueSection == -1) trueSection == oldSection;
				
				if (trueSection != oldSection) fixed++;
				
				noteData[trueSection].sectionNotes.push(note);
			}
			
			if (fixed > 0 || dupes > 0) trace('corrected $fixed notes / removed $dupes duplicates');
		}
		
		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % SONG.keys);
				var playfield:Int = 0;
				
				playfield = Std.int(songNotes[1] / SONG.keys);
				
				if (playfield < 0) // legacy event notes
				{
					events.push(
						{
							strumTime: daStrumTime + ClientPrefs.noteOffset,
							event: songNotes[2],
							value1: songNotes[3],
							value2: songNotes[4]
						});
						
					continue;
				}
				
				if (playfield >= SONG.lanes) continue;
				
				var oldNote:Note = null;
				
				var type:Dynamic = songNotes[3];
				if (!Std.isOfType(type, String)) type = ChartEditorState.noteTypeList[type];
				
				var susLength:Float = songNotes[2];
				var swagNote = new QueueNote(daStrumTime, susLength, daNoteData, type, false, playfield);
				
				if (section.gfSection && playfield == (section.mustHitSection ? 0 : 1)) swagNote.gfNote = true;
				if ((section?.altAnim ?? false) && (type == '' || type == null)) swagNote.noteType = 'Alt Animation';
				
				queueNotes.push(swagNote);
				
				if (susLength > 0)
				{
					swagNote.tail = [];
					
					var susStep:Int = Std.int(Conductor.getStep(daStrumTime + 3)),
						endStep:Float = Conductor.getStep(daStrumTime + susLength);
						
					while (susStep < endStep)
					{
						var time:Float = Math.max(Conductor.stepToSeconds(susStep), daStrumTime);
						var length:Float = (Conductor.stepToSeconds(Math.min(susStep + 1, endStep)) - time);
						
						var sustainNote = new QueueNote(time, length, daNoteData, swagNote.noteType, true, playfield);
						sustainNote.gfNote = swagNote.gfNote;
						
						swagNote.tail.push(sustainNote);
						susStep++;
					}
					
					var time:Float = (daStrumTime + susLength);
					
					var sustainNote = new QueueNote(time, Conductor.getCrotchetAtTime(time) / 4, daNoteData, swagNote.noteType, true, playfield);
					sustainNote.gfNote = swagNote.gfNote;
					sustainNote.isSustainEnd = true;
					
					swagNote.tail.push(sustainNote);
				}
			}
		}
		
		for (event in events)
		{
			final eventName = event.event;
			
			if (!eventsPushed.contains(eventName))
			{
				var baseScriptFile:String = 'data/events/$eventName';
				if (!FunkinAssets.exists(FunkinScript.getPath(baseScriptFile), TEXT)) baseScriptFile = 'events/$eventName';
				
				final scriptFile = FunkinScript.getPath(baseScriptFile);
				
				if (FunkinAssets.exists(scriptFile, TEXT)) eventScripts.addScript(initFunkinScript(scriptFile, eventName));
				
				firstEventPush(event);
				
				eventsPushed.push(eventName);
			}
			
			event.strumTime -= eventNoteEarlyTrigger(event);
			eventNotes.push(event);
			eventPushed(event);
		}
		
		eventNotes.sort(function(a:EventNote, b:EventNote) return (a.strumTime > b.strumTime ? 1 : -1));
		queueNotes.sort(function(a:QueueNote, b:QueueNote) return (a.strumTime > b.strumTime ? 1 : -1));
		_noteSpawnIdx = 0;
		_eventSpawnIdx = 0;

		prewarmNotePool();

		#if android
		if (ClientPrefs.inDevMode) benchmarkFullNoteConstruction();
		#end

		speedChanges.sort(SortUtil.svSort);
		
		#if debug
		trace('loading chart took: ' + (Sys.time() - cpuTime));
		#end
		
		checkEventNote();
		generatedMusic = true;
	}
	
	public function getNoteInitialTime(time:Float):Float
	{
		return getTimeFromSV(time, getSV(time));
	}
	
	public inline function getTimeFromSV(time:Float, event:SpeedEvent):Float return event.position
		+ (modManager.getBaseVisPosD(time - event.songTime, 1) * event.speed);
		
	public function getSV(time:Float):SpeedEvent
	{
		// Reuse speedChanges[0] as the initial "best" instead of allocating a new SpeedEvent
		// on every frame.  speedChanges always starts with a default {} entry (startTime=0,
		// speed=1) so this is equivalent to the original logic for all valid song positions.
		var event:SpeedEvent = speedChanges[0];

		for (shit in speedChanges)
		{
			if (shit.startTime <= time && shit.startTime >= event.startTime)
			{
				if (shit.startSpeed == null) shit.startSpeed = event.speed;
				event = shit;
			}
		}

		return event;
	}
	
	public inline function getVisualPosition() return getTimeFromSV(Conductor.songPosition, currentSV);
	
	function eventPushed(event:EventNote):Void
	{
		switch (event.event)
		{
			case 'Mult SV' | 'Constant SV':
				var speed:Float = 1;
				if (event.event == 'Constant SV')
				{
					var b = Std.parseFloat(event.value1);
					speed = Math.isNaN(b) ? songSpeed : (songSpeed / b);
				}
				else
				{
					speed = Std.parseFloat(event.value1);
					if (Math.isNaN(speed)) speed = 1;
				}
				
				speedChanges.sort(SortUtil.svSort);
				speedChanges.push(
					{
						position: getNoteInitialTime(event.strumTime),
						songTime: event.strumTime,
						startTime: event.strumTime,
						speed: speed
					});
					
			case 'Change Noteskin':
				var fieldID:Int = 0;
				switch (event.value2.toLowerCase())
				{
					case 'dad' | 'opponent' | '1':
						fieldID = 1;
					default:
						fieldID = Std.parseInt(event.value1);
						if (Math.isNaN(fieldID)) fieldID = 0;
				}

				var skin = new NoteSkin(event.value1, SONG.keys, fieldID);

				// load the skin so game no lag when change le skin
				Paths.getAtlasFrames(skin.noteTexture);
				Paths.getAtlasFrames(skin.splashTexture);
				Paths.getAtlasFrames(skin.sustainSplashTexture);

				skin = FlxDestroyUtil.destroy(skin);

			case 'Change Character':
				var charType:Int = 0;
				switch (event.value1.toLowerCase())
				{
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						charType = Std.parseInt(event.value1);
						if (Math.isNaN(charType)) charType = 0;
				}
				
				addCharacterToList(event.value2, charType);
			default:
				callEventScript(event.event, 'onPush', [event]);
		}
		scripts.call('onEventPush', [event]);
	}
	
	function firstEventPush(event:EventNote):Void
	{
		switch (event.event)
		{
			default:
				callEventScript(event.event, 'onFirstPush', [event]);
		}
		scripts.call('onFirstEventPush', [event]);
	}
	
	function eventNoteEarlyTrigger(event:EventNote):Float
	{
		var returnValue:Dynamic = scripts.call('eventEarlyTrigger', [event.event, event.value1, event.value2]);
		if (returnValue != ScriptConstants.CONTINUE_FUNC) return returnValue;
		
		returnValue = callEventScript(event.event, 'offsetStrumTime', [event]);
		if (returnValue != ScriptConstants.CONTINUE_FUNC) return returnValue;
		
		switch (event.event)
		{
			case 'Kill Henchmen': // Better timing so that the kill sound matches the beat intended
				return 280; // Plays 280ms before the actual position
		}
		
		return 0;
	}
	
	public var skipArrowStartTween:Bool = false;
	
	var splashLayering:Array<Dynamic> = [];
	
	override function openSubState(SubState:FlxSubState):Void
	{
		if (paused)
		{
			if (audio != null) audio.pause();
			
			FlxTimer.globalManager.forEach((i:FlxTimer) -> if (!i.finished) i.active = false);
			FlxTween.globalManager.forEach((i:FlxTween) -> if (!i.finished) i.active = false);
			
			#if VIDEOS_ALLOWED
			FunkinVideoSprite.forEachAlive((video) -> if (video.tiedToGame) video.pause());
			FlxG.timeScale = 1;
			#end
			
			for (field in playFields?.members)
			{
				if (field.inControl && field.playerControls)
				{
					for (strum in field.members)
					{
						if (strum.animation.curAnim?.name != 'static')
						{
							strum.playAnim('static');
							strum.resetAnim = 0;
						}
					}
				}
			}
		}
		scripts.call('onSubstateOpen', _scriptEmptyArgs);
		super.openSubState(SubState);
	}
	
	override function closeSubState():Void
	{
		if (paused)
		{
			if (!startingSong)
			{
				audio.time = Conductor.songPosition;
				audio.play();
			}
			
			FlxTimer.globalManager.forEach((i:FlxTimer) -> if (!i.finished) i.active = true);
			FlxTween.globalManager.forEach((i:FlxTween) -> if (!i.finished) i.active = true);
			
			#if VIDEOS_ALLOWED
			FunkinVideoSprite.forEachAlive((video) -> if (video.tiedToGame) video.resume());
			#end
			
			paused = false;
					playbackRate = playbackRate;
			scripts.call('onResume', _scriptEmptyArgs);
			
			resetDiscordRPC(startTimer != null && startTimer.finished);
		}
		#if mobile controls.isInSubstate = false; #end
		scripts.call('onSubstateClose', _scriptEmptyArgs);
		super.closeSubState();
	}

	override public function onFocus():Void
	{
		if (health > 0 && !paused)
		{
			resetDiscordRPC(Conductor.songPosition > 0.0);
		}
		
		super.onFocus();
	}
	
	override public function onFocusLost():Void
	{
		if (health > 0 && !paused) resetDiscordRPC(false);
		
		super.onFocusLost();
	}
	
	/**
	 * Sets the Discord RPC to display the default in song descriptions.
	 * @param showTime if showTime, the RPC will show the current song progress.
	 */
	inline function resetDiscordRPC(showTime:Bool = false)
	{
		if (!showTime) DiscordClient.changePresence(rpcDescription, rpcSongName, dad.healthIcon);
		else DiscordClient.changePresence(rpcDescription, rpcSongName, dad.healthIcon, true, songLength - Conductor.songPosition - ClientPrefs.noteOffset);
	}
	
	function resyncVocals():Void
	{
		if (finishTimer != null) return;
		
		audio.pitch = playbackRate;
		audio.resync(audio.inst.time);
		Conductor.songPosition = audio.inst.time;
	}
	
	public var canAccessEditors:Bool = true;
	
	public var paused:Bool = false;
	public var canReset:Bool = true;
	
	var startedCountdown:Bool = false;
	var canPause:Bool = true;

	// Falling notes, receptors, splashes and the score/health HUD all render
	// through camHUD (see notes.cameras/playFields.cameras/playHUD.cameras
	// assignments in create()) — so if the actual bottleneck is draw-side
	// (sprite/shader draw calls) rather than update-side game logic, it'll
	// show up here and scale with exactly what's on screen, independent of
	// everything profiled inside update().
	override public function draw():Void
	{
		#if android SystemMonitor.profBegin('draw'); #end
		#if android final _gcBeforeDraw = SystemMonitor.gcUsageSnapshot(); #end
		super.draw();
		#if android SystemMonitor.profEnd(); #end
		#if android SystemMonitor.drawGcCollision(_gcBeforeDraw); #end
	}

	override public function update(elapsed:Float):Void
	{
		canPlayAwardSound = true;

		#if android
		_drsRing[_drsRingIdx % DRS_RING_SIZE] = elapsed;
		_drsRingIdx++;
		var _drsSum:Float = 0;
		for (t in _drsRing) _drsSum += t;
		final _drsAvg:Float = _drsSum / DRS_RING_SIZE;
		final _drsNow:Float = haxe.Timer.stamp();
		// drsForceAlwaysOn bypasses the fps-triggered logic entirely, so we can
		// test whether the frame-cache mechanism itself helps at all, isolated
		// from whether the threshold/timing tuning is right.
		if (ClientPrefs.drsForceAlwaysOn)
		{
			if (ClientPrefs.drsEnabled && !_drsActive)
				{ _drsActive = true; _drsActivatedAt = _drsNow; mobile.backend.DynamicResolution.setActive(true); }
			else if (!ClientPrefs.drsEnabled && _drsActive)
				{ _drsActive = false; mobile.backend.DynamicResolution.setActive(false); }
		}
		else
		{
			if (ClientPrefs.drsEnabled && !_drsActive && _drsAvg > 1 / ClientPrefs.drsActivateFps)
				{ _drsActive = true; _drsActivatedAt = _drsNow; mobile.backend.DynamicResolution.setActive(true); }
			else if (_drsActive && (_drsNow - _drsActivatedAt >= ClientPrefs.drsMinActiveSeconds) && (!ClientPrefs.drsEnabled || _drsAvg < 1 / ClientPrefs.drsDeactivateFps))
				{ _drsActive = false; mobile.backend.DynamicResolution.setActive(false); }
		}
		SystemMonitor.reportDrsState(_drsActive);
		#end

		if (cameraLerping && !inCutscene)
		{
			final lerpRate = 0.04 * cameraSpeed;
			FlxG.camera.followLerp = lerpRate;
		}
		
		if (generatedMusic && !endingSong && !isCameraOnForcedPos)
		{
			#if android SystemMonitor.profBegin('camera'); #end
			moveCameraSection();
			#if android SystemMonitor.profEnd(); #end
		}
		
		if (controls.PAUSE && startedCountdown && canPause)
		{
			if (!ScriptConstants.stopping(scripts.call('onPause'))) openPauseMenu();
		}

		#if android
		if (startedCountdown && canPause && FlxG.android.justReleased.BACK)
		{
			if (!ScriptConstants.stopping(scripts.call('onPause'))) openPauseMenu();
		}
		#end

		#if mobile
		if (startedCountdown && canPause)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch.justPressed)
				{
					var _tp = touch.getScreenPosition(camHUD);
					if (mobilePauseBtn.overlapsPoint(_tp, true, camHUD))
					{
						_tp.put();
						if (!ScriptConstants.stopping(scripts.call('onPause'))) openPauseMenu();
						break;
					}
					_tp.put();
				}
			}
		}
		#end

		#if mobile
		if (virtualPadCam != null) virtualPadCam.alpha = camHUD.alpha;
		if (hitboxCam != null) hitboxCam.alpha = camHUD.alpha;
		#end

		if (canAccessEditors && !endingSong && !inCutscene)
		{
			if (FlxG.keys.anyJustPressed(debugKeysChart)) openChartEditor();
			
			if (FlxG.keys.anyJustPressed(debugKeysCharacter)) openCharacterEditor();
		}
		
		if (health > healthBounds.max) health = healthBounds.max;
		
		if (startingSong)
		{
			if (startedCountdown)
			{
				Conductor.songPosition += (elapsed * 1000);
				
				if (Conductor.songPosition >= 0) startSong();
			}
		}
		else
		{
			Conductor.songPosition += (elapsed * 1000);
			
			if (Math.abs(getSongTime() - Conductor.songPosition) > 1000 / 60 / playbackRate) Conductor.songPosition = getSongTime();
			
			Conductor.lastSongPos = Conductor.songPosition;
		}
		
		currentSV = getSV(Conductor.songPosition);
		Conductor.visualPosition = getVisualPosition();
		
		if (!ClientPrefs.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong) health = 0;
		
		checkEventNote();
		
		if (modifiersRegistered)
		{
			modManager.updateTimeline(curDecStep);
			modManager.update(elapsed);
		}
		
		final spawnOffset:Float = (spawnTime / songSpeed);

		// Profiling this (previously untagged, hiding inside "unaccounted")
		// showed noteSpawn cost scaling hard with burst size (~800ms for a
		// 26-note burst). Root cause: disposeNote()/notesLoop used to splice
		// dead notes out of `notes` entirely, so notes.recycle() could never
		// find a reusable dead member — every single spawn fell through to
		// `new Note()` (full FlxSprite construction + a duplicate
		// _resetTexture() on top of the one preRecycle() already does) plus
		// a fresh RGBGraphics allocation, none of which "pooling" was
		// actually avoiding. Both are fixed now (see disposeNote()'s
		// comment, and NoteUtil.getCurColors()'s `into` param) — keeping
		// this tag to confirm the improvement on the next real build.
		#if android SystemMonitor.profBegin('noteSpawn'); #end
		while (_noteSpawnIdx < queueNotes.length && (queueNotes[_noteSpawnIdx].strumTime - Conductor.songPosition) < spawnOffset)
			recycleNote(queueNotes[_noteSpawnIdx++]);
		#if android SystemMonitor.profEnd(); #end

		var tempVector = funkin.backend.math.Vector3.get();
		
		final canUpdateModchart:Bool = (modifiersRegistered && playFields != null);
		
		inline function modchart(obj:Dynamic, id:Int, offsets:haxe.ds.Vector<FlxPoint>)
		{
			final pos = modManager.getPos(0, 0, 0, curDecBeat, obj.noteData, id, obj, tempVector);
			final offsets = (offsets != null ? offsets[obj.noteData] : null);
			
			modManager.updateObject(curDecBeat, obj, pos, id);
			
			obj.spriteOffset.set(offsets?.x, offsets?.y);
			
			return pos;
		}
		
		if (canUpdateModchart)
		{
			#if android SystemMonitor.profBegin('modchart'); #end
			for (playField in playFields)
			{
				final id = playField.ID, skin = playField._skin;

				// Plain loop instead of forEachAlive(function(strum) ...) — that
				// allocated a fresh closure (capturing id/skin) every frame, per
				// playField.
				for (strum in playField.members)
					if (strum != null && strum.exists && strum.alive)
						modchart(strum, id, skin.receptorOffsets);
			}
			#if android SystemMonitor.profEnd(); #end
		}

		if (generatedMusic)
		{
			#if android
			SystemMonitor.reportGameplayFrame(elapsed, SONG.song, Conductor.songPosition, notes.length, playFields != null ? playFields.length : 0);
			#end

			if (!inCutscene)
			{
				if (!cpuControlled)
				{
					#if android SystemMonitor.profBegin('keyShit'); #end
					keyShit();
					#if android SystemMonitor.profEnd(); #end
				}
				else
				{
					final _bfAnim = boyfriend.getAnimName();
					if (boyfriend.holdTimer > Conductor.stepCrotchet * 0.0011 * boyfriend.singDuration
						&& _bfAnim.startsWith('sing') && !_bfAnim.endsWith('miss'))
						boyfriend.dance(boyfriend.forceDance);
				}
			}
			
			#if android SystemMonitor.profBegin('notesLoop'); #end
			var i:Int = 0;
			while (i < notes.length)
			{
				var daNote = notes.members[i ++];

				// Dead notes are left in the group as pool fodder for
				// notes.recycle() (see disposeNote()'s comment) instead of
				// being spliced out — just skip them here.
				if (!daNote.alive) continue;
				
				final field = daNote.playField;

				// Hiding a PlayField (opponentStrums off, middleScroll, or VSlice's
				// always-hide-opponent) only ever hid the receptor group — the actual
				// falling notes live in their own `notes` group and kept rendering
				// regardless, which is why VSlice still showed the opponent's arrows
				// falling. Keep the notes in sync with their own field's visibility.
				daNote.visible = field.visible;

				if (field.inControl && field.autoPlayed)
				{
					if (!daNote.wasGoodHit && !daNote.ignoreNote && daNote.strumTime <= Conductor.songPosition) field.onNoteHit.dispatch(daNote, field);
				}
				
				// Kill extremely late notes and cause misses
				if (!daNote.tooLate && !daNote.wasGoodHit && daNote.isLate())
				{
					daNote.tooLate = true;
					
					if (!daNote.ignoreNote && !daNote.canMiss && !daNote.tailState.missed && (!daNote.isSustainNote || daNote.strum.coyoteTime <= 0) && !endingSong) field.onNoteMiss.dispatch(daNote,
						field);
				}
				
				if ((daNote.tooLate && Conductor.songPosition >= noteKillOffset + daNote.strumTime + daNote.sustainLength)
					|| (daNote.wasGoodHit && (Conductor.songPosition >= daNote.strumTime + daNote.sustainLength
						|| (daNote.isSustainEnd && daNote.clipRect != null && daNote.clipRect.height <= 0)))) field.disposeNote(daNote);
						
				if (!canUpdateModchart || !daNote.alive || !daNote.exists) {
					i --;
					continue;
				}
				
				// ok modchart stuff
				
				final skin = daNote.skin;
				
				final visPos = ((daNote.visualTime - Conductor.visualPosition) * songSpeed);
				final diff = (daNote.strumTime - Conductor.songPosition);
				
				final pos = modManager.getPos(daNote.strumTime, visPos, diff, curDecBeat, daNote.noteData, daNote.lane, daNote, tempVector);
				
				modManager.updateObject(curDecBeat, daNote, pos, daNote.lane);
				
				daNote.spriteOffset.x = (skin.noteOffsets[daNote.noteData].x + daNote.offsetX);
				daNote.spriteOffset.y = (skin.noteOffsets[daNote.noteData].y + daNote.offsetY);
				
				if (daNote.isSustainNote)
				{
					final futureSongPos = Conductor.getBeat(Conductor.songPosition + daNote.sustainLength);
					
					final visPos = ((daNote.visualTime + daNote.visualLength - Conductor.visualPosition) * songSpeed);
					final diff = (daNote.strumTime + daNote.sustainLength - Conductor.songPosition);
					
					var nextPos = modManager.getPos(daNote.strumTime + daNote.sustainLength, visPos, diff, Conductor.getBeat(futureSongPos), daNote.noteData, daNote.lane, daNote);
					
					final rad = Math.atan2(nextPos.y - pos.y, nextPos.x - pos.x);
					
					final deg = (rad * 180 / Math.PI);
					
					daNote.angle = (deg - 90);
					
					if (daNote.wasGoodHit && daNote.tailState?.splash != null && field.trackSustainSplashes) daNote.tailState.splash.angle = daNote.angle;
					
					daNote.spriteOffset.x += skin.sustainOffsets[daNote.noteData].x;
					daNote.spriteOffset.y += skin.sustainOffsets[daNote.noteData].y;
					if (daNote.isSustainEnd)
					{
						daNote.spriteOffset.x += skin.susEndOffsets[daNote.noteData].x;
						daNote.spriteOffset.y += skin.susEndOffsets[daNote.noteData].y;
					}
					else
					{
						final dist:Float = Math.sqrt(Math.pow(pos.y - nextPos.y, 2) + Math.pow(pos.x - nextPos.x, 2));
						
						daNote.scale.y = daNote.baseScale.y = (dist / (daNote.frameHeight - (daNote.antialiasing ? 1 : 0)));
					}
					
					daNote.clip(daNote.playField.members[daNote.noteData]);
					
					nextPos.put();
				}
			}
			#if android SystemMonitor.profEnd(); #end
		}

		if (canUpdateModchart)
		{
			#if android SystemMonitor.profBegin('modchart'); #end
			for (playField in playFields)
			{
				final id = playField.ID, skin = playField._skin;

				// Plain loops instead of forEachAlive(function(splash) ...) — same
				// per-frame closure-allocation reasoning as the receptor loop above.
				for (splash in playField.grpSusSplashes.members)
					if (splash != null && splash.exists && splash.alive)
						modchart(splash, id, skin.sustainSplashOffsets);

				if (playField.trackNoteSplashes)
					for (splash in playField.grpNoteSplashes.members)
						if (splash != null && splash.exists && splash.alive)
							modchart(splash, id, skin.splashOffsets);
			}
			#if android SystemMonitor.profEnd(); #end
		}

		tempVector.put();

		_scriptUpdateArgs[0] = elapsed;
		#if android SystemMonitor.profBegin('script'); #end
		scripts.call('onUpdate', _scriptUpdateArgs);
		#if android SystemMonitor.profEnd(); #end

		// super.update() ticks every member of this state (characters, notes,
		// receptors, HUD, particles) via their own FlxBasic.update() — none of
		// the phases profiled above cover this, and it's the single biggest
		// unaccounted chunk in every sample so far (profiled phases summed to
		// a small fraction of the real per-second frame budget).
		#if android SystemMonitor.profBegin('superUpdate'); #end
		super.update(elapsed);
		#if android SystemMonitor.profEnd(); #end

		#if android SystemMonitor.profBegin('inputUpdate'); #end
		input.update();
		#if android SystemMonitor.profEnd(); #end

		if (controls.NOTE_TAUNT_P && !inCutscene && !cpuControlled)
		{
			var focusPlayer:Character = (focusPlayer ?? boyfriend);
			if (focusPlayer.canTaunt && focusPlayer.hasAnim('hey'))
			{
				focusPlayer.playAnim('hey');
				focusPlayer.specialAnim = focusPlayer.holding = true;
			}
		}

		if (camZooming)
		{
			FlxG.camera.zoom = MathUtil.decayLerp(FlxG.camera.zoom, defaultCamZoom + defaultCamZoomAdd, 6.25 * camZoomingDecay, elapsed);
			camHUD.zoom = MathUtil.decayLerp(camHUD.zoom, defaultHudZoom, 6.25 * camZoomingDecay, elapsed);
		}
		
		doDeathCheck();
		
		for (i in followingCams)
		{
			i.zoom = FlxG.camera.zoom;
			i.scroll.copyFrom(FlxG.camera.scroll);
		}
		
		if (#if debug true || #end chartingMode || ClientPrefs.inDevMode)
		{
			if (!endingSong && !startingSong)
			{
				if (FlxG.keys.justPressed.ONE)
				{
					KillNotes();
					audio.inst.onComplete();
				}
				if (FlxG.keys.justPressed.TWO)
				{
					setSongTime(Conductor.songPosition + 10000);
					clearNotesBefore(Conductor.songPosition);
				}
			}
			if (FlxG.keys.justPressed.SIX)
			{
				cpuControlled = !cpuControlled;
				botplayTxt.visible = !botplayTxt.visible;
			}
		}
		
		scripts.call('onUpdatePost', _scriptUpdateArgs);
	}
	
	public function recycleNote(queueNote:QueueNote, ?parent:Note, ?prevNote:Note):Note
	{
		var note:Note = notes.recycle(Note, () -> new Note());
		
		note.preRecycle(queueNote, parent, prevNote);
		
		if (parent != null) return note;
		
		if (queueNote.tail != null)
		{
			final note:Note = spawnNote(note);
			
			if (note != null)
			{
				var prevNote:Note = note;
				
				for (tail in queueNote.tail)
				{
					final tail:Note = recycleNote(tail, note, prevNote);
					
					note.tail.push(tail);
					
					prevNote = tail;
				}
				
				for (tail in note.tail)
					spawnNote(tail);
			}
			
			return note;
		}
		else
		{
			return spawnNote(note);
		}
	}
	
	inline function spawnNote(note:Note):Null<Note>
	{
		note.postRecycle();

		_scriptNoteArgs[0] = note;
		_scriptNoteTypeExcl[0] = note.noteType;
		if (ScriptConstants.stopping(callNoteTypeScript(note.noteType, 'spawnNote', _scriptNoteArgs))
			|| ScriptConstants.stopping(scripts.call('onSpawnNote', _scriptNoteArgs, false, _scriptNoteTypeExcl)))
		{
			note.kill();
			
			return null;
		}
		
		final expectedPlayfield:Null<PlayField> = getFieldFromID(note.lane);
		
		if (expectedPlayfield == null)
		{
			note.kill();
			
			return null;
		}
		else if (expectedPlayfield.autoPlayed && note.strumTime <= Conductor.songPosition && !note.ignoreNote /* && !note.blockHit */)
		{
			expectedPlayfield.onNoteHit.dispatch(note, expectedPlayfield);
			note.kill();
			
			return null;
		}
		else if (!expectedPlayfield.autoPlayed && note.isLate() && !note.ignoreNote && !note.canMiss && !endingSong) // dont Even bother
		{
			expectedPlayfield.onNoteMiss.dispatch(note, expectedPlayfield);
			note.kill();
			
			return null;
		}
		else
		{
			expectedPlayfield.addNote(note);
			notes.remove(note, true);
			notes.insert(0, note);
			note.spawned = true;
			
			if (!ScriptConstants.stopping(callNoteTypeScript(note.noteType, 'postSpawnNote', _scriptNoteArgs))) scripts.call('onSpawnNotePost', _scriptNoteArgs, false, _scriptNoteTypeExcl);
			
			return note;
		}
	}
	
	function openPauseMenu():Void
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;
		
		audio?.pause();
		openSubState(new PauseSubState());
		
		if (automatedDiscord) DiscordClient.changePresence(rpcPausedDescription, rpcSongName);
	}
	
	function openChartEditor():Void
	{
		ChartEditorState._song = SONG;
		FlxG.camera.followLerp = 0;
		
		persistentUpdate = false;
		paused = true;
		CoolUtil.cancelMusicFadeTween();
		
		#if mobile
		FlxG.switchState(ChartEditorState.new);
		#else
		FlxG.switchState(FlxG.keys.pressed.SHIFT ? ChartEditorState.new : OLDChartEditorState.new);
		#end
		chartingMode = true;
		
		DiscordClient.changePresence('Chart Editor');
	}
	
	function openCharacterEditor():Void
	{
		FlxG.camera.followLerp = 0;
		
		persistentUpdate = false;
		paused = true;
		CoolUtil.cancelMusicFadeTween();
		
		disableModifiers();
		FlxG.switchState(() -> new CharacterEditorState(SONG.player2, true));
		
		DiscordClient.changePresence("Character Editor", null, null, true);
	}
	
	public function updateScoreBar(miss:Bool = false):Void
	{
		_scriptScoreArgs[0] = miss;
		if (!ScriptConstants.stopping(scripts.call('onUpdateScore', _scriptScoreArgs)))
		{
			callHUDFunc(hud -> hud.onUpdateScore(songScore, funkin.utils.MathUtil.floorDecimal(ratingPercent * 100, 2), songMisses, miss));

			ScriptConstants.stopping(scripts.call('onUpdateScorePost', _scriptScoreArgs));
		}
	}
	
	public var isDead:Bool = false;
	
	function doDeathCheck(instakill:Bool = false):Bool
	{
		final healthDeath:Bool = ((healthBounds.max > healthBounds.min && health <= healthBounds.min) || (healthBounds.min > healthBounds.max && health >= healthBounds.min));
		
		if ((instakill || healthDeath) && !practiceMode && !isDead)
		{
			if (!ScriptConstants.stopping(scripts.call('onGameOver')))
			{
				final char = playerStrums.owner;
				
				char.stunned = true;
				deathCounter++;
				
				paused = true;
				
				audio.stop();
				
				persistentUpdate = false;
				persistentDraw = false;
				
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				
				openSubState(new GameOverSubstate(char));
				
				// Game Over doesn't get his own variable because it's only used here
				if (automatedDiscord) DiscordClient.changePresence("Game Over - " + rpcDescription, rpcSongName);
				
				isDead = true;
				totalBeat = 0;
				return true;
			}
		}
		return false;
	}
	
	public function checkEventNote():Void
	{
		while (_eventSpawnIdx < eventNotes.length)
		{
			final leStrumTime:Float = eventNotes[_eventSpawnIdx].strumTime;

			if (Conductor.songPosition < leStrumTime) break;

			final value1:String = eventNotes[_eventSpawnIdx].value1 ?? '';
			final value2:String = eventNotes[_eventSpawnIdx].value2 ?? '';

			triggerEventNote(eventNotes[_eventSpawnIdx].event, value1, value2);
			_eventSpawnIdx++;
		}
	}
	
	function changeCharacter(name:String, charType:Int):Void
	{
		var prevChar:Null<Character> = null;
		
		var newChar:Character = switch (charType)
		{
			case 0:
				prevChar = boyfriend;
				boyfriend = boyfriendGroup.change(name);
				
			case 1:
				prevChar = dad;
				dad = dadGroup.change(name);
				
			case 2:
				prevChar = gf;
				(gf = gfGroup.change(name)).danceSpeed = prevChar.danceSpeed;
				gf;
			
			default:
				null;
		}
		
		for (field in playFields)
		{
			if (field.owner == prevChar) field.owner = newChar;
		}
		
		callHUDFunc(hud -> hud.onCharacterChange());
	}
	
	public function triggerEventNote(eventName:String, value1:String, value2:String):Void
	{
		switch (eventName)
		{
			case 'Hey!':
				var value:Int = 2;
				switch (value1.toLowerCase().trim())
				{
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}
				
				var time:Float = Std.parseFloat(value2);
				if (Math.isNaN(time) || time <= 0) time = 0.6;
				
				if (value != 0)
				{
					if (dad.curCharacter.startsWith('gf'))
					{ // Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnimForDuration('cheer', time);
						dad.specialAnim = true;
					}
					else if (gf != null)
					{
						gf.playAnimForDuration('cheer', time);
						gf.specialAnim = true;
					}
				}
				if (value != 1)
				{
					boyfriend.playAnimForDuration('hey', time);
					boyfriend.specialAnim = true;
				}
				
			case 'Set GF Speed':
				var value:Int = Std.parseInt(value1);
				if (Math.isNaN(value) || value < 1) value = 1;
				if (gf != null) gf.danceSpeed = value;
			case 'Add Camera Zoom':
				if (ClientPrefs.camZooms && FlxG.camera.zoom < 1.35)
				{
					var camZoom:Float = Std.parseFloat(value1);
					var hudZoom:Float = Std.parseFloat(value2);
					if (Math.isNaN(camZoom)) camZoom = 0.015;
					if (Math.isNaN(hudZoom)) hudZoom = 0.03;
					
					FlxG.camera.zoom += camZoom;
					camHUD.zoom += hudZoom;
				}
				
			case 'Camera Zoom':
				FlxTween.cancelTweensOf(FlxG.camera, ['zoom']);
				
				var val1:Float = Std.parseFloat(value1);
				if (Math.isNaN(val1)) val1 = 1;
				
				var targetZoom = defaultCamZoom * val1;
				if (value2 != '')
				{
					var split = value2.split(',');
					var duration:Float = 0;
					var leEase:String = 'linear';
					if (split[0] != null) duration = Std.parseFloat(split[0].trim());
					if (split[1] != null) leEase = split[1].trim();
					if (Math.isNaN(duration)) duration = 0;
					
					if (duration > 0) FlxTween.tween(FlxG.camera, {zoom: targetZoom}, duration, {ease: FlxEase.circOut});
					else FlxG.camera.zoom = targetZoom;
				}
				defaultCamZoom = targetZoom;
				
			case 'HUD Fade':
				FlxTween.cancelTweensOf(camHUD, ['alpha']);
				
				var leAlpha:Float = Std.parseFloat(value1);
				if (Math.isNaN(leAlpha)) leAlpha = 1;
				
				var duration:Float = Std.parseFloat(value2);
				if (Math.isNaN(duration)) duration = 1;
				
				if (duration > 0) FlxTween.tween(camHUD, {alpha: leAlpha}, duration);
				else camHUD.alpha = leAlpha;
			case 'Play Animation':
				var char:Character = dad;
				switch (value2.toLowerCase().trim())
				{
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						var val2:Int = Std.parseInt(value2);
						if (Math.isNaN(val2)) val2 = 0;
						
						switch (val2)
						{
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}
				
				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}
				
			case 'Camera Follow Pos':
				var val1:Float = Std.parseFloat(value1);
				var val2:Float = Std.parseFloat(value2);
				if (Math.isNaN(val1)) val1 = 0;
				if (Math.isNaN(val2)) val2 = 0;
				
				isCameraOnForcedPos = false;
				if (!Math.isNaN(Std.parseFloat(value1)) || !Math.isNaN(Std.parseFloat(value2)))
				{
					camFollow.x = val1;
					camFollow.y = val2;
					isCameraOnForcedPos = true;
				}
				
			case 'Alt Idle Animation':
				var char:Character = dad;
				switch (value1.toLowerCase())
				{
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if (Math.isNaN(val)) val = 0;
						
						switch (val)
						{
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}
				
				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}
				
			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length)
				{
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if (split[0] != null) duration = Std.parseFloat(split[0].trim());
					if (split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if (Math.isNaN(duration)) duration = 0;
					if (Math.isNaN(intensity)) intensity = 0;
					
					if (duration > 0 && intensity != 0) targetsArray[i].shake(intensity, duration);
				}
				
			case 'Change Character':
				var charType:Int = 0;
				switch (value1.toLowerCase())
				{
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if (Math.isNaN(charType)) charType = 0;
				}
				
				var curChar:Character = boyfriend;
				switch (charType)
				{
					case 2:
						curChar = gf;
					case 1:
						curChar = dad;
					case 0:
						curChar = boyfriend;
				}
				
				var newCharacter:String = value2;
				var anim:String = '';
				var frame:Int = 0;
				if (newCharacter.startsWith(curChar.curCharacter) || curChar.curCharacter.startsWith(newCharacter))
				{
					if (!curChar.isAnimNull())
					{
						anim = curChar.getAnimName();
						frame = curChar.animCurFrame;
					}
				}
				
				changeCharacter(value2, charType);
				if (anim != '')
				{
					var char:Character = boyfriend;
					switch (charType)
					{
						case 2:
							char = gf;
						case 1:
							char = dad;
						case 0:
							char = boyfriend;
					}
					
					if (!char.isAnimNull())
					{
						char.playAnim(anim, true);
						char.animCurFrame = frame;
					}
				}
			case 'Change Scroll Speed':
				if (songSpeedType == "constant") return;
				var val1:Float = Std.parseFloat(value1);
				var val2:Float = Std.parseFloat(value2);
				if (Math.isNaN(val1)) val1 = 1;
				if (Math.isNaN(val2)) val2 = 0;
				
				var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed', 1) * val1;
				
				if (val2 <= 0) songSpeed = newValue;
				else
				{
					songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, val2,
						{
							ease: FlxEase.linear,
							onComplete: function(twn:FlxTween) {
								songSpeedTween = null;
							}
						});
				}
				
			case 'Camera Zoom Chain':
				var split1:Array<String> = value1.split(',');
				var gameZoom:Float = Std.parseFloat(split1[0].trim());
				var hudZoom:Float = Std.parseFloat(split1[1].trim());
				
				if (!Math.isNaN(gameZoom)) gameZ = 0.015;
				if (!Math.isNaN(hudZoom)) hudZ = 0.03;
				
				if (split1.length == 4)
				{
					var shGame:Float = Std.parseFloat(split1[2].trim());
					var shHUD:Float = Std.parseFloat(split1[3].trim());
					
					if (!Math.isNaN(shGame)) gameShake = shGame;
					if (!Math.isNaN(shHUD)) hudShake = shHUD;
					shakeTime = true;
				}
				else shakeTime = false;
				
				var split2:Array<String> = value2.split(',');
				var toBeat:Int = Std.parseInt(split2[0].trim());
				var tiBeat:Float = Std.parseFloat(split2[1].trim());
				
				if (Math.isNaN(toBeat)) toBeat = 4;
				if (Math.isNaN(tiBeat)) tiBeat = 1;
				
				totalBeat = toBeat;
				timeBeat = tiBeat;
				
			case 'Screen Shake Chain':
				var split1:Array<String> = value1.split(',');
				var gmShake:Float = Std.parseFloat(split1[0].trim());
				var hdShake:Float = Std.parseFloat(split1[1].trim());
				
				if (!Math.isNaN(gmShake)) gameShake = gmShake;
				if (!Math.isNaN(hdShake)) hudShake = hdShake;
				
				var toBeat:Int = Std.parseInt(value2);
				if (!Math.isNaN(toBeat)) totalShake = 4;
				
				totalShake = toBeat;
				
			case 'Set Cam Zoom':
				defaultCamZoom = Std.parseFloat(value1);
				
			case 'Set Cam Pos':
				var split:Array<String> = value1.split(',');
				var xPos:Float = Std.parseFloat(split[0].trim());
				var yPos:Float = Std.parseFloat(split[1].trim());
				if (Math.isNaN(xPos)) xPos = 0;
				if (Math.isNaN(yPos)) yPos = 0;
				switch (value2)
				{
					case 'bf' | 'boyfriend':
						boyfriendCameraOffset[0] = xPos;
						boyfriendCameraOffset[1] = yPos;
					case 'gf' | 'girlfriend':
						girlfriendCameraOffset[0] = xPos;
						girlfriendCameraOffset[1] = yPos;
					case 'dad' | 'opponent':
						opponentCameraOffset[0] = xPos;
						opponentCameraOffset[1] = yPos;
				}
				
			case 'Set Property':
				try
				{
					var props:Array<String> = value1.split('.');
					if (props.length > 1) Reflect.setProperty(ReflectUtil.getPropertyLoop(props, true), props[props.length - 1], value2);
					else Reflect.setProperty(this, value1, value2);
				}
				catch (e)
				{
					Logger.log('Event [Set Property] failed Exception: ${e.toString()}', ERROR);
				}
		}
		
		_scriptEventArgs[0] = eventName; _scriptEventArgs[1] = value1; _scriptEventArgs[2] = value2;
		scripts.call('onEvent', _scriptEventArgs);

		_scriptEventTriggerArgs[0] = value1; _scriptEventTriggerArgs[1] = value2;
		callEventScript(eventName, 'onTrigger', _scriptEventTriggerArgs);
	}
	
	function moveCameraSection():Void
	{
		if (SONG.notes[curSection] == null) return;
		
		if (gf != null && SONG.notes[curSection].gfSection)
		{
			final gfMid = gf.getMidpoint();
			camFollow.setPosition(gfMid.x, gfMid.y);
			gfMid.put();
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			
			if (ClientPrefs.camFollowsCharacters)
			{
				final displacement = gf.getSingDisplacement();
				
				camFollow.x += displacement.x;
				camFollow.y += displacement.y;
				
				displacement.putWeak();
			}
			
			_scriptMoveCamArgs[0] = 'gf';
			scripts.call('onMoveCamera', _scriptMoveCamArgs);
			scripts.set('whosTurn', 'gf');
			return;
		}

		var isDad = !SONG.notes[curSection].mustHitSection;
		moveCamera(isDad);
		_scriptMoveCamArgs[0] = isDad ? 'dad' : 'boyfriend';
		scripts.call('onMoveCamera', _scriptMoveCamArgs);
	}
	
	public function getCharacterCameraPos(char:Null<Character>):FlxPoint
	{
		if (char == null) return FlxPoint.weak();
		
		final desiredPos = char.getMidpoint();
		
		final offsets = char.isPlayer ? boyfriendCameraOffset : opponentCameraOffset;
		
		desiredPos.y += -100 + char.cameraPosition[1] + offsets[1];
		
		if (char.isPlayer)
		{
			desiredPos.x -= 100 + char.cameraPosition[0];
		}
		else
		{
			desiredPos.x += 100 + char.cameraPosition[0];
		}
		
		desiredPos.x += offsets[0];
		
		return desiredPos;
	}
	
	public function moveCamera(isDad:Bool):Void
	{
		var desiredPos:Null<FlxPoint> = null;
		var curCharacter:Null<Character> = null;
		
		if (opponentStrums != null && playerStrums != null) curCharacter = isDad ? opponentStrums.owner : playerStrums.owner;
		else curCharacter = isDad ? dad : boyfriend;
		
		if (camCurTarget != null) curCharacter = camCurTarget;
		
		desiredPos = getCharacterCameraPos(curCharacter);
		
		camFollow.x = desiredPos.x;
		camFollow.y = desiredPos.y;
		
		if (ClientPrefs.camFollowsCharacters)
		{
			final displacement = curCharacter.getSingDisplacement();
			
			camFollow.x += displacement.x;
			camFollow.y += displacement.y;
			
			displacement.putWeak();
		}
		
		desiredPos.put();
		
		scripts.set('whosTurn', isDad ? 'dad' : 'boyfriend');
	}
	
	/**
	 * 'Snaps the camera to a position.'
	 * @param lockPosition 'if true, locks the camera position after snapping.'
	 */
	function snapCamToPos(x:Float = 0, y:Float = 0, lockPosition:Bool = false):Void
	{
		camFollow.setPosition(x, y);
		FlxG.camera.snapToTarget();
		if (lockPosition) isCameraOnForcedPos = true;
	}
	
	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		
		audio.volume = 0;
		audio.stop();
		audio.stopInst();
		
		if (songEndCallback == null)
		{
			FlxG.log.error('songEndCallback is null! using default callback.');
			songEndCallback = endSong;
		}
		
		if (ClientPrefs.noteOffset <= 0 || ignoreNoteOffset)
		{
			songEndCallback();
		}
		else
		{
			finishTimer = new FlxTimer().start(ClientPrefs.noteOffset / 1000, function(tmr:FlxTimer) {
				songEndCallback();
			});
		}
	}
	
	public var transitioning = false;
	
	public var popUpQueued:Int = 0;
	public var canPlayAwardSound:Bool = true;
	public var popUpEndCallback:Void->Void = null;
	
	public function endSong():Void
	{
		// Should kill you if you tried to cheat
		if (!startingSong)
		{
			notes.forEachAlive(function(daNote:Note) {
				if (daNote.strumTime < songLength - Conductor.safeZoneOffset) health -= 0.05 * healthLoss;
			});
			
			for (i in _noteSpawnIdx...queueNotes.length)
				if (queueNotes[i].strumTime < songLength - Conductor.safeZoneOffset) health -= 0.05 * healthLoss;
				
			if (doDeathCheck()) return;
		}
		
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		#if mobile
		if (hitbox != null) hitbox.visible = false;
		if (virtualPad != null) virtualPad.visible = false;
		#end

		deathCounter = 0;
		seenCutscene = false;
		
		disableModifiers();
		
		if (!ScriptConstants.stopping(scripts.call('onEndSong')) && !transitioning)
		{
			playbackRate = 1;
			var percent:Float = ratingPercent;
			if (Math.isNaN(percent)) percent = 0;
			Highscore.saveScore(SONG.song, songScore, storyMeta.difficulty, percent, songMisses);
			unlockJsonAwards(curSong);
			
			if (chartingMode)
			{
				openChartEditor();
				return;
			}
			
			if (isStoryMode || isChallenge)
			{
				storyMeta.score += songScore;
				storyMeta.misses += songMisses;
				
				storyMeta.playlist.remove(storyMeta.playlist[0]);
				
				if (storyMeta.playlist.length <= 0)
				{
					if (WeekData.weeksList[storyMeta.curWeek] != null)
					{
						unlockJsonAwards(curSong, [WeekData.weeksList[storyMeta.curWeek]]);
					}
					
					var popup:BeansPopup = new BeansPopup(Std.int(storyMeta.score / 600), storyMeta.currency);
					popup.camera = camOther;
					add(popup);
					
					popUpQueued++;
					popup.onFinish = dequeuePopup;
					
					popUpEndCallback = function() {
						removeModifiers();
						
						if (WeekData.weeksList[storyMeta.curWeek] != null)
						{
							if (!ClientPrefs.getGameplaySetting('practice', false) && !ClientPrefs.getGameplaySetting('botplay', false))
							{
								StoryMenuState.weekCompleted.set(WeekData.weeksList[storyMeta.curWeek], true);
								
								FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
								
								Highscore.saveWeekScore(WeekData.getWeekFileName(), storyMeta.score, storyMeta.difficulty);
							}
						}
						
						changedDifficulty = false;
						
						if (!ScriptConstants.stopping(scripts.call('postEndSong')))
						{
							FlxG.sound.playMusic(Paths.music('freakyMenu'));
							CoolUtil.cancelMusicFadeTween();
							
							FlxG.switchState(StoryMenuState.new);
						}
					}
				}
				else
				{
					prevCamFollow = camFollow;
					
					final difficulty:String = Difficulty.getDifficultyFilePath();
					final songLowercase = Paths.sanitize(storyMeta.playlist[0].toLowerCase());
					
					trace('LOADING: ' + Paths.sanitize(storyMeta.playlist[0]) + difficulty);
					
					PlayState.SONG = Chart.fromSong(songLowercase, PlayState.storyMeta.difficulty);
					
					popUpEndCallback = function() {
						if (!ScriptConstants.stopping(scripts.call('postEndSong')))
						{
							CoolUtil.cancelMusicFadeTween();
							FlxG.sound.music.stop();
							
							FlxG.switchState(PlayState.new);
						}
					}
				}
			}
			else
			{
				trace('WENT BACK TO FREEPLAY??');
				
				var popup:BeansPopup = new BeansPopup(Std.int(songScore / 600), funkin.data.CosmicubeData.currentCurrency);
				popup.camera = camOther;
				add(popup);
				
				popUpQueued++;
				popup.onFinish = dequeuePopup;
				
				popUpEndCallback = function() {
					CoolUtil.cancelMusicFadeTween();
					removeModifiers();
					
					if (!ScriptConstants.stopping(scripts.call('postEndSong')))
					{
						FlxG.sound.playMusic(Paths.music('freakyMenu'));
						changedDifficulty = false;
						
						FlxG.switchState(FreeplayState.new);
					}
				}
			}
			transitioning = true;
			
			if (popUpQueued == 0 && popUpEndCallback != null) popUpEndCallback();
		}
		
		audio.stop();
		audio.stopInst();
	}
	
	function dequeuePopup():Void
	{
		popUpQueued--;
		
		if (#if debug true || #end ClientPrefs.inDevMode) trace('$popUpQueued left');
		
		if (popUpQueued == 0 && popUpEndCallback != null) popUpEndCallback();
	}
	
	public function unlockAchievementPopup(id:String):Bool
	{
		if (ClientPrefs.getGameplaySetting('practice', false) || ClientPrefs.getGameplaySetting('botplay', false)) return false;
		if (!GameFlags.giveAchievement(id)) return false;
		
		popUpAchievement(id);
		
		return true;
	}
	
	public function unlockJsonAwards(?currentSong:String = null, ?extraCompletedWeeks:Array<String> = null):Int
	{
		if (ClientPrefs.getGameplaySetting('practice', false) || ClientPrefs.getGameplaySetting('botplay', false)) return 0;
		
		var unlockedCount:Int = 0;
		for (id in GameFlags.unlockAwardsFromJson(currentSong, extraCompletedWeeks))
		{
			popUpAchievement(id);
			unlockedCount++;
		}
		
		if (ProgressionUtil.checkSRanksAchievement())
		{
			unlockAchievementPopup('five_s_ranks');
			unlockedCount++;
		}
		if (ProgressionUtil.checkPAchievement())
		{
			unlockAchievementPopup('first_p');
			unlockedCount++;
		}
		if (ProgressionUtil.checkHundredAchievement())
		{
			unlockAchievementPopup('the_hundred');
			unlockedCount++;
		}
		
		return unlockedCount;
	}
	
	public inline function popUpAchievement(id:String):AwardPopup
	{
		var popUp:AwardPopup = new AwardPopup(id, canPlayAwardSound);
		popUp.camera = camOther;
		add(popUp);
		
		canPlayAwardSound = false;
		
		popUpQueued++;
		popUp.onFinish = dequeuePopup;
		
		return popUp;
	}
	
	public function KillNotes():Void
	{
		// disposeNote() no longer removes members from `notes` (see its
		// comment) so it can't be used to drain this to empty anymore —
		// this is a full teardown (song end/retry), so just kill everything
		// and wipe the group outright instead.
		for (note in notes.members)
			if (note != null) note.kill();
		notes.clear();

		queueNotes.resize(0);
		_noteSpawnIdx = 0;
		_eventSpawnIdx = 0;
		eventNotes.resize(0);
	}
	
	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;
	
	public var showCombo:Bool = true;
	public var showRating:Bool = true;
	
	function popUpScore(note:Note = null):Void
	{
		if (note.hitCausesMiss || note.canMiss) return;

		audio.playerVolume = 1 * volumeMult;

		final rating:Rating = note.ratingData;

		var field:PlayField = note.playField;

		#if android SystemMonitor.profBegin('popUpRating'); #end
		if (!practiceMode && !cpuControlled && !(field?.autoPlayed ?? false))
		{
			if (defaultScoreAddition) songScore += rating.score;
			if (!note.ratingDisabled)
			{
				songHits++;
				totalPlayed++;
				totalNotesHit += (note.ratingMod = rating.ratingMod);
				RecalculateRating(false);
				rating.increase();
			}
		}
		#if android SystemMonitor.profEnd(); #end

		_scriptRatingArgs[0] = note; _scriptRatingArgs[1] = rating;

		// Split so we can see which of these three is actually slow — onPopUpScorePost
		// in particular runs interpreted hscript (utils.hx defines it) on every hit.
		#if android SystemMonitor.profBegin('popUpScriptPre'); #end
		scripts.call('onPopUpScore', _scriptRatingArgs);
		#if android SystemMonitor.profEnd(); #end

		#if android SystemMonitor.profBegin('popUpHud'); #end
		callHUDFunc(hud -> hud.popUpScore(rating.image, combo)); // only pushing the image bc is anyone ever gonna need anything else???
		#if android SystemMonitor.profEnd(); #end

		#if android SystemMonitor.profBegin('popUpScriptPost'); #end
		scripts.call('onPopUpScorePost', _scriptRatingArgs);
		#if android SystemMonitor.profEnd(); #end
	}
	
	public inline function getSongTime():Float
	{
		if (audio.inst?.playing)
		{
			return Math.max(@:privateAccess audio.inst._channel.position, audio.inst.time);
		}
		else
		{
			return Conductor.songPosition;
		}
	}
	
	function onInputPress(event:InputEvent):Void
	{
		if (cpuControlled || paused || !startedCountdown) return;

		#if android SystemMonitor.profBegin('hitProcess'); #end

		final key:Int = event.noteData;

		var prevTime:Float = getSongTime();
		Conductor.songPosition -= (lime.system.System.getTimer() - event.timer);
		
		if (generatedMusic && !endingSong)
		{
			var anyInput:Bool = false;
			var ghostTapped:Bool = true;
			
			for (field in playFields.members)
			{
				if (!field.canInput()) continue;
				
				anyInput = true;
				
				final topNote:Null<Note> = field.getBestTapNote(key);
				// If no tap note but a sustain note is present, suppress ghost tap penalty.
				if (topNote == null)
				{
					for (note in field.notes)
					{
						if (note.alive && note.isSustainNote && note.noteData == key && note.canBeHit && !note.tooLate)
						{ ghostTapped = false; break; }
					}
				}
				
				if (topNote != null)
				{
					#if android
					final _gcBefore = SystemMonitor.gcUsageSnapshot();
					SystemMonitor.profBegin('noteHitDispatch');
					#end
					field.onNoteHit.dispatch(topNote, field);
					#if android
					SystemMonitor.profEnd();
					SystemMonitor.noteGcCollision(_gcBefore);
					#end

					ghostTapped = false;
				}
				else if (field.playAnims)
				{
					var strum = field.members[key];
					
					if (strum != null)
					{
						strum.playAnim('pressed');
						strum.resetAnim = 0;
					}
				}
			}
			
			if (ghostTapped && anyInput)
			{
				_scriptKeyArgs[0] = key;
				scripts.call('onGhostTap', _scriptKeyArgs);

				if (!ClientPrefs.ghostTapping)
				{
					for (field in playFields.members)
					{
						if (field.canInput()) field.onMissPress.dispatch(key, field);
					}
					if (!ScriptConstants.stopping(scripts.call('noteMissPress', _scriptKeyArgs)))
					{
						health -= (healthLoss * pressMissDamage * (++missCombo + 1) / 2);

						FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(.1, .2));
					}
				}
			}
		}

		Conductor.songPosition = prevTime;

		_scriptKeyArgs[0] = key;
		#if android SystemMonitor.profBegin('inputScripts'); #end
		scripts.call('onKeyPress', _scriptKeyArgs);
		scripts.call('onInputPress', _scriptKeyArgs);
		#if android SystemMonitor.profEnd(); #end

		#if android SystemMonitor.profEnd(); #end
	}

	function onInputRelease(event:InputEvent):Void
	{
		final key:Int = event.noteData;

		if (!startedCountdown || paused) return;

		#if android SystemMonitor.profBegin('releaseProcess'); #end

		for (field in playFields.members)
		{
			if (field.inControl && !field.autoPlayed && field.playerControls)
			{
				var spr:StrumNote = field.members[key];
				if (spr != null)
				{
					spr.playAnim('static');
					spr.resetAnim = 0;
				}

				for (splash in field.grpSusSplashes)
				{
					if (splash.alive && splash.noteData == key && !splash.completed) splash.kill();
				}
			}
		}
		_scriptKeyArgs[0] = key;
		scripts.call('onKeyRelease', _scriptKeyArgs);
		scripts.call('onInputRelease', _scriptKeyArgs);

		#if android SystemMonitor.profEnd(); #end
	}
	
	public function setFocusPlayerFromNote(note:Note)
	{
		final playField = note.playField;

		if (playField?.isPlayer)
		{
			focusPlayer = (note.owner ?? (note.gfNote ? gf : null));
			focusPlayer ??= (note.singers == null ? playField.owner : note.singers[0]);

			if (focusPlayer == boyfriend) focusPlayer = null;
		}
	}

	// Hold notes
	var holders:Array<Character> = [];

	function keyShit():Void
	{
		// HOLDING
		final up:Bool = controls.NOTE_UP;
		final right:Bool = controls.NOTE_RIGHT;
		final down:Bool = controls.NOTE_DOWN;
		final left:Bool = controls.NOTE_LEFT;
		final taunting:Bool = (controls.NOTE_TAUNT && (focusPlayer ?? boyfriend)?.canTaunt);
		
		if (startedCountdown && !boyfriend.stunned && generatedMusic)
		{
			var i:Int = notes.length;
			while (--i >= 0)
			{
				var daNote = notes.members[i];
				
				if (!daNote.alive) continue;
				
				if (daNote.isSustainNote && !daNote.blockHit && !daNote.tooLate && !daNote.playField.autoPlayed
					&& daNote.playField.inControl && daNote.playField.playerControls)
				{
					final holding:Bool = input.inputPressed(daNote.noteData);
					
					if (daNote.wasGoodHit)
					{
						final splash = daNote.tailState.splash;
						
						if (holding && splash != null && !splash.alive)
						{
							splash.playAnim('start${splash.noteData}');
							splash.revive();
						}
					}
					else if (holding && Conductor.songPosition >= daNote.strumTime)
					{
						daNote.playField.onNoteHit.dispatch(daNote, daNote.playField);
					}
					else if (!holding && !daNote.ignoreNote && !endingSong && daNote.strum.coyoteTime <= 0 && !daNote.tailState.missed)
					{
						daNote.playField.onNoteMiss.dispatch(daNote, daNote.playField);
					}
				}
			}
			
			if (!left && !down && !up && !right && !taunting)
			{
				// holding=false triggers Character.set_holding() -> dance(), i.e. a
				// full playAnim() switch back to idle — suspected (per user report)
				// to be exactly where the sustain-note-end freeze happens, outside
				// every tag noteHit() already profiles. dance() itself was found to
				// rebuild its anim name strings on every call and has since been
				// fixed (Bopper.hx); gcUsageSnapshot/holdReleaseGcCollision here
				// confirm whether a GC collision still lands in this specific span.
				#if android
				SystemMonitor.profBegin('holdRelease');
				final _gcBeforeHoldRelease = SystemMonitor.gcUsageSnapshot();
				#end
				for (field in playFields)
				{
					if (field.playerControls && field.owner?.holding) field.owner.holding = false;
				}

				if (holders.length > 0)
				{
					for (holder in holders)
						holder.holding = false;

					holders.resize(0);
				}
				#if android
				SystemMonitor.profEnd();
				SystemMonitor.holdReleaseGcCollision(_gcBeforeHoldRelease);
				#end
			}
		}
	}
	
	inline function breakCombo():Void
	{
		if (combo > 5 && gf?.animOffsets.exists('sad'))
		{
			gf.playAnim('sad');
			gf.specialAnim = true;
		}
		
		combo = 0;
	}
	
	public function characterSing(char:Character, note:Note, hold:Bool = false):Void // this is really dirty but i dont care aauaaaaauauauugaauauau
	{
		PlayField.characterSing(char, note, hold);
	}
	
	@:inheritDoc
	override function refreshZ(?group:FlxTypedGroup<FlxBasic>)
	{
		group ??= stage;
		group.sort(SortUtil.sortByZ, flixel.util.FlxSort.ASCENDING);
	}
	
	override function destroy()
	{
		instance = null;

		#if android
		mobile.backend.AndroidUtils.keepScreenOn(false);
		mobile.backend.AndroidUtils.setGameplayState(false);
		mobile.backend.DynamicResolution.setActive(false);
		#end

		scripts.call('onDestroy', _scriptEmptyArgs, true);
		
		scripts = FlxDestroyUtil.destroy(scripts);
		eventScripts = FlxDestroyUtil.destroy(eventScripts);
		noteTypeScripts = FlxDestroyUtil.destroy(noteTypeScripts);
		
		input = FlxDestroyUtil.destroy(input);
		
		modManager = FlxDestroyUtil.destroy(modManager);
		
		FlxDestroyUtil.destroyArray(NoteUtil.noteskins);
		NoteUtil.noteskins.resize(0);

		super.destroy();

		if (_bitmapSnapshotAtCreate != null)
		{
			FunkinAssets.cache.disposeNewSince(_bitmapSnapshotAtCreate);
			_bitmapSnapshotAtCreate = null;
		}
	}
	
	override function stepHit()
	{
		super.stepHit();
		
		final maxToleratedOffset:Float = (1000 / 60 * playbackRate);
		
		if (audio.inst?.playing)
		{
			if (Math.abs(audio.inst.time - (Conductor.songPosition - Conductor.offset)) > maxToleratedOffset
				|| (SONG.needsVoices && audio.getDesyncDifference(Math.abs(Conductor.songPosition - Conductor.offset)) > maxToleratedOffset)) resyncVocals();
		}
		
		if (lastStepHit >= curStep) return;
		
		lastStepHit = curStep;
		
		scripts.call('onStepHit');
		
		callHUDFunc(hud -> hud.stepHit());
	}
	
	var lastStepHit:Int = -1;
	var lastBeatHit:Int = -1;
	var lastSection:Int = -1;
	
	override function beatHit()
	{
		super.beatHit();
		
		if (lastBeatHit >= curBeat) return;
		
		handleBoppers(curBeat);
		
		if (camZooming && ClientPrefs.camZooms && (curBeat == 0 || (beatsPerZoom > 0 && curBeat % beatsPerZoom == 0))) camZoom();
		
		lastBeatHit = curBeat;
		
		if (totalBeat > 0)
		{
			if (curBeat % timeBeat == 0)
			{
				triggerEventNote('Add Camera Zoom', '' + gameZ, '' + hudZ);
				totalBeat -= 1;
				
				if (shakeTime) triggerEventNote('Screen Shake', (((1 / (Conductor.bpm / 60)) / 2) * timeBeat)
					+ ', '
					+ gameShake, (((1 / (Conductor.bpm / 60)) / 2) * timeBeat)
					+ ', '
					+ hudShake);
			}
		}
		
		scripts.call('onBeatHit');
		callHUDFunc(hud -> hud.beatHit());
	}
	
	// rework this
	public function handleBoppers(beat:Int)
	{
		gf?.onBeatHit(beat);
		boyfriend?.onBeatHit(beat);
		dad?.onBeatHit(beat);
		pet?.onBeatHit(beat);
	}
	
	override function sectionHit():Void
	{
		if (SONG.notes[curSection] != null)
		{
			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				scripts.set('bpm', Conductor.bpm);
			}
			scripts.set('mustHitSection', SONG.notes[curSection].mustHitSection);
			scripts.set('altAnim', SONG.notes[curSection].altAnim);
			scripts.set('gfSection', SONG.notes[curSection].gfSection);
		}
		
		if (camZooming && ClientPrefs.camZooms && beatsPerZoom <= 0) camZoom();
		
		super.sectionHit();
		
		scripts.call('onSectionHit');
		callHUDFunc(hud -> hud.sectionHit());
	}
	
	inline function camZoom():Void
	{
		FlxG.camera.zoom += 0.015 * camZoomingMult;
		camHUD.zoom += 0.03 * camZoomingMult;
	}
	
	/**
	 * Attempts to call a function on a event script by event name
	 */
	public function callEventScript(scriptName:String, func:String, args:Array<Dynamic>):Dynamic
	{
		if (!eventScripts.exists(scriptName)) return ScriptConstants.CONTINUE_FUNC;
		
		final script = eventScripts.getScript(scriptName);
		
		return callScript(script, func, args);
	}
	
	/**
	 * Attempts to call a function on a note script by note type
	 */
	public function callNoteTypeScript(noteType:String, func:String, args:Array<Dynamic>):Dynamic
	{
		if (!noteTypeScripts.exists(noteType)) return ScriptConstants.CONTINUE_FUNC;
		
		final script = noteTypeScripts.getScript(noteType);
		
		return callScript(script, func, args);
	}
	
	/**
	 * calls a function directly on a script if it exists
	 */
	public function callScript(script:FunkinScript, event:String, args:Array<Dynamic>):Dynamic
	{
		if (!script.exists(event)) return ScriptConstants.CONTINUE_FUNC;

		final _t = ScriptGroup.timingEnabled ? haxe.Timer.stamp() : 0.0;

		var ret:Dynamic = script.call(event, args)?.returnValue;

		if (ScriptGroup.timingEnabled)
		{
			final _ms = (haxe.Timer.stamp() - _t) * 1000.0;
			if (_ms >= ScriptGroup.slowThresholdMs)
				trace('[ScriptPerf] ${script.name}::$event ${Math.round(_ms * 10) / 10}ms');
		}

		return ret ?? ScriptConstants.CONTINUE_FUNC;
	}
	
	public var ratingPercent:Float = 0.0;
	public var ratingFC:String = '';
	
	public function RecalculateRating(badHit:Bool = false)
	{
		if (!ScriptConstants.stopping(scripts.call('onRecalculateRating', _scriptEmptyArgs)))
		{
			if (totalPlayed > 0) ratingPercent = (totalNotesHit / totalPlayed);
			
			ratingFC = getRatingFC();
		}
		
		updateScoreBar(badHit);
	}
	
	public dynamic function getRatingFC():String
	{
		if (songMisses >= 10) return 'Clear';
		if (songMisses > 0) return 'SDCB';
		if (bads + shits > 0) return 'FC';
		if (goods > 0) return 'GFC';
		if (sicks > 0) return 'SFC';
		if (epics > 0) return 'KFC';
		return '';
	}
	
	override public function startOutro(onOutroComplete:() -> Void)
	{
		if (stage != null && isPixelStage != stage.stageData.isPixelStage) isPixelStage = stage.stageData.isPixelStage;
		super.startOutro(onOutroComplete);
	}
	
	public function updateModifiers()
	{
		for (mod in marathonModifiers)
		{
			trace(mod);
			mod.onActive();
		}
	}
	
	public function disableModifiers()
	{
		for (mod in marathonModifiers)
		{
			mod.onRemove();
		}
	}
	
	public function removeModifiers()
	{
		for (mod in marathonModifiers)
		{
			mod.onRemove();
		}
		
		marathonModifiers.resize(0);
	}
}
