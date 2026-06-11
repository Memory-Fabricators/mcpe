// MCPE terrain shader - replaces GLES1 fixed-function
// Vertex format: pos(3xf32) + uv(2xf32) + color(1xu32 ABGR)

struct CameraUniform {
    view_proj: mat4x4<f32>,
    view: mat4x4<f32>,
    proj: mat4x4<f32>,
    camera_pos: vec4<f32>,
}

struct ModelUniform {
    model: mat4x4<f32>,
}

struct FogUniform {
    color: vec4<f32>,
    mode: u32,    // 0=off, 1=linear, 2=exp
    start: f32,
    end: f32,
    density: f32,
}

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(1) @binding(0) var<uniform> model: ModelUniform;
@group(2) @binding(0) var terrain_texture: texture_2d<f32>;
@group(2) @binding(1) var terrain_sampler: sampler;
@group(3) @binding(0) var<uniform> fog: FogUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,  // unorm8x4, ABGR order from CPU
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) texcoord: vec2<f32>,
    @location(1) vertex_color: vec4<f32>,
    @location(2) world_pos: vec3<f32>,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    let world_pos = model.model * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos.xyz;
    out.clip_position = camera.view_proj * world_pos;
    out.texcoord = in.texcoord;
    out.vertex_color = in.color;  // ABGR from CPU vertex data

    return out;
}

// Constants matching the pixel format switches in Tesselator::assignTexture
// GL_UNSIGNED_SHORT_5_6_5  -> 5_6_5
// GL_UNSIGNED_SHORT_4_4_4_4 -> 4_4_4_4
// GL_UNSIGNED_SHORT_5_5_5_1 -> 5_5_5_1
// Standard RGBA8888 -> no conversion needed

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // Sample the terrain atlas texture
    let tex_color = textureSample(terrain_texture, terrain_sampler, in.texcoord);

    // Multiply by vertex color (GLES1-style vertex coloring)
    var color = tex_color * in.vertex_color;

    // Alpha test: discard fragments with alpha < 0.5
    // (this is handled via two separate pipelines: opaque skips, alpha_test keeps)
    // The alpha_test pipeline will use this entry, opaque will have a different
    // entry point that doesn't discard. For simplicity, we use the same shader
    // and configure alpha test via blend state on the CPU side.
    // if (color.a < 0.5) {
    //     discard;
    // }

    // Apply fog
    if (fog.mode == 1u) {
        // Linear fog
        let dist = length(in.world_pos - camera.camera_pos.xyz);
        let fog_factor = clamp((fog.end - dist) / (fog.end - fog.start), 0.0, 1.0);
        color = vec4<f32>(mix(fog.color.rgb, color.rgb, fog_factor), color.a);
    } else if (fog.mode == 2u) {
        // Exponential fog
        let dist = length(in.world_pos - camera.camera_pos.xyz);
        let fog_factor = exp(-fog.density * dist);
        let fog_factor = clamp(fog_factor, 0.0, 1.0);
        color = vec4<f32>(mix(fog.color.rgb, color.rgb, fog_factor), color.a);
    }

    return color;
}

// Alpha-tested variant
@fragment
fn fs_main_alpha(in: VertexOutput) -> @location(0) vec4<f32> {
    let tex_color = textureSample(terrain_texture, terrain_sampler, in.texcoord);

    // Discard fully transparent fragments
    if (tex_color.a < 0.5) {
        discard;
    }

    var color = tex_color * in.vertex_color;

    // Apply fog
    if (fog.mode == 1u) {
        let dist = length(in.world_pos - camera.camera_pos.xyz);
        let fog_factor = clamp((fog.end - dist) / (fog.end - fog.start), 0.0, 1.0);
        color = vec4<f32>(mix(fog.color.rgb, color.rgb, fog_factor), color.a);
    } else if (fog.mode == 2u) {
        let dist = length(in.world_pos - camera.camera_pos.xyz);
        let fog_factor = exp(-fog.density * dist);
        let fog_factor = clamp(fog_factor, 0.0, 1.0);
        color = vec4<f32>(mix(fog.color.rgb, color.rgb, fog_factor), color.a);
    }

    return color;
}
