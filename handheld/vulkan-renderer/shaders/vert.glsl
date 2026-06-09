// vulkan_renderer/shaders/vert.glsl — vertex shader replicating GLES fixed-function
#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;

layout(push_constant) uniform PushConsts {
    mat4 mvp;
    vec4 fogColor;
    float fogStart;
    float fogEnd;
} pc;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;
layout(location = 2) out float fragFog;

void main() {
    vec4 worldPos = pc.mvp * vec4(inPos, 1.0);
    gl_Position = worldPos;
    fragUV = inUV;
    fragColor = inColor;
    float depth = worldPos.z / worldPos.w;
    fragFog = clamp((pc.fogEnd - depth) / (pc.fogEnd - pc.fogStart + 0.0001), 0.0, 1.0);
}
