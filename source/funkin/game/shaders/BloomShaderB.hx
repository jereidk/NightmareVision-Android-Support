package funkin.game.shaders;

import flixel.system.FlxAssets.FlxShader;

class BloomShaderB extends FlxShader // BLOOM SHADER BY BBPANZU
{
	@:glFragmentSource('
	#pragma header

    // GAUSSIAN BLUR SETTINGS
  	uniform float dim;
    uniform float Directions;
    uniform float Quality; 
    uniform float Size; 

	void main(void)
	{ 
		vec2 uv = openfl_TextureCoordv.xy ;

		float Pi = 6.28318530718; // Pi*2

		vec4 Color = texture2D( bitmap, uv);

		// Hoist the loop-invariant divides (Directions/Quality are uniforms) so
		// they run once instead of every iteration of the tap loops.
		float angleStep = Pi / Directions;
		float qStep = 1.0 / Quality;

		for(float d=0.0; d<Pi; d+=angleStep){
			// cos(d)/sin(d) only depend on the outer loop -- pull them out of the
			// inner loop so they are not recomputed for every Quality sample.
			float cd = cos(d) * Size;
			float sd = sin(d) * Size;
			for(float i=qStep; i<=1.0; i+=qStep){

				float ex = (cd*i)/openfl_TextureSize.x;
				float why = (sd*i)/openfl_TextureSize.y;
				Color += flixel_texture2D( bitmap, uv+vec2(ex,why));
			}
		}
		
		Color /= (dim * Quality) * Directions - 15.0;
		vec4 bloom =  (flixel_texture2D( bitmap, uv)/ dim)+Color;

		gl_FragColor = bloom;

	}
	')
	public function new()
	{
		super();
		
		Size.value = [18.0];
		Quality.value = [8.0];
		dim.value = [2.0];
		Directions.value = [16.0];
	}
}
