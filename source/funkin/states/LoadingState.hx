package funkin.states;

import flixel.addons.display.FlxBackdrop;
import flixel.addons.transition.FlxTransitionableState;
import flixel.tweens.FlxTween.FlxTweenType;
import flixel.util.typeLimit.NextState;
import openfl.display.BitmapData;
import openfl.media.Sound;
import openfl.utils.AssetType;
import lime.media.AudioBuffer;
import lime.media.vorbis.VorbisFile;

import funkin.data.CharacterData.CharacterParser;
import funkin.objects.HealthIcon;
import funkin.Paths.PathsTestMode;

#if (sys && cpp)
import sys.thread.Thread;
import sys.thread.Mutex;
#end

/**
 * Sits between picking a song and PlayState.create() actually running.
 *
 * On Android: launches a background Thread that opens files and decodes
 * raw pixels / audio samples into RAM.  The main thread picks up the
 * decoded data each frame, uploads textures to GPU and registers sounds
 * — all while the loading screen is visible and a progress bar updates
 * in real time.  When every asset is processed (or MIN_SHOW_TIME elapses,
 * whichever is longer), PlayState.create() runs and finds everything
 * already warm in FunkinCache — no sync I/O on the render thread.
 *
 * On desktop: behaves exactly as before (no Thread, just MIN_SHOW_TIME).
 */
class LoadingState extends MusicBeatState
{
	static inline final MIN_SHOW_TIME:Float = 1.1;
	static inline final ACCENT:FlxColor = 0xFFFF4444;

	/** Max GPU uploads per frame to avoid a single-frame stall. */
	static inline final MAX_FINALIZE_PER_FRAME:Int = 3;

	var nextState:NextState;
	var shownTime:Float = 0;
	var switching:Bool = false;

	// ── Background preload shared state ────────────────────────────────────

	#if (sys && cpp)
	static var _mutex:Mutex = new Mutex();

	/** Incremented every time startPreload() creates a new Thread.
	 *  A stale Thread that belongs to a previous generation will
	 *  silently exit instead of contaminating the current state. */
	static var _threadGeneration:Int = 0;
	#end

	/** 0..1 progress. Read under Mutex. */
	static var _progress:Float = 0.0;

	/** Human-readable label. Read under Mutex. */
	static var _label:String = '';

	/** Set true when the background thread has opened every file. */
	static var _allFilesOpened:Bool = false;

	/** Set true after the main thread has finished all GPU uploads. */
	static var _allFinalized:Bool = false;

	// Bridge: worker pushes decoded data here, main thread drains it.
	#if (sys && cpp)
	static var _pendingBitmaps:Array<{key:String, bmd:BitmapData}> = [];
	static var _pendingAudioBuffers:Array<{key:String, buffer:AudioBuffer}> = [];
	#end

	// Progress bar
	var progressBar:FlxSprite;
	var progressBarBg:FlxSprite;
	var progressLabel:FlxText;

	// Only set on Android — the list of asset keys the worker is opening.
	#if (sys && cpp)
	static var _totalTasks:Int = 0;
	static var _completedDecodes:Int = 0; // how many files the worker has decoded
	static var _completedFinalizes:Int = 0; // how many GPU/mixer uploads are done

	// Prefetch tracking — prefetchSong() sets these so endSong() can decide
	// whether to show LoadingState or switch directly.
	static var _prefetchForSongId:String = '';
	static var _prefetchTotal:Int = 0;
	static var _prefetchDone:Int = 0;

	/**
	 * True only when a prefetch for THIS EXACT songId already finished --
	 * checking _prefetchComplete alone isn't enough, since it stays true
	 * (stale) after a completed prefetch until the NEXT prefetchSong() call
	 * resets it, which only happens if the player lingers long enough to
	 * trigger one. Picking a different song faster than that (the common
	 * Freeplay case) would otherwise read a leftover true from a previous,
	 * unrelated song and skip LoadingState for a song that was never
	 * actually prefetched.
	 */
	public static function isPrefetchedFor(songId:String):Bool
	{
		var done = false;
		var forId = '';
		_mutex.acquire();
		done = _prefetchComplete;
		forId = _prefetchForSongId;
		_mutex.release();
		return done && forId == songId;
	}
	static var _prefetchComplete:Bool = false;
	#end

