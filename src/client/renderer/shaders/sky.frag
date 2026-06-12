#version 450

layout(set = 0, binding = 1) uniform SkyColor {
    vec4 color;
} sky;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = sky.color;
}
