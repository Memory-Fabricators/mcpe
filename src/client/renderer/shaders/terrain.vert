#version 450

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;

layout(set = 0, binding = 0) uniform UBO {
    mat4 mvp;
    vec3 offset;
    float _pad;
} ubo;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;

void main() {
    vec3 p = inPos - ubo.offset;
    gl_Position = ubo.mvp * vec4(p, 1.0);
    gl_Position.y = -gl_Position.y; // Vulkan y-down flip
    fragUV    = inUV;
    fragColor = inColor;
}
