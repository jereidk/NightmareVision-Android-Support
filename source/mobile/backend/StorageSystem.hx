package mobile.backend;

import lime.app.Application;

import haxe.io.Path;
import haxe.io.Bytes;

import openfl.utils.ByteArray;
import openfl.utils.Assets;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** * @Authors StarNova (Cream.BR), LumiCoder (FNF BR)
 * @version 0.1.6
 */
class StorageSystem
{
	private static var folderName(get, never):String;

	private static function get_folderName():String
	{
		return Application.current.meta.get('file');
	}

	// Both getters below end up resolving the Android storage root (either a
	// JNI round-trip to Environment.getExternalStorageDirectory(), or to
	// Context.getInternalFilesDir()/getExternalFilesDir() -- see
	// _androidRoot()) for a value that's constant for the whole process once
	// resolved (it only changes if applyStorageMode() explicitly clears the
	// cache below). Several call sites (CrashHandler, GameLogger,
	// SystemMonitor, GlobalScriptManager, FunkinAssets, AndroidUtils) call
	// getDirectory() well after startup, some potentially repeatedly during a
	// burst of external asset/mod loading — cache each result after the first
	// real computation instead of re-paying the JNI cost every time. A
	// same-value race on first use from DLCManager's background thread is
	// harmless (worst case: computed twice, both give the identical string).
	static var _cachedStorageDirectory:String = null;
	static var _cachedDirectory:String = null;

	#if android
	// Mirrors ClientPrefs.storageMode, but persisted separately as a flat
	// file in Context.getInternalFilesDir() -- real app-private internal
	// storage, always accessible with zero permissions, so it can be read
	// this early. This exists because getPermissions() (called from Main.hx
	// before ClientPrefs.tryBindingSave() has even run) already needs to
	// know the mode to decide whether to prompt for "All files access" at
	// all -- ClientPrefs.storageMode itself isn't loaded yet at that point.
	// FileUtils.java / ModFolderDocumentsProvider.java read this exact same
	// file (via their own getFilesDir(), the same real Android directory
	// Context.getInternalFilesDir() resolves to) so the native import/"open
	// mod folder" paths agree with whatever this class resolves to.
	static inline final MODE_FLAG_FILE:String = 'storageMode.txt';

	static function _modeFlagPath():String
		return Path.addTrailingSlash(Context.getInternalFilesDir()) + MODE_FLAG_FILE;

	/**
	 * Reads the bootstrapped mode straight from disk, bypassing ClientPrefs
	 * entirely -- safe to call before ClientPrefs has loaded. Defaults to
	 * 'Shared' (the only mode that ever existed before this option), so
	 * upgrading players who never touch the new setting keep landing on the
	 * exact folder they already have mods/saves/DLC in.
	 */
	static function _readBootstrapMode():String
	{
		try
		{
			final path = _modeFlagPath();
			if (FileSystem.exists(path)) return File.getContent(path).trim();
		}
		catch (e:Dynamic) {}
		return 'Shared';
	}

	/** 'Shared': classic .<folderName> folder on shared external storage. 'Scoped': app-private Android/data/<package>/files/ folder. */
	static function _androidRoot():String
	{
		return (_readBootstrapMode() == 'Scoped')
			? Context.getExternalFilesDir()
			: Environment.getExternalStorageDirectory() + '/.' + folderName;
	}
	#end

	/**
	 * Switches the active storage mode: rewrites the bootstrap flag file (so
	 * the very next boot's getPermissions() sees it before ClientPrefs is
	 * even loaded) and invalidates the cached directory strings so every one
	 * of this class's callers picks up the new path on their very next call
	 * -- no restart needed for the path itself. What this does NOT do:
	 * migrate any files from the old folder to the new one, or reload
	 * anything (mods/scripts/DLC state) already read into memory this
	 * session from the old folder -- by design, same trade-off ShadowEngine's
	 * own equivalent (useExternal.txt) makes. Callers should tell the player
	 * a restart is needed for existing mods/DLC to actually reappear.
	 */
	public static function applyStorageMode(mode:String):Void
	{
		#if android
		try
		{
			File.saveContent(_modeFlagPath(), mode);
		}
		catch (e:Dynamic)
		{
			trace('StorageSystem: failed to persist storage mode: $e');
		}

		_cachedStorageDirectory = null;
		_cachedDirectory = null;

		try
		{
			if (!FileSystem.exists(getDirectory())) FileSystem.createDirectory(getDirectory());
			Sys.setCwd(getStorageDirectory());
		}
		catch (e:Dynamic) {}
		#end
	}

