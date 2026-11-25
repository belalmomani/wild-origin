shader_type spatial;
// Lake water: animated ripples, sky reflection at grazing angles (fresnel), deep blue centre, light shallows and soft foam at the shore.
uniform vec4 deep_color : source_color = vec4(0.02, 0.24, 0.42, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.16, 0.66, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform float radius = 11.0;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float waves(vec2 p, float t) {
	float h = sin(p.x * 1.3 + t * 1.1) * 0.5 + sin(p.y * 1.7 - t * 0.9) * 0.5;
	h += sin((p.x + p.y) * 2.3 + t * 1.7) * 0.35 + sin((p.x - p.y) * 3.1 - t * 1.3) * 0.25;
	return h;
}

void fragment() {
	vec2 p = lpos.xz;
	float e = 0.05;
	float h0 = waves(p, TIME);
	float hx = waves(p + vec2(e, 0.0), TIME);
	float hz = waves(p + vec2(0.0, e), TIME);
	vec3 n = normalize(vec3(-(hx - h0) / e * 0.045, 1.0, -(hz - h0) / e * 0.045));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0), 3.0);
	float r = length(p) / radius;
	float depth = clamp(1.0 - r, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 0.5, depth));
	col = mix(col, vec3(0.62, 0.84, 1.0), fres * 0.6);
	float foam = smoothstep(0.92, 0.985, r + 0.012 * h0);
	col = mix(col, foam_color.rgb, foam * 0.75);
	ALBEDO = col;
	ALPHA = clamp(mix(0.5, 0.8, smoothstep(0.0, 0.3, depth)) + fres * 0.15 + foam * 0.3, 0.0, 1.0) * (1.0 - smoothstep(0.985, 1.0, r));
	ROUGHNESS = 0.04;
	SPECULAR = 0.8;
	METALLIC = 0.0;
}
