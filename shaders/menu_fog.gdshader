shader_type canvas_item;
// Slow drifting fog and a heavy vignette for the title screen background.

uniform vec3 tint : source_color = vec3(0.1, 0.13, 0.2);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(7.3, 1.9);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	uv.x *= 1.78;
	float t = TIME * 0.025;
	float fog = fbm(uv * 2.2 + vec2(t, -t * 0.6));
	fog = fog * fbm(uv * 1.3 - vec2(t * 0.7, t * 0.3) + 4.0);
	vec3 col = tint * fog * 2.6;
	// A faint pale glow low on the right, like a window in the distance.
	float glow = smoothstep(0.7, 0.0, distance(UV, vec2(0.78, 0.62)));
	col += vec3(0.1, 0.12, 0.17) * glow * (0.5 + fog);
	// Vignette.
	float v = smoothstep(0.95, 0.25, distance(UV, vec2(0.5, 0.5)));
	col *= v;
	// Grain.
	col += (hash(UV * vec2(1280.0, 720.0) + fract(TIME) * 50.0) - 0.5) * 0.025;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
