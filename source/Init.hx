package;

import funkin.FunkinAssets;

import flixel.FlxState;
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;

import funkin.backend.math.Vector3;
import funkin.backend.Logger;
import funkin.backend.Logger.Severity;
import StringTools;

/**
 * Initiation state that prepares backend classes and returns to menus when finished
 * 
 * There is no need to open this beyond the first time
 */
@:nullSafety(Strict)
class Init extends FlxState
{
	override public function create():Void
	{
		// DebugDisplay starts early (no prefs needed). Log files need ClientPrefs,
		// so GameLogger/SystemMonitor init below after ClientPrefs.load().
		#if android
		funkin.backend.DebugDisplay.init();

		// Register cache info plugin for DebugDisplay
		funkin.backend.DebugDisplay.addPlugin(function():String {
			var info = '';
			var gCount = 0;
			var sCount = 0;
			var gpuEst = 0.0;
			var lastGraphics:Array<String> = [];
			var lastSounds:Array<String> = [];
			try {
				for (key in FunkinAssets.cache.currentTrackedGraphics.cache.keys()) {
					gCount++;
					// Solo los últimos 3 para no saturar
					if (lastGraphics.length < 3) lastGraphics.push(key);
				}
				for (key in FunkinAssets.cache.currentTrackedSounds.cache.keys()) {
					sCount++;
					if (lastSounds.length < 3) lastSounds.push(key);
				}
				gpuEst = gCount * 0.5;
			} catch (e:Dynamic) {
				Logger.log('Failed to get asset cache info: $e', WARN);
			}

			info = 'Loaded: $gCount graphics, $sCount sounds (GPU ~${Std.int(gpuEst)}MB)';
			if (lastGraphics.length > 0) {
				info += '\nLast graphics:';
				for (g in lastGraphics) {
					// Solo nombre del archivo, no ruta completa
					var shortName = g.split('/').pop();
					if (shortName != null) shortName = shortName.split('\\').pop();
					if (shortName == null) shortName = g;
					if (shortName.length > 25) shortName = shortName.substr(0, 22) + '...';
					info += '\n  - $shortName';
				}
			}
			return info;
		});
		#end

		// ── Crash detection (runs before anything else) ───────────────────────
		#if android
		final _crashLogPath = mobile.backend.StorageSystem.getDirectory() + 'crash.log';

		// Install Java-level uncaught exception handler. Catches JVM/JNI
		// crashes that happen outside the Haxe exception pipeline and writes
		// them to crash.log before the process dies.
		try { mobile.backend.JavaCrashHandler.install(_crashLogPath); }
		catch (e:Dynamic) { Logger.log('Failed to install Java crash handler: $e', WARN); }

		// 1. crash.log written by CrashHandler (Haxe exception) or by the
		//    Java handler (JVM crash) during the previous session.
		//    We collect the message here but defer the popup until after
		//    ClientPrefs.load() so we can offer backup restore if available.
		var _pendingCrashMessage:Null<String> = null;
		#if sys
		try
		{
			var crashLogMessage:Null<String> = null;
			if (sys.FileSystem.exists(_crashLogPath))
			{
				final log = sys.io.File.getContent(_crashLogPath);
				sys.FileSystem.deleteFile(_crashLogPath);
				crashLogMessage = log.length > 900 ? log.substr(0, 900) + '\n[truncated…]' : log;
			}

			// 2. Always ALSO check Android's own exit record (API 30+),
			//    regardless of whether crash.log existed above -- this catches
			//    native SIGSEGV / OOM / ANR from the previous session that
			//    killed the process before any handler could write. Native
			//    trace data lives in a system-wide circular buffer shared with
			//    every other app on the device (confirmed via ApplicationExitInfo's
			//    own docs), so skipping this check on a launch that happened to
			//    also have a pending crash.log would risk losing that trace for
			//    good to another app's crash evicting it, not just delaying
			//    when we'd notice it.
			var nativeInfo = mobile.backend.JavaCrashHandler.readPreviousNativeCrash();
			// Resolves each reported trace's crashing thread against the
			// bundled per-ABI symbol table (see resolveNativeCrashTraces()'s
			// own doc comment) -- best-effort, never removes anything from
			// the original summary even if resolution fails entirely.
			if (nativeInfo != null) nativeInfo = resolveNativeCrashTraces(nativeInfo);

			if (crashLogMessage != null && nativeInfo != null && nativeInfo.length > 0)
				_pendingCrashMessage = crashLogMessage + '\n\n=== Crash nativo (misma o distinta sesión) ===\n\n' + nativeInfo;
			else if (nativeInfo != null && nativeInfo.length > 0)
				_pendingCrashMessage = nativeInfo;
			else
				_pendingCrashMessage = crashLogMessage;

			// Persist the FULL message (untruncated) to disk BEFORE capping it
			// for the in-game popup below -- last_crash_summary.log is meant
			// to be pulled off the device and inspected on a PC, so there's
			// no reason to clip it the same way the popup needs to be. This
			// used to run AFTER the 2000-char cap below, silently losing most
			// of a resolved on-device backtrace (demangled C++ template
			// signatures alone can easily blow past 2000 chars for a handful
			// of frames) -- confirmed via a real device trace whose saved
			// last_crash_summary.log cut off mid-frame.
			//
			// Independent of the popup below and of GameLogger (which isn't
			// initialized yet -- it waits on ClientPrefs.load(), see the
			// comment near the top of this function). readPreviousNativeCrash()
			// already marked this exit as "seen" on the Java side the instant
			// it was read (JavaCrashHandler.java's saveLastSeenTimestamp()),
			// so if THIS session also crashes before ever reaching the popup
			// at super.create() below -- a real observed case, back-to-back
			// crashes a few seconds apart -- the summary would otherwise be
			// gone for good: Android's own history never re-reports an exit
			// once its timestamp has been consumed.
			if (_pendingCrashMessage != null)
			{
				try
				{
					sys.io.File.saveContent(
						mobile.backend.StorageSystem.getDirectory() + 'last_crash_summary.log',
						'[' + Date.now().toString() + ']\n' + _pendingCrashMessage
					);
				}
				catch (e:Dynamic) {}
			}

			// readPreviousNativeCrash() can now report several accumulated exits
			// at once (see JavaCrashHandler.java) -- cap the POPUP (not the file
			// already saved above) the same way crash.log's own content already
			// was, so a long stretch without launching the app can't balloon
			// this into an unreadable wall of text in PopUp's dialog.
			if (_pendingCrashMessage != null && _pendingCrashMessage.length > 2000)
				_pendingCrashMessage = _pendingCrashMessage.substr(0, 2000) + '\n[truncated…]';
		}
		catch (e:Dynamic) { Logger.log('Failed to check for previous crashes: $e', WARN); }
		#end
		#end
		// ──────────────────────────────────────────────────────────────────────

		// Probe GL for ASTC extension support as early as possible.
		// The GL context is guaranteed to be live by the time Init runs.
		#if (android && cpp)
		mobile.backend.AstcSupport.check();
		mobile.backend.AstcLoader.installContextHandler();
		#end

		// Route FlxAnimate spritemap texture loads through FunkinAssets so that
		// ASTC overrides and external-storage paths are handled transparently.
		// getBitmapData: Null<BitmapData> is fine — FlxAnimate tolerates null returns.
		// exists: drops the AssetType arg since FunkinAssets.exists checks both filesystem
		//   and bundled assets regardless of type.
		// getText: FunkinAssets.getContent throws on missing files; wrap so FlxAnimate
		//   gets null instead (matches the original FlxAnimateAssets behaviour).
		animate.FlxAnimateAssets.getBitmapData = (path) -> cast funkin.FunkinAssets.getBitmapData(path);
		// When the APK ships only .astc (no .png counterpart), FunkinAssets.exists()
		// returns false for the .png path — FlxAnimate then treats the image as
		// missing and eventually calls addChild(null) → Error #2007.
		// Fix: also return true when a .astc counterpart exists for a .png query.
		animate.FlxAnimateAssets.exists = (path, _) -> {
			if (funkin.FunkinAssets.exists(path)) return true;
			#if (android && cpp)
			if (path.endsWith('.png')) {
				var astcPath = mobile.backend.AstcLoader.deriveAstcPath(path);
				return astcPath != null && funkin.FunkinAssets.exists(astcPath);
			}
			#end
			return false;
		};
		animate.FlxAnimateAssets.getText      = (path) -> { try return funkin.FunkinAssets.getContent(path) catch (e:Dynamic) { Logger.log('Failed to get text content for: $path - $e', WARN); return cast null; }; };
		// Replace .astc with .png in FlxAnimate's folder scanner so spritemap
		// image selection always resolves to a .png counterpart that FlxAnimate
		// expects. The getBitmapData override above then transparently loads the
		// .astc GPU texture for that path via AstcLoader, making ASTC compression
		// safe even when only .astc exists (no .png counterpart).
		// NOTE: Filtering out .astc (old approach) breaks spritemaps that ONLY
		// have .astc — FlxAnimate cannot find the image file and the path becomes
		// "$path/null", causing a hard crash when entering songs.
		final _animListOrig = animate.FlxAnimateAssets.list;
		animate.FlxAnimateAssets.list = function(path, ?type, ?lib, subs = false) {
			var r = _animListOrig(path, type, lib, subs);
			if (r == null) return [];
			return r.map(f -> f.endsWith('.astc') ? f.substr(0, f.length - 5) + '.png' : f);
		};

		// load settings/save
		funkin.input.Controls.init();
		
		ClientPrefs.load();

		// Safe mode: an external, file-based escape hatch for settings that can
		// leave the screen unusable from inside the game itself (e.g. forcing
		// Virtual Pad nav when touch would still work) -- reachable through the
		// phone's own file manager even when the game can't be seen or navigated
		// at all. Drop an empty SAFE_MODE.txt directly in the .ImpostorLegacy
		// folder (same folder "Open Data Folder" opens) and the next launch
		// resets these to their defaults and deletes the marker.
		#if (android && sys)
		try
		{
			final safeModePath = mobile.backend.StorageSystem.getStorageDirectory() + 'SAFE_MODE.txt';
			if (sys.FileSystem.exists(safeModePath))
			{
				ClientPrefs.navInputMode = 'Touch';
				ClientPrefs.flush();
				sys.FileSystem.deleteFile(safeModePath);
				Logger.log('[SafeMode] SAFE_MODE.txt found -- reset nav input mode to default', NOTICE, true);
			}
		}
		catch (e:Dynamic)
		{
			Logger.log('[SafeMode] Failed to check/apply SAFE_MODE.txt: $e', WARN);
		}
		#end

		funkin.backend.GameLogger.init();
		funkin.backend.SystemMonitor.init();
		funkin.data.Highscore.load();
		
		if (FlxG.save.data.weekCompleted != null) funkin.states.StoryMenuState.weekCompleted = FlxG.save.data.weekCompleted;
		
		FlxSprite.defaultAntialiasing = ClientPrefs.globalAntialiasing;
		
		DiscordClient.check();  // Upstream: checks ClientPrefs.discordRPC before init
		
		#if MODS_ALLOWED
		// Populate Mods.enabled from modsList.txt first — pushGlobalMods/loadTopMod
		// read from it, so without this the top mod and global mods (e.g. installed
		// DLC) stay unset until the first MusicBeatState refresh.
		funkin.Mods.updateModList();
		funkin.Mods.pushGlobalMods();
		funkin.Mods.loadTopMod();
		funkin.FunkinAssets.invalidateAssetListCache(); // Refresh asset list after loading mods
		funkin.Paths.invalidateModPathCache();
		#end
		
		// Make mod folder visible in Android file managers (like FunkinCrew/Funkin's "Data Folder")
		#if android
		mobile.backend.AndroidUtils.scanModFolder();
		#end
		
		// set some flixel settings
		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = 60;
		FlxG.sound.muteKeys = ClientPrefs.muteKeys;
		FlxG.sound.volumeDownKeys = ClientPrefs.volumeDownKeys;
		FlxG.sound.volumeUpKeys = ClientPrefs.volumeUpKeys;
		FlxG.keys.preventDefaultKeys = [TAB];
		FlxG.mouse.visible = false;
		FlxG.plugins.drawOnTop = true;
		
		FlxG.scaleMode = new funkin.backend.FunkinRatioScaleMode();
		FlxG.signals.preStateSwitch.add((cast FlxG.scaleMode : funkin.backend.FunkinRatioScaleMode).resetSize);
		
		FlxG.sound.music = new extensions.flixel.FlxSoundEx();
		FlxG.sound.music.persist = true;
		
		FlxG.autoPause = ClientPrefs.autoPause;
		
		// ready backends
		funkin.data.Lang.reloadLangFile();

		funkin.backend.plugins.HotReloadPlugin.init();
		
		funkin.backend.plugins.DebugTextPlugin.init();
		
		funkin.backend.plugins.FullScreenPlugin.init();
		
		funkin.scripts.FunkinScript.init();
		
		#if VIDEOS_ALLOWED
		funkin.video.FunkinVideoSprite.init();
		#end
		
		#if FEATURE_DEBUG_TRACY
		funkin.utils.WindowUtil.initTracy();
		#end
		
		funkin.scripting.PluginsManager.prepareSignals();
		funkin.scripting.PluginsManager.populate();
		
		FunkinAssets.cache.currentTrackedSounds.addPermanentKey('assets/music/freakyMenu.ogg');
		
		super.create();

		// ── Crash recovery dialog ─────────────────────────────────────────────
		// Shown here (after ClientPrefs.load) so we know save + backups are ready.
		// PopUp.showConfirm is non-blocking on Android: the dialog appears over the
		// loading screen, the game transitions behind it, and the callback fires on
		// the Haxe thread when the user responds.
		#if android
		if (_pendingCrashMessage != null)
		{
			if (funkin.data.ClientPrefs.hasBackup())
			{
				mobile.backend.utils.PopUp.showConfirm(
					'El juego se cerró inesperadamente',
					_pendingCrashMessage + '\n\n¿Restaurar el backup del progreso anterior?',
					'Restaurar backup',
					'Continuar sin restaurar',
					() -> {
						final backupData = funkin.data.ClientPrefs.attemptLoadBackup();
						if (backupData != null && Reflect.fields(backupData).length > 0)
						{
							for (field in (Reflect.fields(backupData) : Array<String>))
								Reflect.setField(FlxG.save.data, field, Reflect.field(backupData, field));
							funkin.data.ClientPrefs.load();
							funkin.data.ClientPrefs.flushSave();
							mobile.backend.utils.PopUp.showAlert('Backup restaurado', 'Tu progreso fue restaurado al estado anterior al crash.', 'OK');
						}
						else
						{
							mobile.backend.utils.PopUp.showAlert('Sin backup disponible', 'No se encontró un backup válido.', 'OK');
						}
					},
					null
				);
			}
			else
			{
				mobile.backend.utils.PopUp.showAlert('El juego se cerró inesperadamente', _pendingCrashMessage, 'OK');
			}
		}
		#end
		// ─────────────────────────────────────────────────────────────────────

		// Signal OS that we finished loading and are entering menus (not active gameplay).
		#if android
		mobile.backend.AndroidUtils.setGameplayState(false);
		#end

		final nextState:Class<FlxState> = Main.startMeta.skipSplash || !ClientPrefs.toggleSplashScreen ? Main.startMeta.initialState : Splash;
		FlxG.switchState(() -> Type.createInstance(nextState, []));
	}

