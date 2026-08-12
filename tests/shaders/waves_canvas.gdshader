shader_type canvas_item;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float wave = 0.5 + 0.5 * sin((UV.x + UV.y) * 28.0);
	vec3 tint = mix(vec3(0.12, 0.35, 0.95), vec3(0.95, 0.20, 0.55), wave);
	COLOR = vec4(source.rgb * tint * 1.5, source.a);
}
