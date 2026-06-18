package funkin.objects.note;

class LaneUnderlay extends FlxSprite
{
	public var parent:PlayField;
	
	public var baseAlpha:Float = 1;
	public var padding:Float = 10;
	
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
			setGraphicSize(maxX - minX, camera.height);
			updateHitbox();
			x = minX;
			
			super.draw();
		}
	}
}