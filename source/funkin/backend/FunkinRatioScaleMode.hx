package funkin.backend;

import flixel.FlxG;
import flixel.system.scaleModes.RatioScaleMode;
import flixel.math.FlxPoint;
import flixel.util.FlxAxes;
import flixel.util.FlxHorizontalAlign;
import flixel.util.FlxVerticalAlign;

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
	
	/**
	 * The maximum aspect ratio to allow before adding black bars.
	 * Default: 21:9 (2.33) for ultra-wide screens.
	 */
	public static var maxAspectRatio:Float = 21.0 / 9.0;

	/**
	 * How much extra logical width/height 'expand' mode revealed beyond the
	 * design resolution (FlxG.initialWidth × FlxG.initialHeight), in game
	 * coordinates. Zero in 'fit'/'stretch' mode, or on a screen that isn't
	 * wider/taller than 16:9. UI that wants to deliberately use the extra
	 * space (instead of just staying centered on the original 1280×720, the
	 * default behaviour) can read this — mirrors FunkinCrew/Funkin's own
	 * FullScreenScaleMode.gameCutoutSize.
	 */
	public static var gameCutoutSize:FlxPoint = FlxPoint.get(0, 0);

	public override function updateGameSize(Width:Int, Height:Int):Void
	{
		// `width`/`height` (the get/set-wrapped properties on this class) are a
		// separate "force a custom resolution" override (see resetSize()) that
		// nothing currently sets to a non-null value, so these getters always
		// resolve to FlxG.initialWidth/Height — the stable, never-mutated design
		// resolution. Reading them (rather than the live FlxG.width/height,
		// which 'expand' mode is about to change) keeps this ratio calculation
		// correct even if updateGameSize() runs again before FlxG.width gets
		// reset back to normal (e.g. a live orientation change).
		var designWidth:Float = width;
		var designHeight:Float = height;
		var ratio:Float = designWidth / designHeight;
		var realRatio:Float = Width / Height;

		// Check if screen is wider than max aspect ratio
		var isUltraWide:Bool = realRatio > maxAspectRatio;

		// Default: scale to fit (keeps 16:9, adds black bars)
		// If aspectRatioMode is 'stretch' and not ultra-wide, stretch to fill
		var doStretch:Bool = false;
		var doExpand:Bool = false;
		#if mobile
		if (funkin.data.ClientPrefs.aspectRatioMode == 'stretch' && !isUltraWide)
			doStretch = true;
		else if (funkin.data.ClientPrefs.aspectRatioMode == 'expand')
			doExpand = true;
		#end

		var scaleY:Bool = realRatio < ratio;
		if (fillScreen || doStretch)
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

		var finalWidth:Int = Std.int(designWidth);
		var finalHeight:Int = Std.int(designHeight);

		if (doExpand)
		{
			// Grow the actual logical resolution (FlxG.width/height), not just
			// the render target, so a wider/taller-than-16:9 screen reveals more
			// of the game world at a UNIFORM scale — instead of the old
			// 'expand', which left FlxG.width pinned at the design width and let
			// scale.x/scale.y diverge, silently stretching every sprite
			// non-uniformly (circles into ovals) on any screen wider than 16:9.
			final clampedRatio:Float = Math.min(realRatio, maxAspectRatio);

			if (realRatio > ratio)
			{
				// Wider than 16:9 (the common case: landscape phones/tablets):
				// keep height at the design value, grow width to match.
				finalHeight = Std.int(designHeight);
				finalWidth = Math.ceil(designHeight * clampedRatio);

				// If the screen is wider than maxAspectRatio, finalWidth is
				// clamped and no longer matches the raw device width — scale
				// gameSize.x by the SAME factor as gameSize.y (Height/finalHeight)
				// so scale.x == scale.y stays true (updateScaleOffset() below
				// divides gameSize by FlxG.width/height). Otherwise this reduces
				// to gameSize.x == Width exactly, same as the unclamped case.
				final deviceScale:Float = Height / finalHeight;
				gameSize.x = finalWidth * deviceScale;
				gameSize.y = Height;
			}
			else
			{
				// Narrower/taller than 16:9 (unusual for a landscape-locked game,
				// but handled symmetrically): keep width, grow height instead.
				final clampedInvRatio:Float = Math.min(1 / realRatio, maxAspectRatio);
				finalWidth = Std.int(designWidth);
				finalHeight = Math.ceil(designWidth * clampedInvRatio);

				final deviceScale:Float = Width / finalWidth;
				gameSize.y = finalHeight * deviceScale;
				gameSize.x = Width;
			}

			gameCutoutSize.set(finalWidth - designWidth, finalHeight - designHeight);
		}
		else
		{
			gameCutoutSize.set(0, 0);

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
		}

		@:privateAccess {
			for (c in FlxG.cameras.list)
			{
				if (c.width == FlxG.width && c.height == FlxG.height)
				{
					c.width = finalWidth;
					c.height = finalHeight;
				}
			}

			FlxG.width = finalWidth;
			FlxG.height = finalHeight;
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
	
	/**
	 * Resets the scale mode to apply preference changes immediately.
	 * Called when aspectRatioMode preference changes.
	 */
	public static function resetScaleMode():Void
	{
		if (FlxG.scaleMode != null)
		{
			var mode = cast(FlxG.scaleMode, FunkinRatioScaleMode);
			if (mode != null)
			{
				mode.width = null;
				mode.height = null;
				mode.resetSize();
				@:privateAccess
				FlxG.game.onResize(null);
			}
		}
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
