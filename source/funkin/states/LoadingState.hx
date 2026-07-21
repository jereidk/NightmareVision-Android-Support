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
import funkin.objects.note.NotePoolPlan;
import funkin.Paths.PathsTestMode;

#if (sys && cpp)
import sys.thread.Thread;
import sys.thread.Mutex;
#end

/**
 * A single background-preloadable file backing one logical asset (a
 * character, a stage prop, a noteskin...). `cacheKey` is the string
 * FunkinAssets.getGraphicUnsafe() / FlxAnimateFrames.getGraphic() will
 * look this decoded data up under LATER, during PlayState's own
 * (synchronous) load -- normally identical to `realPath` (the file this
 * actually reads off disk), except when `realPath` is a `.astc` file
 * standing in for a spritemap that Init.hx's FlxAnimateAssets.list()
 * override always reports under its `.png` name (see
 * LoadingState.resolveAssetTasks()'s own doc comment for why).
 */
typedef PreloadTask = {realPath:String, cacheKey:String, label:String};

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

	/**
	 * Absolute upper bound on how long this screen waits for the background
	 * preload before giving up on it and switching anyway. Without this, a
	 * worker Thread that dies mid-file (a native decoder hang, a genuinely
	 * corrupt asset, anything that doesn't hit one of the try/catch blocks
	 * below) leaves `done` false forever -- update()'s switch condition never
	 * fires, and the player is stuck on this screen permanently with no BACK
	 * handling to escape it. Firing the switch anyway once this elapses isn't
	 * free of a real load: PlayState.create() falls back to loading whatever
	 * wasn't finished synchronously, the exact same path it already used
	 * before this background-preload feature existed -- worst case is one
	 * slow frame, not a stuck game.
	 */
	static inline final MAX_WAIT_TIME:Float = 15.0;

	/** Max GPU uploads per frame to avoid a single-frame stall. */
	/**
	 * Per-frame TIME budget for main-thread finalization (GPU uploads /
	 * mixer registration), in seconds. The old cap was a fixed COUNT
	 * (3 per frame), which doesn't bound frame time at all: one 4096-class
	 * atlas upload can cost 50-100ms on a mobile GPU, so a frame that
	 * happened to pull three of those stalled the render loop for a third
	 * of a second -- with several big characters that repeated frame after
	 * frame, and the "threaded" loading screen still looked frozen. 6ms
	 * leaves most of a 60fps frame (16.6ms) for update+render so the bar
	 * and tips actually animate; at least one item is always processed per
	 * frame so progress can never stall entirely.
	 */
	static inline final FINALIZE_FRAME_BUDGET_S:Float = 0.006;

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
	// .astc files can only be read (bytes off disk) on the worker thread --
	// the actual GL upload needs the render context, so it's deferred to
	// finalizePendingAssets() same as the two queues above. `cacheKey` is
	// what the resulting bitmap gets registered under (see PreloadTask's own
	// doc comment for why that isn't always the same string as `astcPath`).
	static var _pendingAstcTextures:Array<{cacheKey:String, astcPath:String, bytes:haxe.io.Bytes}> = [];
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
			_pendingAstcTextures.resize(0);
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
	 * @return true only for the trivial `song == null` case (nothing to do).
	 *         Otherwise always false -- a Thread was launched and is
	 *         resolving/decoding in the background; even figuring out
	 *         whether there's anything to preload at all now happens on
	 *         that Thread (see its own comment), so this can no longer
	 *         answer synchronously. Callers already treat this as
	 *         fire-and-forget and don't read the return value -- use
	 *         isPrefetchedFor() to poll actual completion.
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

	/**
	 * Resolves a character/stage/noteskin asset key (e.g.
	 * "characters/GF_assets", or a bare stage asset like "stageback") into
	 * every file that actually needs to be read off disk to warm it.
	 *
	 * Two shapes exist in this fork's real asset tree (confirmed directly
	 * against it, not assumed):
	 *  - Flat sparrow atlas: a single `images/$assetKey.png` (+ .xml
	 *    alongside, tiny, loaded on-the-fly later -- not preloaded here),
	 *    optionally with a `.astc` GPU-compressed override next to it.
	 *  - Adobe Animate export: a FOLDER at `images/$assetKey/` holding
	 *    Animation.json plus one or more spritemapN(.astc|.png) +
	 *    spritemapN.json pairs. This is what the MAJORITY of this fork's
	 *    actual characters use -- and the spritemap NAMING isn't uniform
	 *    (this asset tree has both "spritemap1", "spritemap2"... and
	 *    "spritemap-0", "spritemap-1"... conventions), so it can't be
	 *    guessed by sequential probing. This re-uses
	 *    animate.FlxAnimateAssets.list() -- the SAME, already-correct
	 *    function FlxAnimateFrames itself calls internally -- to discover
	 *    them for real, instead of reimplementing that discovery here.
	 *
	 * Before this function existed, callers just assumed
	 * `images/$assetKey.png` unconditionally, which is why this preload
	 * never actually warmed anything for an Animate-format character (the
	 * overwhelming majority of them): that file simply doesn't exist, the
	 * background thread's own try/catch silently swallowed the resulting
	 * miss, and the loading bar kept advancing anyway without having
	 * cached a single byte for it.
	 */
	static function resolveAssetTasks(assetKey:String, label:String):Array<PreloadTask>
	{
		final tasks:Array<PreloadTask> = [];
		final folderKey = Paths.getPath('images/$assetKey', null, LOOSE);

		if (FunkinAssets.exists('$folderKey/Animation.json'))
		{
			// Mirrors FlxAnimateFrames._fromAnimatePath()'s own spritemap
			// discovery exactly (same listWithFilter() call shape), so this
			// finds precisely what that function will look for later.
			final libraryPrefix = folderKey.substring(0, folderKey.indexOf(':'));
			final entries:Array<String> = animate.FlxAnimateAssets.list(folderKey, null, libraryPrefix, false);
			final spriteFiles = entries.filter(f -> f.startsWith('spritemap'));
			final jsonFiles = spriteFiles.filter(f -> f.endsWith('.json'));

			for (sm in jsonFiles)
			{
				final id = sm.split('spritemap')[1].split('.')[0];
				final imageFile = spriteFiles.filter(f -> f.startsWith('spritemap$id') && !f.endsWith('.json'))[0];
				if (imageFile == null) continue;

				// FlxAnimateAssets.list() (Init.hx's override) always
				// reports spritemap images under their .png name, even when
				// the real file on disk is .astc -- that's also the exact
				// string FlxAnimateFrames.getGraphic() will request later,
				// so it's this task's cacheKey regardless of which file
				// resolveSingleImageTask() actually decides to read.
				tasks.push(resolveSingleImageTask('$folderKey/$imageFile', '$label:sm$id'));
			}
		}
		else
		{
			tasks.push(resolveSingleImageTask(Paths.getPath('images/$assetKey.png', null, LOOSE), label));
		}

		return tasks;
	}

	/**
	 * Statically scans a script-built stage's .hx for the assets it loads, so
	 * they can be warmed on the preload thread instead of decoding
	 * synchronously in create(). Covers the asset-loading call shapes that
	 * account for ~95% of real references across this fork's stage scripts:
	 *   images/atlases -- Paths.image(...), Paths.getSparrowAtlas(...),
	 *                     and flixel-animate .loadAtlas(...)
	 *   sounds         -- Paths.sound(...)
	 * each with an argument that's one of:
	 *   ext + 'name'    (ext = the stage's own `ext = '...'` subfolder literal)
	 *   '${ext}name'    (string-interpolated ext prefix)
	 *   'literal/key'   (no variable at all)
	 * Keys built from loop counters / random / other variables are skipped --
	 * they just load on demand as before. Pure text scan: no hscript runs, and
	 * it happens off the main thread. Returns image keys and sound base paths
	 * (the latter ready to hand straight to the preload's addSound()).
	 */
	static function resolveStageScriptAssets(stage:String):{images:Array<String>, sounds:Array<String>}
	{
		final images:Array<String> = [];
		final sounds:Array<String> = [];
		final result = {images: images, sounds: sounds};
		if (stage == null || stage.length == 0) return result;

		// Mirror Stage.runScript()'s own script-file candidates.
		var scriptPath:Null<String> = null;
		for (cand in ['data/stages/$stage/script', 'data/stages/$stage', 'stages/$stage/script', 'stages/$stage'])
		{
			final p = funkin.scripts.FunkinScript.getPath(cand);
			if (FunkinAssets.exists(p, TEXT)) { scriptPath = p; break; }
		}
		if (scriptPath == null) return result;

		final src:String = FunkinAssets.getContent(scriptPath);
		if (src == null || src.length == 0) return result;

		// The stage's `ext = '...'` asset-subfolder literal, if any.
		var ext:String = '';
		final extRe = ~/\bext\s*=\s*['"]([^'"]+)['"]/;
		if (extRe.match(src)) ext = extRe.matched(1);

		// arg-shape matchers, shared by the image and sound passes.
		final concatRe = ~/^ext\s*\+\s*['"]([^'"$]+)['"]$/;   // ext + 'name'
		final interpRe = ~/^['"]\$\{ext\}([^'"$]+)['"]$/;      // '${ext}name'
		final literalRe = ~/^['"]([^'"$]+)['"]$/;              // 'literal'
		function keyFromArg(arg:String):Null<String>
		{
			if (concatRe.match(arg)) return ext + concatRe.matched(1);
			if (interpRe.match(arg)) return ext + interpRe.matched(1);
			if (literalRe.match(arg)) return literalRe.matched(1);
			return null; // dynamic (loop/random/other var)
		}

		final seenImg:Map<String, Bool> = new Map();
		function pushImage(key:String):Void
		{
			if (key == null || key.length == 0 || seenImg.exists(key)) return;
			seenImg.set(key, true);
			// Only keep keys that actually resolve -- a script may reference art
			// conditionally, or a scanned literal may be a false positive.
			// Feeding a nonexistent image key into the preload adds a task that
			// decodes nothing and never advances _completedDecodes, leaving the
			// bar short of 100%. Accept an Animate folder, a flat PNG, or
			// (Android) its .astc sibling. (addSound() self-filters, so sounds
			// don't need this.)
			final folder = Paths.getPath('images/$key', null, LOOSE);
			final png = Paths.getPath('images/$key.png', null, LOOSE);
			final exists = FunkinAssets.exists('$folder/Animation.json')
				|| FunkinAssets.exists(png)
				#if (android && cpp) || FunkinAssets.exists(png.substr(0, png.length - 4) + '.astc') #end;
			if (exists) images.push(key);
		}

		final seenSnd:Map<String, Bool> = new Map();
		function pushSound(key:String):Void
		{
			if (key == null || key.length == 0 || seenSnd.exists(key)) return;
			seenSnd.set(key, true);
			sounds.push(Paths.getPath('sounds/$key', null, LOOSE));
		}

		// Images / atlases: Paths.image, Paths.getSparrowAtlas, .loadAtlas.
		final imgRe = ~/(?:Paths\.image|Paths\.getSparrowAtlas|\bloadAtlas)\s*\(\s*([^,)\n]+)/;
		var rest = src;
		while (imgRe.match(rest))
		{
			pushImage(keyFromArg(StringTools.trim(imgRe.matched(1))));
			rest = imgRe.matchedRight();
			if (images.length >= 128) break; // sanity cap
		}

		// Sounds: Paths.sound.
		final sndRe = ~/Paths\.sound\s*\(\s*([^,)\n]+)/;
		rest = src;
		while (sndRe.match(rest))
		{
			pushSound(keyFromArg(StringTools.trim(sndRe.matched(1))));
			rest = sndRe.matchedRight();
			if (sounds.length >= 64) break; // sanity cap
		}

		return result;
	}

	/**
	 * Resolves one image key (always ending in .png, whether or not that's
	 * the real file on disk) to the task that actually loads it --
	 * preferring a .astc GPU-compressed sibling when one exists AND the
	 * device actually supports ASTC, matching FunkinAssets.getBitmapData()'s
	 * (via AstcLoader.tryLoad()) own preference exactly, so this preload
	 * warms the same representation PlayState will really end up using
	 * instead of wastefully decoding one this device will never render.
	 */
	static function resolveSingleImageTask(pngKey:String, label:String):PreloadTask
	{
		#if (android && cpp)
		if (mobile.backend.AstcSupport.isSupported)
		{
			final astcPath = mobile.backend.AstcLoader.deriveAstcPath(pngKey);
			if (astcPath != null && FunkinAssets.exists(astcPath))
				return {realPath: resolveLoadPath(astcPath), cacheKey: pngKey, label: label};
		}
		#end
		return {realPath: resolveLoadPath(pngKey), cacheKey: pngKey, label: label};
	}

	public static function prefetchSong(song:funkin.data.Song):Bool
	{
		if (song == null) return true;

		// Escape hatch: skip the background prefetch entirely. Deliberately
		// does NOT touch _prefetchComplete/_prefetchForSongId, so
		// isPrefetchedFor() stays honestly "no" for this song -- the caller
		// (PlayState.endSong()'s hybrid check) falls through to routing
		// through LoadingState normally instead of short-circuiting straight
		// to PlayState.new() with nothing actually warmed.
		if (!funkin.data.ClientPrefs.threadedPreload) return true;

		// Reset any previously-stale prefetch state (from a different song).
		_mutex.acquire();
		final hadStaleData = _prefetchForSongId != song.song;
		if (hadStaleData)
		{
			_pendingBitmaps.resize(0);
			_pendingAudioBuffers.resize(0);
			_pendingAstcTextures.resize(0);
			_prefetchComplete = false;
			_prefetchTotal = 0;
			_prefetchDone  = 0;
		}
		_prefetchForSongId = song.song;
		_mutex.release();

		final myGen = ++_threadGeneration;

		Thread.create(() ->
		{
			// Resolving each asset key into real file tasks (resolveAssetTasks())
			// probes the filesystem/asset manifest -- FunkinAssets.exists() and,
			// for every Animate-format character/stage prop, a real directory
			// listing via animate.FlxAnimateAssets.list(). That's cheap for a
			// flat sparrow atlas but not for a roster of Animate characters, and
			// this used to run synchronously on the CALLER's thread (here, the
			// main thread, since prefetchSong() is called from PlayState.endSong()
			// while the score popup is showing) before ever spawning this Thread
			// -- freezing the game for however long collection took. Collecting
			// inside the Thread instead means the caller returns immediately and
			// the freeze is gone; see the same fix in startPreload() below.
			if (_threadGeneration != myGen) return;

			final tasks:Array<PreloadTask> = [];

			function addAtlas(assetKey:String):Void
				for (t in resolveAssetTasks(assetKey, assetKey)) tasks.push(t);

			function addSound(basePath:String):Void
			{
				for (ext in ['ogg', 'wav'])
				{
					final p = '$basePath.$ext';
					if (FunkinAssets.exists(p))
					{
						final resolved = resolveLoadPath(p);
						tasks.push({realPath: resolved, cacheKey: resolved, label: ''});
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

			if (_threadGeneration != myGen) return;

			if (tasks.length == 0)
			{
				_mutex.acquire();
				_prefetchComplete = true;
				_mutex.release();
				return;
			}

			_mutex.acquire();
			_prefetchTotal = tasks.length;
			_prefetchDone  = 0;
			_prefetchComplete = false;
			_mutex.release();

			Logger.log('[LoadingState] prefetch thread: song="${song.song}" — decoding ${tasks.length} asset task(s) in background (lingered on song in Freeplay)', NOTICE, true);

			for (task in tasks)
			{
				if (_threadGeneration != myGen) return;
				final path = task.realPath;
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
							_pendingBitmaps.push({key: task.cacheKey, bmd: bmd});
							_mutex.release();
						}
					}
					else if (StringTools.endsWith(lower, '.astc'))
					{
						// Phase 1 (thread-safe): just read the raw compressed
						// bytes -- the actual GL upload can only run on the
						// main thread (see AstcLoader.loadAndTrack(), called
						// from finalizePendingAssets()).
						var bytes:Null<haxe.io.Bytes> = null;
						if (sys.FileSystem.exists(path))
							bytes = sys.io.File.getBytes(path);
						else if (openfl.Assets.exists(path, BINARY))
							bytes = openfl.Assets.getBytes(path);

						if (bytes != null)
						{
							_mutex.acquire();
							_pendingAstcTextures.push({cacheKey: task.cacheKey, astcPath: path, bytes: bytes});
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
								_pendingAudioBuffers.push({key: task.cacheKey, buffer: buffer});
								_mutex.release();
							}
						}
					}
				}
				catch (_:Dynamic) {}

				_mutex.acquire();
				_prefetchDone++;
				final _justCompleted = (_prefetchDone >= _prefetchTotal && !_prefetchComplete);
				if (_prefetchDone >= _prefetchTotal)
					_prefetchComplete = true;
				final _pdone = _prefetchDone;
				final _ptot = _prefetchTotal;
				_mutex.release();
				if (_justCompleted)
					Logger.log('[LoadingState] prefetch thread: song="${song.song}" fully prefetched ($_pdone/$_ptot) — selecting it now will finalize instantly', NOTICE, true);
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

		#if (sys && cpp)
		_mutex.acquire();
		final _pb = _pendingBitmaps.length;
		final _pa = _pendingAudioBuffers.length;
		final _pt = _pendingAstcTextures.length;
		_mutex.release();
		Logger.log('[LoadingState] ── create: song="$songName" — starting preload. Carrying prefetched pending assets: bmp=$_pb audio=$_pa astc=$_pt', NOTICE, true);
		#end

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
		final timedOut = shownTime >= MAX_WAIT_TIME;
		if (!switching && ((shownTime >= MIN_SHOW_TIME && done) || timedOut))
		{
			if (timedOut && !done)
				Logger.log('LoadingState: preload did not finish after ${MAX_WAIT_TIME}s (progress ${Std.int(p * 100)}%) — switching anyway, PlayState will load the rest synchronously', WARN);

			// Compact the decode garbage the finalize phase just produced (the
			// CPU-side BitmapData/AudioBuffer copies left over after each
			// cacheBitmap/cacheSound) HERE, with the bar already full and the
			// transition about to start -- a natural place for a pause. Left to
			// PlayState.create()'s end-of-create GC alone, that same garbage
			// got compacted later, at the create->countdown boundary, bundled
			// with create's own; splitting it lands each pause where it's least
			// noticeable instead of stacking both right before gameplay.
			FunkinAssets.cache.forceGcPass();

			Logger.log('[LoadingState] ── switching to gameplay after ${Std.int(shownTime * 1000)}ms on screen (progress ${Std.int(p * 100)}%, done=$done, timedOut=$timedOut)', NOTICE, true);

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
		final budgetEnd = haxe.Timer.stamp() + FINALIZE_FRAME_BUDGET_S;
		var done = 0;
		// Shared across all three queues: keep pulling while inside the time
		// budget, but always finalize at least ONE item per frame overall.
		inline function budgetLeft():Bool
			return done == 0 || haxe.Timer.stamp() < budgetEnd;

		// Upload bitmaps to GPU
		while (budgetLeft())
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
		while (budgetLeft())
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

		#if (android && cpp)
		// Upload ASTC (GPU-compressed) textures. This can only ever run here,
		// on the main thread that owns the GL context -- the worker thread
		// already did the safe part (reading the raw bytes off disk).
		while (budgetLeft())
		{
			_mutex.acquire();
			if (_pendingAstcTextures.length == 0)
			{
				_mutex.release();
				break;
			}
			final entry = _pendingAstcTextures.shift();
			_mutex.release();

			try
			{
				final bitmap = mobile.backend.AstcLoader.loadAndTrack(entry.cacheKey, entry.astcPath, entry.bytes);
				if (bitmap != null)
					cache.cacheBitmap(entry.cacheKey, bitmap, false);
			}
			catch (e:Dynamic)
			{
				Logger.log('LoadingState: ASTC upload failed for ${entry.cacheKey}: $e', WARN);
			}

			_mutex.acquire();
			_completedFinalizes++;
			_mutex.release();
			done++;
		}
		#end

		// All done?
		if (_allFilesOpened && _pendingBitmaps.length == 0 && _pendingAudioBuffers.length == 0 && _pendingAstcTextures.length == 0)
		{
			_mutex.acquire();
			final _wasFinalized = _allFinalized;
			_allFinalized = true;
			_progress = 1.0;
			_label = 'Ready!';
			final _dec = _completedDecodes;
			final _fin = _completedFinalizes;
			final _tot = _totalTasks;
			_mutex.release();
			if (!_wasFinalized)
				Logger.log('[LoadingState] finalize: all assets ready ("Ready!") — decoded=$_dec finalized=$_fin of $_tot task(s)', NOTICE, true);
		}
	}
	#end

	// ── Launch background Thread ───────────────────────────────────────────

	#if (sys && cpp)
	function startPreload():Void
	{
		final song = PlayState.SONG;
		if (song == null) return;

		// Escape hatch (ClientPrefs.threadedPreload): skip the worker Thread
		// entirely and land in the exact same terminal state as the "nothing
		// to preload" case below -- update()'s Phase C just waits MIN_SHOW_TIME
		// then switches, and PlayState.create() decodes everything itself the
		// old synchronous way. Bump _threadGeneration first so any prior
		// still-running background thread (e.g. from prefetchSong()) notices
		// and bails out instead of writing into the state we're about to reset.
		if (!funkin.data.ClientPrefs.threadedPreload)
		{
			++_threadGeneration;
			_mutex.acquire();
			_totalTasks = 0;
			_completedDecodes = 0;
			_completedFinalizes = 0;
			_allFilesOpened = true;
			_allFinalized = true;
			_progress = 1.0;
			_label = 'Preparing…';
			_mutex.release();
			Logger.log('[LoadingState] threadedPreload disabled -- skipping background decode, PlayState will load synchronously', NOTICE, true);
			return;
		}

		// Reset static state from any previous run, but keep any
		// BitmapData / AudioBuffer / ASTC bytes that prefetchSong() already
		// decoded.
		_mutex.acquire();
		_totalTasks = 0;
		// (Re)seeded to 0 and authoritatively set once the task list is built
		// below; the decode loop then counts every task exactly once. _totalTasks
		// == 0 pins progress at 0 during this window, so these don't display yet.
		_completedDecodes = 0;
		_completedFinalizes = 0;
		_allFilesOpened = false;
		_allFinalized = false;
		_progress = 0.0;
		_label = 'Preparing…';
		// Do NOT clear _pendingBitmaps / _pendingAudioBuffers / _pendingAstcTextures —
		// prefetchSong() may have already populated them.
		_mutex.release();

		final myGen = ++_threadGeneration;

		Thread.create(() ->
		{
			// Resolving each asset key into real file tasks (resolveAssetTasks())
			// probes the filesystem/asset manifest -- FunkinAssets.exists() and,
			// for every Animate-format character/stage prop, a real directory
			// listing via animate.FlxAnimateAssets.list(). That's cheap for a
			// flat sparrow atlas but not for a roster of Animate characters, and
			// this used to run synchronously in create() -- on the main thread,
			// before this Thread was even spawned -- blocking the whole render
			// loop (progress bar included) for however long collection took.
			// Long enough on a song with several Animate characters to look
			// exactly like a hang: the "Loading" screen would just sit there,
			// frozen, not yet animating, because the frame that would have
			// drawn it hadn't happened yet. Collecting inside the Thread
			// instead means create() returns immediately and the screen
			// actually renders/animates while this work happens.
			if (_threadGeneration != myGen) return;

			final tasks:Array<PreloadTask> = [];

			function addAtlas(assetKey:String, label:String):Void
				for (t in resolveAssetTasks(assetKey, label)) tasks.push(t);

			function addSound(basePath:String, label:String):Void
			{
				for (ext in ['ogg', 'wav'])
				{
					final p = '$basePath.$ext';
					if (FunkinAssets.exists(p))
					{
						final resolved = resolveLoadPath(p);
						tasks.push({realPath: resolved, cacheKey: resolved, label: label});
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

			// Stage — script-built art AND sound. A script stage loads its
			// sprites/atlases (Paths.image/getSparrowAtlas/loadAtlas) and its
			// SFX/ambience (Paths.sound) from its own .hx, all invisible to the
			// stageObjects loop above and decoded synchronously in create().
			// Statically scan the script text and warm whatever it references
			// with string-literal arguments (~95% of real calls in this fork;
			// loop/random/variable keys are left to load on demand as before).
			// Runs on this worker thread -- no main-loop cost.
			final stageAssets = resolveStageScriptAssets(song.stage);
			for (key in stageAssets.images)
			{
				if (_threadGeneration != myGen) return;
				addAtlas(key, 'stage:$key');
			}
			for (basePath in stageAssets.sounds)
			{
				if (_threadGeneration != myGen) return;
				addSound(basePath, 'stagesfx');
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

			// Dialogue -- box/bubble/portrait art readDialogue() (assets/legacy/
			// scripts/dialogue.hx, auto-loaded into every song) builds the
			// instant a story-mode cutscene first triggers mid-song, none of it
			// preloaded -- measured on device as an 800ms+ single-frame decode.
			// dialogue.txt only lists which characters speak; each one's actual
			// portrait atlas comes from data/dialogue/<char>.json's own "asset"
			// field, same lookup dialogue.hx's speakerAnims() does at runtime.
			// Gated on PlayState.seenCutscene (same flag readDialogue() checks)
			// but NOT further narrowed by isStoryMode/videoCheckStory -- a
			// per-song script can override videoCheckStory, which isn't visible
			// here without actually running that script, so this can
			// occasionally warm a portrait a freeplay run never shows. A
			// couple of small UI images is a non-issue next to the
			// note/character/stage assets already decoding on this thread.
			if (!PlayState.seenCutscene)
			{
				final dialogueTxt = Paths.getPath('songs/${Paths.sanitize(song.song)}/dialogue.txt', null, PathsTestMode.NORMAL);
				final dialogueLines = CoolUtil.coolTextFile(dialogueTxt);
				if (dialogueLines.length > 0)
				{
					addAtlas('ui/dialogue/dialogueBox', 'dialogue');
					addAtlas('ui/dialogue/bubble', 'dialogue');

					final seenChars:Map<String, Bool> = new Map();
					for (line in dialogueLines)
					{
						if (_threadGeneration != myGen) return;

						final splitName = line.split(':');
						if (splitName.length < 2) continue;

						final charKey = splitName[1];
						if (charKey.length == 0 || seenChars.exists(charKey)) continue;
						seenChars.set(charKey, true);

						final charPath = Paths.getPath('data/dialogue/$charKey.json', null, PathsTestMode.NORMAL);
						if (!FunkinAssets.exists(charPath, TEXT)) continue;

						final dialogueChar:Dynamic = FunkinAssets.parseJson5(FunkinAssets.getContent(charPath));
						final asset:String = (dialogueChar != null) ? dialogueChar.asset : null;
						if (asset != null && asset.length > 0) addAtlas('ui/dialogue/characters/$asset', 'dialogue:$asset');
					}
				}
			}

			// Audio. Mirrors SyncedFlxSoundGroup.populate()'s own path
			// resolution (Paths.inst/voices/trackSwap) so the exact files the
			// song will actually load get decoded on this thread instead of
			// synchronously in PlayState.create(). Previously only the flat
			// Inst/Voices pair was covered, so a song using the songs/<name>/
			// audio/ subfolder, split vocals (Voices-player/Voices-opp), or a
			// trackSwap (Track-main/Track-miss) decoded all of it on the main
			// thread mid-create -- a chunk of the post-bar hitch.
			final songName = Paths.sanitize(song.song);
			// audio/ subfolder variant takes precedence, same check populate() makes.
			final audioBase = FunkinAssets.isDirectory(Paths.getPath('songs/$songName/audio', null, LOOSE))
				? '$songName/audio' : '$songName';

			if (song.trackSwap == true)
			{
				addSound(Paths.getPath('songs/$audioBase/Track-main', null, LOOSE), 'Track');
				addSound(Paths.getPath('songs/$audioBase/Track-miss', null, LOOSE), 'Track-miss');
			}
			else
			{
				addSound(Paths.getPath('songs/$audioBase/Inst', null, LOOSE), 'Inst');
				if (song.needsVoices)
				{
					// Flat Voices (mono) OR split Voices-player/Voices-opp --
					// addSound() no-ops on any that don't exist, so covering all
					// three is safe and matches whichever layout the song uses.
					addSound(Paths.getPath('songs/$audioBase/Voices', null, LOOSE), 'Voices');
					addSound(Paths.getPath('songs/$audioBase/Voices-player', null, LOOSE), 'Voices-player');
					addSound(Paths.getPath('songs/$audioBase/Voices-opp', null, LOOSE), 'Voices-opp');
				}
			}

			// Notes
			addAtlas('NOTE_assets', 'notes');
			addAtlas('noteskins/default', 'noteskin');

			// Note pool pre-warm plan: a sweep-line pass over the ALREADY-KNOWN
			// full chart (song.notes) to find, per (field, direction) bucket,
			// how many notes are ever alive at once -- pure chart-data work, no
			// Flixel/GL objects touched, so it's safe here on the worker
			// thread. PlayState.prewarmNotePool() (called from
			// generatePlayfields(), once real PlayField._skin instances exist)
			// consumes this to build exactly that many already-reloaded dead
			// notes per bucket instead of discovering the need one cold
			// reloadNote() at a time during real gameplay. See
			// NotePoolPlan.hx's own class doc for the full reasoning.
			NotePoolPlan.computeAndStore(song);

			if (_threadGeneration != myGen) return;

			if (tasks.length == 0)
			{
				_mutex.acquire();
				_allFilesOpened = true;
				_allFinalized = true;
				_progress = 1.0;
				_label = 'Nothing to preload';
				_mutex.release();
				Logger.log('[LoadingState] preload thread: nothing to preload (0 tasks) — ready immediately', NOTICE, true);
				return;
			}

			// Start the decode count at 0 -- the loop below counts EVERY task
			// exactly once (already-prefetched ones via the alreadyDecoded
			// branch's ++, fresh ones after decoding), so it lands at
			// tasks.length when done. Seeding it with the prefetched count here,
			// as before, double-counted those items (seed + the loop's ++),
			// pushing the bar ahead of the real progress -- worse the more the
			// prefetch had covered. Prefetched items are processed instantly in
			// the loop (no decode), so the bar still climbs to reflect them
			// within the first pass rather than sitting at 0.
			_mutex.acquire();
			_totalTasks = tasks.length;
			_completedDecodes = 0;
			_mutex.release();

			Logger.log('[LoadingState] preload thread: collected ${tasks.length} asset task(s) — decoding on background thread', NOTICE, true);

			for (i in 0...tasks.length)
			{
				// Abandon ship: a newer startPreload() / prefetchSong() has
				// reset the static state — our work would pollute it.
				if (_threadGeneration != myGen) return;

				final task = tasks[i];
				final path = task.realPath;
				final lower = path.toLowerCase();

				_mutex.acquire();
				_label = 'Loading ${task.label}… (${i + 1}/${tasks.length})';
				_mutex.release();

				// Skip if prefetchSong() already decoded this exact cache key.
				var alreadyDecoded = false;
				_mutex.acquire();
				for (entry in _pendingBitmaps)
				{
					if (entry.key == task.cacheKey) { alreadyDecoded = true; break; }
				}
				if (!alreadyDecoded)
				{
					for (entry in _pendingAudioBuffers)
					{
						if (entry.key == task.cacheKey) { alreadyDecoded = true; break; }
					}
				}
				if (!alreadyDecoded)
				{
					for (entry in _pendingAstcTextures)
					{
						if (entry.cacheKey == task.cacheKey) { alreadyDecoded = true; break; }
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
							_pendingBitmaps.push({key: task.cacheKey, bmd: bmd});
							_completedDecodes++;
							_mutex.release();
						}
					}
					else if (StringTools.endsWith(lower, '.astc'))
					{
						// Phase 1 (thread-safe): just read the raw compressed
						// bytes -- the actual GL upload can only run on the
						// main thread (see AstcLoader.loadAndTrack(), called
						// from finalizePendingAssets()).
						var bytes:Null<haxe.io.Bytes> = null;
						if (sys.FileSystem.exists(path))
							bytes = sys.io.File.getBytes(path);
						else if (openfl.Assets.exists(path, BINARY))
							bytes = openfl.Assets.getBytes(path);

						if (bytes != null)
						{
							_mutex.acquire();
							_pendingAstcTextures.push({cacheKey: task.cacheKey, astcPath: path, bytes: bytes});
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
								_pendingAudioBuffers.push({key: task.cacheKey, buffer: buffer});
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

			// Every write inside the loop above bails out via the
			// _threadGeneration check at its top the moment a newer
			// startPreload()/prefetchSong() supersedes this run -- but this
			// tail line sat outside that loop, unguarded, so a thread that
			// legitimately finished its OWN last iteration (generation still
			// matched at that point) could still reach here and stamp
			// _allFilesOpened = true onto a NEWER generation's fresh state if
			// that newer run started in the split second before this line
			// executes. finalizePendingAssets() would then see "all files
			// opened" with empty pending queues (the new thread hasn't
			// decoded anything yet) and conclude the NEW load is done --
			// switching to PlayState before its assets are actually ready.
			_mutex.acquire();
			final _stillCurrent = (_threadGeneration == myGen);
			if (_stillCurrent) _allFilesOpened = true;
			final _dec = _completedDecodes;
			final _tot = _totalTasks;
			_mutex.release();
			if (_stillCurrent)
				Logger.log('[LoadingState] preload thread: background decode finished ($_dec/$_tot) — main thread will finalize (GPU upload / audio register)', NOTICE, true);
		});
	}
	#else
	function startPreload():Void {}
	#end
}
