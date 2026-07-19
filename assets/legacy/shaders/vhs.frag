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

// NOTE: the 33 NTSC luma/chroma filter taps below used to be written into two
// float[TAPS+1] arrays *every fragment* and then read with a dynamic index --
// a real perf cliff on mobile GPUs (private-array indexing spills to slow
// memory). They're compile-time constants, so main() now folds them straight
// into a fully-unrolled accumulation: no per-pixel array construction, no
// dynamic indexing, bit-identical output.

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

vec3 fetch_yiq(vec2 uv, float offset, float one_x)
{
	// same sample position as the old fetch_offset(); alpha is unused downstream
	// (the final pixel's alpha is sampled fresh at uv), so only YIQ is carried.
	return pass1(uv + vec2((offset - 0.5) * one_x, 0.0)).xyz;
}

void main()
{
	vec2 uv = openfl_TextureCoordv;
	float one_x = 1.0 / openfl_TextureSize.x;
	vec3 signal = vec3(0.0);

	// 33-tap one-sided NTSC filter, unrolled. The 32 outer taps carry weight x2
	// and the final centre tap weight x1 -- exactly the old loop + trailing tap.
	signal += fetch_yiq(uv, -32.0, one_x) * 2.0 * vec3(-0.000174844, 0.001384762, 0.001384762);
	signal += fetch_yiq(uv, -31.0, one_x) * 2.0 * vec3(-0.000205844, 0.001678312, 0.001678312);
	signal += fetch_yiq(uv, -30.0, one_x) * 2.0 * vec3(-0.000149453, 0.002021715, 0.002021715);
	signal += fetch_yiq(uv, -29.0, one_x) * 2.0 * vec3(-0.000051693, 0.002420562, 0.002420562);
	signal += fetch_yiq(uv, -28.0, one_x) * 2.0 * vec3(0.000000000, 0.002880460, 0.002880460);
	signal += fetch_yiq(uv, -27.0, one_x) * 2.0 * vec3(-0.000066171, 0.003406879, 0.003406879);
	signal += fetch_yiq(uv, -26.0, one_x) * 2.0 * vec3(-0.000245058, 0.004004985, 0.004004985);
	signal += fetch_yiq(uv, -25.0, one_x) * 2.0 * vec3(-0.000432928, 0.004679445, 0.004679445);
	signal += fetch_yiq(uv, -24.0, one_x) * 2.0 * vec3(-0.000472644, 0.005434218, 0.005434218);
	signal += fetch_yiq(uv, -23.0, one_x) * 2.0 * vec3(-0.000252236, 0.006272332, 0.006272332);
	signal += fetch_yiq(uv, -22.0, one_x) * 2.0 * vec3(0.000198929, 0.007195654, 0.007195654);
	signal += fetch_yiq(uv, -21.0, one_x) * 2.0 * vec3(0.000687058, 0.008204665, 0.008204665);
	signal += fetch_yiq(uv, -20.0, one_x) * 2.0 * vec3(0.000944112, 0.009298238, 0.009298238);
	signal += fetch_yiq(uv, -19.0, one_x) * 2.0 * vec3(0.000803467, 0.010473450, 0.010473450);
	signal += fetch_yiq(uv, -18.0, one_x) * 2.0 * vec3(0.000363199, 0.011725413, 0.011725413);
	signal += fetch_yiq(uv, -17.0, one_x) * 2.0 * vec3(0.000013422, 0.013047155, 0.013047155);
	signal += fetch_yiq(uv, -16.0, one_x) * 2.0 * vec3(0.000253402, 0.014429548, 0.014429548);
	signal += fetch_yiq(uv, -15.0, one_x) * 2.0 * vec3(0.001339461, 0.015861306, 0.015861306);
	signal += fetch_yiq(uv, -14.0, one_x) * 2.0 * vec3(0.002932972, 0.017329037, 0.017329037);
	signal += fetch_yiq(uv, -13.0, one_x) * 2.0 * vec3(0.003983485, 0.018817382, 0.018817382);
	signal += fetch_yiq(uv, -12.0, one_x) * 2.0 * vec3(0.003026683, 0.020309220, 0.020309220);
	signal += fetch_yiq(uv, -11.0, one_x) * 2.0 * vec3(-0.001102056, 0.021785952, 0.021785952);
	signal += fetch_yiq(uv, -10.0, one_x) * 2.0 * vec3(-0.008373026, 0.023227857, 0.023227857);
	signal += fetch_yiq(uv, -9.0, one_x) * 2.0 * vec3(-0.016897700, 0.024614500, 0.024614500);
	signal += fetch_yiq(uv, -8.0, one_x) * 2.0 * vec3(-0.022914480, 0.025925203, 0.025925203);
	signal += fetch_yiq(uv, -7.0, one_x) * 2.0 * vec3(-0.021642347, 0.027139546, 0.027139546);
	signal += fetch_yiq(uv, -6.0, one_x) * 2.0 * vec3(-0.008863273, 0.028237893, 0.028237893);
	signal += fetch_yiq(uv, -5.0, one_x) * 2.0 * vec3(0.017271957, 0.029201910, 0.029201910);
	signal += fetch_yiq(uv, -4.0, one_x) * 2.0 * vec3(0.054921920, 0.030015081, 0.030015081);
	signal += fetch_yiq(uv, -3.0, one_x) * 2.0 * vec3(0.098342579, 0.030663170, 0.030663170);
	signal += fetch_yiq(uv, -2.0, one_x) * 2.0 * vec3(0.139044281, 0.031134640, 0.031134640);
	signal += fetch_yiq(uv, -1.0, one_x) * 2.0 * vec3(0.168055832, 0.031420995, 0.031420995);
	signal += fetch_yiq(uv, 0.0, one_x) * vec3(0.178571429, 0.031517031, 0.031517031);

	vec3 rgb = yiq2rgb(signal);
	gl_FragColor = vec4(pow(rgb, vec3(NTSC_CRT_GAMMA / NTSC_MONITOR_GAMMA)), flixel_texture2D(bitmap, uv).a);
}
