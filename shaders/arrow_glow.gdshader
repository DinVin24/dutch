shader_type spatial;
render_mode unshaded, blend_add, depth_draw_opaque, cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;

void fragment() {
	vec4 color = texture(tex, UV);
	// Brightness keying: discard dark/black pixels to make it transparent
	float brightness = max(color.r, max(color.g, color.b));
	if (brightness < 0.08) {
		discard;
	}
	// Boost the color value to create a glowing neon effect
	ALBEDO = color.rgb * 1.6;
	ALPHA = color.a;
}
