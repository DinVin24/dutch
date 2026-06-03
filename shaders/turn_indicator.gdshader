shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;

uniform int active_player_index : hint_range(-1, 3) = -1;
uniform vec4 active_color : source_color = vec4(0.9, 0.1, 0.1, 0.95); // Sleek Cyber Red
uniform vec4 inactive_color : source_color = vec4(0.08, 0.08, 0.1, 0.4); // Dark translucent cyber slate
uniform float inner_radius : hint_range(0.0, 2.0) = 0.25;
uniform float outer_radius : hint_range(0.0, 2.0) = 0.85;

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    float dist = length(local_pos.xz);
    
    // Discard pixels outside the ring
    if (dist < inner_radius || dist > outer_radius) {
        discard;
    }
    
    // Calculate angle in range [-PI, PI]
    float angle = atan(local_pos.z, local_pos.x);
    
    // Shift angle by PI/4 to align sector separations
    float shifted_angle = angle + 3.14159265359 / 4.0;
    if (shifted_angle < 0.0) {
        shifted_angle += 2.0 * 3.14159265359;
    }
    if (shifted_angle >= 2.0 * 3.14159265359) {
        shifted_angle -= 2.0 * 3.14159265359;
    }
    
    // Determine quadrant: 0 = Right, 1 = Bottom, 2 = Left, 3 = Top
    int quadrant = int(shifted_angle / (3.14159265359 / 2.0));
    
    // Map quadrant to player index
    int player_idx = -1;
    if (quadrant == 0) {
        player_idx = 3; // Player 3 (Right, +X)
    } else if (quadrant == 1) {
        player_idx = 0; // Player 0 (Bottom, +Z)
    } else if (quadrant == 2) {
        player_idx = 1; // Player 1 (Left, -X)
    } else if (quadrant == 3) {
        player_idx = 2; // Player 2 (Top, -Z)
    }
    
    // Draw sector lines and borders
    float angle_mod = mod(shifted_angle, 3.14159265359 / 2.0);
    // Dynamic border thickness based on distance to keep lines sharp
    float sector_line_width = 0.015 / dist;
    float border_thickness = 0.012;
    
    if (angle_mod < sector_line_width || angle_mod > (3.14159265359 / 2.0) - sector_line_width ||
        dist < inner_radius + border_thickness || dist > outer_radius - border_thickness) {
        // Black sleek grid lines
        ALBEDO = vec3(0.02, 0.02, 0.03);
        ALPHA = 0.9;
    } else {
        if (player_idx == active_player_index) {
            // Neon pulse effect
            float pulse = 0.15 * sin(TIME * 6.0) + 0.15;
            ALBEDO = active_color.rgb + vec3(pulse * 0.5, 0.0, pulse * 0.1);
            ALPHA = active_color.a;
        } else {
            ALBEDO = inactive_color.rgb;
            ALPHA = inactive_color.a;
        }
    }
}
