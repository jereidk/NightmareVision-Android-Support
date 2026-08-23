package funkin.objects.menu;

import flixel.group.FlxSpriteGroup;
import flixel.util.FlxSignal;

@:nullSafety
class ScrollBar extends FlxSpriteGroup
{
	public final track:FlxSprite;
	public final thumb:FlxSprite;
	
	public var onDrag:FlxSignal = new FlxTypedSignal();
	public var onRelease:FlxSignal = new FlxTypedSignal();
	public var onInteract:FlxSignal = new FlxTypedSignal();
	
	public var onPage:FlxTypedSignal<Float -> Float -> Void> = new FlxTypedSignal();
	public var onScroll:FlxTypedSignal<Float -> Float -> Void> = new FlxTypedSignal();
	
	public var thumbPadding:Int = 1;
	
	public var minThumbHeight:Int = 24;
	public var maxThumbHeight:Null<Int> = null;
	
	public var interactable:Bool = true;
	public var interacting:Bool = false;
	
	var trackHeight:Int;
	var barWidth:Int;
	var thumbColor:Int;
	
	public var scroll:Float = 0;
	public var progress:Float = 0;
	
	public var rate:Float = (1 / 12);
	public var initialDelay:Float = (1 / 3);
	
	public function new(x:Float, y:Float, width:Int, height:Int, trackColor:FlxColor = FlxColor.BLACK, thumbColor:FlxColor = FlxColor.WHITE)
	{
		super(x, y);
		
		barWidth = width;
		trackHeight = height;
		this.thumbColor = thumbColor;
		
		track = new FlxSprite().makeGraphic(barWidth, trackHeight, trackColor);
		track.alpha = .65;
		thumb = new FlxSprite(0, thumbPadding).makeGraphic(barWidth, minThumbHeight, thumbColor);
		thumb.setGraphicSize(barWidth - thumbPadding * 2, thumb.height);
		
		add(track);
		add(thumb);
	}
	
	var jack:Float = -1;
	var mouseDiff:Float = -1;
	var draggingThumb:Bool = false;
	
	public override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		
		if (!visible)
		{
			draggingThumb = false;
			jack = -1;
			
			return;
		}
		
		if (interactable && FlxG.mouse.justPressed && FlxG.mouse.overlaps(this))
		{
			interacting = true;
			
			mouseDiff = (FlxG.mouse.getWorldPosition(this.camera).y - thumb.y);
			
			onInteract.dispatch();
			
			if (FlxG.mouse.overlaps(thumb))
			{
				draggingThumb = true;
				
				onDrag.dispatch();
			}
			else
			{
				scrollPage(mouseDiff > 0 ? 1 : -1);
				
				jack = 0;
			}
		}
		
		if (interactable) updateInteract(elapsed);
		
		thumb.alpha = (draggingThumb ? .75 : (FlxG.mouse.overlaps(this) ? 1 : .875));
		
		setScroll(MathUtil.fpsLerp(scroll, progress, .3));
	}
	
	public function updateInteract(elapsed:Float):Void
	{
		if (interacting && !FlxG.mouse.pressed)
		{
			interacting = false;
			
			onRelease.dispatch();
			
			draggingThumb = false;
			jack = -1;
		}
		
		if (jack >= 0)
		{
			final mod:Int = (mouseDiff > 0 ? 1 : -1);
			
			jack += elapsed;
			
			if (jack >= initialDelay)
			{
				scrollPage(mod);
				
				jack -= rate;
			}
			
			if ((FlxG.mouse.getWorldPosition(this.camera).y > (getYFromScroll(progress) + thumb.height * .5 + track.y) ? 1 : -1) != mod)
				jack = -1;
		}
		
		if (draggingThumb)
		{
			final y:Float = (FlxG.mouse.getWorldPosition(this.camera).y - mouseDiff);
			
			progress = setScroll(getScrollFromY(y - track.y));
		}
	}
	
	public function setMetrics(visibleRegion:Float, totalRegion:Float):Void
	{
		if (visibleRegion <= 0 || totalRegion <= 0 || totalRegion <= visibleRegion)
		{
			visible = false;
			return;
		}
		
		visible = true;
		
		var thumbHeight:Float = trackHeight * (visibleRegion / totalRegion);
		if (thumbHeight < minThumbHeight) thumbHeight = minThumbHeight;
		if (maxThumbHeight != null && thumbHeight > maxThumbHeight) thumbHeight = maxThumbHeight;
		if (thumbHeight > trackHeight) thumbHeight = trackHeight;
		
		thumb.makeGraphic(barWidth, Std.int(Math.ceil(thumbHeight)), thumbColor);
		thumb.setGraphicSize(barWidth - thumbPadding * 2, thumb.height);
	}
	
	public function setProgress(ratio:Float):Void
	{
		scroll = progress = ratio;
		
		updateThumb();
	}
	
	inline function updateThumb():Void
	{
		thumb.x = track.x;
		thumb.y = (getYFromScroll(scroll) + track.y);
	}
	
	public function setScroll(v:Float):Float
	{
		final prevScroll:Float = scroll;
		
		if (prevScroll != v)
		{
			scroll = v;
			
			updateThumb();
			
			onScroll.dispatch(v, prevScroll);
		}
		
		return scroll;
	}
	
	public function scrollPage(pages:Int = 0):Void
	{
		final prevProgress:Float = progress;
		final pageProgress:Float = getScrollFromY(thumb.y + thumb.height * pages - track.y);
		
		if (progress != pageProgress)
		{
			progress = pageProgress;
			
			onPage.dispatch(progress, prevProgress);
		}
	}
	
	public inline function getScrollFromY(y:Float):Float
	{
		return FlxMath.bound((y - thumbPadding) / (track.height - thumb.height - thumbPadding * 2), 0, 1);
	}
	
	public inline function getYFromScroll(scroll:Float):Float
	{
		return FlxMath.lerp(thumbPadding, track.height - thumb.height - thumbPadding, scroll);
	}
}
