#pragma header

//main part
//https://www.shadertoy.com/view/csc3W8

vec2 complexRot(vec2 a, vec2 b)
{
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main()
{
	vec4 tex = flixel_texture2D(bitmap, openfl_TextureCoordv);

	float thick = 3.;
	float otl = 0.;
	vec2 dir = vec2(1., 0.);
	vec2 roter = vec2(.866, .5);

	for (int i = 0; i < 12; i ++) //360/12 degree/times rotation
	{
		dir = complexRot(dir, roter);
		otl = min(otl + flixel_texture2D(bitmap, openfl_TextureCoordv + (dir * thick / openfl_TextureSize)).a / 3., 1.);
	}

	gl_FragColor = mix(vec4(1.) * otl, tex, tex.a);
}
