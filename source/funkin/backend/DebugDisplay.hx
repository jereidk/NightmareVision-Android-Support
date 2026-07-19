package funkin.backend;

import openfl.display.BitmapData;
import openfl.display.Bitmap;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Assets;
import openfl.display.Sprite;
import openfl.events.Event;

import flixel.util.FlxStringUtil;
import flixel.util.FlxColor;
import flixel.FlxG;

/**
 * enum that handles the display type of the FPS counter.
 */
class FpsDisplayMode
{
	// if we wanna abuse the abstract part more go back to a abstract
	// inline static finals get inlined with less garbage than abstract inlines for whatever reason so consider this the most minute optimization ever
	
	/**
	 * The Fps counter will not be shown.
	 */
	public static inline final DISABLED:Int = 0;
	
	/**
	 * The Fps counter will show Fps and Memory.
	 */
	public static inline final SIMPLE:Int = 1;
	
	/**
	 * The Fps counter will additional info per state.
	 */
	public static inline final ADVANCED:Int = 2;
	
	/**
	 * The Fps counter will show detailed memory breakdown.
	 */
	public static inline final MEMORY:Int = 3;
	
	public static inline function fromString(str:String):Int
	{
		return switch (str)
		{
			case 'Advanced': ADVANCED;
			case 'Memory':   MEMORY;
			case 'Simple':   SIMPLE;
			default:         DISABLED;
		}
	}
}

// /**
//  * enum that handles the display type of the FPS counter.
//  */
// enum abstract FpsDisplayMode(Int) from Int to Int
// {
// 	var DISABLED;
// 	var SIMPLE;
// 	var ADVANCED;
// }

/**
 * A FL Sprite that displays the current FPS and GC memory
 */
@:nullSafety
class DebugDisplay extends Sprite
{
	public static var instance:Null<DebugDisplay> = null;
	
	/**
	 * Creates a DebugDisplay instance
	 * 
	 * Use after your FlxGame is initiated.
	 */
	public static function init()
	{
		if (FlxG.game?.parent == null || instance != null) return;
		
		instance = new DebugDisplay(10, 3, 0xFFFFFF);
		instance.visible = instance.displayType != FpsDisplayMode.DISABLED;
		instance.mouseEnabled = false;
		instance.mouseChildren = false;

		var parent = FlxG.game.parent;
		parent.addChild(instance);
		parent.addEventListener(Event.ADDED, function(_) {
			if (parent.contains(instance) && parent.getChildIndex(instance) < parent.numChildren - 1)
				parent.setChildIndex(instance, parent.numChildren - 1);
		});
	}
	
	/**
	 * The visualized text showing the current fps
	 */
	final textField:TextField;
	
	/**
	 * The bg for the text
	 */
	public final textUnderlay:Bitmap;
	
	/**
	 * If disabled, the fps counter will no longer update visually
	 */
	var canUpdate:Bool = true;
	
	/**
		The current frame rate, expressed using frames-per-second
	**/
	public var currentFPS(default, null):Int = 0;
	
	/**
	 * GC Memory - Heap en uso por HXCPP
	 */
	public var gcMemory(get, never):Float;
	
	/**
	 * GC Reserved - Heap reservado total
	 */
	public var gcReserved(get, never):Float;
	
	/**
	 * GC Large Pool - Pool para objetos grandes
	 */
	public var gcLargePool(get, never):Float;
	
	/**
	 * Task Memory (RSS) - Memoria física real del proceso
	 */
	public var taskMemory(get, never):Float;
	
	/**
	 * Gráficos en cache de Flixel
	 */
	public var cachedGraphics(get, never):Int;
	
	public var displayType:Int = FpsDisplayMode.SIMPLE;
	
	public var plugins:Array<Void->Null<String>> = [];
	
	var times:Array<Float> = [];
	
	var deltaTimeout:Float = 0.0;
	
	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();
		
		textUnderlay = new Bitmap();
		textUnderlay.bitmapData = new BitmapData(1, 1, true, 0x6F000000);
		
		final textFormat = new TextFormat(Assets.getFont("assets/fonts/aller.ttf").fontName, 14, color);
		textFormat.leading = 5;
		
		textField = new TextField();
		textField.selectable = false;
		textField.mouseEnabled = false;
		textField.defaultTextFormat = textFormat;
		textField.autoSize = LEFT;
		textField.multiline = true;
		textField.text = "FPS: ";
		
		displayType = FpsDisplayMode.fromString(ClientPrefs.fpsDisplayType);
		
		addChild(textUnderlay);
		addChild(textField);
		
