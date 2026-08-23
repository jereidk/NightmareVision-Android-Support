package funkin.objects.note;

import flixel.group.FlxContainer.FlxTypedContainer;
import flixel.util.FlxSignal.FlxTypedSignal;
import flixel.math.FlxMath;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxGroup.FlxTypedGroup;

import funkin.objects.Character;
import funkin.game.Rating;
import funkin.data.*;
import funkin.backend.SystemMonitor;
import funkin.Mods;

typedef NoteSignal = FlxTypedSignal<(Note, PlayField) -> Void>;

class PlayField extends FlxTypedContainer<StrumNote>
{
	public var _skin:NoteSkin;
	
	public var owner(get, set):Character;
	public var singers:Array<Null<Character>> = [];
	public var quants(default, set):Bool = ClientPrefs.quants;
	
	private function set_quants(value:Bool)
	{
		quants = value;
		
		for (i in members)
		{
			if (i != null)
			{
				i.isQuant = quants;
				i.reloadNote();
			}
		}
		
		return value;
	}
	
	function set_owner(value:Character)
	{
		singers.remove(owner);
		singers.unshift(value);
		
		return value;
	}
	
	function get_owner():Character
	{
		return singers[0];
	}
	
	public var onNoteHit:NoteSignal = new NoteSignal();
	public var onNoteMiss:NoteSignal = new NoteSignal();
	public var onMissPress:FlxTypedSignal<(Int, PlayField) -> Void> = new FlxTypedSignal<(Int, PlayField) -> Void>();
	
	public var playAnims:Bool = true;
	public var noteSplashes:Bool = false;
	public var autoPlayed:Bool = false;
	public var isPlayer:Bool = false;
	public var playerControls:Bool = false;
	public var inControl(default, set):Bool = true; // incase you want to lock up the playfield
	
	public var trackNoteSplashes:Bool = true;
	public var trackSustainSplashes:Bool = true; // splash angle follows sustain angle
	
	public var notes:Array<Note> = [];
	public var keyCount(default, set):Int = 0;
	
	public var underlay:LaneUnderlay;
	
	public var swagWidth(get, never):Float;
	
	public var showRatings:Bool = false;
	
	public function get_swagWidth()
	{
		return Note.swagWidth;
	}
	
	public var baseX:Float = 0;
	public var baseY:Float = 0;
	public var baseAlpha:Float = 1;
	public var offsetReceptors:Bool = false;
	public var player:Int = 0;
	public var alpha(default, set):Float = 1;
	
	public var holdDropLeniency:Float = (1 / 3);
	
	public function set_alpha(value:Float)
	{
		value = FlxMath.bound(value, 0, 1);
		for (strum in members)
		{
			strum.alphaMult = value;
		}
		return alpha = value;
	}
	
	public function set_keyCount(value:Int)
	{
		keyCount = value;
		if (members.length > 0) generateReceptors();
		return keyCount;
	}
	
	public function set_inControl(value:Bool)
	{
		if (!value)
		{
			for (strum in members)
			{
				strum.playAnim("static");
				strum.resetAnim = 0;
			}
		}
		return inControl = value;
	}
	
	public var splashLayer:FlxTypedContainer<FlxTypedContainer<Dynamic>>;

	/**
	 * The container that all notesplashes are held in
	 */
	public var grpNoteSplashes:FlxTypedContainer<NoteSplash>;

	/**
		The container that all sustain notesplashes are held in
	**/
	public var grpSusSplashes:FlxTypedContainer<SustainSplash>;

	// Pre-allocated args for script calls in noteHit/noteMiss to avoid per-hit heap allocation.
	// Must be static because noteHit/noteMiss are static callbacks.
	static final _noteScriptArgs:Array<Dynamic> = [null, 0];
	static final _noteTypeExclusions:Array<String> = [''];
	static final _gfCharArray:Array<Null<Character>> = [null];
	static final _ownerCharArray:Array<Null<Character>> = [null];
	
