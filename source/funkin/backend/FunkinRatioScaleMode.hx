package funkin.backend;

import flixel.FlxG;
import flixel.system.scaleModes.RatioScaleMode;
import flixel.math.FlxPoint;

#if mobile
import mobile.backend.ScreenUtil;
#end

class FunkinRatioScaleMode extends RatioScaleMode
{
	@:isVar public var width(get, set):Null<Int> = null;
	@:isVar public var height(get, set):Null<Int> = null;
	
	#if mobile
	/**
	 * Notch/cutout position and size in device pixels.
	 */
	public static var notchPosition:FlxPoint = FlxPoint.get(0, 0);
	public static var notchSize:FlxPoint = FlxPoint.get(0, 0);
	#end
	
	public override function updateGameSize(Width:Int, Height:Int):Void
	{
		var ratio:Float = width / height;
		var realRatio:Float = Width / Height;
		
		var scaleY:Bool = realRatio < ratio;
		if (fillScreen)
		{
			scaleY = !scaleY;
		}
		
		// On mobile, adjust for notch/cutout
		#if mobile
		var notch = ScreenUtil.safeArea();
		var safeTop:Float = notch.top;
		var safeLeft:Float = notch.left;
		var safeRight:Float = notch.right;
		
		// Update notch info for mobile UI elements
		if (safeTop > 0 || safeLeft > 0)
		{
			notchPosition.set(safeLeft, safeTop);
			notchSize.set(safeLeft + safeRight, safeTop);
		}
		else
		{
			notchPosition.set(0, 0);
			notchSize.set(0, 0);
		}
		#end
		
		if (scaleY)
		{
			gameSize.x = Width;
			gameSize.y = Math.floor(gameSize.x / ratio);
		}
		else
		{
			gameSize.y = Height;
			gameSize.x = Math.floor(gameSize.y * ratio);
		}
		
		@:privateAccess {
			for (c in FlxG.cameras.list)
			{
				if (c.width == FlxG.width && c.height == FlxG.height)
				{
					c.width = width;
					c.height = height;
				}
			}
			
			FlxG.width = width;
			FlxG.height = height;
		}
	}
	
	public function resetSize()
	{
		width = null;
		height = null;
		#if mobile
		notchPosition.set(0, 0);
		notchSize.set(0, 0);
		#end
	}
	
	private inline function get_width():Null<Int> return this.width == null ? FlxG.initialWidth : this.width;
	
	private inline function get_height():Null<Int> return this.height == null ? FlxG.initialHeight : this.height;
	
	private inline function set_width(v:Null<Int>):Null<Int>
	{
		this.width = v;
		@:privateAccess
		FlxG.game.onResize(null);
		return v;
	}
	
	private inline function set_height(v:Null<Int>):Null<Int>
	{
		this.height = v;
		@:privateAccess
		FlxG.game.onResize(null);
		return v;
	}
}
