package mobile.backend;

import lime.app.Application;

import haxe.io.Path;
import haxe.io.Bytes;

import openfl.utils.ByteArray;
import openfl.utils.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.thread.Thread;
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
	
	/**
	 * Returns the base storage directory path without forcing a trailing slash.
	 */
	public static inline function getStorageDirectory():String
	{
		#if android
		return Path.addTrailingSlash(Environment.getExternalStorageDirectory() + '/.' + folderName);
		#elseif ios
		return lime.system.System.documentsDirectory;
		#else
		return Sys.getCwd();
		#end
	}
	
	/**
	 * Returns the base storage directory path.
	 */
	public static function getDirectory():String
	{
		#if android
		return Environment.getExternalStorageDirectory() + '/.' + folderName + '/';
		#elseif ios
		return lime.system.System.documentsDirectory;
		#else
		return Sys.getCwd();
		#end
	}
	
	/**
	 * Requests Android storage permissions and verifies external assets.
	 * @return Bool Returns TRUE if the game boot should halt (permissions pending or full extract), FALSE if ready to play.
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
		
		if (VERSION.SDK_INT >= VERSION_CODES.R)
		{
			if (!Environment.isExternalStorageManager()) 
			{
				Interface.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
				return true;
			}
		}
		
		try
		{
			var path = getDirectory();
			if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
			
			if (!FileSystem.exists(path + "assets") || !FileSystem.exists(path + "content"))
			{
				startApkCopy();
				return true;
			}

			return false;
		}
		catch (e:Dynamic)
		{
			trace("Storage Error: " + e);
		}
		#end
		
		return false; // If not Android, or no interruption needed, proceed.
	}
	
	/**
	 * Initiates the internal APK asset extraction with an animated progress overlay.
	 * Shows a blocking alert first, then extracts on a background thread while the
	 * main thread animates a progress screen via ENTER_FRAME. On completion, prompts
	 * the user to restart the game.
	 */
	private static function startApkCopy():Void
	{
		#if android
		PopUp.showAlert("First-Time Setup", "Game assets need to be extracted from the APK.\nThis only happens once and may take about a minute.", "OK");

		var stage = Lib.current.stage;
		var sw:Float = stage.stageWidth > 0 ? stage.stageWidth : 1280;
		var sh:Float = stage.stageHeight > 0 ? stage.stageHeight : 720;

		var overlay = new Sprite();
		overlay.graphics.beginFill(0x000000, 1.0);
		overlay.graphics.drawRect(0, 0, sw, sh);
		overlay.graphics.endFill();

		var tf = new TextFormat();
		tf.font = "_sans";
		tf.size = 28;
		tf.color = 0xFFFFFF;
		tf.bold = true;
		tf.align = TextFormatAlign.CENTER;

		var label = new TextField();
		label.defaultTextFormat = tf;
		label.width = sw;
		label.height = 60;
		label.y = (sh - 60) / 2;
		label.selectable = false;
		label.text = "Extracting assets, please wait...";
		overlay.addChild(label);
		stage.addChild(overlay);

		var done = false;
		var failed = false;
		var dotCount = 0;
		var frameTimer = 0;

		var onFrame:Event -> Void = null;
		onFrame = function(_:Event)
		{
			frameTimer++;
			if (frameTimer % 20 == 0)
			{
				dotCount = (dotCount + 1) % 4;
				label.text = "Extracting assets, please wait" + ["", ".", "..", "..."][dotCount];
			}

			if (done)
			{
				stage.removeEventListener(Event.ENTER_FRAME, onFrame);
				stage.removeChild(overlay);

				if (failed)
					PopUp.showAlert("Extraction Failed", "An error occurred. Please reinstall the game.", "OK");
				else
					PopUp.showConfirm("Setup Complete!", "Assets extracted successfully.\nThe game must restart to continue.", "Restart", "Later", function() {
						lime.system.System.exit(0);
					});
			}
		};

		stage.addEventListener(Event.ENTER_FRAME, onFrame);

		Thread.create(function()
		{
			try
			{
				copyFromAPK("assets/", null, true);
				copyFromAPK("content/", null, true);
			}
			catch (e:Dynamic)
			{
				trace("Extraction error: " + e);
				failed = true;
			}
			done = true;
		});
		#end
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