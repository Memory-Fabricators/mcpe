#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;

layout(set = 1, binding = 0) uniform sampler2D texSampler;

layout(location = 0) out vec4 outColor;

void main() {
    vec4 texCol = texture(texSampler, fragUV);
    if (texCol.a < 0.1) discard;
    outColor = texCol * fragColor;
}
