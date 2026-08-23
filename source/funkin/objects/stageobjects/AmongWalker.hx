package funkin.objects.stageobjects;

import flixel.util.FlxSignal;

typedef AmongWalkerColorData = {
	var name:String;
	var weight:Float;
	var ?atlas:String;
}

class AmongWalker extends Bopper
{
	public var isCustom:Bool = false;
	
	public var currentColorData:AmongWalkerColorData = fallbackColor;
	public var currentColor:String = '';
	public var walkSpeed:Float = 30;
	
	public var xRange:Array<Float> = [0, 0];
	public var savedHeight:Float;
	
	var idle:Bool = false;
	var actionTimer:Float;
	var time:Float;
	var right:Bool;
	var hibernating:Bool = false;
	
	public var onAction:FlxTypedSignal<Bool -> Bool -> Void> = new FlxTypedSignal();
	public var onEnter:FlxTypedSignal<Void -> Void> = new FlxTypedSignal();
	public var onAway:FlxTypedSignal<Void -> Void> = new FlxTypedSignal();
	
	public var friends:Array<AmongWalker> = [];
	
	public var colors:Array<AmongWalkerColorData>;
	public static var defaultColors:Array<AmongWalkerColorData> = [
		{
			name: 'blue',
			weight: 1
		},
		{
			name: 'brown',
			weight: 1
		},
		{
			name: 'lime',
			weight: 1
		},
		{
			name: 'tan',
			weight: 1
		},
		{
			name: 'white',
			weight: .85
		},
		{
			name: 'yellow',
			weight: .75
		},
		{
			name: 'foe', // its a real color ! source: Pantone
			weight: .05,
		}
	];
	public static final fallbackColor:AmongWalkerColorData = {
		name: 'blue',
		weight: 1
	};
	
	public function new(range:Array<Float>, height:Float, thescale:Float, ?friends:Array<AmongWalker>, ?colors:Array<AmongWalkerColorData>)
	{
		super();
		
		this.colors = (colors ?? defaultColors);
		
		if (friends != null) this.friends = friends;
		
		xRange = range;
		savedHeight = height;
		scale.set(thescale, thescale);
		
		swapSkin();
		triggerNextAction();
	}
	
	public function findFreeColor():AmongWalkerColorData
	{
		var friendsColors:Array<String> = [for (friend in friends) friend.currentColor];
		var choosableColors:Array<AmongWalkerColorData> = [for (color in colors) if (!friendsColors.contains(color.name)) color];
		
		if (choosableColors.length == 0)
		{
			trace('we outta color\'s $friendsColors');
			return (Lambda.find(colors, function(color) return (currentColor == color.name)) ?? fallbackColor);
		}
		
		return FlxG.random.getObject(choosableColors, [for (color in choosableColors) color.weight]);
	}
	
	public function setCustom(?name:String, ?atlas:String):Void
	{
		if (name == null)
		{
			isCustom = false;
			return swapSkin();
		}
		
		isCustom = true;
		
		currentColorData = {
			atlas: atlas,
			name: name,
			weight: 1
		};
		currentColor = currentColorData.name;
		
		reloadAtlas();
	}
	
	function swapSkin():Void
	{
		if (!isCustom)
		{
			currentColor = (currentColorData = findFreeColor()).name;
			
			reloadAtlas();
		}
	}
	
	function reloadAtlas():Void
	{
		stopAnim();
		if (hasAnim('idle')) removeAnim('idle');
		if (hasAnim('walk')) removeAnim('walk');
		
		loadAtlas(currentColorData.atlas ?? 'stages/mira/cafeteria/walkers');
		
		addAnimByPrefix('walk', '$currentColor walk', 24, true);
		addAnimByPrefix('idle', '$currentColor idle', 24, false);
		playAnim('idle', true);
		
		canDance = idle;
		
		updateHitbox();
		y = (savedHeight - height);
		
		playAnim(idle ? 'idle' : 'walk', true);
	}
	
	function setNewActionTime():Void
	{
		actionTimer = FlxG.random.float(.75, 3);
	}
	
	function triggerNextAction():Void
	{
		if (!hibernating && FlxG.random.bool(20)) right = FlxG.random.bool(50);
		
		if (!idle && FlxG.random.bool(60))
		{
			idle = true;
		}
		else if (idle && FlxG.random.bool(50))
		{
			idle = false;
		}
		
		setNewActionTime();
		
		onAction.dispatch(idle, right);
		
		if (hibernating)
		{
			hibernating = false;
			visible = true;
			
			onEnter.dispatch();
		}
	}
	
	override function update(elapsed:Float):Void
	{
		actionTimer -= elapsed;
		
		if (actionTimer <= 0) triggerNextAction();
		
		super.update(elapsed);
		
		if (!hibernating)
		{
			if (x > xRange[1] && right)
			{
				actionTimer = FlxG.random.float(5, 10);
				visible = false;
				
				x -= 50;
				swapSkin();
				right = false;
				hibernating = true;
				
				onAway.dispatch();
			}
			else if (x < xRange[0] && !right)
			{
				actionTimer = FlxG.random.float(5, 10);
				visible = false;
				
				x += 50;
				swapSkin();
				right = true;
				hibernating = true;
				
				onAway.dispatch();
			}
			
			if (!idle)
			{
				if (canDance)
				{
					playAnim('walk', true);
					
					canDance = false;
				}
				
				walk(elapsed);
				flipX = !right;
			}
			else
			{
				if (!canDance)
				{
					walk(elapsed * .5);
					
					if (animCurFrame == 0 || animCurFrame == 10)
					{
						playAnim('idle', true);
						
						canDance = true;
					}
				}
				
				flipX = !right;
			}
		}
	}
	
	public inline function walk(elapsed:Float):Void
	{
		x += (elapsed * (right ? walkSpeed : -walkSpeed) * 9);
	}
}