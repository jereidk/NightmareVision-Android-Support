import funkin.objects.stageobjects.AmongWalker;

public var walkers:Array<AmongWalker> = [];

function onLoad()
{
	videoCutscene('week2/sussus-toogus');
	
	for (i in 0...6)
	{
		var walker = new AmongWalker([-700, 1700], 500 + i * 20, .7 + i * .02, walkers);
		walker.x = (FlxG.random.bool(50) ? walker.xRange[0] + 50 : walker.xRange[1] - 50);
		walker.zIndex = (i + 2);
		
		walker.onAction.add(function() walker.walkSpeed = FlxG.random.float(18, 40));
		
		walker.hibernating = true;
		walker.visible = false;
		
		walkers.push(stage.add(walker));
	}
	
	comeIn();
}

function onCreatePost()
{
	refreshZ();
	
	saxguy = new FlxSprite(0, 0);
	saxguy.frames = Paths.getSparrowAtlas('stages/mira/cafeteria/cyan_toogus');
	saxguy.animation.addByPrefix('bop', 'Cyan Dancy', 24, true);
	saxguy.scrollFactor.set(1.2, 1.2);
	saxguy.scale.set(1.1, 1.1);
	saxguy.alpha = 0.001;
	add(saxguy);
}

function onBeatHit()
{
	for (walker in walkers) walker.onBeatHit(curBeat);
}

function onUpdate(elapsed)
{
	saxguy.x += (elapsed * 15.5 * 9);
}

function onEvent(eventName, value1, value2)
{
	switch (eventName)
	{
		case 'Toogus Sax':
			saxguy.alpha = 1;
			saxguy.setPosition(-550, 275);
			saxguy.animation.play('bop');
		case 'Legacy':
			switch (value1)
			{
				case 'Crewmates Come In': comeIn();
				case 'Crewmates Walk Away': walkAway();
				case 'Crewmates Return': comeBack();
			}
	}
}

function walkAway():Void
{
	for (walker in walkers)
	{
		new FlxTimer().start(FlxG.random.float(.5, 2), function(_) {
			walker.actionTimer = 999;
			
			if (!walker.hibernating)
			{
				walker.idle = false;
				walker.right = (walker.x >= FlxMath.remapToRange(FlxG.random.float(.4, .6), 0, 1, -700, 1700));
				
				walker.onAway.addOnce(function() walker.kill());
			}
			else
			{
				walker.kill();
			}
		});
	}
}

function comeIn():Void
{
	for (walker in walkers)
	{
		new FlxTimer().start(FlxG.random.float(.5, 2), function(_) {
			walker.actionTimer = FlxG.random.float(.5, 1);
			
			function funny():Void
			{
				final randX:Float = FlxMath.remapToRange(FlxG.random.float(.2, .8), 0, 1, -700, 1700);
				
				walker.idle = false;
				walker.right = (walker.x < randX);
				walker.actionTimer = Math.abs((walker.x - randX) / walker.walkSpeed / 9);
				
				walker.onAction.addOnce(function() {
					walker.idle = true;
					walker.right = (walker.x < randX);
					walker.actionTimer = FlxG.random.float(5, 10);
				});
			}
			
			if (walker.hibernating)
			{
				walker.onEnter.addOnce(funny);
			}
			else
			{
				funny();
			}
		});
	}
}

function comeBack():Void
{
	for (walker in walkers)
	{
		walker.setNewActionTime();
		walker.revive();
	}
}
