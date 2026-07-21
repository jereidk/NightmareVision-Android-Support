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

// Shared by every deferred tail segment queued from the same head note (see
// PlayState._pendingTails). `headQueueNote` lets a deferred entry detect
// that its head's pool slot has since been reused for a different note
// (see spawnPendingTail()).
private typedef PendingTailChain = {headQueueNote:QueueNote};

private typedef PendingTail =
{
	qn:QueueNote,
	parentNote:Note,
	chain:PendingTailChain,
	// Known upfront from this segment's position in its hold's tail array --
	// stamped onto the spawned Note as isFirstTailSegment once it exists
	// (see spawnPendingTail()).
	isFirst:Bool
};

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
	 * Off-screen, never-added-to-any-group Character for `boyfriend`'s
	 * gameover character, built right after `boyfriend` itself so its
	 * atlas/animations are already warm in FunkinAssets.cache by the time
	 * the player can actually die. Without this, GameOverSubstate.create()
	 * calls `new Character(...)` for the FIRST time only at the moment of
	 * death, and for any gameover character that isn't literally the same
	 * model as `boyfriend` (the common case -- see resetVariables()'s
	 * 'genericDeath' default) that's a cold synchronous atlas load/decode
	 * landing exactly when the game is supposed to freeze-frame into the
	 * death animation, not before. Consumed (and nulled) by
	 * GameOverSubstate.new() if the player actually dies; disposed in
	 * destroy() below otherwise.
	 */
	public var preloadedGameoverChar:Null<Character> = null;

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
	// Single-sprite hold trails (see SustainTrail.hx) -- deliberately a
	// separate group from `notes`, never touched by keyShit()/scoring.
	public var susTrails:FlxTypedGroup<funkin.objects.note.SustainTrail>;
	public var queueNotes:Array<QueueNote> = [];
	public var eventNotes:Array<EventNote> = [];
	// Index pointers so we advance by pointer rather than O(n) shift().
	var _noteSpawnIdx:Int = 0;
	var _eventSpawnIdx:Int = 0;

	// A sustain note's tail segments used to all be recycled synchronously
	// the instant their head spawned -- for a long hold that's dozens of
	// Note constructions dumped into a single frame. recycleNote() now only
	// builds the head immediately and queues the rest here, letting them
	// drain a few at a time (see the second noteSpawn loop in update()) as
	// each segment's OWN strumTime actually earns it. `chain` is shared by
	// every entry queued from the same head and carries `headQueueNote`,
	// the QueueNote the head was originally recycled against -- preRecycle()
	// always re-stamps `note.queueNote` on every recycle, so comparing that
	// back against this lets a deferred entry detect "my head's pool slot
	// became a different note" instead of corrupting a stranger's state
	// (see spawnPendingTail()).
	static inline final MAX_NOTE_SPAWNS_PER_FRAME:Int = 12;
	var _pendingTails:Array<PendingTail> = [];
	var _pendingTailIdx:Int = 0;

	/**
	 * Dead (killed but still-pooled, see disposeNote()) notes bucketed by
	 * the (skin, noteData) they last had loaded -- lets recycleCompatibleNote()
	 * find an exact-match reuse candidate in O(1) instead of linearly
	 * scanning the whole pool hoping to find one, which failed unpredictably
	 * depending on the chart's own note pattern (a burst of one direction
	 * with no matching dead notes currently sitting in the pool forced a
	 * full reloadNote() -- fresh atlas + animation rebuild -- for every note
	 * in that burst). A real device log on a script-heavy song showed
	 * noteSpawn cost spiking 100-300ms+ in bursts that lined up exactly with
	 * this cache-miss pattern, with the pool size itself staying constant
	 * throughout (so it wasn't pool growth -- this was it).
	 *
	 * Entries can go stale if a note gets revived through a path that
	 * doesn't know about this index (Flixel's own FlxTypedGroup.recycle(),
	 * used when recycleNote() has no specific target field) --
	 * recycleCompatibleNote() verifies `!exists` before trusting a popped
	 * entry instead of assuming the bucket is always accurate, so a missed
	 * untrack never causes an already-alive note to be handed out twice.
	 */
	var _deadNotesByType:Map<NoteSkin, Map<Int, Array<Note>>> = [];

	/** Call from every place a note becomes available for reuse (kill()). */
	inline function _trackDeadNote(note:Note):Void
	{
		if (note._lastLoadedSkin == null) return; // never actually loaded -- nothing to index yet

		var bySkin = _deadNotesByType.get(note._lastLoadedSkin);
		if (bySkin == null)
		{
			bySkin = new Map();
			_deadNotesByType.set(note._lastLoadedSkin, bySkin);
		}

		var bucket = bySkin.get(note._lastLoadedNoteData);
		if (bucket == null)
		{
			bucket = [];
			bySkin.set(note._lastLoadedNoteData, bucket);
		}

		bucket.push(note);
	}

	/**
	 * Dead (killed but still-pooled) SustainTrail instances bucketed by the
	 * skin texture they last had loaded -- same idea and same reason as
	 * _deadNotesByType above, applied to the one pool that never got that
	 * fix. setupSustainTrail()'s susTrails.recycle() used to grab the first
	 * dead trail in pool order regardless of what texture it last had
	 * loaded; SustainTrail.setupTrail()'s own reload guard
	 * (`_textureLoaded != skin.noteTexture`) then forced a full atlas +
	 * addAnimByPrefix reload -- the exact cost noteReload was built to catch
	 * on the Note side -- every time that guess was wrong. susTrails is a
	 * SINGLE pool shared by every player/field, so any song with more than
	 * one note skin in play (P1 vs P2, per-lane arrowSkins) was thrashing
	 * this on nearly every hold, and because it's SustainTrail-specific code
	 * (not Note.set_texture()), it never showed up as its own tag -- it just
	 * silently inflated noteSpawn's total. See SustainTrail.hx's own
	 * 'trailReload' profiling tag for direct confirmation.
	 */
	var _deadTrailsByTexture:Map<String, Array<funkin.objects.note.SustainTrail>> = [];

	/** Call from every place a SustainTrail becomes available for reuse (kill()). */
	inline function _trackDeadTrail(trail:funkin.objects.note.SustainTrail):Void
	{
		if (trail._textureLoaded == null) return; // never actually loaded -- nothing to index yet

		var bucket = _deadTrailsByTexture.get(trail._textureLoaded);
		if (bucket == null)
		{
			bucket = [];
			_deadTrailsByTexture.set(trail._textureLoaded, bucket);
		}

		bucket.push(trail);
	}

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

	/** Dev-only Showcase mode is active this song (see refreshGameplaySettings()). */
	public var showcaseActive(default, null):Bool = false;

	#if mobile
	/**
	 * Whether the gameplay touch overlay (hitbox / virtual pad) is inside its
	 * "should be shown" window (post-countdown, not in a cutscene, song not
	 * over). The actual .visible is resolved every frame from this AND
	 * camHUD.visible AND the botplay/showcase rules -- the pad lives on its
	 * own camera, so a modchart hiding camHUD would otherwise leave it
	 * floating alone on screen.
	 */
	var mobileControlsActive:Bool = false;
	#end
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

	var _bitmapSnapshotAtCreate:Null<haxe.ds.StringMap<Bool>> = null;

	/** In story mode, true when this is the last song of the week.
	 *  Set by endSong() just before the score popup. */
	var _isLastSongOfWeek:Bool = false;

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

	/**
	 * Re-reads healthGain/healthLoss/instakillOnMiss/practiceMode/cpuControlled
	 * from ClientPrefs.gameplaySettings. Called once at create(), and again
	 * from closeSubState() whenever resuming from a pause -- GameplayChangersSubstate
	 * (reachable from the pause menu) writes straight into gameplaySettings, but
	 * these fields are only ever cached copies, so a change made while paused
	 * would otherwise silently do nothing until the song restarts. scrollspeed/
	 * scrolltype don't need this: everywhere they're used already calls
	 * ClientPrefs.getGameplaySetting() live instead of caching into a field.
	 */
	function refreshGameplaySettings():Void
	{
		healthGain = ClientPrefs.getGameplaySetting('healthgain', 1);
		healthLoss = ClientPrefs.getGameplaySetting('healthloss', 1);
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill', false);
		practiceMode = ClientPrefs.getGameplaySetting('practice', false);
		// Showcase (dev-only) rides botplay's autoplay but keeps the HUD live
		// and the mobile controls visible/animated -- see ClientPrefs.showcaseMode.
		showcaseActive = ClientPrefs.inDevMode && ClientPrefs.showcaseMode;
		cpuControlled = ClientPrefs.getGameplaySetting('botplay', false) || showcaseActive;
		// Repaint the score line so toggling botplay from the pause menu's
		// gameplay options swaps the BOTPLAY label / live score immediately on
		// resume, instead of only after the next scored note. Guarded because
		// refreshGameplaySettings() also runs once during create(), before the
		// HUD exists.
		if (playHUD != null) updateScoreBar();
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

		// Real device logs showed LoadingState -> PlayState taking upwards of
		// 50 SECONDS for dense songs, entirely inside this one synchronous
		// create() call (no frame renders during it, so it's a genuine
		// frozen-screen wait for the player, not just a log curiosity).
		// Phase-timing this is the only way to find out where that time
		// actually goes instead of guessing -- logged as plain [CreatePhase]
		// lines so they land in sysmon.log alongside everything else.
		final _phaseStampStart:Float = haxe.Timer.stamp();
		var _phaseStamp:Float = _phaseStampStart;
		function _logPhase(name:String):Void
		{
			if (!ClientPrefs.inDevMode) return;
			final now:Float = haxe.Timer.stamp();
			Logger.log('[CreatePhase] $name: ${Std.int((now - _phaseStamp) * 1000)}ms (total so far: ${Std.int((now - _phaseStampStart) * 1000)}ms)');
			_phaseStamp = now;
		}

		FlxG.sound.music?.stop();

		_bitmapSnapshotAtCreate = FunkinAssets.cache.snapshotBitmapKeys();

		FunkinAssets.cache.clearStoredMemory();

		// This whole create() is one long synchronous allocation burst (stage,
		// characters, notes...) -- letting the collector fire mid-burst risks
		// landing its pause during the countdown that plays right after create()
		// returns. Suppress it for the burst's duration; forceGcPass() (inside
		// clearUnusedMemory() below) sweeps everything in one deliberate pass
		// once the burst is over instead of leaving it to fire on its own.
		#if cpp cpp.vm.Gc.enable(false); #end

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
		refreshGameplaySettings();

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

		_logPhase('stage');

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

		_logPhase('pet');

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

		_logPhase('girlfriend');

		trace('[PlayState] Creating dad (${SONG.player2})...');
		dad = new Character(SONG.player2);
		trace('[PlayState] Dad created, loading animations...');
		checkStageFlag(dad);
		dadGroup.addChar(dad);
		dadGroup.parent = dad;
		startCharacterScript(dad.curCharacter, dad);
		trace('[PlayState] Dad OK');

		_logPhase('dad');

		trace('[PlayState] Creating boyfriend...');
		boyfriend = new Character((allowBFSkin ? ClientPrefs.equipment.get('playerSkin') : null) ?? SONG.player1, true);
		trace('[PlayState] BF created, loading animations...');
		checkStageFlag(boyfriend);
		boyfriendGroup.addChar(boyfriend);
		boyfriendGroup.parent = boyfriend;
		startCharacterScript(boyfriend.curCharacter, boyfriend);
		trace('[PlayState] BF OK');

		// See preloadedGameoverChar's own doc comment: warm the gameover
		// character's atlas now instead of letting GameOverSubstate.create()
		// load it cold at the moment of death. Matches the exact name
		// resolution GameOverSubstate.new() itself does (gameoverCharacter,
		// falling back to the 'genericDeath' default set by
		// resetVariables() above) -- if that resolves to the same model as
		// boyfriend, no separate preload is needed since GameOverSubstate
		// already reuses `boyfriend` directly for that case.
		final gameoverCharName = boyfriend.gameoverCharacter ?? GameOverSubstate.characterName;
		if (gameoverCharName != null && gameoverCharName != boyfriend.curCharacter)
		{
			preloadedGameoverChar = new Character(0, 0, gameoverCharName, true);
			preloadedGameoverChar.visible = false;
		}

		_logPhase('boyfriend');

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
		
		// TimedFlxGroup (funkin.backend) instead of a plain FlxTypedGroup for
		// these three -- they're top-level state members, so their own share
		// of the generic per-member update cascade ('flxMemberLoop', see
		// MusicBeatState.update()) was otherwise invisible, same gap
		// Stage.hx/TouchInputManager.hx's own update() overrides exist to
		// close for what THEY wrap. Only times each group's own call, not
		// every child individually -- doesn't multiply per-note overhead.
		playFields = new funkin.backend.TimedFlxGroup<PlayField>('playFieldsGroupUpdate');
		add(playFields);

		// Added before `notes` so heads/holdend caps (real Note sprites) draw
		// on top of the plain trail body, matching how the old segment chain
		// visually stacked (later-spawned segments/caps over earlier ones).
		susTrails = new funkin.backend.TimedFlxGroup<funkin.objects.note.SustainTrail>('susTrailsGroupUpdate');
		add(susTrails);

		notes = new funkin.backend.TimedFlxGroup<Note>('notesGroupUpdate');
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
		
		// The standalone BOTPLAY banner is retired -- the PsychHUD score line
		// shows the BOTPLAY label now, so this was a duplicate. Kept as an
		// always-invisible object because a few song scripts still reference
		// botplayTxt cosmetically (e.g. top-10/sigh.hx's setFormat) and would
		// NPE if it were removed outright.
		botplayTxt = new FlxText(400, 55, FlxG.width - 800, "BOTPLAY", 32);
		botplayTxt.setFormat(Paths.DEFAULT_FONT, 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);

		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = false;
		if (ClientPrefs.downScroll) botplayTxt.y = FlxG.height - botplayTxt.height - 55;
		add(botplayTxt);
		
		notes.cameras = [camHUD];
		playFields.cameras = [camHUD];
		botplayTxt.cameras = [camHUD];
		
		addSongScripts('songs/${Paths.sanitize(SONG.song)}/');
		addSongScripts('songs/${Paths.sanitize(SONG.song)}/scripts/');

		_logPhase('song scripts');

		#if mobile
		addMobileControls(false, true);
		mobileControlsActive = false;
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
		
		if (genNotesBeforeCountdown)
		{
			generatePlayfields();
			_logPhase('playfields');
		}
		generateSong(SONG.song);
		_logPhase('generateSong');
		
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

		#if cpp cpp.vm.Gc.enable(true); #end
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
			// Shared with MobileHitbox's NOTE_TAP layout so the touch zones it
			// builds (before these playfields even exist) land exactly here.
			modManager.vsliceBaseY = funkin.objects.note.StrumNote.getVSliceBaseY();
			// Real mobile VSlice pins the opponent's strumline near the top,
			// small, regardless of downscroll -- see getVSliceOpponentBaseY().
			modManager.vsliceOpponentBaseY = funkin.objects.note.StrumNote.getVSliceOpponentBaseY();
		}

		for (lane in 0...SONG.lanes)
		{
			final character = (lane == 1 ? dad : boyfriend);
			final isPlayer = (lane != 1);

			final auto = (lane != 0 || cpuControlled);

			// Real VSlice shows BOTH strumlines at once, side by side (player on the
			// right half, opponent flush left) -- see StrumNote.getCenteredXPos()'s
			// comment. getCenteredXPos already applies spacingScale.
			final isOpponentLane = (lane == 1);
			// Spacing between the 4 lanes and the receptor/note art's own size are
			// tuned independently for the player (spread out MORE, render SMALLER)
			// -- the opponent's compact strumline shrinks both together instead.
			final spacingMult = isOpponentLane ? funkin.objects.note.StrumNote.VSLICE_OPPONENT_SCALE : funkin.objects.note.StrumNote.VSLICE_PLAYER_SPACING_MULT;
			final sizeScale = isOpponentLane ? funkin.objects.note.StrumNote.VSLICE_OPPONENT_SCALE : funkin.objects.note.StrumNote.VSLICE_PLAYER_SIZE_SCALE;
			var baseX:Float = _isVSlice ? funkin.objects.note.StrumNote.getCenteredXPos(0, lane == 0, spacingMult) : 0;
			var baseY:Float = _isVSlice ? (isOpponentLane ? modManager.vsliceOpponentBaseY : modManager.vsliceBaseY) : 0;

			var strums = new PlayField(baseX, baseY, SONG.keys, character, isPlayer, auto, lane, arrowSkins[lane]);
			// strums.scale = NoteUtil.getSkinFromID(lane).scale;
			if (_isVSlice && lane <= 1)
			{
				// noteScale defaults to 0.7 (our engine-wide default), leaving falling notes
				// visually smaller than the 104px VSlice receptor they're meant to match.
				// Applies to both the player (lane 0) and opponent (lane 1) strumlines --
				// both are real, visible VSlice receptors now, not just the player's. The
				// opponent's strumline is additionally shrunk to match real mobile VSlice's
				// small, always-top-anchored compact strumline (VSLICE_OPPONENT_SCALE); the
				// player's is independently tuned via VSLICE_PLAYER_SIZE_SCALE.
				// VSLICE_*_SCALE were pixel-measured against the DEFAULT skin's 0.7 native
				// scale, so apply them RELATIVE to that -- not as an absolute assignment.
				// Assigning absolutely clobbers skins whose art has a different native scale
				// (the pixel skin renders at 6 because its source arrows are ~17px), which
				// shrank e.g. Dank Bars' pixel notes to a fraction of their intended size.
				// Scaling relative leaves the default skin identical (0.7 -> sizeScale) while
				// keeping every other skin's proportions.
				final vsliceScale = sizeScale / funkin.data.NoteSkin.DEFAULT_SCALE;
				strums._skin.receptorScale *= vsliceScale;
				strums._skin.noteScale *= vsliceScale;
			}
			scripts.call('preReceptorGeneration', [strums, lane]);
			strums.generateReceptors();
			strums.ID = lane;

			// Real VSlice has exactly two strumlines (player + opponent), both
			// visible at once. This engine's "lane" concept can go beyond that
			// (extra characters/multiplayer) -- VSlice has no equivalent for
			// those, so keep anything past the opponent lane hidden.
			if (_isVSlice && lane > 1)
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

				#if mobile
				// Showcase: the bot plays, the controls perform -- pulse the
				// button/hint mapped to the hit column so the overlay animates
				// along. Sustain pieces retrigger with held=true so the light
				// stays solid through the hold instead of strobing per step.
				if (showcaseActive && field.playerControls)
				{
					final flashId = switch (note.noteData % 4)
					{
						case 0: mobile.backend.flixel.input.FlxMobileInputID.noteLEFT;
						case 1: mobile.backend.flixel.input.FlxMobileInputID.noteDOWN;
						case 2: mobile.backend.flixel.input.FlxMobileInputID.noteUP;
						default: mobile.backend.flixel.input.FlxMobileInputID.noteRIGHT;
					};
					if (virtualPad != null) virtualPad.flashButton(flashId, note.isSustainNote);
					if (hitbox != null) hitbox.flashButton(flashId, note.isSustainNote);
				}
				#end
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

		prewarmNotePool();
	}

	/**
	 * Consumes whatever LoadingState's background thread precomputed (see
	 * NotePoolPlan.hx) and builds exactly that many already-reloaded dead
	 * Note instances per (field, direction) bucket, straight into
	 * _deadNotesByType, using the SAME NoteSkin instance (playField._skin)
	 * real gameplay notes will be matched against -- a different NoteSkin
	 * object with identical data would still miss _deadNotesByType's
	 * identity-keyed lookup, so this can only run here, after
	 * generatePlayfields() has built the real PlayField instances, not any
	 * earlier. Textures are already warm in FunkinCache by this point
	 * (LoadingState's normal preload), so each reload here is a cache hit,
	 * not a disk decode -- the only new cost is the object construction
	 * itself, paid once now instead of scattered as reloadNote() calls
	 * through the whole song.
	 */
	function prewarmNotePool():Void
	{
		final plan = NotePoolPlan.consume(SONG.song);
		if (plan.length == 0) return;

		final _t0 = haxe.Timer.stamp();
		var built = 0;

		for (bucket in plan)
		{
			final field = getFieldFromID(bucket.fieldID);
			if (field == null || field._skin == null) continue;

			for (_ in 0...bucket.count)
			{
				final note = new Note();
				note.player = bucket.fieldID;
				note.noteData = bucket.noteData;
				note.skin = field._skin;
				note.texture = field._skin.noteTexture; // triggers reloadNote() via set_texture, same path addNote() uses
				note.baseScale.copyFrom(note.scale);
				note.updateHitbox();

				notes.add(note);
				disposeNote(note); // kill() + garbage flag + _trackDeadNote(), same as any other note's real disposal
				built++;
			}
		}

		if (built > 0 && ClientPrefs.inDevMode)
			Logger.log('[PlayState] prewarmNotePool: built $built dead note(s) across ${plan.length} bucket(s) in ${Std.int((haxe.Timer.stamp() - _t0) * 1000)}ms', NOTICE);
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
		mobileControlsActive = true;
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
		_trackDeadNote(note);
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
	 *
	 * Both thresholds depend on `songSpeed`, which a 'Change Scroll Speed'
	 * event (direct or tweened -- either way its value stays within
	 * [min(old,new), max(old,new)] the whole time) can change mid-song --
	 * a slower songSpeed widens both windows, so a chart that starts fast
	 * and later has a slowdown could have MORE notes in flight at once
	 * than a peak computed from the chart's starting songSpeed alone would
	 * predict. Use the smallest songSpeed this chart can ever reach
	 * (starting value, plus every 'Change Scroll Speed' target) for the
	 * whole sweep instead, so the estimate stays a safe upper bound
	 * regardless of when in the song the slowdown actually lands. (A
	 * script/modchart driving songSpeed directly, outside any chart event,
	 * is outside what static analysis of the chart can predict -- the pool
	 * still recovers correctly either way, just via a real allocation the
	 * one time it happens, same as before this function existed.)
	 */
	function prewarmNotePool():Void
	{
		var minSongSpeed:Float = songSpeed;

		if (songSpeedType != "constant")
		{
			for (event in eventNotes)
			{
				if (event.event != 'Change Scroll Speed') continue;

				var val1:Float = Std.parseFloat(event.value1);
				if (Math.isNaN(val1)) val1 = 1;

				final target:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed', 1) * val1;
				if (target < minSongSpeed) minSongSpeed = target;
			}
		}

		final safeSpawnOffset:Float = (spawnTime / minSongSpeed);
		final safeNoteKillOffset:Float = Math.max(Conductor.stepCrotchet, 350 / minSongSpeed * playbackRate);

		final edges:Array<{t:Float, delta:Int}> = [];

		inline function addInterval(qn:QueueNote):Void
		{
			edges.push({t: qn.strumTime - safeSpawnOffset, delta: 1});
			edges.push({t: qn.strumTime + qn.sustainLength + safeNoteKillOffset, delta: -1});
		}

		for (qn in queueNotes)
		{
			addInterval(qn);
			if (qn.tail != null) for (tail in qn.tail) addInterval(tail);
		}

		// Tie-break same-instant edges with spawns (delta=1) before
		// despawns (delta=-1). Charts routinely land a note's spawn at the
		// exact instant a previous note/sustain despawns (e.g. a sustain
		// ending right where the next note starts) -- if the dispose were
		// processed first at that tick, the sweep would briefly free a slot
		// that runtime never actually frees before needing it (spawning
		// happens before disposing within the same frame, see noteSpawn/
		// notesLoop order in update()), silently undercounting the true
		// peak. Sorting spawns first keeps this a guaranteed upper bound
		// instead of an average-case guess.
		edges.sort((a, b) -> a.t < b.t ? -1 : (a.t > b.t ? 1 : b.delta - a.delta));

		var concurrent:Int = 0, peakConcurrent:Int = 0;
		for (e in edges)
		{
			concurrent += e.delta;
			if (concurrent > peakConcurrent) peakConcurrent = concurrent;
		}

		// The sweep above is a static upper bound on the CHART, but actual
		// dispose timing at runtime also depends on things no static analysis
		// sees: hit-timing variance (a late/early hit shifts exactly when a
		// note leaves the pool) and sustain "coyote time" grace windows. A
		// real device log confirmed this gap directly -- predicted peak=48 for
		// one song, actual runtime peak=57 (~19% higher) -- which forced one
		// live pool-grow mid-song and caused a visible stutter. Padding the
		// prewarm target absorbs that class of error; the extra Notes cost
		// nothing but a few constructions during the loading screen.
		final paddedPeak:Int = Math.ceil(peakConcurrent * 1.25);

		for (i in notes.length...paddedPeak)
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
			if (daNote.strumTime - 350 < time)
			{
				// A still-alive note is also tracked in its PlayField's own
				// `notes` array (used for hit-detection scans, see
				// PlayField.addNote/forEachAliveNote) -- disposing it here
				// via the pool-only disposeNote() kills it but never calls
				// PlayField.removeNote(), leaving a stale reference behind.
				// If that same Note object later gets recycled back into the
				// same field, addNote() pushes it again with no dedupe check,
				// so the field ends up with two entries for one physical
				// note -- forEachAliveNote() would then run its callback on
				// it twice. Route through the field's own disposeNote() (which
				// also removes it from that array) whenever the note is
				// actually attached to one; already-dead pool fodder has no
				// playField, so the plain kill is enough for those.
				if (daNote.playField != null) daNote.playField.disposeNote(daNote);
				else disposeNote(daNote);
			}

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
		_pendingTails.resize(0);
		_pendingTailIdx = 0;
		susTrails?.forEachAlive(t -> t.kill());

		prewarmNotePool();

		// benchmarkFullNoteConstruction() used to run here automatically
		// whenever ClientPrefs.inDevMode was on. It already did its job (the
		// numbers it produced are why we stuck with pooling instead of
		// migrating to a build-everything-upfront model) and is real,
		// uncounted cost from then on -- constructing a live Note per chart
		// note (3928 of them for "Finale", not just the pool's peak-concurrency
		// count) inside the exact PlayState.create() freeze we're trying to
		// measure/shrink, on the one device (dev mode) we actually test load
		// times on. Left callable for future one-off use, just not wired to
		// fire on every single load anymore.

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

			// Picks up any Botplay/Practice/Instakill/health-multiplier change
			// made via the pause menu's Gameplay Options screen -- those write
			// straight into ClientPrefs.gameplaySettings, but the fields above
			// are only cached copies (see refreshGameplaySettings()'s own doc).
			refreshGameplaySettings();
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
		super.draw();
		#if android
		SystemMonitor.profEnd();
		// 'draw' above only covers the CPU-side sprite/draw-call batching
		// this call actually does. FlxGame.draw() (the caller of this
		// override, via _state.draw()) still has FlxG.cameras.render() --
		// the real GPU tile-batch submission -- and unlock()/postDraw left to
		// run after this function returns, which used to be pure
		// "unaccounted" time with zero attribution. See
		// SystemMonitor.beginGpuPresent()'s own doc comment for exactly what
		// this covers and why it's closed via a signal instead of a plain
		// profEnd() call.
		SystemMonitor.beginGpuPresent();
		#end
	}

	override public function update(elapsed:Float):Void
	{
		canPlayAwardSound = true;

		// Everything from here through the spawnOffset calc right before
		// noteSpawn used to be entirely untagged -- mobile overlay visibility,
		// camera lerp setup, pause-input polling (keyboard/BACK/touch),
		// editor hotkeys, conductor songPosition tracking. None of it is
		// individually expensive, but summed it was a real, previously
		// invisible slice of "unaccounted". 'camera'/'eventNotes'/
		// 'modifierTimeline' nest inside as their own sub-tags.
		#if android SystemMonitor.profBegin('preUpdate'); #end

		#if mobile
		// Resolve the touch overlay's real visibility every frame from three
		// independent conditions (see mobileControlsActive's doc):
		//   - the show-window (post-countdown, no cutscene, song not over);
		//   - camHUD.visible, so a modchart hiding the HUD takes the overlay
		//     with it instead of leaving the pad floating on its own camera;
		//   - botplay hides the controls outright (nothing to touch), while
		//     Showcase keeps them up so the bot can animate them.
		final overlayShown = mobileControlsActive && camHUD.visible && (!cpuControlled || showcaseActive);
		if (hitbox != null && hitbox.visible != overlayShown) hitbox.visible = overlayShown;
		if (virtualPad != null && virtualPad.visible != overlayShown) virtualPad.visible = overlayShown;
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

		#if android SystemMonitor.profBegin('eventNotes'); #end
		checkEventNote();
		#if android SystemMonitor.profEnd(); #end

		if (modifiersRegistered)
		{
			#if android SystemMonitor.profBegin('modifierTimeline'); #end
			modManager.updateTimeline(curDecStep);
			modManager.update(elapsed);
			#if android SystemMonitor.profEnd(); #end
		}

		final spawnOffset:Float = (spawnTime / songSpeed);

		#if android SystemMonitor.profEnd(); #end // preUpdate

		// Profiling this (previously untagged, hiding inside "unaccounted")
		// showed noteSpawn cost scaling hard with burst size (~800ms for a
		// 26-note burst). Root cause: disposeNote()/notesLoop used to splice
		// dead notes out of `notes` entirely, so notes.recycle() could never
		// find a reusable dead member — every single spawn fell through to
		// `new Note()` (full FlxSprite construction + a duplicate
		// _resetTexture() on top of the one preRecycle() already does) plus
		// a fresh RGBGraphics allocation, none of which "pooling" was
		// actually avoiding. Both are fixed now (see disposeNote()'s
		// comment, and NoteUtil.getCurColors()'s `into` param).
		//
		// A second, separate burst source remains: a sustain used to recycle
		// EVERY tail segment synchronously alongside its head, so one long
		// hold could dump dozens of Note constructions into a single frame.
		// recycleNote() now only builds the head here and queues its tails
		// into _pendingTails (see enqueuePendingTails()); the second loop
		// below drains them on their OWN schedule instead. Both loops cap
		// how many notes they'll spawn in a single frame (MAX_NOTE_SPAWNS_PER_FRAME)
		// -- Conductor.songPosition tracks real audio time, not render frame
		// count, so an uncapped loop lets one slow frame hand the NEXT frame
		// an even bigger backlog crossed at once, a self-feeding spiral.
		// Notes that miss a frame's cap simply spawn next frame, a few ms
		// later than their ideal threshold at worst.
		#if android SystemMonitor.profBegin('noteSpawn'); #end
		var _headsSpawnedThisFrame:Int = 0;
		while (_headsSpawnedThisFrame < MAX_NOTE_SPAWNS_PER_FRAME && _noteSpawnIdx < queueNotes.length
			&& (queueNotes[_noteSpawnIdx].strumTime - Conductor.songPosition) < spawnOffset)
		{
			#if android SystemMonitor.profBegin('noteSpawn.recycleHead'); #end
			recycleNote(queueNotes[_noteSpawnIdx++]);
			#if android SystemMonitor.profEnd(); #end
			_headsSpawnedThisFrame++;
		}

		var _pendingTailsDrained:Int = 0;
		while (_pendingTailsDrained < MAX_NOTE_SPAWNS_PER_FRAME && _pendingTailIdx < _pendingTails.length
			&& (_pendingTails[_pendingTailIdx].qn.strumTime - Conductor.songPosition) < spawnOffset)
		{
			#if android SystemMonitor.profBegin('noteSpawn.spawnTail'); #end
			spawnPendingTail(_pendingTails[_pendingTailIdx++]);
			#if android SystemMonitor.profEnd(); #end
			_pendingTailsDrained++;
		}
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
			SystemMonitor.profBegin('gameplayReport');
			SystemMonitor.reportGameplayFrame(elapsed, SONG.song, Conductor.songPosition, notes.length, playFields != null ? playFields.length : 0);
			SystemMonitor.profEnd();
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

				// Intermediate segments of a hold currently being rendered by its
				// SustainTrail (updated separately, once per hold, right after
				// this loop) are pure bookkeeping -- skip the position/modchart/
				// clip work entirely: keyShit()'s hit/hold logic and scoring
				// never read position (verified against the current code, not
				// assumed), and the only position-derived thing that fed
				// disposal timing (isSustainEnd's clipRect check above) only
				// applies to the one segment this deliberately leaves untouched.
				// Re-checked every frame, not cached -- see isModchartActive()'s
				// comment for why this can flip mid-hold.
				if (daNote.isSustainNote && !daNote.isSustainEnd && !isModchartActive(daNote.player))
				{
					daNote.visible = false;
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

			// One position update per ACTIVE HOLD instead of per intermediate
			// segment (was 2x modManager.getPos() + atan2/sqrt/pow PER SEGMENT
			// PER FRAME above) -- see SustainTrail.hx's class doc for the full
			// reasoning. Every hold has a trail (see setupSustainTrail()), but
			// it only actually renders while isModchartActive() is false for
			// that player -- otherwise it hides and the segment chain above
			// (which just resumed normal per-frame positioning this same
			// frame) takes over instead.
			#if android SystemMonitor.profBegin('susTrails'); #end
			for (trail in susTrails.members)
			{
				if (trail == null || !trail.alive) continue;

				final headNote = trail.headNote;
				// headNote.alive alone can't tell "this is still my hold's
				// head" -- once the real head is disposed, its pool slot can
				// be handed straight back out to a totally unrelated note
				// before this loop's next pass ever sees it dead, at which
				// point .alive reads true again for someone else's hold.
				// queueNote is re-stamped on every single preRecycle() call,
				// so comparing it against what was captured when this trail
				// was set up (see setupSustainTrail()) catches that reuse
				// reliably -- same mechanism spawnPendingTail()'s Guards 1/2
				// already use for the same reason.
				if (headNote == null || !headNote.alive || headNote.queueNote != trail.headQueueNote)
				{
					trail.kill();
					_trackDeadTrail(trail);
					continue;
				}

				// A modifier can activate mid-hold (see isModchartActive()'s
				// comment) -- when that happens, the intermediate segments
				// above resume normal per-segment rendering on their own on
				// this same frame (their skip-check re-checks live too), so
				// just get out of their way instead of drawing a straight
				// trail on top of/behind a now-curved chain. Don't kill it,
				// though -- the mod could clear again before this hold ends,
				// and killing+respawning every toggle is wasteful for
				// something like an oscillating EaseEvent.
				if (isModchartActive(headNote.player))
				{
					trail.visible = false;
					continue;
				}

				trail.visible = (trail.field?.visible ?? true);

				if (!canUpdateModchart) continue;

				// Before being hit: the whole hold (head included) scrolls as
				// one unbroken piece toward the strum. Once hit and held: the
				// part already past the strum is being "consumed" (mirrors how
				// intermediate segments individually dispose themselves via the
				// tooLate/wasGoodHit conditions above as songPosition passes
				// each one's own tiny strumTime window) -- so the trail's front
				// edge sticks at Conductor.songPosition instead of continuing
				// to scroll past the receptor.
				final frontTime:Float = headNote.wasGoodHit ? Math.max(headNote.strumTime, Conductor.songPosition) : headNote.strumTime;
				final backTime:Float = (headNote.strumTime + headNote.sustainLength);

				if (frontTime >= backTime)
				{
					trail.kill();
					_trackDeadTrail(trail);
					continue;
				}

				final frontBeat = Conductor.getBeat(frontTime);
				final frontVisPos = ((getNoteInitialTime(frontTime) - Conductor.visualPosition) * songSpeed);
				final frontDiff = (frontTime - Conductor.songPosition);
				final frontPos = modManager.getPos(frontTime, frontVisPos, frontDiff, frontBeat, headNote.noteData, headNote.lane, headNote, tempVector);

				final backBeat = Conductor.getBeat(backTime);
				final backVisPos = ((getNoteInitialTime(backTime) - Conductor.visualPosition) * songSpeed);
				final backDiff = (backTime - Conductor.songPosition);
				final backPos = modManager.getPos(backTime, backVisPos, backDiff, backBeat, headNote.noteData, headNote.lane, headNote);

				final skin = trail.skin;

				// Mirrors modManager.updateObject()'s isSustainNote-specific
				// convention (note.y = pos.y directly, not pos.y - height*.5)
				// -- calling updateObject() itself here would take the WRONG,
				// non-sustain branch since `trail` isn't a Note.
				trail.x = (frontPos.x - trail.width * .5);
				trail.y = frontPos.y;

				trail.spriteOffset.x = (skin.noteOffsets[headNote.noteData].x + headNote.typeOffsetX + skin.sustainOffsets[headNote.noteData].x);
				trail.spriteOffset.y = (skin.noteOffsets[headNote.noteData].y + headNote.typeOffsetY + skin.sustainOffsets[headNote.noteData].y);

				final rad = Math.atan2(backPos.y - frontPos.y, backPos.x - frontPos.x);
				trail.angle = (rad * 180 / Math.PI) - 90;

				final dist:Float = Math.sqrt(Math.pow(frontPos.y - backPos.y, 2) + Math.pow(frontPos.x - backPos.x, 2));
				trail.scale.y = trail.baseScale.y = (dist / (trail.frameHeight - (trail.antialiasing ? 1 : 0)));

				trail.alpha = headNote.tailState.missed ? 0.3 : 1;

				backPos.put();
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

		// Tail of the function was entirely untagged too -- taunt input, cam
		// zoom decay, the death check, following-cam sync, debug hotkeys.
		#if android SystemMonitor.profBegin('postUpdate'); #end

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

		#if android SystemMonitor.profBegin('doDeathCheck'); #end
		doDeathCheck();
		#if android SystemMonitor.profEnd(); #end

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
				// Repaint the score line so the BOTPLAY label appears/clears
				// immediately instead of waiting for the next scored note.
				updateScoreBar();
			}
		}

		#if android SystemMonitor.profEnd(); #end // postUpdate

		#if android SystemMonitor.profBegin('scriptPost'); #end
		scripts.call('onUpdatePost', _scriptUpdateArgs);
		#if android SystemMonitor.profEnd(); #end
	}
	
	public function recycleNote(queueNote:QueueNote, ?parent:Note):Note
	{
		final targetField:Null<PlayField> = getFieldFromID(queueNote.playField);

		#if android SystemMonitor.profBegin('noteSpawn.findCompatible'); #end
		var note:Note = (targetField != null)
			? recycleCompatibleNote(targetField._skin, queueNote.noteData)
			: notes.recycle(Note, () -> new Note());
		#if android SystemMonitor.profEnd(); #end

		#if android SystemMonitor.profBegin('noteSpawn.preRecycle'); #end
		note.preRecycle(queueNote, parent);
		#if android SystemMonitor.profEnd(); #end

		if (parent != null) return note;

		if (queueNote.tail != null)
		{
			#if android SystemMonitor.profBegin('noteSpawn.spawnNoteCall'); #end
			final note:Note = spawnNote(note);
			#if android SystemMonitor.profEnd(); #end

			if (note != null)
			{
				#if android SystemMonitor.profBegin('noteSpawn.enqueueTails'); #end
				enqueuePendingTails(note, queueNote, queueNote.tail);
				#if android SystemMonitor.profEnd(); #end

				#if android SystemMonitor.profBegin('noteSpawn.sustainTrailSetup'); #end
				setupSustainTrail(note, targetField);
				#if android SystemMonitor.profEnd(); #end
			}

			return note;
		}
		else
		{
			#if android SystemMonitor.profBegin('noteSpawn.spawnNoteCall'); #end
			final _spawned = spawnNote(note);
			#if android SystemMonitor.profEnd(); #end
			return _spawned;
		}
	}

	function enqueuePendingTails(headNote:Note, headQueueNote:QueueNote, tails:Array<QueueNote>):Void
	{
		final chain:PendingTailChain = {headQueueNote: headQueueNote};
		for (i in 0...tails.length)
			_pendingTails.push({qn: tails[i], parentNote: headNote, chain: chain, isFirst: i == 0});
	}

	// Always spawns a trail alongside the head. Whether it actually RENDERS
	// (vs. the hold falling back to the old per-segment chain) is decided
	// fresh every frame in notesLoop()/the trail-update pass below, not
	// here -- ModManager.activeMods can change mid-hold (DLC/scripts push
	// modifiers via EaseEvents and scripted setValue/setPercent calls at
	// arbitrary chart timing), so a hold that starts with no mods active
	// still needs to be able to fall back correctly if one activates
	// partway through, and vice versa.
	inline function isModchartActive(player:Int):Bool return (modManager.activeMods[player]?.length ?? 0) > 0;

	function setupSustainTrail(headNote:Note, field:Null<PlayField>):Void
	{
		if (field == null) return;

		final trail:SustainTrail = recycleCompatibleTrail(field._skin.noteTexture);
		trail.setupTrail(headNote, field);
		trail.headQueueNote = headNote.queueNote;
		headNote.sustainTrail = trail;
	}

	// Mirrors recycleCompatibleNote() (see its own doc comment for the full
	// reasoning) -- prefers a dead trail from _deadTrailsByTexture that
	// already has the texture this spawn needs, so SustainTrail.setupTrail()'s
	// own reload guard skips addAnims() instead of paying a full atlas +
	// addAnimByPrefix rebuild. Plain susTrails.recycle() (FlxGroup.
	// getFirstAvailable()) just grabs the first dead member regardless of
	// what it last had loaded -- with susTrails shared across every player/
	// field, that's a near-guaranteed reload on any song mixing more than
	// one note skin.
	function recycleCompatibleTrail(targetTexture:String):SustainTrail
	{
		final bucket = _deadTrailsByTexture.get(targetTexture);
		if (bucket != null)
		{
			while (bucket.length > 0)
			{
				final candidate = bucket.pop();
				// Can be stale if something revived this trail through a path
				// that doesn't know about this index -- verify before trusting it.
				if (candidate != null && !candidate.exists)
				{
					candidate.revive();
					return candidate;
				}
			}
		}

		// No exact match available -- any dead member will do (a reload is
		// unavoidable here either way).
		for (member in susTrails.members)
		{
			if (member == null || member.exists) continue;

			member.revive();
			return member;
		}

		return susTrails.add(new SustainTrail());
	}

	// Builds one deferred tail segment. Mirrors what the old inline loop in
	// recycleNote() used to do (recycle against the shared parent chain,
	// append to the parent's tail array, spawn it), with two guards verified
	// against the CURRENT code (not assumed from history):
	function spawnPendingTail(entry:PendingTail):Void
	{
		// Guard 1: the head's pool slot has been reused for a totally
		// different note since this entry was queued (preRecycle() always
		// re-stamps `note.queueNote` on every recycle).
		if (entry.parentNote.queueNote != entry.chain.headQueueNote) return;

		// Guard 2: the head is dead but hasn't been reused YET -- the
		// identity check above can't catch this case (nothing re-stamps
		// queueNote until the next preRecycle()). Building onto a dead head
		// is useless (its hold is already fully over) and risks
		// notes.recycle()/recycleCompatibleNote() handing it right back out
		// as THIS very segment's own Note object.
		if (!entry.parentNote.exists) return;

		// Guard 3: this segment's own natural despawn window (the same
		// threshold notesLoop() uses to dispose a missed/expired note) has
		// already elapsed -- either a severe lag backlog, or
		// Conductor.songPosition jumped forward from a practice-mode time
		// skip (clearNotesBefore()). Building it now would show something
		// that should already be gone; drop it silently instead, visually
		// identical to it never having lagged.
		if (entry.qn.strumTime + entry.qn.sustainLength + noteKillOffset < Conductor.songPosition) return;

		final tailNote:Note = recycleNote(entry.qn, entry.parentNote);
		tailNote.isFirstTailSegment = entry.isFirst;

		entry.parentNote.tail.push(tailNote);

		// Replay whatever state the parent is CURRENTLY in onto a segment
		// that didn't exist yet when that state was decided -- mirrors
		// PlayField.noteHit()'s existing-tail loop (only touches
		// sustain.blockHit) and noteMiss()'s (tooLate/blockHit/ignoreNote/
		// copyAlpha/alpha), which only ever reach segments that already
		// existed at that moment.
		if (tailNote.tailState.missed)
		{
			tailNote.tooLate = true;
			tailNote.blockHit = true;
			tailNote.ignoreNote = true;
			tailNote.copyAlpha = false;
			tailNote.alpha = 0.3;
		}
		else if (entry.parentNote.wasGoodHit) tailNote.blockHit = false;

		spawnNote(tailNote);
	}

	// Prefers reusing a pooled Note whose PREVIOUS life already had the exact
	// skin+direction this spawn needs, so Note.set_texture()'s fast path (skin
	// == _lastLoadedSkin && noteData == _lastLoadedNoteData, in Note.hx) can
	// skip reloadNote() entirely instead of paying loadNoteAnims()'s
	// per-instance animation registration. Plain notes.recycle()
	// (FlxGroup.getFirstAvailable()) just grabs the FIRST dead member in
	// array order regardless of what it was last loaded as -- with only a
	// handful of distinct (skin, noteData) combinations possible all song
	// (one per lane per player), and the pool having almost certainly cycled
	// through every one of them within the first few seconds, that's usually
	// a wasted reload during a sustain-tail burst (this function building
	// many segments of the SAME hold, all wanting the SAME skin+noteData, in
	// one frame).
	// This can only ever pick a DIFFERENT dead member to reuse -- it never
	// changes WHETHER a reload happens, that correctness-critical decision
	// still lives entirely in Note.set_texture()'s own guard (which also
	// checks `texture == resolved`, one condition this doesn't replicate), so
	// a miss here just falls through to a real reload exactly like before,
	// never a wrong render.
	// Exact-match lookup is O(1) via _deadNotesByType (see its own doc
	// comment for why the old linear scan here used to spike noteSpawn cost
	// unpredictably). Only the "no exact match" fallback still scans --
	// that path always pays for a real reloadNote() regardless of which
	// dead member it picks, so the scan itself was never the expensive part
	// there; the pool is small (settles at the song's peak concurrent note
	// count), so it stays cheap.
	// Not `inline`: this has multiple return points (an early return inside
	// the loop), and Haxe's inliner can't flatten that into the ternary
	// expression at the call site above ("Cannot inline a not final return").
	function recycleCompatibleNote(targetSkin:NoteSkin, targetNoteData:Int):Note
	{
		final bySkin = _deadNotesByType.get(targetSkin);
		if (bySkin != null)
		{
			final bucket = bySkin.get(targetNoteData);
			if (bucket != null)
			{
				while (bucket.length > 0)
				{
					final candidate = bucket.pop();
					// Can be stale if something revived this note through a
					// path that doesn't know about this index (Flixel's own
					// FlxTypedGroup.recycle(), used by the caller when there's
					// no specific target field) -- verify before trusting it.
					if (candidate != null && !candidate.exists)
					{
						candidate.revive();
						return candidate;
					}
				}
			}
		}

		// No exact match available -- any dead member will do (a reload is
		// unavoidable here either way).
		for (member in notes.members)
		{
			if (member == null || member.exists) continue;

			member.revive();
			return member;
		}

		return notes.add(new Note());
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
			_trackDeadNote(note);

			return null;
		}

		final expectedPlayfield:Null<PlayField> = getFieldFromID(note.lane);

		if (expectedPlayfield == null)
		{
			note.kill();
			_trackDeadNote(note);

			return null;
		}
		else if (expectedPlayfield.autoPlayed && note.strumTime <= Conductor.songPosition && !note.ignoreNote /* && !note.blockHit */)
		{
			expectedPlayfield.onNoteHit.dispatch(note, expectedPlayfield);
			note.kill();
			_trackDeadNote(note);

			return null;
		}
		else if (!expectedPlayfield.autoPlayed && note.isLate() && !note.ignoreNote && !note.canMiss && !endingSong) // dont Even bother
		{
			expectedPlayfield.onNoteMiss.dispatch(note, expectedPlayfield);
			note.kill();
			_trackDeadNote(note);

			return null;
		}
		else
		{
			expectedPlayfield.addNote(note);

			// This used to be `notes.remove(note, true); notes.insert(0, note);`,
			// carried over unchanged from the pre-pooling code where `notes`
			// only ever held currently-alive notes (so re-inserting a brand
			// new member at the front was cheap). Under pooling `notes` holds
			// the WHOLE pool (dead members kept as fodder, see disposeNote()),
			// so `length` is now the pool size, not the alive count -- and
			// FlxGroup.remove()/insert() are indexOf+splice/indexOf+array.insert,
			// all O(n) on that array. That's 4 full O(n) passes per note JUST
			// to move it to index 0, on every single spawn -- a real device
			// log on a dense song ("Finale") showed noteSpawn costs of
			// 300-1600ms/frame from exactly this, independent of and on top
			// of the disposeNote()/notesLoop pooling fix. Dead pool members
			// are already skipped by both draw() and notesLoop() via
			// `exists`/`alive`, so there's no correctness need to keep alive
			// notes clustered at the front -- leave the note wherever
			// notes.recycle() found it.
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
	
	public function openChartEditor():Void
	{
		ChartEditorState._song = SONG;
		FlxG.camera.followLerp = 0;
		
		persistentUpdate = false;
		paused = true;
		CoolUtil.cancelMusicFadeTween();
		
		FlxG.switchState(ChartEditorState.new);
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

			// Tails queued but not yet spawned (see _pendingTails) aren't
			// covered by either check above -- their heads already left
			// queueNotes, but they're not "alive" in `notes` yet either.
			for (i in _pendingTailIdx..._pendingTails.length)
				if (_pendingTails[i].qn.strumTime < songLength - Conductor.safeZoneOffset) health -= 0.05 * healthLoss;

			if (doDeathCheck()) return;
		}
		
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		#if mobile
		mobileControlsActive = false;
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
					_isLastSongOfWeek = true;
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
					
					// Prefetch next song's assets in background while the player
					// watches the score popup.  LoadingState will pick up the
					// work on the next switch and show real progress.
					#if (android && sys)
					funkin.states.LoadingState.prefetchSong(PlayState.SONG);
					#end
					
					popUpEndCallback = function() {
						if (!ScriptConstants.stopping(scripts.call('postEndSong')))
						{
							CoolUtil.cancelMusicFadeTween();
							FlxG.sound.music.stop();
							
							// Hybrid: if prefetch already finished FOR THIS EXACT
							// song, go straight to PlayState (assets are
							// cache-warm). Otherwise show LoadingState with
							// real progress.
							#if (android && sys)
							if (PlayState.SONG != null && funkin.states.LoadingState.isPrefetchedFor(PlayState.SONG.song))
								FlxG.switchState(PlayState.new);
							else
								funkin.states.LoadingState.loadAndSwitchState(() -> new PlayState());
							#else
							FlxG.switchState(PlayState.new);
							#end
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
		// notes.clear() throws away every member this index could still be
		// pointing at -- drop it too instead of leaving stale references to
		// notes that are no longer part of the pool.
		_deadNotesByType = [];

		for (trail in susTrails.members)
			if (trail != null) trail.kill();
		susTrails.clear();
		// susTrails.clear() throws away every member this index could still
		// be pointing at -- drop it too, same reasoning as _deadNotesByType above.
		_deadTrailsByTexture = [];

		queueNotes.resize(0);
		_noteSpawnIdx = 0;
		_eventSpawnIdx = 0;
		eventNotes.resize(0);
		_pendingTails.resize(0);
		_pendingTailIdx = 0;
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
		// Showcase rides botplay's autoplay but is meant to look like a real
		// playthrough for footage, so it DOES accumulate score/accuracy here
		// (the numbers just never get saved -- cpuControlled still guards
		// Highscore). Plain botplay stays excluded. popUpScore is only ever
		// called for the player-controls field (see the onNoteHit handler),
		// so the autoPlayed check is purely the botplay exclusion, which
		// showcase deliberately bypasses.
		final scoreThisHit = showcaseActive || (!practiceMode && !cpuControlled && !(field?.autoPlayed ?? false));
		if (scoreThisHit)
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
					#if android SystemMonitor.profBegin('noteHitDispatch'); #end
					field.onNoteHit.dispatch(topNote, field);
					#if android SystemMonitor.profEnd(); #end

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
				// fixed (Bopper.hx); this tag is on SystemMonitor's _gcWatchNested
				// list (nested inside keyShit, but fires once per frame like a
				// top-level tag would) so profBegin/profEnd still confirm whether a
				// GC collision lands in this specific span.
				#if android SystemMonitor.profBegin('holdRelease'); #end
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
				#if android SystemMonitor.profEnd(); #end
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

		// Only reached if the player never died (GameOverSubstate.new()
		// would have nulled this on its way to taking ownership otherwise).
		preloadedGameoverChar = FlxDestroyUtil.destroy(preloadedGameoverChar);

		#if android
		mobile.backend.AndroidUtils.keepScreenOn(false);
		mobile.backend.AndroidUtils.setGameplayState(false);
		#end

		scripts.call('onDestroy', _scriptEmptyArgs, true);
		
		scripts = FlxDestroyUtil.destroy(scripts);
		eventScripts = FlxDestroyUtil.destroy(eventScripts);
		noteTypeScripts = FlxDestroyUtil.destroy(noteTypeScripts);
		
		input = FlxDestroyUtil.destroy(input);
		
		modManager = FlxDestroyUtil.destroy(modManager);
		
		FlxDestroyUtil.destroyArray(NoteUtil.noteskins);
		NoteUtil.noteskins.resize(0);

		Conductor.bpmChangeMap.resize(0);

		super.destroy();

	// In Story Mode, keep assets warm between songs of the same week
	// so the next LoadingState → PlayState transition is instant.
	// Only flush the cache when leaving the week entirely or on Freeplay.
	if (_bitmapSnapshotAtCreate != null)
	{
		if (!isStoryMode || _isLastSongOfWeek)
		{
			FunkinAssets.cache.disposeNewSinceIfDestructive(_bitmapSnapshotAtCreate);
		}
		_bitmapSnapshotAtCreate = null;
	}
	}
	
	override function stepHit()
	{
		super.stepHit();
		
		final maxToleratedOffset:Float = (1000 / 60 * playbackRate);
		
		if (audio.inst?.playing)
		{
			final instDrift = Math.abs(audio.inst.time - (Conductor.songPosition - Conductor.offset));
			final vocalDrift = SONG.needsVoices ? audio.getDesyncDifference(Math.abs(Conductor.songPosition - Conductor.offset)) : 0.0;
			if (instDrift > maxToleratedOffset || vocalDrift > maxToleratedOffset)
			{
				#if android
				SystemMonitor.reportAudioResync(vocalDrift > instDrift ? 'vocals' : 'inst', Math.max(instDrift, vocalDrift), Conductor.songPosition);
				#end
				resyncVocals();
			}
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
