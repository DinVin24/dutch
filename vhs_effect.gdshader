shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float scanline_count : hint_range(0, 1080) = 400.0;
uniform float distortion_intensity : hint_range(0.0, 0.1) = 0.003;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float roll_speed : hint_range(0.0, 10.0) = 2.0;

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Much rarer vertical roll (Once every 8 seconds)
    if (mod(TIME, 8.0) < 0.1) {
        uv.y = fract(uv.y + sin(TIME * 10.0) * 0.02);
    }
    
    // Horizontal Distort (Much slower and subtler)
    float wave = sin(uv.y * 10.0 + TIME * 4.0) * distortion_intensity;
    uv.x += wave * (1.0 - uv.y); // More distortion at the top
    
    // Chromatic Aberration
    float r = texture(screen_texture, uv + vec2(0.005, 0.0)).r;
    float g = texture(screen_texture, uv).g;
    float b = texture(screen_texture, uv - vec2(0.005, 0.0)).b;
    vec3 color = vec3(r, g, b);
    
    // Scanlines
    float s = sin(uv.y * scanline_count * 3.14159);
    color -= s * 0.1;
    
    // Noise / Grain
    float noise = (random(uv + TIME) - 0.5) * noise_intensity;
    color += noise;
    
    // Vignette
    float vignette = 1.0 - distance(uv, vec2(0.5)) * 1.2;
    color *= clamp(vignette, 0.2, 1.0);
    
    // Slight Green/Magenta tint for "trashy sensor" look
    color.g *= 1.05;
    color.rb *= 0.95;
    
    COLOR = vec4(color, 1.0);
}
