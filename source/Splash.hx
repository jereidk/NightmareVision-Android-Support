package;

import flixel.FlxState;

import funkin.FunkinAssets;
import funkin.states.TitleState;
#if VIDEOS_ALLOWED
import funkin.video.FunkinVideoSprite;
#end

using StringTools;

@:access(flixel.FlxGame)
class Splash extends FlxState
{
	var _cachedAutoPause:Bool;
	
	var logo:FlxSprite;
	
	var willSkip:Bool = false;
	var canSkip:Bool = true;
	
	var initialTimer:Null<FlxTimer> = null;
	
	var spriteEvents:FlxTimer;
	
	#if VIDEOS_ALLOWED
	var video:FunkinVideoSprite;
	#end
	
	override function create()
	{
		_cachedAutoPause = FlxG.autoPause;
		FlxG.autoPause = false;
		
		#if VIDEOS_ALLOWED
		var canPlayVid:Bool = false;
		var video = new FunkinVideoSprite();
		video.onFormat(() -> {
			video.setGraphicSize(0, FlxG.height);
			video.updateHitbox();
			video.screenCenter();
			add(video);
		});
		
		canPlayVid = video.load(Paths.video('intro'));
		#end
		
		initialTimer = FlxTimer.wait(1, () ->
			{
				#if VIDEOS_ALLOWED
				video.onEnd(logoFunc);
				
				if (canPlayVid) video.play() else #end logoFunc();
			});
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		if (logo != null)
		{
			logo.updateHitbox();
			logo.screenCenter();
		}
		
		if (canSkip && (FlxG.keys.justPressed.SPACE || FlxG.keys.justPressed.ENTER || FlxG.mouse.justPressed)) finish();
	}
	
	function logoFunc()
	{
		var folder:Array<String> = [];
		if (!FunkinAssets.isDirectory('assets/images/branding/watermarks') || (folder = FunkinAssets.readDirectory('assets/images/branding/watermarks')).length == 0) { finish(); return; }
		
		folder = folder.filter(str -> !FunkinAssets.isDirectory('assets/images/branding/watermarks/$str'));
		
		var img = FlxG.random.getObject(folder);
                trace(folder);
		
		logo = new FlxSprite().loadGraphic(Paths.image('branding/watermarks/${Path.withoutExtension(img)}'));
		logo.screenCenter();
		logo.visible = false;
		add(logo);
		
		var step = 0;
		new FlxTimer().start(0.25, (t:FlxTimer) -> {
			switch (step++)
			{
				case 0:
					FlxG.sound.volume = 1;
					FlxG.sound.play(Paths.sound('intro'));
					logo.visible = true;
					logo.scale.set(0.2, 1.25);
					t.reset(0.06125);
				case 1:
					logo.scale.set(1.25, 0.5);
					t.reset(0.06125);
				case 2:
					logo.scale.set(1.125, 1.125);
					FlxTween.tween(logo.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.elasticOut});
					t.reset(1.25);
				case 3:
					FlxTween.tween(logo.scale, {x: 0.2, y: 0.2}, 1.5, {ease: FlxEase.quadIn});
					FlxTween.tween(logo, {alpha: 0}, 1.5,
						{
							ease: FlxEase.quadIn,
							onComplete: (t:FlxTween) -> {
								FlxTimer.wait(0.8, finish);
							}
						});
			}
		});
	}
	
	function finish()
	{
		initialTimer?.cancel();
		complete();
	}
	
	function complete()
	{
		FlxG.autoPause = _cachedAutoPause;
		FlxG.switchState(() -> Type.createInstance(Main.startMeta.initialState, []));
	}
}