	/**
	 * Returns the base storage directory path without forcing a trailing slash.
	 */
	public static inline function getStorageDirectory():String
	{
		#if (android || ios)
		if (_cachedStorageDirectory == null)
		{
			#if android
			_cachedStorageDirectory = Path.addTrailingSlash(_androidRoot());
			#else
			_cachedStorageDirectory = lime.system.System.documentsDirectory;
			#end
		}
		return _cachedStorageDirectory;
		#else
		// Sys.getCwd() is genuinely dynamic on desktop (Sys.setCwd() can change
		// it mid-session) — not safe to cache, so this branch stays uncached.
		return Sys.getCwd();
		#end
	}

	/**
	 * Returns the base storage directory path.
	 */
	public static function getDirectory():String
	{
		#if (android || ios)
		if (_cachedDirectory == null)
		{
			#if android
			_cachedDirectory = Path.addTrailingSlash(_androidRoot());
			#else
			_cachedDirectory = lime.system.System.documentsDirectory;
			#end
		}
		return _cachedDirectory;
		#else
		// Sys.getCwd() is genuinely dynamic on desktop (Sys.setCwd() can change
		// it mid-session) — not safe to cache, so this branch stays uncached.
		return Sys.getCwd();
		#end
	}

	/**
	 * Requests Android storage permissions and creates the app's external directory.
	 *
	 * Always returns FALSE (never halts boot). No APK extraction happens here — all
	 * base-game assets are readable directly from the APK via Assets.xxx(). External
	 * storage is only used for crash logs, save files, user mods, and DLC downloaded
	 * at runtime, none of which are required to start the game.
	 *
	 * The "All files access" system settings screen (when requested) launches as a
	 * separate Activity and does not block this method — boot continues underneath it
	 * so the game is already running by the time the player returns from Settings.
	 * Previously this returned TRUE to halt boot while that screen was pending, but
	 * with no resume hook to continue afterwards, that left the game stuck on a blank
	 * screen until force-closed and relaunched.
	 */
	public static function getPermissions():Bool
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.TIRAMISU)
		{
			PermissionUtils.requestPermissions([
				'READ_MEDIA_IMAGES',
				'READ_MEDIA_VIDEO',
				'READ_MEDIA_AUDIO',
				'READ_MEDIA_VISUAL_USER_SELECTED'
			]);
		}
		else
		{
			PermissionUtils.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
		}

		if (_readBootstrapMode() == 'Shared' && VERSION.SDK_INT >= VERSION_CODES.R && !Environment.isExternalStorageManager())
		{
			Interface.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
		}

		try
		{
			var path = getDirectory();
			if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
		}
		catch (e:Dynamic)
		{
			trace("Storage Error: " + e);
		}
		#end

		return false;
	}
	
	/**
	 * Recursively copies folders from the APK to external directory.
	 * @return Int The number of files successfully copied.
	 */
	public static function copyFromAPK(sourceDir:String, targetDir:String = null, forceOverwrite:Bool = true):Int
	{
		var copiedCount = 0;
		
		#if mobile
		if (!StringTools.endsWith(sourceDir, "/")) sourceDir += "/";
		
		var baseDirectory = getDirectory();
		if (targetDir == null) targetDir = baseDirectory + sourceDir;
		if (!StringTools.endsWith(targetDir, "/")) targetDir += "/";
		
		try
		{
			if (!FileSystem.exists(targetDir)) createDirectoryRecursive(targetDir);
			
			var assetList:Array<String> = Assets.list();
			
			for (assetPath in assetList)
			{
				if (StringTools.startsWith(assetPath, sourceDir))
				{
					var relativePath = assetPath.substring(sourceDir.length);
					if (relativePath == "" || relativePath == null) continue;
					
					if (StringTools.startsWith(relativePath, "embeds/")) relativePath = relativePath.substring(7);
					else if (StringTools.startsWith(relativePath, "game/")) relativePath = relativePath.substring(5);
					else if (StringTools.startsWith(relativePath, "legacy/")) relativePath = relativePath.substring(7);
					
					var fullTargetPath = targetDir + relativePath;
					var targetFolder = Path.directory(fullTargetPath);
					
					if (!FileSystem.exists(targetFolder)) createDirectoryRecursive(targetFolder);
					
					if (Assets.exists(assetPath))
					{
						if (FileSystem.exists(fullTargetPath) && !forceOverwrite) continue;
						
						var fileBytes:Bytes = null;
						try { fileBytes = Assets.getBytes(assetPath); } catch (e:Dynamic) {}
						
						if (fileBytes != null)
						{
							File.saveBytes(fullTargetPath, fileBytes);
							copiedCount++;
						}
						else
						{
							try
							{
								var b:ByteArray = Assets.getBytes(assetPath);
								if (b != null)
								{
									File.saveBytes(fullTargetPath, Bytes.ofData(b));
									copiedCount++;
								}
								else if (!StringTools.endsWith(assetPath, ".ttf") && !StringTools.endsWith(assetPath, ".otf"))
								{
									var text = Assets.getText(assetPath);
									if (text != null)
									{
										File.saveContent(fullTargetPath, text);
										copiedCount++;
									}
								}
							}
							catch (e:Dynamic)
							{
								if (!FileSystem.exists(fullTargetPath)) trace('Warn: failure extracting $assetPath');
							}
						}
					}
				}
			}
			
			if (copiedCount > 0) trace('Extraction Success! $copiedCount files written to: $targetDir');
		}
		catch (e:Dynamic)
		{
			trace('Critical Error during copyFromAPK: $e');
		}
		#end
		
		return copiedCount;
	}
	
	/**
	 * Saves text content to the internal 'files' directory.
	 */
	#if sys
	public static function saveContent(name:String = 'file', ext:String = '.json', data:String = ''):Void
	{
		var saveFolder:String = Path.join([getDirectory(), "files"]);
		var fullPath:String = Path.join([saveFolder, name + ext]);
		
		try
		{
			if (!FileSystem.exists(saveFolder)) FileSystem.createDirectory(saveFolder);
			
			File.saveContent(fullPath, data);
			PopUp.showAlert("Success!", "File saved in:\n" + saveFolder + "/" + name + ext, "OK");
		}
		catch (e:haxe.Exception)
		{
			var errorMsg:String = "Error on Save!:\n" + e.message;
			trace('Error ' + errorMsg);
			PopUp.showAlert("Error saving file", errorMsg, "Close");
		}
	}
	#end
	
	/**
	 * Creates folders recursively in a safe way, fixing absolute path issues.
	 */
	private static function createDirectoryRecursive(path:String):Void
	{
		#if mobile
		if (FileSystem.exists(path)) return;
		
		var pathParts = path.split("/");
		var currentPath = "";
		
		if (StringTools.startsWith(path, "/"))
		{
			currentPath = "/";
			pathParts.shift();
		}
		
		for (part in pathParts)
		{
			if (part == "") continue;
			
			currentPath = (currentPath == "/") ? (currentPath + part) : (currentPath + "/" + part);
			
			if (!FileSystem.exists(currentPath))
			{
				try
				{
					FileSystem.createDirectory(currentPath);
				}
				catch (e:Dynamic)
				{
					trace('Error Creating Subfolder $currentPath: $e');
				}
			}
		}
		#end
	}
}