	public static function loadAndSwitchState(nextState:NextState):Void
	{
		FlxG.switchState(() -> new LoadingState(nextState));
	}

	/**
	 * Abandons an in-flight/finished prefetch that's about to go unused --
	 * e.g. Freeplay lingered 2s on a song (starting a background decode
	 * Thread), then the player left without ever picking that song. Nothing
	 * else cancels that Thread otherwise: it only self-terminates early once
	 * a NEWER prefetchSong()/startPreload() bumps _threadGeneration, so an
	 * abandoned one just runs to completion on its own, competing with the
	 * foreground (Freeplay/StoryMenu, including virtual pad input handling)
	 * for CPU during hxcpp's stop-the-world GC pauses, for zero benefit since
	 * nothing will ever call finalizePendingAssets() to consume its output.
	 *
	 * `keepSongId` is the song actually being committed to (if any) -- pass
	 * null to always cancel, or the target songId to skip cancelling when
	 * the pending prefetch is exactly the one about to be consumed.
	 */
	#if (sys && cpp)
	public static function cancelPendingPrefetch(?keepSongId:String):Void
	{
		_mutex.acquire();
		final shouldCancel = _prefetchForSongId != '' && _prefetchForSongId != keepSongId;
		if (shouldCancel)
		{
			_threadGeneration++;
			_pendingBitmaps.resize(0);
			_pendingAudioBuffers.resize(0);
			_prefetchComplete = false;
			_prefetchForSongId = '';
			_prefetchTotal = 0;
			_prefetchDone = 0;
		}
		_mutex.release();
	}
	#else
	public static function cancelPendingPrefetch(?keepSongId:String):Void {}
	#end

	/**
	 * Fire-and-forget: start preloading the given song's assets in a
	 * background Thread right now.  Called from PlayState.endSong() while
	 * the score popup is showing, so by the time LoadingState appears
	 * and calls startPreload(), the heaviest files are already decoded.
	 *
	 * @return true if all assets were already decoded (prefetch complete),
	 *         false if a background Thread was launched and is still working.
	 */
	#if (sys && cpp)
	/**
	 * Only prefix with the external-storage directory when `rawPath` is a
	 * CONFIRMED loose/mod/DLC file (sys.FileSystem.exists() true for the
	 * plain relative path). Bundled (embed="false") assets -- the common
	 * case for any regular, non-DLC song -- were never extracted there;
	 * lime's own asset resolution expects the plain relative path (it tries
	 * that first, only falling back to its own APK base path, never to
	 * external storage). Same gate FunkinAssets.getBitmapData()/
	 * getSoundUnsafe()/Paths.font() already use -- unconditionally prefixing
	 * every atlas/audio path here (as this used to) made BitmapData.fromFile()/
	 * VorbisFile.fromFile() fail for every bundled asset, silently and near-
	 * instantly (caught by the thread's own try/catch), so the "prefetch"
	 * finished in milliseconds having warmed nothing -- PlayState.create()
	 * ended up loading everything itself synchronously anyway, defeating the
	 * entire point of this feature without ever throwing a visible error.
	 */
	static inline function resolveLoadPath(rawPath:String):String
		return sys.FileSystem.exists(rawPath) ? FunkinAssets.androidStoragePath(rawPath) : rawPath;

