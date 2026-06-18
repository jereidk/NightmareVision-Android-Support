package funkin.states.editors.ui;

class EditorNote extends funkin.objects.note.Note
{
	public var chartData:Array<Dynamic> = null;
	
	public var interactable:Bool = true;
	public var selected:Bool = false;
	
	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';
	
	public var sustainSprite:FlxSprite;
	public var sustainHeight:Float = 0;
	
	public var section:Int;
	
	public override function draw():Void
	{
		if (sustainHeight > 0)
		{
			createSustainSprite();
			
			final ct = colorTransform;
			final gridSize:Float = funkin.states.editors.ChartEditorState.GRID_SIZE;
			
			sustainSprite.setGraphicSize(8, sustainHeight);
			sustainSprite.updateHitbox();
			sustainSprite.setPosition(x + (gridSize - sustainSprite.width) * .5, y + gridSize * .5);
			sustainSprite.setColorTransform(ct.redMultiplier, ct.greenMultiplier, ct.blueMultiplier, ct.alphaMultiplier);
			
			sustainSprite.draw();
		}
		
		super.draw();
	}
	
	public inline function createSustainSprite():FlxSprite
	{
		if (sustainSprite == null)
		{
			sustainSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
			sustainSprite.antialiasing = false;
		}
		
		return sustainSprite;
	}
}
