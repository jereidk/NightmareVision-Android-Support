#pragma header

#pragma format R8G8B8A8_SRGB

#define NTSC_CRT_GAMMA 2.5
#define NTSC_MONITOR_GAMMA 2.0

#define TWO_PHASE
#define COMPOSITE
//#define THREE_PHASE
// #define SVIDEO

// begin params
#define PI 3.14159265

#if defined(TWO_PHASE)
	#define CHROMA_MOD_FREQ (4.0 * PI / 15.0)
#elif defined(THREE_PHASE)
	#define CHROMA_MOD_FREQ (PI / 3.0)
#endif

#if defined(COMPOSITE)
	#define SATURATION 1.0
	#define BRIGHTNESS 1.0
	#define ARTIFACTING 1.0
	#define FRINGING 1.0
#elif defined(SVIDEO)
	#define SATURATION 1.0
	#define BRIGHTNESS 1.0
	#define ARTIFACTING 0.0
	#define FRINGING 0.0
#endif
// end params

uniform int uFrame;
uniform float uInterlace;

// fragment compatibility #defines

#if defined(COMPOSITE) || defined(SVIDEO)
mat3 mix_mat = mat3(
	BRIGHTNESS, FRINGING, FRINGING,
	ARTIFACTING, 2.0 * SATURATION, 0.0,
	ARTIFACTING, 0.0, 2.0 * SATURATION
);
#endif

// begin ntsc-rgbyuv
const mat3 yiq2rgb_mat = mat3(
	1.0, 0.956, 0.6210,
	1.0, -0.2720, -0.6474,
	1.0, -1.1060, 1.7046);

vec3 yiq2rgb(vec3 yiq)
{
	return yiq * yiq2rgb_mat;
}

const mat3 yiq_mat = mat3(
	0.2989, 0.5870, 0.1140,
	0.5959, -0.2744, -0.3216,
	0.2115, -0.5229, 0.3114
);

vec3 rgb2yiq(vec3 col)
{
	return col * yiq_mat;
}
// end ntsc-rgbyuv

#define TAPS 16 // NTSC kernel length: 33->17 fetches (~half); weights renormalized so brightness/saturation are unchanged, only the horizontal colour-bleed tail is shorter
float luma_filter[TAPS + 1];
float chroma_filter[TAPS + 1];

vec4 pass1(vec2 uv)
{
	vec2 fragCoord = uv * openfl_TextureSize;

	vec4 cola = flixel_texture2D(bitmap, uv).rgba;
	vec3 yiq = rgb2yiq(cola.rgb);

	#if defined(TWO_PHASE)
		float chroma_phase = PI * (mod(fragCoord.y, 2.0) + float(uFrame));
	#elif defined(THREE_PHASE)
		float chroma_phase = 0.6667 * PI * (mod(fragCoord.y, 3.0) + float(uFrame));
	#endif

	float mod_phase = chroma_phase + fragCoord.x * CHROMA_MOD_FREQ;

	float i_mod = cos(mod_phase);
	float q_mod = sin(mod_phase);

	if(uInterlace == 1.0) {
		yiq.yz *= vec2(i_mod, q_mod); // Modulate.
		yiq *= mix_mat; // Cross-talk.
		yiq.yz *= vec2(i_mod, q_mod); // Demodulate.
	}
	return vec4(yiq, cola.a);
}

vec4 fetch_offset(vec2 uv, float offset, float one_x) {
	return pass1(uv + vec2((offset - 0.5) * one_x, 0.0)).xyzw;
}

void main()
{
	luma_filter[0] = 0.000253889;
	luma_filter[1] = 0.001342038;
	luma_filter[2] = 0.002938614;
	luma_filter[3] = 0.003991148;
	luma_filter[4] = 0.003032506;
	luma_filter[5] = -0.001104176;
	luma_filter[6] = -0.008389134;
	luma_filter[7] = -0.016930207;
	luma_filter[8] = -0.022958562;
	luma_filter[9] = -0.021683982;
	luma_filter[10] = -0.008880324;
	luma_filter[11] = 0.017305184;
	luma_filter[12] = 0.055027577;
	luma_filter[13] = 0.098531767;
	luma_filter[14] = 0.139311770;
	luma_filter[15] = 0.168379132;
	luma_filter[16] = 0.178914959;

	chroma_filter[0] = 0.017775994;
	chroma_filter[1] = 0.019539800;
	chroma_filter[2] = 0.021347922;
	chroma_filter[3] = 0.023181438;
	chroma_filter[4] = 0.025019258;
	chroma_filter[5] = 0.026838468;
	chroma_filter[6] = 0.028614774;
	chroma_filter[7] = 0.030323002;
	chroma_filter[8] = 0.031937678;
	chroma_filter[9] = 0.033433647;
	chroma_filter[10] = 0.034786719;
	chroma_filter[11] = 0.035974307;
	chroma_filter[12] = 0.036976065;
	chroma_filter[13] = 0.037774457;
	chroma_filter[14] = 0.038355268;
	chroma_filter[15] = 0.038708034;
	chroma_filter[16] = 0.038826342;
	
	vec2 uv = openfl_TextureCoordv;
	vec2 fragCoord = uv * openfl_TextureSize;

	float one_x = 1.0 / openfl_TextureSize.x;
	vec4 signal = vec4(0.0);

	for (int i = 0; i < TAPS; i++)
	{
		float offset = float(i);

		vec4 sums = fetch_offset(uv, offset - float(TAPS), one_x) * 2.0;

		signal += sums * vec4(luma_filter[i], chroma_filter[i], chroma_filter[i], 1.0);
	}
	signal += pass1(uv - vec2(0.5 / openfl_TextureSize.x, 0.0)).xyzw *
		vec4(luma_filter[TAPS], chroma_filter[TAPS], chroma_filter[TAPS], 1.0);

	vec3 rgb = yiq2rgb(signal.xyz);
	gl_FragColor = vec4(pow(rgb, vec3(NTSC_CRT_GAMMA / NTSC_MONITOR_GAMMA)), flixel_texture2D(bitmap, uv).a);
}