	public static function prefetchSong(song:funkin.data.Song):Bool
	{
		if (song == null) return true;

		// Reset any previously-stale prefetch state (from a different song).
		_mutex.acquire();
		final hadStaleData = _prefetchForSongId != song.song;
		if (hadStaleData)
		{
			_pendingBitmaps.resize(0);
			_pendingAudioBuffers.resize(0);
			_prefetchComplete = false;
			_prefetchTotal = 0;
			_prefetchDone  = 0;
		}
		_prefetchForSongId = song.song;
		_mutex.release();

		// Collect paths the same way startPreload() does.
		final paths:Array<String> = [];

		function addAtlas(assetKey:String):Void
		{
			final pngPath = resolveLoadPath(Paths.getPath('images/$assetKey.png', 'characters', LOOSE));
			paths.push(pngPath);
		}

		function addSound(basePath:String):Void
		{
			for (ext in ['ogg', 'wav'])
			{
				final p = '$basePath.$ext';
				if (FunkinAssets.exists(p))
				{
					paths.push(resolveLoadPath(p));
					return;
				}
			}
		}

		// Stage
		final stageFile = funkin.data.StageData.getStageFile(song.stage);
		if (stageFile != null && stageFile.stageObjects != null)
		{
			for (obj in stageFile.stageObjects)
			{
				if (obj.asset == null) continue;
				for (asset in obj.asset.split(','))
				{
					final t = StringTools.trim(asset);
					if (t.length > 0) addAtlas(t);
				}
			}
		}

		// Characters
		final chars:Array<String> = [song.player1, song.player2];
		if (song.gfVersion != null && song.gfVersion.length > 0)
			chars.push(song.gfVersion);
		for (charName in chars)
		{
			final info = CharacterParser.fetchInfoUnsafe(charName);
			if (info == null || info.image == null) continue;
			for (img in info.image.split(','))
			{
				final t = StringTools.trim(img);
				if (t.length > 0) addAtlas(t);
			}
		}

		// Audio
		final songName = Paths.sanitize(song.song);
		addSound(Paths.getPath('songs/$songName/Inst', null, LOOSE));
		addSound(Paths.getPath('songs/$songName/Voices', null, LOOSE));

		// Notes
		addAtlas('NOTE_assets');
		addAtlas('noteskins/default');

		if (paths.length == 0)
		{
			_mutex.acquire();
			_prefetchComplete = true;
			_mutex.release();
			return true;
		}

		_mutex.acquire();
		_prefetchTotal = paths.length;
		_prefetchDone  = 0;
		_prefetchComplete = false;
		_mutex.release();

		final myGen = ++_threadGeneration;

		Thread.create(() ->
		{
			for (path in paths)
			{
				if (_threadGeneration != myGen) return;
				try
				{
					final lower = path.toLowerCase();
					if (StringTools.endsWith(lower, '.png') || StringTools.endsWith(lower, '.jpg'))
					{
						var bmd:Null<BitmapData> = null;
						if (sys.FileSystem.exists(path))
							bmd = BitmapData.fromFile(path);
						else if (openfl.Assets.exists(path, IMAGE))
							bmd = openfl.Assets.getBitmapData(path, false);

						if (bmd != null)
						{
							_mutex.acquire();
							_pendingBitmaps.push({key: path, bmd: bmd});
							_mutex.release();
						}
					}
					else if (StringTools.endsWith(lower, '.ogg'))
					{
						final vf = VorbisFile.fromFile(path);
						if (vf != null)
						{
							final buffer = AudioBuffer.fromVorbisFile(vf);
							if (buffer != null)
							{
								_mutex.acquire();
								_pendingAudioBuffers.push({key: path, buffer: buffer});
								_mutex.release();
							}
						}
					}
				}
				catch (_:Dynamic) {}

				_mutex.acquire();
				_prefetchDone++;
				if (_prefetchDone >= _prefetchTotal)
					_prefetchComplete = true;
				_mutex.release();
			}
		});

		return false; // Thread is running
	}
	#else
	public static function prefetchSong(song:funkin.data.Song):Bool return true;
	public static function isPrefetchedFor(songId:String):Bool return true;
	#end

