#version 450

layout(location = 0) in vec2 fragUV;

layout(set = 0, binding = 1) uniform CloudColor {
    vec4 color; // rgb tint + alpha
} cloud;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = cloud.color;
}