		this.x = x #if mobile + 50 #end;
		this.y = y;
	}
	
	public static function addPlugin(fun:Void->String):Void->Null<String>
	{
		if (instance == null || instance.plugins.contains(fun)) return fun;
		
		instance.plugins.push(fun);
		
		return fun;
	}
	
	// Event Handlers
	override function __enterFrame(deltaTime:Float):Void
	{
		final now:Float = haxe.Timer.stamp() * 1000;
		times.push(now);
		while (times[0] < now - 1000)
			times.shift();
			
		// prevents the overlay from updating every frame, why would you need to anyways @crowplexus
		if (deltaTimeout < 100)
		{
			deltaTimeout += deltaTime;
			return;
		}
		
		currentFPS = times.length;
		updateText();
		textUnderlay.width = textField.width + 3;
		textUnderlay.height = textField.height + (displayType == FpsDisplayMode.ADVANCED ? 0 : -5);
		
		deltaTimeout = 0.0;
	}
	
	// rebind this function to set a custom fps counter
	public dynamic function updateText():Void
	{
		__updateText();
        #if mobile setScale(); #end
	}
	
	function __updateText()
	{
		displayType = FpsDisplayMode.fromString(ClientPrefs.fpsDisplayType);
		visible = displayType != FpsDisplayMode.DISABLED;

		if (!canUpdate || (displayType == FpsDisplayMode.DISABLED)) return;

		#if cpp
		var str = 'FPS: $currentFPS • GC: ${FlxStringUtil.formatBytes(gcMemory)}';
		#else
		var str = 'FPS: $currentFPS • GC: ${FlxStringUtil.formatBytes(gcMemory)}';
		#end

		#if mobile
		str += ' • ${get_arch()}';
		#end
		
		if (displayType == FpsDisplayMode.MEMORY)
		{
			#if cpp
			final rss = taskMemory;
			final heap = gcMemory;
			final pct = rss > 0 ? Std.int(heap / rss * 100) : 0;
			// Plain ASCII instead of box-drawing/geometric-shape characters --
			// none of them are in aller.ttf's glyph set (confirmed via
			// fonttools cmap), so they risked rendering as blank boxes.
			str += '\n+-- MEMORY --------------------------+';
			str += '\n|  GC Heap   : ${_pad(FlxStringUtil.formatBytes(heap), 12)}  ${pct}% of RSS';
			str += '\n|  GC Rsvd   : ${FlxStringUtil.formatBytes(gcReserved)}';
			str += '\n|  Large Pool: ${FlxStringUtil.formatBytes(gcLargePool)}';
			str += '\n|  RSS (proc): ${FlxStringUtil.formatBytes(rss)}';
			str += '\n|  Textures  : $cachedGraphics cached';
			str += '\n+--------------------------------------+';
			#elseif mobile
			str += '\n+-- MEMORY --------------------------+';
			str += '\n|  Textures  : $cachedGraphics cached';
			str += '\n|  RSS (proc): ${FlxStringUtil.formatBytes(taskMemory)}';
			str += '\n+--------------------------------------+';
			#else
			str += '\n| Textures: $cachedGraphics cached';
			#end
		}

		if (displayType == FpsDisplayMode.ADVANCED)
		{
			var className = Type.getClassName(Type.getClass(FlxG.state));
			if (className.indexOf("ScriptedState") != -1)
			{
				var scripted:funkin.scripting.ScriptedState = cast FlxG.state;
				var path = funkin.scripts.FunkinScript.getPath('scripts/states/${scripted.scriptName}');
				className = 'ScriptedState (${path.replace('scripts/states/', '')})';
			}
			else
			{
				// trim long package names for readability
				final parts = className.split('.');
				className = parts[parts.length - 1];
			}

			str += '\n-----------------------------------';
			str += '\nState  : $className';

			if (FlxG.state.subState != null)
			{
				var subName = Type.getClassName(Type.getClass(FlxG.state.subState));
				final sp = subName.split('.');
				str += '\nSubstate: ${sp[sp.length - 1]}';
			}

			#if android
			str += '\nTex    : $cachedGraphics cached';
			final winW = FlxG.stage.window.width;
			final winH = FlxG.stage.window.height;
			str += '\nDevice : ${winW}×${winH} -> game ${FlxG.width}×${FlxG.height}';
			#else
			str += '\nTex: $cachedGraphics cached';
			#end

			for (fun in plugins)
			{
				try
				{
					final pluginStr:Null<String> = fun();
					if (pluginStr != null && pluginStr.length > 0) str += '\n$pluginStr';
				}
				catch (e)
				{
					Logger.log('Error on debug display plugin: $e', WARN);
					plugins.remove(fun);
				}
			}
		}
		
		textField.text = str;
		textField.textColor = ClientPrefs.fpsRGB
			? FlxColor.fromHSB((haxe.Timer.stamp() * 90) % 360, 1.0, 1.0)
			: 0xFFFFFFFF;
	}

	inline function get_gcMemory():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
		#elseif hl
		return hl.Gc.stats().currentMemory;
		#else
		return (cast openfl.system.System.totalMemoryNumber : UInt);
		#end
	}
	
	inline function get_gcReserved():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED);
		#else
		return 0;
		#end
	}
	
	inline function get_gcLargePool():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_LARGE);
		#else
		return 0;
		#end
	}
	
	inline function get_cachedGraphics():Int
	{
		#if flixel
		var count = 0;
		@:privateAccess
		for (key in FlxG.bitmap._cache.keys()) count++;
		return count;
		#else
		return 0;
		#end
	}

    #if mobile
	public inline function setScale(?scale:Float):Void {
	    if (scale == null) {
	        var screenW:Float = FlxG.stage.window.width;
	        var screenH:Float = FlxG.stage.window.height;
	        scale = Math.min(screenW / FlxG.width, screenH / FlxG.height);
	    }

	    #if android
	        var finalScale:Float = (scale > 1) ? scale : 1;
	    #else
	        var finalScale:Float = (scale < 1 ? scale : 1);
	    #end

	    scaleX = scaleY = finalScale;
	}
	#end

    inline function get_arch():String
	{
		#if HXCPP_ARM64
		return "ARM64";
		#elseif HXCPP_ARMV7
		return "ARMv7";
		#elseif HXCPP_X86
		return "x86";
		#elseif (HXCPP_X86_64 || HXCPP_M64)
		return "x86_64";
		#else
		return "Unknown Arch";
		#end
	}

	inline function get_taskMemory():Float
	{
		return external.Native.getTaskMemory();
	}

	static inline function _pad(s:String, len:Int):String
	{
		while (s.length < len) s += ' ';
		return s;
	}
}
