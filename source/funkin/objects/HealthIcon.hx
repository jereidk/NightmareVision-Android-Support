package funkin.objects;

import flixel.FlxSprite;

@:nullSafety
class HealthIcon extends FlxSprite
{
	/**
	 * Optional parented sprite
	 * 
	 * If set `this` will follow the set parents position
	 */
	public var sprTracker:Null<FlxSprite> = null;
	
	/**
	 * Additional offsets for the icon
	 * 
	 * Used when `sprTracker` is not null.
	 */
	public var sprOffsets(default, null):FlxPoint = FlxPoint.get(10, -30);
	
	/**
	 * The icons current character name
	 */
	public var characterName(default, null):String = '';
	
	@:allow(funkin.states.editors.ChartEditorState)
	var updateOffset:Bool = true;
	
	var iconOffsets:Array<Float> = [0, 0];
	
	/**
	 * Used to decide if the icon will be flipped
	 */
	var isPlayer:Bool = false;
	
	public function new(char:String = 'bf', isPlayer:Bool = false)
	{
		super();
		this.isPlayer = isPlayer;
		changeIcon(char);
	}
	
	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		
		if (sprTracker != null) setPosition(sprTracker.x + sprTracker.width + sprOffsets.x, sprTracker.y + sprOffsets.y);
	}
	
	/**
	 * Attempts to load a new icon by file name
	 */
	public function changeIcon(char:String):Void
	{
		if (this.characterName == char) return;
		
		this.characterName = char;
		
		var name:String = 'icons/' + char;
		if (!Paths.fileExists('images/' + name + '.png', LOOSE)) name = 'icons/icon-' + char; // Older versions of psych engine's support
		if (!Paths.fileExists('images/' + name + '.png', LOOSE)) name = 'icons/icon-placeholder'; // Prevents crash from missing icon
		
		final graphic = Paths.image(name, null, false, LOOSE);
		
		var icons = Math.round(Math.max(graphic.width / graphic.height, 1));
		var frameWidth = (graphic.width / icons);
		
		loadGraphic(graphic, true, Std.int(frameWidth), Std.int(graphic.height));
		iconOffsets[0] = ((frameWidth - 150) / 2);
		iconOffsets[1] = ((frameHeight - 150) / 2);
		updateHitbox();
		
		animation.add(char, [for (i in 0...frames.frames.length) i], 0, false, isPlayer);
		animation.play(char); // i do plan on adding more functionality to icons at a later date
		
		antialiasing = char.endsWith('-pixel') ? false : ClientPrefs.globalAntialiasing;
	}
	
	override function updateHitbox()
	{
		super.updateHitbox();
		
		if (updateOffset)
		{
			offset.x = iconOffsets[0];
			offset.y = iconOffsets[1];
		}
	}
	
	override function destroy()
	{
		sprOffsets = FlxDestroyUtil.put(sprOffsets);
		super.destroy();
	}
	
	/**
	 * Updates the current animation based on a value from 0 - 1.
	 */
	public inline function updateIconAnim(health:Float):Void
	{
		animation.frameIndex = health < 0.2 ? 1 : 0;
	}
}
