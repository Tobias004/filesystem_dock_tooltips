shader_type spatial;
render_mode cull_disabled;

// Uses a generated NoiseTexture2D so loading the material also exercises
// expensive procedural texture generation similar to the benchmark cases.
uniform sampler2D noise_tex : source_color, repeat_enable;
uniform vec3 dark_color : source_color = vec3(0.02, 0.05, 0.08);
uniform vec3 bright_color : source_color = vec3(0.15, 0.75, 1.0);

void fragment() {
	float n = texture(noise_tex, UV * 3.0).r;
	float bands = smoothstep(0.35, 0.78, n);
	ALBEDO = mix(dark_color, bright_color, bands);
	EMISSION = bright_color * pow(bands, 3.0) * 0.25;
	ROUGHNESS = mix(0.75, 0.28, bands);
}