	public function new(x:Float, y:Float, keyCount:Int = 4, ?who:Character, isPlayer:Bool = false, cpu:Bool = false, ?playerControls:Bool, player:Int = 0, skin:String = 'default')
	{
		super();
		if (playerControls == null) playerControls = isPlayer;
		
		this.autoPlayed = cpu;
		
		this.owner = who;
		this.isPlayer = isPlayer;
		this.playerControls = playerControls;
		this.player = player;
		
		this.baseX = x;
		this.baseY = y;
		this.keyCount = keyCount;
		
		underlay = new LaneUnderlay(this);
		underlay.baseAlpha = ClientPrefs.laneUnderlayAlpha;
		
		this._skin = new NoteSkin(skin, keyCount, player);
		NoteUtil.noteskins.push(this._skin);
		
		splashLayer = new FlxTypedContainer();
		
		grpNoteSplashes = new FlxTypedContainer<NoteSplash>();
		
		var splash:NoteSplash = new NoteSplash(100, 100, 0, player);
		grpNoteSplashes.add(splash);
		splash.alpha = 0.0;
		
		grpSusSplashes = new FlxTypedContainer<SustainSplash>();
		
		var sus = new SustainSplash(0, 0, 0, 0);
		grpSusSplashes.add(sus);
		sus.alpha = 0.0;
		
		splashLayer.add(grpSusSplashes);
		splashLayer.add(grpNoteSplashes);
		
		this.onNoteHit.add(noteHit);
		this.onNoteMiss.add(noteMiss);
		this.onMissPress.add(noteMissPress);
	}
	
	public function clearReceptors()
	{
		while (members.length > 0)
		{
			var note:StrumNote = members.pop();
			note.kill();
			note.destroy();
		}
	}
	
	public function generateReceptors()
	{
		clearReceptors();
		for (data in 0...keyCount)
		{
			var babyArrow:StrumNote = new StrumNote(player, baseX, baseY, data, this);
			babyArrow.downScroll = ClientPrefs.downScroll;
			babyArrow.alphaMult = alpha;
			add(babyArrow);
			babyArrow.postAddedToGroup();
		}
	}
	