	public function new(nextState:NextState)
	{
		super();
		this.nextState = nextState;
	}

	// ── UI ─────────────────────────────────────────────────────────────────

	override function create():Void
	{
		persistentUpdate = persistentDraw = true;

		add(new FlxBackdrop(Paths.image('menu/common/starBG')));
		add(new FlxBackdrop(Paths.image('menu/common/starFG')));

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

		// Progress bar
		final barW = Std.int(FlxG.width * 0.6);
		final barH = 18;
		final barX = Std.int((FlxG.width - barW) / 2);
		final barY = Std.int(titleText.y + titleText.height + 40);

		progressBarBg = new FlxSprite(barX - 2, barY - 2).makeGraphic(barW + 4, barH + 4, FlxColor.BLACK);
		progressBarBg.alpha = 0.45;
		progressBarBg.scrollFactor.set();
		add(progressBarBg);

		progressBar = new FlxSprite(barX, barY).makeGraphic(2, barH, ACCENT);
		progressBar.scrollFactor.set();
		add(progressBar);

		progressLabel = new FlxText(0, barY + barH + 12, FlxG.width, '', 18);
		progressLabel.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		progressLabel.borderSize = 2;
		progressLabel.scrollFactor.set();
		add(progressLabel);

		// Tips
		var eligibleTips = TitleState.funFacts.filter(t -> t.songs == null || t.songs.contains(songName));
		var tipEntry = FlxG.random.getObject(eligibleTips);
		var tip:String = (tipEntry != null) ? Lang.str(tipEntry.key, tipEntry.fallback) : '';
		var tipText = new FlxText(100, FlxG.height - 100, FlxG.width - 200, tip, 20);
		tipText.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		tipText.borderSize = 2;
		tipText.scrollFactor.set();
		add(tipText);

		super.create();

		startPreload();
	}

	// ── Update ─────────────────────────────────────────────────────────────

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		#if (sys && cpp)
		// ── Phase A: finalize decoded data on the main thread ───────────
		finalizePendingAssets();

		// ── Phase B: read progress ──────────────────────────────────────
		// Defaults to 0, not 1 -- _totalTasks stays 0 until startPreload()'s
		// synchronous path-collection finishes, right before the background
		// Thread launches. Defaulting to "done" during that window made the
		// bar jump to nearly-full on the very first frame and stay there
		// (looked frozen/stuck) instead of showing real progress from 0%.
		var p:Float = 0.0;
		var label:String = '';
		var done:Bool = false;
		_mutex.acquire();
		if (_totalTasks > 0)
			p = (_completedDecodes + _completedFinalizes) / (_totalTasks * 2.0); // 2 phases per task
		label = _label;
		done  = _allFinalized;
		_mutex.release();

		if (p < 0) p = 0;
		if (p > 1) p = 1;

		// Draw bar
		final maxW = Std.int(FlxG.width * 0.6);
		final w = Std.int(2 + (maxW - 2) * p);
		if (Math.abs(progressBar.scale.x - w / 2.0) > 0.01)
		{
			progressBar.scale.x = w / 2.0;
			progressBar.updateHitbox();
		}
		if (label != progressLabel.text)
			progressLabel.text = label;

