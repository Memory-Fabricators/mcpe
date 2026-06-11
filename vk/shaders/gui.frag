#version 450

layout(location = 0) in vec2  v_uv;
layout(location = 1) in vec4  v_color;
layout(location = 2) in float v_fog_depth;  // unused – present to match vertex outputs

layout(set = 1, binding = 0) uniform sampler2D u_tex;

layout(location = 0) out vec4 out_color;

void main() {
    out_color = texture(u_tex, v_uv) * v_color;
}
