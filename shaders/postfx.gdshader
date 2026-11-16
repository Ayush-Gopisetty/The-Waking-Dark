shader_type canvas_item;
// Film grain, vignette, slight chromatic aberration and a cold grade.
// Works on both Forward+ and Compatibility (web).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.07;
uniform float vignette = 0.55;
uniform float aberration = 0.0018;
// 0..1: how long the player has been in the dark. Tightens the vignette.
uniform float exposure = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float ca = aberration * (1.0 + exposure * 2.5);
	vec3 col;
	col.r = texture(screen_tex, uv + d * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * ca).b;

	// Cold, slightly desaturated grade.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, 0.8) * vec3(0.93, 0.98, 1.07);

	// Grain, animated per frame.
	float n = hash(floor(uv * vec2(640.0, 360.0)) + fract(TIME * 7.0) * 100.0);
	col += (n - 0.5) * grain;

	// Vignette closes in as darkness exposure grows.
	float r = length(d * vec2(1.6, 1.0));
	float inner = mix(0.35, 0.12, exposure);
	float v = 1.0 - smoothstep(inner, 0.95, r) * (vignette + exposure * 0.35);
	col *= clamp(v, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
