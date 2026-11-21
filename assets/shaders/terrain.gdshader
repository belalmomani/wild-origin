shader_type spatial;
// 4-layer splat terrain: vertex COLOR channels = grass / dirt / gravel / rock weights.
uniform sampler2D grass_a : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_a : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D gravel_a : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_a : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float tile = 0.28;

varying vec4 w;
varying vec2 wuv;

void vertex() {
	w = COLOR;
	wuv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = wuv * tile;
	vec4 k = w / max(w.r + w.g + w.b + w.a, 0.001);
	// two grass scales blended: hides the repeating tile pattern
	vec3 g1 = texture(grass_a, uv).rgb;
	vec3 g2 = texture(grass_a, uv * 0.23 + vec2(0.37, 0.11)).rgb;
	vec3 col = mix(g1, g2, 0.4) * k.r
		+ texture(dirt_a, uv * 0.9).rgb * k.g
		+ texture(gravel_a, uv * 1.6).rgb * k.b
		+ texture(rock_a, uv * 0.6).rgb * k.a;
	float macro = texture(grass_a, wuv * 0.031).g;   // large-scale colour variation
	float macro2 = texture(grass_a, wuv * 0.0075).r;  // very large patches: lush vs dry areas
	col *= (0.78 + 0.5 * macro) * (0.9 + 0.22 * macro2);
	col = mix(col, col * vec3(1.06, 1.0, 0.86), clamp(macro2 * 1.4 - 0.5, 0.0, 1.0) * k.r);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	vec3 n = mix(texture(grass_n, uv).rgb, texture(rock_n, uv * 0.6).rgb, k.a);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.8;
}
