#pragma header

uniform float uTopWidth;
uniform float uBottomWidth;
uniform float uDepthPow;
uniform float uScrollY;

void main()
{
	vec2 uv = openfl_TextureCoordv;
	float depth = clamp(pow(uv.y, uDepthPow), 0.0, 1.0);
	float width = mix(uTopWidth, uBottomWidth, depth);
	float sampleX = ((uv.x - 0.5) / max(width, 0.0001)) + 0.5;
	float sampleY = fract(depth - uScrollY);

	if (sampleX < 0.0 || sampleX > 1.0)
	{
		gl_FragColor = vec4(0.0);
		return;
	}

	gl_FragColor = flixel_texture2D(bitmap, vec2(sampleX, sampleY));
}
