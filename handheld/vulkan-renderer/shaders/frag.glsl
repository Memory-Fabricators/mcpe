// vulkan_renderer/shaders/frag.glsl — fragment shader with fog + alpha test
#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in float fragFog;

layout(push_constant) uniform PushConsts {
    mat4 mvp;
    vec4 fogColor;
    float fogStart;
    float fogEnd;
} pc;

layout(location = 0) out vec4 outColor;

void main() {
    vec4 lit = fragColor;
    if (lit.a < 0.01) discard;
    outColor = mix(pc.fogColor, lit, fragFog);
}
