#version 450

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec4 in_color;  // R8G8B8A8_UNORM → [0,1]

layout(push_constant) uniform Push {
    mat4 mvp;
} push;

layout(location = 0) out vec2  v_uv;
layout(location = 1) out vec4  v_color;
layout(location = 2) out float v_fog_depth;  // abs(clip.w) = view-Z distance

void main() {
    vec4 clip = push.mvp * vec4(in_pos, 1.0);
    gl_Position  = clip;
    v_uv         = in_uv;
    v_color      = in_color;
    v_fog_depth  = abs(clip.w);
}
