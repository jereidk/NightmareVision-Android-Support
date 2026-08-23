package funkin.game.shaders;

// Written by Rozebud, teehee!!

class RimLight extends FlxBasic
{
	public var shader(default, null):RimLightShader = new RimLightShader();
	
	public var angle(default, set):Float = 0;
	public var distance(default, set):Float = 10;
	public var rimlightColor(default, set):FlxColor = FlxColor.WHITE;
	public var refSprite:FlxSprite;
	
	public function new(angle:Float = 0, distance:Float = 10, rimlightColor:FlxColor = FlxColor.WHITE, refSprite:FlxSprite)
	{
		super();
		
		this.angle = angle;
		this.distance = distance;
		this.refSprite = refSprite;
		this.rimlightColor = rimlightColor;
	}
	
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		uvUpdate();
	}
	
	public function uvUpdate():Void
	{
		if (refSprite.frame == null) return;
		shader.bounds.value = [refSprite.frame.uv.left, refSprite.frame.uv.top, refSprite.frame.uv.right, refSprite.frame.uv.bottom];
	}
	
	function set_angle(v:Float):Float
	{
		angle = v;
		shader.angle.value = [angle];
		return v;
	}
	
	function set_distance(v:Float):Float
	{
		distance = v;
		shader.distance.value = [distance];
		return v;
	}
	
	function set_rimlightColor(v:FlxColor):FlxColor
	{
		rimlightColor = v;
		shader.rimlightColor.value = [rimlightColor.redFloat, rimlightColor.greenFloat, rimlightColor.blueFloat, rimlightColor.alphaFloat];
		return v;
	}
}

class RimLightShader extends flixel.system.FlxAssets.FlxShader
{
	@:glFragmentSource('
		#pragma header
		
		uniform float angle;
		uniform float distance;
		uniform vec4 rimlightColor;
		
		uniform vec4 bounds;
		
		void main() {
			vec2 pixelSize = (1.0 / openfl_TextureSize);
			
			vec4 textureColor = flixel_texture2D(bitmap, openfl_TextureCoordv);
			float overlapAlpha;
			
			vec2 distanceScaled = vec2(cos(radians(angle)) * pixelSize.x * distance, sin(radians(angle)) * pixelSize.y * distance);
			
			vec2 overlapCoord = vec2(openfl_TextureCoordv.x + distanceScaled.x, openfl_TextureCoordv.y - distanceScaled.y);
			if (overlapCoord.x < bounds.x || overlapCoord.x > bounds.z || overlapCoord.y < bounds.y || overlapCoord.y > bounds.w) {
				overlapAlpha = 0.;
			} else {
				overlapAlpha = flixel_texture2D(bitmap, overlapCoord).a;
			}
			
			vec3 outColor = mix(rimlightColor.rgb, textureColor.rgb / textureColor.a, overlapAlpha * rimlightColor.a);
			
			gl_FragColor = vec4(outColor.rgb * textureColor.a, textureColor.a);
		}
	')
	public function new()
	{
		super();
	}
}
