package funkin.objects.menu;

import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import funkin.Paths.PathsTestMode;

/**
 * Builds a 9-slice-scaled BitmapData from a source image: the four
 * `margin`px corners are copied unscaled, the four edges stretch along a
 * single axis to fill the gap between corners, and the center stretches on
 * both axes. Meant for UI "card" backgrounds (see card.png) that get resized
 * to wildly different aspect ratios across screens -- a plain
 * FlxSprite.setGraphicSize() stretch distorts a fixed-radius rounded
 * corner/border baked into the bitmap (rounder/thicker where the stretch
 * compresses it, flatter/thinner where it elongates it -- different at
 * every call site despite being "the same card"), which a 9-slice avoids
 * entirely since the corners themselves are never scaled at all.
 *
 * Each call composites a brand-new BitmapData -- cheap enough for UI
 * construction (a handful of calls when a menu opens or rebuilds its
 * labels), but NOT meant to be called every frame or every tween tick the
 * way setGraphicSize() safely could be. All of this codebase's current
 * 9-sliced cards are sized once at construction and never resized again, so
 * this fits how they're already built.
 */
class NineSlice
{
	/**
	 * @param key    Paths.image() key for the source graphic.
	 * @param margin Corner/edge size, in the SOURCE image's own pixels --
	 *               must fully contain whatever rounded corner/border the art
	 *               has baked in, or the curve gets cut through and the slice
	 *               seams show. (card.png's own corner radius measures out to
	 *               ~16-17px; callers use 20 there for a couple px of buffer.)
	 * @param width  Target width, in stage pixels.
	 * @param height Target height, in stage pixels.
	 * @param mode   Forwarded to Paths.image() as-is (e.g. NONE to skip the
	 *               mod-folder lookup for a base-game-only asset) -- defaults
	 *               to the same NORMAL a plain Paths.image(key) call gets.
	 */
	public static function build(key:String, margin:Int, width:Float, height:Float, mode:PathsTestMode = NORMAL):BitmapData
	{
		final src = Paths.image(key, null, true, mode).bitmap;
		final sw = src.width;
		final sh = src.height;

		// Half the smaller source dimension is the hard ceiling -- past that
		// the four corner rects would start overlapping each other in the
		// source image itself.
		final m = Std.int(Math.min(margin, Math.min(sw, sh) * 0.5 - 1));

		final w = Std.int(Math.max(width, m * 2 + 1));
		final h = Std.int(Math.max(height, m * 2 + 1));

		final out = new BitmapData(w, h, true, 0x00000000);

		// Corners: copied 1:1, never scaled -- this is the entire point.
		out.copyPixels(src, new Rectangle(0, 0, m, m), new Point(0, 0));
		out.copyPixels(src, new Rectangle(sw - m, 0, m, m), new Point(w - m, 0));
		out.copyPixels(src, new Rectangle(0, sh - m, m, m), new Point(0, h - m));
		out.copyPixels(src, new Rectangle(sw - m, sh - m, m, m), new Point(w - m, h - m));

		// Edges: stretched along one axis only.
		drawScaledRegion(out, src, new Rectangle(m, 0, sw - m * 2, m), new Rectangle(m, 0, w - m * 2, m));
		drawScaledRegion(out, src, new Rectangle(m, sh - m, sw - m * 2, m), new Rectangle(m, h - m, w - m * 2, m));
		drawScaledRegion(out, src, new Rectangle(0, m, m, sh - m * 2), new Rectangle(0, m, m, h - m * 2));
		drawScaledRegion(out, src, new Rectangle(sw - m, m, m, sh - m * 2), new Rectangle(w - m, m, m, h - m * 2));

		// Center: stretched on both axes.
		drawScaledRegion(out, src, new Rectangle(m, m, sw - m * 2, sh - m * 2), new Rectangle(m, m, w - m * 2, h - m * 2));

		return out;
	}

	/**
	 * Crops `srcRect` out of `src` first, then scales that piece alone onto
	 * `out` at `destRect` -- simpler and less error-prone than a single
	 * matrix that both offsets into an arbitrary region of `src` and scales
	 * it in the same step.
	 */
	static function drawScaledRegion(out:BitmapData, src:BitmapData, srcRect:Rectangle, destRect:Rectangle):Void
	{
		if (srcRect.width <= 0 || srcRect.height <= 0 || destRect.width <= 0 || destRect.height <= 0) return;

		final piece = new BitmapData(Std.int(srcRect.width), Std.int(srcRect.height), true, 0x00000000);
		piece.copyPixels(src, srcRect, new Point(0, 0));

		final matrix = new Matrix();
		matrix.scale(destRect.width / srcRect.width, destRect.height / srcRect.height);
		matrix.translate(destRect.x, destRect.y);
		out.draw(piece, matrix, null, null, null, true);

		piece.dispose();
	}
}