	#if (android && sys)
	/**
	 * Extracts every "Trace guardado en: <path>" entry from
	 * JavaCrashHandler.readPreviousNativeCrash()'s summary text, resolves
	 * each trace's crashing thread's unresolved (our own, stripped-code)
	 * frames against the bundled per-ABI symbol table (see
	 * TombstoneParser/SymbolResolver's own doc comments), and appends a
	 * human-readable resolved-backtrace block right after each matching
	 * line -- the popup and last_crash_summary.log then show function
	 * names directly, without needing the CI Symbolicate job or the full
	 * unstripped .so this session's crash hunts otherwise required.
	 *
	 * Best-effort throughout: any failure for a given trace (missing symbol
	 * table for this build, corrupt/foreign trace, nothing to resolve) just
	 * skips that one trace -- the original summary text is never altered or
	 * removed, only ever appended to.
	 */
	static function resolveNativeCrashTraces(info:String):String
	{
		final marker = 'Trace guardado en: ';
		final lines = info.split('\n');
		final out:Array<String> = [];

		for (line in lines)
		{
			out.push(line);

			final idx = line.indexOf(marker);
			if (idx < 0) continue;

			final tracePath = line.substr(idx + marker.length);
			if (tracePath.length == 0) continue;

			try
			{
				final resolved = resolveOneTrace(tracePath);
				if (resolved != null) out.push(resolved);
			}
			catch (e:Dynamic) {}
		}

		return out.join('\n');
	}

	static function resolveOneTrace(tracePath:String):Null<String>
	{
		final threadInfo = mobile.backend.TombstoneParser.parse(tracePath);
		if (threadInfo == null) return null;

		final abi = mobile.backend.TombstoneParser.readHeaderField(tracePath, 'abi');
		if (!mobile.backend.SymbolResolver.load(abi)) return null;

		final resolvedLines:Array<String> = [];
		for (frame in threadInfo.frames)
		{
			if (frame.funcName != '') continue; // already resolved by the OS's own unwinder
			if (frame.fileName.indexOf('base.apk') < 0) continue; // not our own code

			final name = mobile.backend.SymbolResolver.resolve(frame.relPc);
			if (name == null) continue;

			resolvedLines.push('    0x' + StringTools.hex(frame.relPc) + ': ' + name);
		}

		if (resolvedLines.length == 0) return null;

		return '  Hilo crasheado: ${threadInfo.name} (tid=${threadInfo.tid})\n  Backtrace resuelto:\n' + resolvedLines.join('\n');
	}
	#end
}