	public function fadeIn(skip:Bool = false)
	{
		for (data in 0...members.length)
		{
			var babyArrow:StrumNote = members[data];
			if (skip) babyArrow.alpha = baseAlpha;
			else
			{
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {alpha: baseAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * data)});
			}
		}
	}
	
	public function getNotes(dir:Int, ?get:Note->Bool):Array<Note>
	{
		var collected:Array<Note> = [];
		for (note in notes)
		{
			if (note.alive && note.noteData == dir && !note.wasGoodHit && !note.tooLate && note.canBeHit)
			{
				if (get == null || get(note)) collected.push(note);
			}
		}
		return collected;
	}

	public function getTapNotes(dir:Int):Array<Note> return getNotes(dir, (note:Note) -> !note.isSustainNote);

	/**
	 * Zero-allocation version of getTapNotes: returns the highest-priority tap note
	 * for the given direction without allocating any intermediate Array.
	 */
	public function getBestTapNote(dir:Int):Null<Note>
	{
		var best:Null<Note> = null;
		for (note in notes)
		{
			if (!note.alive || note.isSustainNote || note.noteData != dir
				|| note.wasGoodHit || note.tooLate || !note.canBeHit) continue;

			if (best == null
				|| note.hitPriority > best.hitPriority
				|| (note.hitPriority == best.hitPriority && note.strumTime < best.strumTime))
				best = note;
		}
		return best;
	}
	
	public function getHoldNotes(dir:Int):Array<Note> return getNotes(dir, (note:Note) -> note.isSustainNote);
	
	/**
	 * Removes a note from this
	 * @param note 
	 */
	public inline function removeNote(note:Note)
	{
		notes.remove(note);
		
		note.scale.copyFrom(note.baseScale);
		note.updateHitbox();
		
		if (note.playField == this) note.playField = null;
	}
	
	public inline function addNote(note:Note)
	{
		notes.push(note);
		
		note.player = player;
		
		// hotswapping catch all
		note.skin = _skin;
		note.texture = _skin.noteTexture;
		note.rgbEnabled = _skin.inEngineColoring;
		note.rgbShader.enabled = note.rgbEnabled;
		
		note.baseScale.copyFrom(note.scale);
		note.updateHitbox();
		
		if (note.playField != this || note.playField == null) note.playField = this;
		
		note.strum = members[note.noteData];
	}
	
	public function forEachAliveNote(func:Note->Void)
	{
		for (note in notes)
			if (note != null && note.exists && note.alive) func(note);
	}
	
	public inline function disposeNote(note:Note):Void
	{
		note.kill();
		
		removeNote(note);
	}
	
	// Paths.sound('hitsound') resolves through getPath()/modFolders(), which on
	// Android (MODS_ALLOWED) does a real FileSystem.exists() call per enabled mod,
	// falling back to a full linear scan of the cached asset list (thousands of
	// entries) whenever none of those exist() checks hit — every single time,
	// even though the Sound itself is already cached by FunkinAssets and the
	// resolved path never changes between hits. Cached here once so a hit-dense
	// section doesn't re-pay that resolution cost on every note.
	static var _hitsoundCache:Null<openfl.media.Sound> = null;
	static var _hitsoundCacheMod:String = null;

	static inline function hitsound():openfl.media.Sound
	{
		if (_hitsoundCache == null || _hitsoundCacheMod != Mods.currentModDirectory)
		{
			_hitsoundCache = Paths.sound('hitsound');
			_hitsoundCacheMod = Mods.currentModDirectory;
		}
		return _hitsoundCache;
	}

	public static function noteHit(note:Note, field:PlayField):Void
	{
		var scriptFunc:String = '';
		var scriptFuncPre:String = '';
		if (field.playerControls) { scriptFunc = 'goodNoteHit'; scriptFuncPre = 'goodNoteHitPre'; }
		else if (field.ID == 1) { scriptFunc = 'opponentNoteHit'; scriptFuncPre = 'opponentNoteHitPre'; }
		else { scriptFunc = 'extraNoteHit'; scriptFuncPre = 'extraNoteHitPre'; }

		_noteScriptArgs[0] = note;
		_noteScriptArgs[1] = field.ID;
		final scriptArgs = _noteScriptArgs;

		// scriptFuncPre used to be `scriptFunc + 'Pre'`, concatenated fresh on
		// every single note hit -- three literal constants instead, same
		// branching, zero per-hit allocation. This fires continuously for the
		// whole song (every opponent/player note), not just at a few points,
		// so the concat was a real sustained GC-pressure source.
		#if android SystemMonitor.profBegin('hitPreScript'); #end
		PlayState.instance.scripts.call(scriptFuncPre, scriptArgs);
		#if android SystemMonitor.profEnd(); #end

		final strum:StrumNote = note.strum;

		#if android SystemMonitor.profBegin('hitStrum'); #end
		if (strum != null)
		{
			strum.copyNoteColor(note);
			strum.playAnim('confirm', true);

			if (field.autoPlayed)
			{
				var time:Float = 0.15;
				if (note.isSustainNote && !note.isSustainEnd) time += 0.15;
				time /= PlayState.instance.playbackRate;

				strum.resetAnim = time;
			}
		}

		if (!note.isSustainNote)
		{
			for (sustain in note.tail) // makes the hold note active when you press the base note
			{
				if (sustain.parent != note) continue; // ignore notes that have already been recycled

				sustain.blockHit = false;
			}
		}
		else if (strum != null)
		{
			strum.coyoteTime = field.holdDropLeniency;
		}
		#if android SystemMonitor.profEnd(); #end

		if (field.playerControls)
		{
			if (note.wasGoodHit || field.autoPlayed && (note.ignoreNote || note.hitCausesMiss || note.canMiss)) return;

			#if android SystemMonitor.profBegin('hitsoundPlay'); #end
			if (ClientPrefs.hitsoundVolume > 0 && !note.hitsoundDisabled) FlxG.sound.play(hitsound(), ClientPrefs.hitsoundVolume);
			#if android SystemMonitor.profEnd(); #end

			if (note.hitCausesMiss)
			{
				field.onNoteMiss.dispatch(note, field);

				note.wasGoodHit = true;

				if (!note.isSustainNote)
				{
					#if android SystemMonitor.profBegin('hitDispose'); #end
					field.disposeNote(note);
					#if android SystemMonitor.profEnd(); #end
				}

				return;
			}

			final susMult:Float = (note.isSustainNote ? 1 / PlayState.instance.holdSubdivisions : 1);

			// set_health() runs the HUD health-bar update synchronously on every
			// hit — untagged until now, so any cost here was landing inside the
			// unexplained noteHitDispatch gap instead of its own line.
			#if android SystemMonitor.profBegin('hitHealth'); #end
			PlayState.instance.health += note.hitHealth * PlayState.instance.healthGain * susMult;
			#if android SystemMonitor.profEnd(); #end
			PlayState.instance.missCombo = 0;
		}

		var chars:Array<Null<Character>>;
		if (note.owner != null)
		{
			if (note.singers != null && note.singers.length > 0)
				chars = note.singers;
			else
			{
				_ownerCharArray[0] = note.owner;
				chars = _ownerCharArray;
			}
		}
		else if (note.gfNote)
		{
			_gfCharArray[0] = PlayState.instance.gf;
			chars = _gfCharArray;
		}
		else
		{
			chars = field.singers;
		}

		// Prime suspect for the Android hit-lag: bf-running/danger (Danger song)
		// use the heavier FlxAnimate atlas format instead of a plain sprite
		// sheet, and char.playAnim() runs here on every single note hit.
		#if android SystemMonitor.profBegin('hitCharSing'); #end
		for (char in chars)
			if (char != null) characterSing(char, note, field.playerControls);
		#if android SystemMonitor.profEnd(); #end

		note.wasGoodHit = true;

		#if android SystemMonitor.profBegin('hitSplash'); #end
		var shouldSplash:Bool = true;
		if (field.playerControls)
		{
			shouldSplash = ((note.ratingData = Rating.judgeNote(note, Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.ratingOffset) / PlayState.instance?.playbackRate)).ratingMod >= 1);
		}

		if (field.noteSplashes && shouldSplash) field.spawnSplash(note);
		field.spawnSusSplash(note, field.playerControls);
		#if android SystemMonitor.profEnd(); #end

		#if android SystemMonitor.profBegin('hitNoteScript'); #end
		final globalScript = PlayState.instance.callNoteTypeScript(note.noteType, 'hit', scriptArgs);
		if (ScriptConstants.stopping(globalScript))
		{
			#if android SystemMonitor.profEnd(); #end
			return;
		}

		_noteTypeExclusions[0] = note.noteType;
		final noteScriptRet = PlayState.instance.callNoteTypeScript(note.noteType, scriptFunc, scriptArgs);
		if (noteScriptRet != ScriptConstants.STOP_FUNC) PlayState.instance.scripts.call(scriptFunc, scriptArgs, false, _noteTypeExclusions);
		#if android SystemMonitor.profEnd(); #end

		if (!note.isSustainNote)
		{
			#if android SystemMonitor.profBegin('hitDispose'); #end
			field.disposeNote(note);
			#if android SystemMonitor.profEnd(); #end
		}
	}
	
	public static function noteMiss(note:Note, field:PlayField):Void
	{
		final susMult:Float = (note.isSustainNote ? 1 / PlayState.instance.holdSubdivisions : 1);
		
		if (field.playerControls)
		{
			final missMult:Float = (note.missHealth * PlayState.instance.healthLoss);
			
			if (!note.isSustainNote)
			{
				var combo = (++ PlayState.instance.missCombo);
				PlayState.instance.health -= (missMult * (combo + 1) / 2);
			}
			else
			{
				PlayState.instance.health -= (missMult * susMult);
			}
		}
		
		for (owner in field.singers)
		{
			var char:Character = owner;
			if (note.gfNote) char = PlayState.instance.gf;
			
			if (char != null && !note.noMissAnimation)
			{
				if (char.animTimer <= 0)
				{
					final baseMiss = field._skin.singAnimations[Std.int(Math.abs(note.noteData))] + 'miss';
					final animToPlay:String = (note.noteType == 'Alt Animation') ? baseMiss + '-alt' : baseMiss;
					char.playAnim(animToPlay, true);
					char.holdTimer = 0;
				}
			}
		}
		
		_noteScriptArgs[0] = note;
		_noteScriptArgs[1] = field.ID;
		final scriptArgs = _noteScriptArgs;

		_noteTypeExclusions[0] = note.noteType;
		final noteScriptRet = PlayState.instance.callNoteTypeScript(note.noteType, 'noteMiss', scriptArgs);
		if (noteScriptRet != ScriptConstants.STOP_FUNC) PlayState.instance.scripts.call('noteMiss', scriptArgs, false, _noteTypeExclusions);
		
		// hold note missing stuff, makes the hold unhittable (and kills it, might make it just transparent if i can fix some stuff)
		if (!note.hitCausesMiss && !note.canMiss)
		{
			note.tailState.missed = true;

			// note here can be either the head itself (parent == null) or one
			// of its own tail segments (parent == the head) -- always anchor
			// the identity check on the actual head note, mirroring
			// noteHit()'s "sustain.parent != note" idiom (there, note is
			// always the head, guarded by !note.isSustainNote). Comparing
			// against note.parent unconditionally broke for head notes: every
			// valid sibling sustain (parent == the head, non-null) looked
			// "already recycled" and got skipped, while a stale Note sitting
			// in this hold's shared tail array whose own .parent field also
			// happened to be null would incorrectly pass the check instead.
			final headNote:Note = (note.parent != null) ? note.parent : note;

			for (sustain in note.tail)
			{
				if (sustain.parent != headNote) continue; // ignore notes that have already been recycled

				sustain.tooLate = true;
				sustain.blockHit = true;
				sustain.ignoreNote = true;
				sustain.copyAlpha = false;
				sustain.alpha = 0.3;
			}
		}
	}
	
	public static function noteMissPress(key:Int, field:PlayField):Void
	{
		for (char in field.singers)
		{
			if (char == null) continue;
			
			if (char.animTimer <= 0)
			{
				char.playAnim(field._skin.singAnimations[Std.int(Math.abs(key))] + 'miss', true);
				char.holdTimer = 0;
			}
		}
	}
	
	@:access(funkin.states.PlayState)
	public static function characterSing(char:Character, note:Note, hold:Bool = false)
	{
		if (note.noAnimation) return;
		
		final baseAnim = note.skin.singAnimations[Std.int(Math.abs(note.noteData))];
		final animToPlay = note.animSuffix.length > 0 ? baseAnim + note.animSuffix : baseAnim;
		
		char.holdTimer = 0;
		
		if (hold && !note.playField?.autoPlayed)
		{
			PlayState.instance?.holders.push(char);
			
			char.holding = true;
		}
		
		switch (note.noteType)
		{
			case 'Hey!' if (char.animation.exists('hey')):
				char.playAnimForDuration('hey', 0.6);
				char.specialAnim = true;
				return;
		}
		
		// ghost stuff
		
		if (!char.vSliceSustains || !note.isSustainNote)
		{
			if (note.noteType == "Ghost Note")
			{
				char.playGhostAnim(note.noteData, animToPlay, true);
			}
			else
			{
				final ghostAnim:String = char.getAnimName();
				
				if (!note.isSustainNote && Math.abs(char.lastHitTime - note.strumTime) < 3 && ClientPrefs.jumpGhosts
					&& PlayState.instance?.scripts.call('onGhostAnim', [ghostAnim, note]) != ScriptConstants.STOP_FUNC)
				{
					char.playGhostAnim(note.noteData, ghostAnim, true);
				}
				
				char.playAnim(animToPlay, true);
				
				// Same "not the very first segment of a fresh hold" check the
				// old prevNote?.isSustainNote read answered (a hold's HEAD
				// QueueNote is always constructed with isSustainNote=false, so
				// a first tail segment's old prevNote -- the head -- always
				// read isSustainNote=false too; !isFirstTailSegment is that
				// same fact without chasing another Note's identity for it).
				if (!note.isSustainNote || !note.isFirstTailSegment) char.lastHitTime = note.strumTime;
			}
		}
	}
	
	public function spawnSplash(note:Note):NoteSplash
	{
		if (ClientPrefs.noteSplashes
			&& note != null
			&& !note.hitCausesMiss
			&& !note.isSustainNote
			&& !note.noteSplashDisabled
			&& noteSplashes
			&& _skin?.splashesEnabled ?? true)
		{
			final strum:Null<StrumNote> = note.playField.members[note.noteData];
			if (strum != null)
			{
				final skin:String = _skin.splashTexture;
				
				var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
				splash.setupNoteSplash(strum, note, skin, note.rgbShader, this);
				grpNoteSplashes.add(splash);
				
				PlayState.instance.scripts.call('onSpawnNoteSplash', [splash, note]);
				
				return note.noteSplash = splash;
			}
		}
		
		return null;
	}
	
	public function spawnSusSplash(note:Note, isPlayer:Bool = false):SustainSplash
	{
		// Same "ignore notes that have already been recycled" identity check
		// noteHit()/noteMiss() already apply to tail-array entries before
		// touching them -- this function read note.tailState/note.tail
		// unconditionally despite that, the one place in this class that
		// didn't. `note` itself can't go stale mid-call (single-threaded,
		// synchronously reached from noteHit()), but a corrupted/shared
		// tailState reaching here from elsewhere shouldn't be trusted either.
		if (!note.exists || note.tailState == null) return null;

		if (_skin?.sustainSplashes && note.tailState.splash == null && note.tail.length > 0)
		{
			final strum:Null<StrumNote> = note.playField?.members[note.noteData];
			if (strum != null)
			{
				var splash:SustainSplash = grpSusSplashes.recycle(SustainSplash);
				splash.setupSplash(strum, note, isPlayer, note.rgbShader, this);
				grpSusSplashes.add(splash);

				PlayState.instance.scripts.call('onSpawnSustainSplash', [splash, note]);

				return note.tailState.splash = note.sustainSplash = splash;
			}
		}

		return null;
	}
	
	public inline function canInput():Bool
	{
		return (playerControls && inControl && !autoPlayed && (owner == null || !owner.stunned));
	}
	
	override function destroy()
	{
		onNoteHit.removeAll();
		onNoteHit.destroy();
		
		onNoteMiss.removeAll();
		onNoteMiss.destroy();
		
		onMissPress.removeAll();
		onMissPress.destroy();
		
		underlay.destroy();
		super.destroy();
	}
}
