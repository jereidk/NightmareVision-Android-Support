package funkin.data;

#if mobile
import flixel.util.FlxTimer;
import mobile.backend.DLCManager;
import mobile.backend.DLCManager.DLCEntry;
#end

/**
 * Maps the "Bonus Songs" week's shop-purchasable songs (weekBonus.json --
 * Ow, Who, Insane Streamer, Sussus Nuzzus, Idk, Esculent, Drippypop,
 * Crewicide, Monotone Attack, Top 10) to their individual DLC package ids.
 *
 * Each of these 10 songs ships as its OWN small DLC (chart+audio+exclusive
 * character/stage art) instead of the whole week as one bundle -- buying
 * just one shouldn't force downloading the other nine. weekBonus.json
 * itself (names/prices/icons, all tiny) stays bundled in the APK so the
 * shop cards can render and be purchased before anything is downloaded;
 * only the heavy per-song assets are DLC-gated.
 *
 * Explicit hardcoded map rather than deriving the id from the song name
 * (e.g. 'weekbonus-' + Paths.sanitize(name)) -- a wrong guess here would
 * silently fail to find the entry instead of erroring, and there are only
 * ever exactly 10 of these, so there's nothing saved by deriving it.
 */
class BonusSongDLC
{
	static final _ids:Map<String, String> = [
		'Ow' => 'weekbonus-ow',
		'Who' => 'weekbonus-who',
		'Insane Streamer' => 'weekbonus-insane-streamer',
		'Sussus Nuzzus' => 'weekbonus-sussus-nuzzus',
		'Idk' => 'weekbonus-idk',
		'Esculent' => 'weekbonus-esculent',
		'Drippypop' => 'weekbonus-drippypop',
		'Crewicide' => 'weekbonus-crewicide',
		'Monotone Attack' => 'weekbonus-monotone-attack',
		'Top 10' => 'weekbonus-top-10',
	];

	/** Null if `songName` isn't one of this DLC set's songs -- never gates anything else. */
	public static inline function dlcIdFor(songName:String):Null<String>
		return _ids.get(songName);

	/**
	 * True for any song this class doesn't gate at all (nothing to check),
	 * or one whose DLC package is actually present on disk.
	 */
	public static function isInstalled(songName:String):Bool
	{
		final id = dlcIdFor(songName);
		if (id == null) return true;
		#if mobile
		return DLCManager.isDLCInstalled(id);
		#else
		return true;
		#end
	}

	#if mobile
	/**
	 * Fire-and-forget: called right after a successful shop purchase (see
	 * FreeplayState.acceptSong()) so the download is very likely already
	 * done by the time the player actually presses play. This is a
	 * best-effort nicety, NOT the safety net -- FreeplayState.loadSong()'s
	 * own gate is what actually guarantees the files exist before a song
	 * starts, and shows the blocking download substate if this background
	 * attempt hasn't finished (or never started -- e.g. the app was closed
	 * and reopened before it completed).
	 *
	 * No-ops if already installed, if a DLCManager task is already running
	 * (never stomps an in-flight download/install), or if the registry
	 * doesn't have this id for some reason (stale registry, id typo) --
	 * loadSong()'s substate retries the lookup properly and surfaces a real
	 * error to the player if it's still missing there.
	 */
	public static function beginBackgroundDownload(songName:String):Void
	{
		final id = dlcIdFor(songName);
		if (id == null || DLCManager.isDLCInstalled(id)) return;
		if (DLCManager.taskState == BUSY) return;

		function tryStart():Void
		{
			if (DLCManager.taskState == BUSY) return;
			final entry = findEntry(id);
			if (entry != null) DLCManager.downloadAndInstallAsync(entry);
		}

		if (DLCManager.registryData != null)
		{
			tryStart();
			return;
		}

		// Registry not fetched yet this session -- kick off the fetch and
		// give it a few short retries. Bounded (6 x 0.5s = 3s) since this is
		// only the background nicety; if the network is slow or down,
		// loadSong()'s own gate fetches/retries again for real later.
		DLCManager.fetchRegistryAsync();
		new FlxTimer().start(0.5, function(_)
		{
			if (DLCManager.registryData != null) tryStart();
		}, 6);
	}

	public static function findEntry(id:String):Null<DLCEntry>
	{
		if (DLCManager.registryData == null) return null;
		for (e in DLCManager.registryData.dlcs)
			if (e.id == id) return e;
		return null;
	}
	#else
	public static function beginBackgroundDownload(songName:String):Void {}
	#end
}
