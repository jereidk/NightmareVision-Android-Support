package funkin.game.shaders;

import flixel.graphics.tile.FlxDrawBaseItem;

@:access(flixel.FlxCamera._currentDrawItem)
class RGBGraphics
{
	static inline var VERTICES_PER_QUAD = 4;
	
	public var enabled:Bool;
	
	public var r:FlxColor;
	public var g:FlxColor;
	public var b:FlxColor;
	
	public var mult:Float;
	public var alpha:Float;
	public var flash:Float;
	
	public var alphaMult(get, set):Float;
	
	public function new(?r:FlxColor, ?g:FlxColor, ?b:FlxColor, mult:Float = 1.0)
	{
		enabled = true;
		reset(r, g, b, mult);
	}
	
	public function setColors(colors:Array<FlxColor>)
	{
		reset(colors[0], colors[1], colors[2], mult, alpha, flash);
	}
	
	public function getColors()
	{
		return [r, g, b];
	}
	
	public function copyFrom(graphics:RGBGraphics)
	{
		reset(graphics.r, graphics.g, graphics.b, graphics.mult, graphics.alpha, graphics.flash);
	}
	
	public function reset(?r:FlxColor, ?g:FlxColor, ?b:FlxColor, mult:Float = 1.0, alpha:Float = 1.0, flash:Float = 0.0)
	{
		this.r = r ?? FlxColor.RED;
		this.g = g ?? FlxColor.LIME;
		this.b = b ?? FlxColor.BLUE;
		
		this.mult = mult;
		this.alpha = alpha;
		this.flash = flash;
	}
	
	public function pushQuad(camera:FlxCamera)
	{
		if (!FlxG.renderBlit) push(getDrawItem(camera), VERTICES_PER_QUAD);
	}
	
	public function pushTriangles(camera:FlxCamera, indicesLength:Int)
	{
		if (!FlxG.renderBlit) push(getDrawItem(camera), indicesLength);
	}
	
	function getDrawItem(camera:FlxCamera)
	{
		final item = camera._currentDrawItem;
		item.graphics.rgbShader ??= new RGBShader();
		item.rgbShader = item.graphics.rgbShader;
		return item;
	}
	
	inline function pushColor(param:Array<Float>, color:FlxColor)
	{
		param.push(color.redFloat);
		param.push(color.greenFloat);
		param.push(color.blueFloat);
	}
	
	inline function push<T>(drawItem:FlxDrawBaseItem<T>, indicesLength:Int)
	{
		for (_ in 0...indicesLength)
		{
			drawItem.rgbEnabled.push(enabled ? 1 : 0);
			
			pushColor(drawItem.rgbR, r);
			pushColor(drawItem.rgbG, g);
			pushColor(drawItem.rgbB, b);
			
			drawItem.rgbMult.push(mult);
			
			drawItem.rgbAlpha.push(alpha);
			drawItem.rgbFlash.push(flash);
		}
	}
	
	inline function get_alphaMult():Float return alpha;
	
	inline function set_alphaMult(a:Float):Float return alpha = a;
}

class RGBShader extends flixel.system.FlxAssets.FlxShader
{
	@:glVertexSource('
		#pragma header
	
		attribute vec3 r;
		attribute vec3 g;
		attribute vec3 b;
		attribute float mult;
		attribute float enabled;

		attribute float a_alpha;
		attribute float a_flash;
	
		varying vec3 _r;
		varying vec3 _g;
		varying vec3 _b;
		varying float _mult;
		varying float _enabled;

		varying float _a_alpha;
		varying float _a_flash;

		void main()
		{
			#pragma body
			_r = r;
			_g = g;
			_b = b;
			_mult = mult;
			_enabled = enabled;
			_a_alpha = a_alpha;
			_a_flash = a_flash;
		}
	')
	@:glFragmentSource('
		#pragma header
		
		varying vec3 _r;
		varying vec3 _g;
		varying vec3 _b;
		varying float _mult;
		varying float _enabled;

		varying float _a_alpha;
		varying float _a_flash;

		vec4 rgb(sampler2D bitmap, vec2 coord) 
		{
			vec4 color = flixel_texture2D(bitmap, coord);
			
			if (!hasTransform || color.a == 0. || _mult == 0. || _enabled == 0.) return color;

			vec4 newColor = color;
			newColor.rgb = min(color.r * _r + color.g * _g + color.b * _b, vec3(1.));
			newColor.a = color.a;
			
			color = mix(color, newColor, _mult * _enabled);
			
			if (color.a > 0.) return vec4(color.rgb, color.a);
			
			return vec4(0.);
		}

		void main() 
		{
			vec4 texOutput = rgb(bitmap, openfl_TextureCoordv);
			
			if (_a_flash != 0.0) texOutput = mix(texOutput, vec4(1.), _a_flash) * texOutput.a;

			texOutput *= _a_alpha;

			gl_FragColor = texOutput;
		}
	')
	public function new()
	{
		super();
	}
}

// non batchewd version for compat purposes
class RGBPalette
{
	public var shader:RGBShader;
	
	public var r(default, set):FlxColor;
	public var g(default, set):FlxColor;
	public var b(default, set):FlxColor;
	public var mult(default, set):Float;
	public var alpha(default, set):Float;
	public var flash(default, set):Float;
	public var enabled(default, set):Bool;
	
	public function new(r:FlxColor = 0xFFFF0000, g:FlxColor = 0xFF00FF00, b:FlxColor = 0xFF0000FF, mult:Float = 1.0, alpha:Float = 1.0, flash:Float = 0.0)
	{
		shader = new RGBShader();
		
		this.r = r;
		this.g = g;
		this.b = b;
		this.mult = mult;
		this.alpha = alpha;
		this.flash = flash;
		this.enabled = true;
	}
	
	public function getColors():Array<FlxColor>
	{
		return [r, g, b];
	}
	
	public function setColors(colors:Array<FlxColor>):Void
	{
		r = colors[0];
		g = colors[1];
		b = colors[2];
	}
	
	function set_r(value:FlxColor):FlxColor
	{
		// Extract components and normalize to 0.0 - 1.0 range
		shader.data.r.value = [value.redFloat, value.greenFloat, value.blueFloat];
		return r = value;
	}
	
	function set_g(value:FlxColor):FlxColor
	{
		shader.data.g.value = [value.redFloat, value.greenFloat, value.blueFloat];
		return g = value;
	}
	
	function set_b(value:FlxColor):FlxColor
	{
		shader.data.b.value = [value.redFloat, value.greenFloat, value.blueFloat];
		return b = value;
	}
	
	function set_mult(value:Float):Float
	{
		shader.data.mult.value = [mult = value];
		return value;
	}
	
	function set_alpha(value:Float):Float
	{
		shader.data.a_alpha.value = [alpha = value];
		return value;
	}
	
	function set_flash(value:Float):Float
	{
		shader.data.a_flash.value = [flash = value];
		return value;
	}
	
	function set_enabled(value:Bool):Bool
	{
		shader.data.enabled.value = [value ? 1 : 0];
		return enabled = value;
	}
}
