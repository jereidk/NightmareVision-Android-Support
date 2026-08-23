package funkin.backend;

@:nullSafety
class FallbackState extends MusicBeatState
{
	final warningMessage:String;
	
	final continueCallback:Void->Void;
	
	public function new(warningMessage:String, continueCallback:Void->Void)
	{
		this.continueCallback = continueCallback;
		this.warningMessage = warningMessage;
		super();
	}
	
	override function create()
	{
		// Use only crash-safe primitives — no Paths calls, no external files.
		// If the crash handler fires while the asset system is broken or before
		// extraction completes, loadGraphic/DEFAULT_FONT would throw again and the
		// error screen would never appear.
		var bg = new FlxSprite();
		bg.makeGraphic(FlxG.width, FlxG.height, 0xFF1A0A2E);
		add(bg);

		var error = new FlxText(0, 25, 0, 'ERROR', 46);
		error.setFormat(null, 46, FlxColor.RED, LEFT, OUTLINE, FlxColor.BLACK);
		error.screenCenter(X);
		add(error);
		FlxTween.tween(error, {y: error.y + 45}, 2, {ease: FlxEase.sineInOut, type: PINGPONG});

		var text = new FlxText(25, 0, FlxG.width - 50, warningMessage, 28);
		text.setFormat(null, 28, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		add(text);
		text.screenCenter(Y);

		var hint = new FlxText(0, FlxG.height - 25 - 32, FlxG.width,
			#if android 'Tap to continue.' #else 'Press Confirm to continue.' #end, 32);
		hint.setFormat(null, 32, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		add(hint);

		super.create();
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		var shouldContinue = controls.ACCEPT;
		#if android
		if (!shouldContinue)
		{
			var touch = FlxG.touches.getFirst();
			shouldContinue = touch != null && touch.justPressed;
		}
		#end
		if (shouldContinue)
		{
			persistentUpdate = false;
			continueCallback();
		}
	}
}
