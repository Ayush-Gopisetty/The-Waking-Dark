shader_type canvas_item;
// The inside of a wardrobe's doors: dark wood, with the seam between the two
// doors and a row of louvre slits to look (and shine a light) through.
uniform float amount = 0.0;   // 0 = not hiding, 1 = inside
uniform float peek = 0.0;     // how far the head is turned (-1..1): the gaps slide

float slit(float d, float half_width, float soft) {
	return 1.0 - smoothstep(half_width, half_width + soft, abs(d));
}

void fragment() {
	vec2 uv = UV;
	float x = uv.x - 0.5 + peek * 0.16;
	// The seam between the doors, a little wider toward the middle.
	float open = slit(x, 0.016 + 0.006 * sin(uv.y * 3.14159), 0.012);
	// Louvre slits across each door at eye level.
	float rows = 0.0;
	for (int i = 0; i < 5; i++) {
		float y = 0.30 + float(i) * 0.075;
		rows = max(rows, slit(uv.y - y, 0.011, 0.008));
	}
	float in_door = smoothstep(0.035, 0.06, abs(x)) * (1.0 - smoothstep(0.30, 0.33, abs(x)));
	open = max(open, rows * in_door);
	// Faint grain so the dark isn't flat black.
	float grain = fract(sin(dot(floor(uv * vec2(260.0, 40.0)), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 wood = vec3(0.018, 0.014, 0.011) * (0.7 + 0.6 * grain);
	COLOR = vec4(wood, (1.0 - open) * amount);
}
