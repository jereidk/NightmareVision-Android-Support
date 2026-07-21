package funkin.backend.plugins;

import openfl.display.BitmapData;

import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.transition.FlxTransitionableState;

/**
 * Plugin that shows debug content in game without the need of a console
 */
@:nullSafety
class DebugTextPlugin extends FlxTypedGroup<DebugText>
{
	static var instance:Null<DebugTextPlugin> = null;
	
	public static function init()
	{
		if (instance == null)
		{
			FlxG.plugins.addPlugin(instance = new DebugTextPlugin());
			FlxG.signals.preStateSwitch.add(clearTxt);
		}
	}
	
	static inline function posText()
	{
		if (instance == null) return;
		
		var y:Float = 25;
		
		instance.forEachAlive((txt:DebugText) ->
		{
			txt.y = y;
			y += txt.height;
		});
	}
	
	static function grabText(message:String):DebugText
	{
		if (instance == null) return new DebugText(message);
		
		for (text in instance)
		{
			if (text == null) continue;
			
			if (text.alive && text._trace == message) return text;
		}
		
		return instance.recycle(DebugText, () -> new DebugText(message));
	}
	
	#if android
	// A device log showed a 702ms [SPIKE] from 48 new "textNNN" bitmap
	// textures created inside a single frame during real gameplay -- FlxText
	// re-rasterizes into a brand-new cached bitmap every time its .text
	// changes (see DebugText.draw()'s `this.text = ...`), and addText() is
	// the one thing that can fire many DISTINCT messages in the same frame
	// (each unique message -> a new/recycled DebugText -> a fresh texture on
	// its next draw()). Counts calls in a short rolling window and traces a
	// burst with its actual messages, instead of just "+48 texture(s)" with
	// no indication of who's responsible.
	static var _burstCount:Int = 0;
	static var _burstWindowStart:Float = 0;
	static var _burstMessages:Array<String> = [];
	static inline final _BURST_WINDOW_S:Float = 0.1;
	static inline final _BURST_THRESHOLD:Int = 8;
	#end

	public static function addText(message:String, colour:FlxColor = FlxColor.WHITE)
	{
		if (instance == null) return;

		#if android
		final _now = haxe.Timer.stamp();
		if (_now - _burstWindowStart > _BURST_WINDOW_S)
		{
			if (_burstCount >= _BURST_THRESHOLD)
				trace('[DebugTextPlugin] burst: $_burstCount addText() call(s) within ${Std.int(_BURST_WINDOW_S * 1000)}ms -- sample: ${_burstMessages.join(" | ")}');
			_burstWindowStart = _now;
			_burstCount = 0;
			_burstMessages = [];
		}
		_burstCount++;
		if (_burstMessages.length < 5 && !_burstMessages.contains(message)) _burstMessages.push(message);
		#end

		final text = grabText(message);
		
		text.traceCount++;
		text.color = colour;
		text.setText(message);
		text.resetValues();
		text.revive();
		
		instance.remove(text, true);
		instance.insert(0, text);
		
		instance.camera = CameraUtil.lastCamera;
		
		posText();
	}
	
	static function clearTxt()
	{
		if (instance == null) return;
		
		instance.forEach(text -> text?.destroy());
		
		instance.clear();
	}
}

class DebugText extends FlxText
{
	public var disableTime:Float = 4;
	public var traceCount(default, set):Int = 0;
	
	@:allow(funkin.backend.plugins.DebugTextPlugin)
	private var _trace = '';
	
	var _dirty:Bool = false;
	
	public function new(text:String, color:FlxColor = FlxColor.WHITE)
	{
		super(10, 10, FlxG.width, text, 16);
		
		setFormat(Paths.DEFAULT_FONT, 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scrollFactor.set();
		borderSize = 1;
		this.color = color;
		
		setText(text);
	}
	
	public function setText(input:String)
	{
		this._trace = input;
		_dirty = true;
	}
	
	public function resetValues()
	{
		this.disableTime = 4;
		this.alpha = 1;
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		disableTime -= elapsed;
		if (y >= FlxG.height) kill();
		
		if (disableTime <= 0)
		{
			traceCount = 0;
			kill();
		}
		else if (disableTime < 1) alpha = disableTime;
	}
	
	override function draw()
	{
		if (_dirty)
		{
			final traceCounter = traceCount > 1 ? '[' + '$traceCount' + ']' + ' - ' : '';
			
			this.text = '$traceCounter$_trace';
			_dirty = false;
		}
		super.draw();
	}
	
	inline function set_traceCount(v:Int)
	{
		if (v == traceCount) return v;
		
		_dirty = true;
		
		return traceCount = v;
	}
}
