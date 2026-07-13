package funkin.objects.note;

class LaneUnderlay extends FlxSprite
{
	public var parent:PlayField;
	
	public var baseAlpha:Float = 1;
	public var padding:Float = 10;

	var _cachedMinX:Float = Math.NaN;
	var _cachedMaxX:Float = Math.NaN;
	var _cachedHeight:Float = Math.NaN;

	public function new(parent:PlayField)
	{
		super();
		
		this.parent = parent;
		
		if (ClientPrefs.laneUnderlayStyle == 'D') // fade thing
		{
			loadGraphic(flixel.util.FlxGradient.createGradientBitmapData(1, FlxG.height, [for (i in 0 ... 14) (i == 13 ? 0x30000000 : FlxColor.BLACK)] /* u cant set gradient stops so whatever*/));
			flipY = ClientPrefs.downScroll;
		}
		else
		{
			makeGraphic(1, 1, FlxColor.BLACK);
			antialiasing = false;
		}
	}
	
	public override function draw():Void
	{
		if (!parent.visible) return;
		
		if (baseAlpha > 0)
		{
			var minX:Float = Math.POSITIVE_INFINITY,
				maxX:Float = Math.NEGATIVE_INFINITY,
				maxAlpha:Float = 0;
				
			for (strum in parent)
			{
				minX = Math.min(strum.x - padding, minX);
				maxX = Math.max(strum.x + strum.width + padding, maxX);
				maxAlpha = Math.max(strum.visible ? strum.alpha * strum.rgbShader.alpha : 0, maxAlpha);
			}
			
			if (maxAlpha <= 0) return;
			
			alpha = (baseAlpha * maxAlpha);

			// Strums essentially never move mid-song, so minX/maxX are almost
			// always identical frame to frame -- skip the setGraphicSize()/
			// updateHitbox() bookkeeping (and the x reassignment) when they
			// are, since redoing them would produce the exact same result.
			if (minX != _cachedMinX || maxX != _cachedMaxX || camera.height != _cachedHeight)
			{
				setGraphicSize(maxX - minX, camera.height);
				updateHitbox();
				x = minX;
				_cachedMinX = minX;
				_cachedMaxX = maxX;
				_cachedHeight = camera.height;
			}

			super.draw();
		}
	}
}