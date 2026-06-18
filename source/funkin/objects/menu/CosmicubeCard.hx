package funkin.objects.menu;

import funkin.data.CosmicubeData;
import funkin.utils.ProgressionUtil;

class CosmicubeCard extends flixel.group.FlxSpriteGroup
{
	var ext:String = 'menu/cosmicube/';
	
	public var id:String;
	public var meta:CosmicubeMetadata;
	
	public var border:FlxSprite;
	public var cover:FlxSprite;
	public var slide:FlxSprite;
	
	public var title:FlxText;
	public var counterText:FlxText;
	public var completionText:FlxText;
	public var currencyIcon:FlxSprite;
	
	public var looksie:FlxSprite;
	public var checkbox:FlxSprite;
	
	public var activated:Bool = false;
	public var selected:Bool = false;
	
	public var colorSwap = new funkin.game.shaders.ColorSwap();
	
	public function new(x:Float = 0, y:Float = 0, meta:CosmicubeMetadata)
	{
		super(x, y);
		
		this.id = meta.fileName;
		this.meta = meta;
		
		add(slide = new FlxSprite(8, Paths.image('${ext}slides/${Paths.fileExists('images/${ext}slides/$id.png') ? id : 'unknown'}')));
		add(cover = new FlxSprite(8, 8, Paths.image('${ext}cover')));
		add(border = new FlxSprite(Paths.image('${ext}cardBorder')));
		
		slide.y = (slide.y + (border.height - slide.height) / 2);
		
		title = new FlxText(322, 45, 0, meta.title);
		title.setFormat(Paths.font('liberbold.ttf'), 36, OUTLINE, 0xff333333);
		title.letterSpacing = -2;
		title.borderSize = 2;
		
		currencyIcon = new FlxSprite(322, 100, Paths.image('currency/${meta.currency}'));
		currencyIcon.setGraphicSize(0, 30);
		currencyIcon.updateHitbox();
		
		counterText = new FlxText(322 + 48, 100, 0, '1234');
		counterText.setFormat(Paths.font('liberbold.ttf'), 26, 0xff333333);
		
		completionText = new FlxText(322 + 48, 135, 0, '0% completed');
		completionText.setFormat(Paths.font('liber.ttf'), 20, 0xff333333);
		
		add(title);
		add(counterText);
		add(completionText);
		add(currencyIcon);
		
		add(looksie = new FlxSprite(0, 40, Paths.image('${ext}looksie')));
		add(checkbox = new FlxSprite(0, 20));
		checkbox.frames = Paths.getSparrowAtlas('${ext}checkbox');
		checkbox.animation.addByPrefix('unchecked', 'unchecked', 24, false);
		checkbox.animation.addByPrefix('checked', 'checked', 24, false);
		checkbox.animation.play('unchecked', true);
		
		checkbox.x = (width - checkbox.width - 50);
		looksie.x = (checkbox.x - looksie.width - 20);
		looksie.scale.set(.85, .85);
		
		refresh();
		select(false);
		activate(ClientPrefs.activeCosmicube == id);
		
		checkbox.animation.finish();
	}
	
	public override function update(elapsed:Float):Void
	{
		counterText.color = 0xff333333; // sigh h h h  h h h
		completionText.color = 0xff333333;
		
		colorSwap.hue = ((colorSwap.hue + elapsed / (ClientPrefs.flashing ? 2 : 5)) % 1);
		
		super.update(elapsed);
	}
	
	public function refresh():Void
	{
		counterText.text = flixel.util.FlxStringUtil.formatMoney(CosmicubeData.getMoney(meta.currency), false);
		var completion = ProgressionUtil.calculateCubeCompletion(id);
		completionText.text = Lang.str('cosmicube_completed').replace('@', Std.string(Math.floor(completion.percent)));
	}
	
	public function select(isIt:Bool):Void
	{
		selected = isIt;
	}
	
	public function activate(isIt:Bool):Void
	{
		if (activated != isIt)
		{
			checkbox.animation.play(isIt ? 'checked' : 'unchecked');
			
			if (isIt && ClientPrefs.flashing)
			{
				colorSwap.brightness = 1;
				FlxTween.tween(colorSwap, {brightness: 0}, .25, {ease: FlxEase.sineOut});
			}
		}
		
		cover.loadGraphic(Paths.image(ext + (isIt ? 'selectCover' : 'cover')));
		
		cover.shader = (isIt ? colorSwap.shader : null);
		
		activated = isIt;
	}
}
