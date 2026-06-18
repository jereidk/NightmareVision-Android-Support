package funkin.states.substates;

import funkin.backend.MusicBeatSubstate;

class MissCounterSubstate extends MusicBeatSubstate
{
	var ext:String = 'menu/freeplay/miss/';
	
	var blackBG:flixel.system.FlxBGSprite;
	
	var dummySprites:Array<FlxSprite> = [];
	var missAmountArrow:FlxSprite;
	var missTxt:FlxText;
	
	var curSelection:Int = 0;
	
	var MISSES:Int;
	var MISS_LIMIT:Int = 5;
	
	public var canMove = false;
	public var onConfirm:Int->Void = null;
	
	public function new(?onConfirm:Int->Void)
	{
		super();
		this.onConfirm = onConfirm;
	}
	
	override function create()
	{
		camera = CameraUtil.lastCamera;
		
		canMove = false;
		FlxTimer.wait(0.2, () -> {
			canMove = true;
		});
		
		FlxG.sound.music?.fadeOut(2);
		
		blackBG = new flixel.system.FlxBGSprite();
		blackBG.color = FlxColor.BLACK;
		blackBG.alpha = 0;
		add(blackBG);
		
		dummySprites = [];
		var spacing:Int = 180;
		for (i in 0...MISS_LIMIT + 1)
		{
			var dummypostor:FlxSprite = new FlxSprite(i * spacing, 300).loadGraphic(Paths.image(ext + 'dummypostor' + (i + 1)));
			dummypostor.scale.set(0.8, 0.8);
			dummypostor.updateHitbox();
			dummypostor.alpha = 0;
			dummypostor.ID = i;
			dummySprites.push(dummypostor);
			add(dummypostor);
		}
		// im trying to fugkcing center them
		var last = dummySprites[MISS_LIMIT];
		var totalWidth = last.x + last.width;
		var offsetX = (FlxG.width - totalWidth) / 2;
		for (d in dummySprites)
			d.x += offsetX;
		missAmountArrow = new FlxSprite(0, 400).loadGraphic(Paths.image(ext + 'missAmountArrow'));
		missAmountArrow.alpha = 0;
		add(missAmountArrow);
		
		missTxt = new FlxText(0, 125, FlxG.width, "", 20);
		missTxt.setFormat(Paths.font("vcr.ttf"), 80, FlxColor.RED, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missTxt.antialiasing = false;
		missTxt.scrollFactor.set();
		missTxt.alpha = 0;
		missTxt.borderSize = 3;
		add(missTxt);
		changeSelection(0);
		openDeath();
		
		var bottomControls = new funkin.objects.menu.AmongControls([
			['arrow', 'select'], // select
			['enter', 'conf'], // conf
			['esc', 'back'] // back
		], false);
		bottomControls.color = FlxColor.RED;
		bottomControls.zIndex = 10;
		add(bottomControls);
		
		bottomControls.alpha = 0;
		FlxTween.tween(bottomControls, {alpha: 1}, 0.25, {ease: FlxEase.circIn});
		
		super.create();
	}
	
	function openDeath()
	{
		for (d in dummySprites)
			FlxTween.tween(d, {alpha: 1}, 0.25, {ease: FlxEase.circIn});
		FlxTween.tween(blackBG, {alpha: 1}, 0.25, {ease: FlxEase.circIn});
		FlxTween.tween(missAmountArrow, {alpha: 1}, 0.25, {ease: FlxEase.circIn});
		FlxTween.tween(missTxt, {alpha: 1}, 0.25, {ease: FlxEase.circIn});
	}
	
	function changeSelection(by)
	{
		if (by != 0) FlxG.sound.play(Paths.sound('hover'), 0.5);
		curSelection = FlxMath.wrap(curSelection + by, 0, MISS_LIMIT); // damn why havent i been doing this
		
		for (d in dummySprites)
		{
			final selected:Bool = (d.ID == curSelection);
			
			final mult:Float = (selected ? 1 : 0), inv:Float = (selected ? 0 : 1);
			
			d.setColorTransform(mult, mult, mult, d.alpha, inv * 49, inv * 36, inv * 44);
		}
		
		var sprite = dummySprites[curSelection];
		missAmountArrow.setPosition(sprite.x + (sprite.width - missAmountArrow.width) / 2, sprite.y - 25);
		
		MISSES = (MISS_LIMIT - curSelection);
		missTxt.text = Lang.str('miss_defeat').replace('@', Std.string(MISSES));
		missTxt.x = ((FlxG.width / 2) - (missTxt.width / 2));
	}
	
	override function update(elapsed:Float)
	{
		if (canMove)
		{
			if (controls.UI_RIGHT_P) changeSelection(1);
			if (controls.UI_LEFT_P) changeSelection(-1);
			
			if (FlxG.mouse.justPressed)
			{
				for (d in dummySprites)
				{
					if (!FlxG.mouse.overlaps(d, camera)) continue;
					
					if (curSelection != d.ID)
					{
						changeSelection(d.ID - curSelection);
					}
					else
					{
						confirm();
					}
				}
			}
			
			if (controls.ACCEPT) confirm();
			if (controls.BACK)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
				cancel();
			}
		}
		
		super.update(elapsed);
	}
	
	function confirm()
	{
		if (!canMove) return;
		
		canMove = false;
		
		PlayState.missLimit = true;
		PlayState.totalMisses = MISSES;
		
		FlxG.sound.play(Paths.sound('kill'), .9);
		
		killMembers();
		blackBG.revive(); // lol
		
		FlxTimer.wait(1, () -> if (onConfirm != null) onConfirm(MISSES));
	}
	
	function cancel()
	{
		if (!canMove) return;
		
		for (member in members) FlxTween.tween(member, {alpha: 0}, 0.25, {ease: FlxEase.circIn});
		FlxTimer.wait(0.25, close);
		
		PlayState.missLimit = false;
		
		canMove = false;
	}
}
