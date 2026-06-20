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
		PopUp.showAlert("First-Time Setup", "VS IMPOSTOR: LEGACY needs to extract game files from the APK.\nThis only happens once and may take about a minute.", "Got it!");

		var stage = Lib.current.stage;
		var sw:Float = stage.stageWidth > 0 ? stage.stageWidth : 1280;
		var sh:Float = stage.stageHeight > 0 ? stage.stageHeight : 720;

		var overlay = new Sprite();

		// Dark background
		overlay.graphics.beginFill(0x0D0D0D, 1.0);
		overlay.graphics.drawRect(0, 0, sw, sh);
		overlay.graphics.endFill();

		// Top & bottom accent bars (Among Us green)
		overlay.graphics.beginFill(0x2DB83D, 1.0);
		overlay.graphics.drawRect(0, 0, sw, 7);
		overlay.graphics.endFill();
		overlay.graphics.beginFill(0x2DB83D, 1.0);
		overlay.graphics.drawRect(0, sh - 7, sw, 7);
		overlay.graphics.endFill();

		// Center card
		var cardW:Float = sw * 0.56;
		var cardH:Float = sh * 0.52;
		var cardX:Float = Math.round((sw - cardW) / 2);
		var cardY:Float = Math.round((sh - cardH) / 2);

		overlay.graphics.beginFill(0x171717, 1.0);
		overlay.graphics.drawRoundRect(cardX, cardY, cardW, cardH, 16, 16);
		overlay.graphics.endFill();

		// Card top accent strip
		overlay.graphics.beginFill(0x2DB83D, 1.0);
		overlay.graphics.drawRoundRect(cardX, cardY, cardW, 6, 16, 16);
		overlay.graphics.endFill();

		// --- Text helpers ---
		var makeTf = function(size:Int, color:Int, bold:Bool):TextFormat
		{
			var tf = new TextFormat();
			tf.font = "_sans";
			tf.size = size;
			tf.color = color;
			tf.bold = bold;
			tf.align = TextFormatAlign.CENTER;
			return tf;
		};

		var addLabel = function(text:String, tf:TextFormat, x:Float, y:Float, w:Float, h:Float, multi:Bool = false):TextField
		{
			var label = new TextField();
			label.defaultTextFormat = tf;
			label.selectable = false;
			label.multiline = multi;
			label.wordWrap = multi;
			label.width = w;
			label.height = h;
			label.x = x;
			label.y = y;
			label.text = text;
			overlay.addChild(label);
			return label;
		};

		var lx:Float = cardX + 24;
		var lw:Float = cardW - 48;

		// Game title
		addLabel("VS IMPOSTOR: LEGACY", makeTf(Math.round(sw * 0.022), 0x2DB83D, true),
			lx, cardY + 20, lw, 44);

		// Subtitle
		addLabel("First-Time Setup", makeTf(Math.round(sw * 0.016), 0xFFFFFF, true),
			lx, cardY + 68, lw, 36);

		// Description
		addLabel("Extracting game files from the APK.\nThis only needs to happen once.", makeTf(Math.round(sw * 0.012), 0x888888, false),
			cardX + 32, cardY + 112, cardW - 64, 60, true);

		// Status label (animated)
		var statusLabel = addLabel("Extracting...", makeTf(Math.round(sw * 0.014), 0xCCCCCC, false),
			lx, cardY + cardH - 80, lw, 34);

		// Progress bar track
		var barW:Float = cardW - 80;
		var barH:Float = 14;
		var barX:Float = cardX + 40;
		var barY:Float = cardY + cardH - 44;

		var barTrack = new Sprite();
		barTrack.graphics.beginFill(0x2A2A2A, 1.0);
		barTrack.graphics.drawRoundRect(0, 0, barW, barH, 8, 8);
		barTrack.graphics.endFill();
		barTrack.x = barX;
		barTrack.y = barY;
		overlay.addChild(barTrack);

		var fillW:Float = barW * 0.22;
		var barFill = new Sprite();
		barFill.graphics.beginFill(0x2DB83D, 1.0);
		barFill.graphics.drawRoundRect(0, 0, fillW, barH, 8, 8);
		barFill.graphics.endFill();
		barFill.x = barX;
		barFill.y = barY;
		overlay.addChild(barFill);

		stage.addChild(overlay);

		var done = false;
		var failed = false;
		var dotCount = 0;
		var frameTimer = 0;
		var barProgress:Float = 0;
		var barDir:Float = 1;

		var onFrame:Event -> Void = null;
		onFrame = function(_:Event)
		{
			frameTimer++;

			if (frameTimer % 20 == 0)
			{
				dotCount = (dotCount + 1) % 4;
				statusLabel.text = "Extracting" + ["", ".", "..", "..."][dotCount];
			}

			// Bouncing indeterminate progress bar
			barProgress += barDir * 3;
			if (barProgress + fillW > barW)
			{
				barProgress = barW - fillW;
				barDir = -1;
			}
			else if (barProgress < 0)
			{
				barProgress = 0;
				barDir = 1;
			}
			barFill.x = barX + barProgress;

			if (done)
			{
				stage.removeEventListener(Event.ENTER_FRAME, onFrame);
				stage.removeChild(overlay);

				if (failed)
					PopUp.showAlert("Extraction Failed", "An error occurred. Please reinstall the game.", "OK");
				else
					PopUp.showConfirm("Setup Complete!", "All game assets have been extracted.\nThe game needs to restart to continue.", "Restart", "Later", function() {
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