package funkin.objects;

import flixel.FlxSprite;

@:nullSafety
class CheckboxThingie extends FlxSprite
{
	public var sprTracker:Null<FlxSprite> = null;
	public var daValue(default, set):Bool = false;
	
	public var copyAlpha:Bool = true;
	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	
	public function new(x:Float = 0, y:Float = 0, checked = false)
	{
		super(x, y);
		
		loadGraphic(Paths.image('menu/options/impastacheckbox'), true, 30, 30);
		animation.add("unchecked", [0], 24, false);
		animation.add("checked", [1], 24, false);
		animation.play(checked ? 'checked' : 'unchecked', true);
		
		daValue = checked;
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
	
	private function set_daValue(check:Bool):Bool
	{
		if (animation.curAnim == null) return (daValue = check);
		
		animation.play(check ? 'checked' : 'unchecked', true);
		return (daValue = check);
	}
	
}
