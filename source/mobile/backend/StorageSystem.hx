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

	// Both getters below end up calling Environment.getExternalStorageDirectory()
	// on Android, a JNI round-trip into Java, for a value that's constant for
	// the whole process (the OS storage root + a fixed app folder name never
	// change mid-session, regardless of whether storage permission has been
	// granted yet — permission only gates actual file I/O on this path, not
	// the path string itself). Several call sites (CrashHandler, GameLogger,
	// SystemMonitor, GlobalScriptManager, FunkinAssets, AndroidUtils) call
	// getDirectory() well after startup, some potentially repeatedly during a
	// burst of external asset/mod loading — cache each result after the first
	// real computation instead of re-paying the JNI cost every time. A
	// same-value race on first use from DLCManager's background thread is
	// harmless (worst case: computed twice, both give the identical string).
	static var _cachedStorageDirectory:String = null;
	static var _cachedDirectory:String = null;

	/**
	 * Returns the base storage directory path without forcing a trailing slash.
	 */
	public static inline function getStorageDirectory():String
	{
		#if (android || ios)
		if (_cachedStorageDirectory == null)
		{
			#if android
			_cachedStorageDirectory = Path.addTrailingSlash(Environment.getExternalStorageDirectory() + '/.' + folderName);
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
			_cachedDirectory = Environment.getExternalStorageDirectory() + '/.' + folderName + '/';
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

		if (VERSION.SDK_INT >= VERSION_CODES.R && !Environment.isExternalStorageManager())
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