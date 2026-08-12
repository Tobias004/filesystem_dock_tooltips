shader_type spatial;
render_mode cull_disabled;

void fragment() {
	vec2 uv = UV * 12.0;
	vec2 grid = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);
	vec3 base_color = vec3(0.025, 0.07, 0.10);
	vec3 line_color = vec3(0.0, 0.82, 1.0);
	ALBEDO = mix(base_color, line_color, line);
	EMISSION = line_color * line * 0.18;
	METALLIC = 0.18;
	ROUGHNESS = 0.28;
}
