package mobile.backend;

import mobile.backend.DLCManager;
import mobile.backend.DLCManager.DLCEntry;
import mobile.backend.DLCManager.DLCTaskState;

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;
import funkin.Mods;

/**
 * Metadata for a downloadable language font pack.
 */
typedef LangFontPack =
{
	/** content/<id>/ folder name, and the DLCEntry id used for install tracking. */
	var id:String;
	var displayName:String;
	var zipName:String;
	var sha256:String;
	var sizeMb:Float;
}

/**
 * The CJK fonts (Korean, Japanese, Chinese) are ~52MB combined -- most of
 * that never gets looked at by a player who doesn't read those languages.
 * Rather than ship them in every install, they're pulled out of
 * assets/legacy/fonts/ entirely and fetched on demand the first time
 * someone actually picks one of those languages, reusing DLCManager's
 * existing download/verify/extract pipeline (content/<id>/, global:true in
 * meta.json, so Paths.font()'s existing FileSystem-before-Assets check in
 * Paths.hx picks the downloaded file up automatically -- no changes needed
 * there or in Mods.hx).
 */
class LangFontPacks
{
	static final RELEASE_BASE = "https://github.com/jereidk/NightmareVision-Android-Support/releases/download/langs.font-v1/";

	static final PACKS:Map<String, LangFontPack> = [
		"korean" => {
			id: "asian-langs-korean",
			displayName: "Korean",
			zipName: "korean-fonts.zip",
			sha256: "407ed6b853ad4d43289a8f67840e8a4624ebc1dabee15eed0af178b9b48ca0cf",
			sizeMb: 4.3,
		},
		"japanese" => {
			id: "asian-langs-japanese",
			displayName: "Japanese",
			zipName: "japanese-fonts.zip",
			sha256: "bc6d9929c7099b12fa7d3b75dcb29cb642f9ac68d4ff66334f5b6d57ffcdbab8",
			sizeMb: 6.05,
		},
		// zh-cn and zh-tw share the exact same font_replacement targets, so
		// they share one pack/one download instead of fetching it twice.
		"zh-cn" => {
			id: "asian-langs-chinese",
			displayName: "Chinese",
			zipName: "chinese-fonts.zip",
			sha256: "6c35715e607c0235ccf096752ca58c2de90b495b04b462e48c20fbc47c738cf8",
			sizeMb: 17.7,
		},
		"zh-tw" => {
			id: "asian-langs-chinese",
			displayName: "Chinese",
			zipName: "chinese-fonts.zip",
			sha256: "6c35715e607c0235ccf096752ca58c2de90b495b04b462e48c20fbc47c738cf8",
			sizeMb: 17.7,
		},
	];

	/** Ids of packs this session has already started/finished a download for -- avoids re-triggering on every language reload. */
	static var _attempted:Map<String, Bool> = [];

	/**
	 * The pack id our own in-flight DLCManager task belongs to, or null.
	 * DLCManager only ever runs one task at a time (downloadAndInstallAsync
	 * no-ops while BUSY) and clears activeTaskId to "" on success -- so
	 * there's no way to tell from DLCManager's own state alone which entry
	 * just finished. Since nothing else can be BUSY while ours is, whatever
	 * SUCCESS/FAILED transition happens next after we set this must be ours.
	 */
	static var _pendingPackId:Null<String> = null;

	/**
	 * Returns the pack a language needs, or null if that language ships its
	 * fonts bundled (no separate download required).
	 */
	public static function getPack(langCode:String):Null<LangFontPack>
	{
		return PACKS.get(langCode);
	}

	public static function isInstalled(langCode:String):Bool
	{
		final pack = getPack(langCode);
		if (pack == null) return true;
		return DLCManager.isDLCInstalled(pack.id);
	}

	/**
	 * Kicks off a background download+install for `langCode`'s font pack if
	 * (and only if) it needs one and isn't already installed or in flight.
	 * Safe to call on every language switch/reload -- no-ops otherwise.
	 */
	public static function ensureDownloaded(langCode:String):Void
	{
		#if sys
		final pack = getPack(langCode);
		if (pack == null) return;
		if (_attempted.exists(pack.id)) return;
		if (DLCManager.isDLCInstalled(pack.id)) return;
		if (DLCManager.taskState == DLCTaskState.BUSY) return; // another download already running, don't collide

		_attempted.set(pack.id, true);
		_pendingPackId = pack.id;

		Logger.log('[LangFontPacks] Downloading "${pack.displayName}" font pack (~${pack.sizeMb} MB)...', NOTICE);

		final entry:DLCEntry = {
			id: pack.id,
			name: '${pack.displayName} Fonts',
			description: 'Downloadable font pack for ${pack.displayName}.',
			author: 'VS Impostor Legacy',
			version: '1.0',
			sizeMb: pack.sizeMb,
			downloadUrl: RELEASE_BASE + pack.zipName,
			sha256: pack.sha256,
		};

		DLCManager.downloadAndInstallAsync(entry);
		#end
	}

	/**
	 * Polls for completion of a font-pack install kicked off by
	 * ensureDownloaded(), and -- unlike regular DLC, which needs a restart
	 * -- refreshes the mod list right away so the font is usable
	 * immediately. Call this once per frame from somewhere that's always
	 * alive (e.g. MusicBeatState.update()); it's a cheap no-op once there's
	 * nothing left to finish.
	 */
	public static function pollCompletion():Void
	{
		#if sys
		if (_pendingPackId == null) return;
		if (DLCManager.taskState != DLCTaskState.SUCCESS && DLCManager.taskState != DLCTaskState.FAILED) return;

		if (DLCManager.taskState == DLCTaskState.SUCCESS)
		{
			Logger.log('[LangFontPacks] Font pack installed, refreshing mod list.', NOTICE);
			Mods.updateModList();
			Mods.pushGlobalMods();
		}
		else
		{
			Logger.log('[LangFontPacks] Font pack download failed: ${DLCManager.taskMessage}', WARN);
		}

		_pendingPackId = null;

		// Leaving DLCManager.taskState at SUCCESS/FAILED would surface a
		// stale "<font pack> installed!" banner the next time the user
		// opens the actual DLC browser (MobileDLCSubState starts its own
		// fade timer at 0, so it'd replay whatever state DLCManager is
		// still sitting in). Our own completion is already handled above,
		// so put it back to IDLE.
		DLCManager.taskState = DLCTaskState.IDLE;
		#end
	}
}
