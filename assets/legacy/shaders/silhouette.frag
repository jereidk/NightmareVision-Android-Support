#pragma header

uniform vec3 col;
uniform float amount;

void main() {
	vec4 orig = flixel_texture2D(bitmap, openfl_TextureCoordv);
	// mix(black, col, a) is exactly col*a -- one multiply instead of a mix.
	gl_FragColor = vec4(mix(orig.rgb, col * orig.a, amount), orig.a);
}