		// ── Phase C: switch when ready ──────────────────────────────────
		shownTime += elapsed;
		if (!switching && shownTime >= MIN_SHOW_TIME && done)
		{
			switching = true;
			FlxTransitionableState.skipNextTransIn = true;
			FlxG.switchState(nextState);
		}
		#else
		shownTime += elapsed;
		if (!switching && shownTime >= MIN_SHOW_TIME)
		{
			switching = true;
			FlxTransitionableState.skipNextTransIn = true;
			FlxG.switchState(nextState);
		}
		#end
	}

	// ── Finalize decoded data on the main thread ───────────────────────────

	#if (sys && cpp)
	function finalizePendingAssets():Void
	{
		final cache = FunkinAssets.cache;
		var done = 0;

		// Upload bitmaps to GPU
		while (done < MAX_FINALIZE_PER_FRAME)
		{
			_mutex.acquire();
			if (_pendingBitmaps.length == 0)
			{
				_mutex.release();
				break;
			}
			final entry = _pendingBitmaps.shift();
			_mutex.release();

			try
			{
				cache.cacheBitmap(entry.key, entry.bmd, true);
			}
			catch (e:Dynamic)
			{
				#if android
				Logger.log('LoadingState: GPU upload failed for ${entry.key}: $e', WARN);
				#end
			}

			_mutex.acquire();
			_completedFinalizes++;
			_mutex.release();
			done++;
		}

		// Register audio buffers as Sounds in the mixer
		while (done < MAX_FINALIZE_PER_FRAME)
		{
			_mutex.acquire();
			if (_pendingAudioBuffers.length == 0)
			{
				_mutex.release();
				break;
			}
			final entry = _pendingAudioBuffers.shift();
			_mutex.release();

			try
			{
				final sound = Sound.fromAudioBuffer(entry.buffer);
				cache.cacheSound(entry.key, sound);
			}
			catch (e:Dynamic)
			{
				#if android
				Logger.log('LoadingState: audio register failed for ${entry.key}: $e', WARN);
				#end
			}

			_mutex.acquire();
			_completedFinalizes++;
			_mutex.release();
			done++;
		}

		// All done?
		if (_allFilesOpened && _pendingBitmaps.length == 0 && _pendingAudioBuffers.length == 0)
		{
			_mutex.acquire();
			_allFinalized = true;
			_progress = 1.0;
			_label = 'Ready!';
			_mutex.release();
		}
	}
	#end

	// ── Launch background Thread ───────────────────────────────────────────

	#if (sys && cpp)
	function startPreload():Void
	{
		final song = PlayState.SONG;
		if (song == null) return;

		// Reset static state from any previous run, but keep any
		// BitmapData / AudioBuffer that prefetchSong() already decoded.
		_mutex.acquire();
		_totalTasks = 0;
		_completedDecodes = _pendingBitmaps.length + _pendingAudioBuffers.length; // prefetched
		_completedFinalizes = 0;
		_allFilesOpened = false;
		_allFinalized = false;
		_progress = 0.0;
		_label = '';
		// Do NOT clear _pendingBitmaps or _pendingAudioBuffers —
		// prefetchSong() may have already populated them.
		_mutex.release();

		// Collect every asset path.
		final paths:Array<String> = [];
		final labels:Array<String> = [];

		function addAtlas(assetKey:String, label:String):Void
		{
			final pngPath = resolveLoadPath(Paths.getPath('images/$assetKey.png', 'characters', LOOSE));
			// XML is tiny, loaded on-the-fly later. Only precache the PNG.
			paths.push(pngPath);
			labels.push('$label.png');
		}

		function addSound(basePath:String, label:String):Void
		{
			for (ext in ['ogg', 'wav'])
			{
				final p = '$basePath.$ext';
				if (FunkinAssets.exists(p))
				{
					paths.push(resolveLoadPath(p));
					labels.push(label);
					return;
				}
			}
		}

		// Stage
		final stageFile = funkin.data.StageData.getStageFile(song.stage);
		if (stageFile != null && stageFile.stageObjects != null)
		{
			for (obj in stageFile.stageObjects)
			{
				if (obj.asset == null) continue;
				for (asset in obj.asset.split(','))
				{
					final t = StringTools.trim(asset);
					if (t.length > 0) addAtlas(t, 'stage:$t');
				}
			}
		}

		// Characters
		final chars:Array<String> = [song.player1, song.player2];
		if (song.gfVersion != null && song.gfVersion.length > 0)
			chars.push(song.gfVersion);
		for (charName in chars)
		{
			final info = CharacterParser.fetchInfoUnsafe(charName);
			if (info == null || info.image == null) continue;
			for (img in info.image.split(','))
			{
				final t = StringTools.trim(img);
				if (t.length > 0) addAtlas(t, '$charName:$t');
			}
		}

		// Audio
		final songName = Paths.sanitize(song.song);
		addSound(Paths.getPath('songs/$songName/Inst', null, LOOSE), 'Inst');
		addSound(Paths.getPath('songs/$songName/Voices', null, LOOSE), 'Voices');

		// Notes
		addAtlas('NOTE_assets', 'notes');
		addAtlas('noteskins/default', 'noteskin');

		if (paths.length == 0)
		{
			_mutex.acquire();
			_allFilesOpened = true;
			_allFinalized = true;
			_progress = 1.0;
			_label = 'Nothing to preload';
			_mutex.release();
			return;
		}

		_totalTasks = paths.length;

		// Count already-prefetched items so the progress bar doesn't reset.
		_mutex.acquire();
		_completedDecodes = _pendingBitmaps.length + _pendingAudioBuffers.length;
		if (_totalTasks > 0 && _completedDecodes > 0)
			_progress = _completedDecodes / (_totalTasks * 2.0);
		_mutex.release();

		final myGen = ++_threadGeneration;

		Thread.create(() ->
		{
			for (i in 0...paths.length)
			{
				// Abandon ship: a newer startPreload() / prefetchSong() has
				// reset the static state — our work would pollute it.
				if (_threadGeneration != myGen) return;

				final path = paths[i];
				final lower = path.toLowerCase();

				_mutex.acquire();
				_label = 'Loading ${labels[i]}… (${i + 1}/${paths.length})';
				_mutex.release();

				// Skip if prefetchSong() already decoded this exact path.
				var alreadyDecoded = false;
				_mutex.acquire();
				for (entry in _pendingBitmaps)
				{
					if (entry.key == path) { alreadyDecoded = true; break; }
				}
				if (!alreadyDecoded)
				{
					for (entry in _pendingAudioBuffers)
					{
						if (entry.key == path) { alreadyDecoded = true; break; }
					}
				}
				_mutex.release();

				if (alreadyDecoded)
				{
					_mutex.acquire();
					_completedDecodes++; // already done by prefetch
					_mutex.release();
					continue;
				}

				try
				{
					if (StringTools.endsWith(lower, '.png') || StringTools.endsWith(lower, '.jpg'))
					{
						// Phase 1 (thread-safe): decode PNG → raw pixels.
						var bmd:Null<BitmapData> = null;
						if (sys.FileSystem.exists(path))
							bmd = BitmapData.fromFile(path);
						else if (openfl.Assets.exists(path, IMAGE))
							bmd = openfl.Assets.getBitmapData(path, false);

						if (bmd != null)
						{
							_mutex.acquire();
							_pendingBitmaps.push({key: path, bmd: bmd});
							_completedDecodes++;
							_mutex.release();
						}
					}
					else if (StringTools.endsWith(lower, '.ogg'))
					{
						// Phase 1 (thread-safe): decode Vorbis → AudioBuffer.
						final vf = VorbisFile.fromFile(path);
						if (vf != null)
						{
							final buffer = AudioBuffer.fromVorbisFile(vf);
							if (buffer != null)
							{
								_mutex.acquire();
								_pendingAudioBuffers.push({key: path, buffer: buffer});
								_completedDecodes++;
								_mutex.release();
							}
						}
					}
					// XML and WAV aren't pre-decoded — they're fast enough
					// to load synchronously later.
				}
				catch (e:Dynamic)
				{
					#if android
					Logger.log('LoadingState preload: failed $path — $e', WARN);
					#end
					_mutex.acquire();
					_completedDecodes++; // count it so the bar still advances
					_mutex.release();
				}
			}

			_mutex.acquire();
			_allFilesOpened = true;
			_mutex.release();
		});
	}
	#else
	function startPreload():Void {}
	#end
}
