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
	vec3 col = texture(grass_a, uv).rgb * k.r
		+ texture(dirt_a, uv * 0.9).rgb * k.g
		+ texture(gravel_a, uv * 1.6).rgb * k.b
		+ texture(rock_a, uv * 0.6).rgb * k.a;
	float macro = texture(grass_a, wuv * 0.031).g;   // large-scale colour variation
	col *= 0.78 + 0.5 * macro;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	vec3 n = mix(texture(grass_n, uv).rgb, texture(rock_n, uv * 0.6).rgb, k.a);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.8;
}
