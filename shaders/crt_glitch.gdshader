shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float scanline_count : hint_range(0, 1080) = 300.0;
uniform float scanline_intensity : hint_range(0, 1) = 0.1;
uniform float aberration_amount : hint_range(0, 50) = 1.0;
uniform float vignette_intensity : hint_range(0, 1) = 0.4;
uniform float curvature : hint_range(0, 10) = 1.5;
uniform float glitch_intensity : hint_range(0, 1) = 0.0;
uniform float time;

const float PI_VAL = 3.1415926535;

vec2 curve(vec2 uv) {
	if (curvature <= 0.0) return uv;
	uv = uv * 2.0 - 1.0;
	vec2 offset = abs(uv.yx) / curvature;
	uv = uv + uv * offset * offset;
	uv = uv * 0.5 + 0.5;
	return uv;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Glitch logic
	if (glitch_intensity > 0.0) {
		float jitter = fract(sin(dot(vec2(floor(uv.y * 20.0), time), vec2(12.9898, 78.233))) * 43758.5453) * 2.0 - 1.0;
		if (abs(jitter) < glitch_intensity) {
			uv.x += jitter * glitch_intensity * 0.1;
		}
	}
	
	// Basic Chromatic Aberration
	float r = texture(screen_texture, uv + vec2(aberration_amount * 0.001, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(aberration_amount * 0.001, 0.0)).b;
	
	vec3 color = vec3(r, g, b);
	
	// Scanlines
	float s = sin(uv.y * scanline_count * PI_VAL * 2.0);
	s = (s * 0.5 + 0.5) * scanline_intensity;
	color *= (1.0 - s); // Multiply instead of subtract for safer blending
	
	COLOR = vec4(color, 1.0);
}
