package funkin.objects;

import flixel.FlxSprite;

/**
 * The Add/Subtract box for the Options submenu
**/
@:nullSafety
class AddBox extends FlxSprite
{
	public var sprTracker:Null<FlxSprite> = null;
	
	public var copyAlpha:Bool = true;
	
	public function new(x:Float = 0, y:Float = 0, adding:Bool = false)
	{
		super(x, y);
		
		loadGraphic(Paths.image('menu/options/impastacheckbox'), true, 30, 30);
		animation.add("left", [2], 24, false);
		animation.add("right", [3], 24, false);
		animation.play(adding ? 'right' : 'left', true);
	}
	
	override function update(elapsed:Float)
	{
		if (sprTracker != null)
		{
			if (copyAlpha)
			{
				alpha = sprTracker.alpha;
			}
		}
		super.update(elapsed);
	}
}
