#version 450

layout(location = 0) in vec2  v_uv;
layout(location = 1) in vec4  v_color;
layout(location = 2) in float v_fog_depth;

layout(set = 0, binding = 0) uniform Fog {
    vec4  color;
    float start;
    float end;
    float density;
    uint  mode;   // 0=off  1=linear  2=exp
} fog;

layout(set = 1, binding = 0) uniform sampler2D u_tex;

layout(location = 0) out vec4 out_color;

void main() {
    vec4 c = texture(u_tex, v_uv) * v_color;

    if (fog.mode == 1u) {
        float denom = fog.end - fog.start;
        float f = (denom > 0.0001)
            ? clamp((fog.end - v_fog_depth) / denom, 0.0, 1.0)
            : 0.0;
        c.rgb = mix(fog.color.rgb, c.rgb, f);
    } else if (fog.mode == 2u) {
        float f = clamp(exp(-fog.density * v_fog_depth), 0.0, 1.0);
        c.rgb = mix(fog.color.rgb, c.rgb, f);
    }

    out_color = c;
}
