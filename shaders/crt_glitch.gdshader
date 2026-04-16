shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float scanline_count : hint_range(0, 1080) = 300.0;
uniform float scanline_intensity : hint_range(0, 1) = 0.1;
uniform float aberration_amount : hint_range(0, 50) = 1.0;
uniform float vignette_intensity : hint_range(0, 1) = 0.4;
uniform float curvature : hint_range(0, 10) = 1.5;
uniform float glitch_intensity : hint_range(0, 1) = 0.0;
// We use Godot's built-in TIME instead of a manual uniform

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
	vec2 uv = curve(SCREEN_UV);
	
	// Black borders for the curvature bounds
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}
	
	// Glitch logic
	if (glitch_intensity > 0.0) {
		float jitter = fract(sin(dot(vec2(floor(uv.y * 20.0), TIME), vec2(12.9898, 78.233))) * 43758.5453) * 2.0 - 1.0;
		if (abs(jitter) < glitch_intensity) {
			uv.x += jitter * glitch_intensity * 0.1;
		}
	}
	
	// Much rarer vertical roll (Once every 8 seconds)
	if (mod(TIME, 8.0) < 0.2) {
		uv.y = fract(uv.y + sin(TIME * 6.0) * 0.02);
	}
	
	// Chromatic Aberration
	float r = texture(screen_texture, uv + vec2(aberration_amount * 0.001, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(aberration_amount * 0.001, 0.0)).b;
	
	vec3 color = vec3(r, g, b);
	
	// Scanlines & Roll
	float scanline_wave = sin(uv.y * scanline_count * PI_VAL * 2.0 - TIME * 5.0);
	float s = (scanline_wave * 0.5 + 0.5) * scanline_intensity;
	color *= (1.0 - s);
	
	// Vignette
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(0.8, 1.0 - vignette_intensity, dist * (1.0 + vignette_intensity));
	color *= vignette;
	
	// Retro Greenish Tint (Phosphor look)
	color.r *= 0.95;
	color.g *= 1.05;
	color.b *= 0.95;
	color = mix(color, vec3(dot(color, vec3(0.299, 0.587, 0.114))), 0.1); // Slightly desaturate a bit
	
	COLOR = vec4(color, 1.0);
}
