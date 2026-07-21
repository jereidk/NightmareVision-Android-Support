package funkin.states.substates;

import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import funkin.backend.MusicBeatSubstate;
import funkin.data.BonusSongDLC;

#if mobile
import mobile.backend.DLCManager;
import mobile.backend.DLCManager.DLCTaskState;
#end

/**
 * Blocking screen shown by FreeplayState.loadSong() when a bonus-shop song
 * is unlocked (purchased, or ClientPrefs.forceUnlock) but its DLC package
 * isn't installed yet -- either BonusSongDLC.beginBackgroundDownload()
 * (fired right after purchase) hasn't finished, or it never got a chance
 * to run (app closed/reopened before it completed).
 *
 * Reuses DLCManager's existing task-state polling (the same fields
 * MobileDLCSubState already reads) instead of inventing a second download
 * pipeline -- this substate only starts a NEW download if one isn't
 * already the active task for this exact id, so it picks up right where a
 * background download left off instead of restarting it.
 */
class BonusDLCDownloadSubstate extends MusicBeatSubstate
{
	var songName:String;
	var onReady:Void->Void;

	#if mobile
	var dlcId:Null<String>;
	var statusText:FlxText;
	var progressBg:FlxSprite;
	var progressFill:FlxSprite;
	var cancelText:FlxText;
	var failed:Bool = false;
	var barW:Int = 500;
	// Guards against spinning fetchRegistryAsync() every single frame if the
	// device has no network -- each failed attempt would otherwise be
	// noticed on the very next update() (taskState FAILED, no matching
	// activeTaskId) and immediately retried. One automatic attempt per time
	// this substate is open; after that, a real failure message sticks and
	// BACK/reopen is the retry (which resets this flag via create()).
	var registryFetchAttempted:Bool = false;
	#end

	public function new(songName:String, onReady:Void->Void)
	{
		super();
		this.songName = songName;
		this.onReady = onReady;
	}

	override function create():Void
	{
		super.create();

		#if mobile
		final bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 8, 200));
		add(bg);

		final titleText = new FlxText(0, FlxG.height * 0.5 - 70, FlxG.width, Lang.str('bonusdlc_downloading_title', 'Downloading Song'), 32);
		titleText.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		add(titleText);

		final barX = Std.int((FlxG.width - barW) / 2);
		final barY = Std.int(FlxG.height * 0.5 - 10);

		final progressBgOutline = new FlxSprite(barX - 2, barY - 2).makeGraphic(barW + 4, 24, FlxColor.BLACK);
		progressBgOutline.alpha = 0.6;
		add(progressBgOutline);

		progressBg = new FlxSprite(barX, barY).makeGraphic(barW, 20, FlxColor.fromRGB(60, 60, 60));
		add(progressBg);

		progressFill = new FlxSprite(barX, barY).makeGraphic(2, 20, 0xFFFF4444);
		add(progressFill);

		statusText = new FlxText(0, barY + 34, FlxG.width, '', 18);
		statusText.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		statusText.borderSize = 1.5;
		add(statusText);

		cancelText = new FlxText(0, barY + 70, FlxG.width, Lang.str('bonusdlc_cancel_hint', 'BACK to cancel'), 16);
		cancelText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.GRAY, CENTER, OUTLINE, FlxColor.BLACK);
		cancelText.borderSize = 1.5;
		add(cancelText);

		dlcId = BonusSongDLC.dlcIdFor(songName);
		if (dlcId == null)
		{
			// Shouldn't happen -- loadSong() only opens this for a gated
			// song -- but fail safely rather than get stuck on a blocking
			// screen forever if it somehow does.
			close();
			if (onReady != null) onReady();
			return;
		}

		ensureDownloadRunning();
		#else
		close();
		if (onReady != null) onReady();
		#end
	}

	#if mobile
	function ensureDownloadRunning():Void
	{
		// Already the active task (started by beginBackgroundDownload()
		// right after purchase, or a previous open of this same substate)
		// -- just keep polling it below, don't start a second one.
		if (DLCManager.taskState == BUSY && DLCManager.activeTaskId == dlcId) return;

		if (DLCManager.taskState == BUSY)
		{
			// Some OTHER task is mid-flight (shouldn't normally happen --
			// this substate is the only other caller of downloadAndInstallAsync
			// besides the purchase-time background kick, and that one
			// targets this exact id). Wait for it to clear rather than
			// stomp it; the next update() poll re-evaluates.
			statusText.text = Lang.str('bonusdlc_waiting', 'Waiting...');
			return;
		}

		final entry = BonusSongDLC.findEntry(dlcId);
		if (entry != null)
		{
			statusText.text = Lang.str('bonusdlc_starting', 'Starting download...');
			DLCManager.downloadAndInstallAsync(entry, BonusSongDLC.installRoot());
		}
		else if (DLCManager.registryData == null && !registryFetchAttempted)
		{
			registryFetchAttempted = true;
			statusText.text = Lang.str('bonusdlc_fetching_registry', 'Fetching download info...');
			DLCManager.fetchRegistryAsync();
		}
		else
		{
			// Either the registry loaded but this id isn't in it (stale
			// registry / bad id), or the one automatic fetch attempt above
			// already failed (no network) -- either way, a real, user-facing
			// failure now instead of retrying forever.
			failed = true;
			statusText.text = Lang.str('bonusdlc_not_found', 'This download is not available right now.');
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (controls.BACK #if android || FlxG.android.justReleased.BACK #end #if mobile || virtualPad?.buttonC?.justPressed == true #end)
		{
			// Deliberately does NOT cancel the DLCManager task itself -- it
			// keeps downloading in the background exactly like the
			// purchase-time kick already does, so backing out here doesn't
			// throw away progress. Re-opening this same song just re-attaches
			// to whatever's still running.
			close();
			return;
		}

		if (failed) return;

		if (BonusSongDLC.isInstalled(songName))
		{
			close();
			if (onReady != null) onReady();
			return;
		}

		switch (DLCManager.taskState)
		{
			case BUSY:
				if (DLCManager.activeTaskId == dlcId)
				{
					final w = Std.int(2 + (barW - 2) * (DLCManager.taskProgress / 100.0));
					if (Math.abs(progressFill.scale.x - w / 2.0) > 0.01)
					{
						progressFill.scale.x = w / 2.0;
						progressFill.updateHitbox();
					}
					statusText.text = DLCManager.taskMessage;
				}
			case FAILED:
				if (DLCManager.activeTaskId == '${dlcId}_failed')
				{
					failed = true;
					statusText.text = DLCManager.taskMessage;
					cancelText.text = Lang.str('bonusdlc_cancel_hint_failed', 'BACK to go back');
				}
				else
				{
					// A failure that isn't ours (e.g. a stray earlier task) --
					// just try again instead of reporting someone else's error.
					ensureDownloadRunning();
				}
			case IDLE, SUCCESS:
				// SUCCESS but isInstalled() above already said false, or IDLE
				// with nothing running -- (re)kick it.
				ensureDownloadRunning();
		}
	}
	#end
}
