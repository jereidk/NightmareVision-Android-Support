package funkin.objects.note;

/**
 * How many dead, already-reloaded Note objects to pre-warm into
 * PlayState._deadNotesByType for one (field, direction) combination before
 * the song's real countdown ends.
 */
typedef NotePoolBucketPlan =
{
	fieldID:Int,
	noteData:Int,
	count:Int,
}

/**
 * PlayState already pools dead notes by exact (skin, direction) match --
 * see PlayState._deadNotesByType -- but that pool starts EMPTY and only
 * fills as notes die during real gameplay. Two consequences: the FIRST note
 * of every (field, direction) combination always pays a full reloadNote()
 * cold, and any chart section where 2+ notes of the SAME combination are
 * alive at once (chords, jacks, dense/technical patterns) exhausts however
 * many spares happen to be sitting in that bucket and falls through to a
 * real reload for the rest -- this can keep happening for the ENTIRE song,
 * not just at the start, on dense charts.
 *
 * Neither Psych Engine (no note pooling at all -- create/destroy per note)
 * nor Shadow Engine (a single flat pool, no skin/direction bucketing, also
 * lazy/empty-start) pre-warm their pools; this is this fork's own addition,
 * not a port of either.
 *
 * The chart is fully known ahead of time (SONG.notes, built once when the
 * song is picked), so the actual PEAK CONCURRENCY per (field, direction)
 * bucket can be computed with a sweep-line pass over every note's
 * approximate alive window, instead of guessing -- and unlike constructing
 * real Note/NoteSkin display objects, that sweep only touches plain chart
 * data (arrays of floats/ints), so it's safe to run entirely off the main
 * thread. compute() is called from LoadingState's background preload
 * Thread (see LoadingState.startPreload()) for exactly that reason: it
 * moves the one CPU-heavy part of this feature off the render thread,
 * leaving PlayState.create() with only the cheap part -- building however
 * many Note objects each bucket calls for, using the SAME NoteSkin
 * instances generatePlayfields() already built, with textures that are now
 * warm in FunkinCache thanks to LoadingState's normal preload -- see
 * PlayState.prewarmNotePool(), called once generatePlayfields() has real
 * PlayField._skin instances to build against.
 */
class NotePoolPlan
{
	/**
	 * Above this many concurrently-alive notes in one bucket, stop counting
	 * higher -- a chart that dense would mean something is wrong with the
	 * sweep's estimate (or the chart itself), and pre-warming an unbounded
	 * amount of notes up front would trade a mid-song hitch for a worse one
	 * during the countdown. The normal reload fallback still covers
	 * whatever this cap leaves short.
	 */
	static inline final MAX_PER_BUCKET:Int = 12;

	// Conservative, fixed estimates for how long a note stays "alive" in the
	// pool sense (spawned through disposed) -- mirrors PlayState's real
	// spawnTime (3000, divided by songSpeed) and noteKillOffset (~350ms)
	// defaults closely enough for SIZING purposes. This only decides how
	// many spares to pre-build; getting it slightly wrong just means a
	// bucket is a little over- or under-sized, never an incorrect render --
	// any shortfall still falls through to Note.set_texture()'s existing
	// reload path exactly as it did before this feature existed.
	static inline final SPAWN_OFFSET_ESTIMATE_MS:Float = 3000;
	static inline final KILL_OFFSET_ESTIMATE_MS:Float = 350;

	static var _pending:Array<NotePoolBucketPlan> = [];
	static var _pendingSongId:String = '';

	/**
	 * Computes the peak-concurrency pre-warm plan for `song` and stores it
	 * for a later consume() call. Pure data work (chart arrays in, plain
	 * struct array out) -- safe to call from a background Thread, which is
	 * the whole point: LoadingState.startPreload()'s worker calls this so
	 * the sweep never costs the render thread anything.
	 */
	public static function computeAndStore(song:funkin.data.Song):Void
	{
		_pending = compute(song);
		_pendingSongId = (song != null) ? song.song : '';
	}

	/**
	 * Consumes (and clears) whatever computeAndStore() produced for the
	 * given songId. Returns an empty array if nothing was precomputed for
	 * this exact song -- LoadingState's background preload was skipped
	 * (desktop, ClientPrefs.threadedPreload disabled, or it timed out
	 * before finishing) -- in which case PlayState.prewarmNotePool() simply
	 * does nothing and every note pays for its own reload exactly as it did
	 * before this feature existed. Clearing on read means a stale plan can
	 * never leak into a later, unrelated song.
	 */
	public static function consume(songId:String):Array<NotePoolBucketPlan>
	{
		if (_pendingSongId != songId) return [];
		final result = _pending;
		_pending = [];
		_pendingSongId = '';
		return result;
	}

	/**
	 * Sweep-line peak concurrency per (fieldID, noteData) bucket. Mirrors
	 * PlayState.generateSong()'s own note-to-(field,direction) decoding
	 * exactly (songNotes[0]=strumTime, [1]=raw direction+field, [2]=sustain
	 * length; raw/keys=fieldID, raw%keys=noteData; fieldID<0 is a legacy
	 * event note, fieldID>=lanes is out of range) so the buckets this
	 * produces line up with the ones _trackDeadNote()/recycleCompatibleNote()
	 * actually index by by the time real gameplay runs.
	 */
	public static function compute(song:funkin.data.Song):Array<NotePoolBucketPlan>
	{
		final result:Array<NotePoolBucketPlan> = [];
		if (song == null || song.notes == null || song.keys <= 0 || song.lanes <= 0) return result;

		final spawnOffsetEstimate = SPAWN_OFFSET_ESTIMATE_MS / Math.max(song.speed, 0.1);

		// Keyed by a packed (fieldID, noteData) int so this doesn't need an
		// object/tuple key type -- mirrors the same packing the chart's own
		// raw note-data field already uses (fieldID * keys + noteData).
		final events:Map<Int, Array<{time:Float, delta:Int}>> = new Map();

		for (section in song.notes)
		{
			if (section == null || section.sectionNotes == null) continue;

			for (songNotes in section.sectionNotes)
			{
				if (songNotes == null || songNotes.length < 3) continue;

				final strumTime:Float = songNotes[0];
				final rawData:Int = Std.int(songNotes[1]);
				final susLength:Float = songNotes[2];

				final noteData:Int = Std.int(rawData % song.keys);
				final fieldID:Int = Std.int(rawData / song.keys);
				if (fieldID < 0 || fieldID >= song.lanes) continue; // legacy event note / out of range

				final key = fieldID * song.keys + noteData;
				var arr = events.get(key);
				if (arr == null)
				{
					arr = [];
					events.set(key, arr);
				}

				final windowStart = strumTime - spawnOffsetEstimate;
				final windowEnd = strumTime + Math.max(susLength, 0) + KILL_OFFSET_ESTIMATE_MS;
				arr.push({time: windowStart, delta: 1});
				arr.push({time: windowEnd, delta: -1});
			}
		}

		for (key => arr in events)
		{
			// +1 events before -1 events at the same timestamp -- touching
			// intervals count as overlapping, which only ever rounds the
			// estimate UP, never causes an under-count.
			arr.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : (a.delta > b.delta ? -1 : 1)));

			var current = 0, peak = 0;
			for (ev in arr)
			{
				current += ev.delta;
				if (current > peak) peak = current;
			}
			if (peak <= 0) continue;

			final count = (peak > MAX_PER_BUCKET) ? MAX_PER_BUCKET : peak;
			result.push({fieldID: Std.int(key / song.keys), noteData: key % song.keys, count: count});
		}

		return result;
	}
}
