#pragma header

uniform float block;
uniform float phase;
uniform float rand;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

void main() {
	vec2 px = (openfl_TextureSize / block);
	
	vec2 coord = floor(openfl_TextureCoordv * px) / px;
	coord.x += (sin(coord.y * 32. * step(hash22(vec2(phase + rand, coord.y)).x, .5)) * hash22(vec2(phase - rand, coord.y)).x * 10. / openfl_TextureSize.x);
	coord.y += pow(sin(coord.y * 3.14) * .75, 2.) * (step(hash22(vec2(phase - rand, 0.)).y, .03) * vec2(phase + rand, coord.y).x * .02);
	
	vec4 color = flixel_texture2D(bitmap, coord);
	float wave = (cos(coord.y * openfl_TextureSize.y * .3 - phase * 32.) * .15);
	
	color.g += (color.a * .125);
	color.rba *= .75 + wave;
	
	gl_FragColor = color;
}