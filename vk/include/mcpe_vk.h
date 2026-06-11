#ifndef MCPE_VK_H__
#define MCPE_VK_H__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialise Vulkan renderer. sdl_window is an SDL_Window*.
/// Returns 0 on success.
int vk_init(void *sdl_window, uint32_t width, uint32_t height);

/// Shut down and release all Vulkan resources.
void vk_shutdown(void);

/// Handle window resize.
void vk_resize(uint32_t width, uint32_t height);

/// Begin a new frame. Returns 0 on success, -1 if the swapchain is out of date.
int vk_begin_frame(void);

/// End the current frame (present + flush).
void vk_end_frame(void);

/// Set the clear colour (0.0–1.0 range).
void vk_set_clear_color(float r, float g, float b, float a);

/// Set scissor rectangle.
void vk_set_scissor(int32_t x, int32_t y, uint32_t w, uint32_t h, int enable);

// ---- Projection ----

void vk_projection_perspective(float fov, float aspect, float near, float far);
void vk_projection_ortho(float l, float r, float b, float t, float n, float f);

// ---- Matrix stack ----

void vk_push_matrix(void);
void vk_pop_matrix(void);
void vk_load_identity(void);
void vk_translate(float x, float y, float z);
void vk_rotate(float angle, float x, float y, float z);
void vk_scale(float x, float y, float z);

// ---- Fog ----

/// Linear fog: near..far, blend between fogColor and bg.
void vk_fog_linear(float start, float end, float r, float g, float b);

/// Exponential fog. density = 0 → clear, 1 → solid.
void vk_fog_exp(float density, float r, float g, float b);

/// Disable fog.
void vk_fog_off(void);

// ---- Textures ----

/// Load a texture and return an integer id. data must be (width * height * 4) bytes (RGBA).
uint32_t vk_texture_load(const uint8_t *data, uint32_t width, uint32_t height, int has_alpha);

/// Bind a previously loaded texture.
void vk_texture_bind(uint32_t id);

/// Update a sub-region of an existing texture.
void vk_texture_update_sub(uint32_t id, uint32_t x, uint32_t y, uint32_t w, uint32_t h, const uint8_t *data);

// ---- Vertex submission ----

/// Vertex layout expected by all draw functions (24 bytes, matches VertexDeclPTC):
///   float x, y, z;    // position
///   float u, v;       // texcoord
///   uint32_t color;   // ABGR packed (R in bits 0-7, A in bits 24-31)

/// Reserve `count` vertices in the frame's persistently-mapped GPU vertex buffer.
/// Returns a CPU-writable pointer you must fill before calling vk_commit().
/// Returns NULL if the frame buffer is full.
/// Draw state (texture, fog, matrices) is captured at vk_commit() time.
void *vk_reserve_verts(uint32_t count);

/// Submit a draw call for the `count` vertices just written via vk_reserve_verts().
/// Uses the current texture, fog, pipeline, and matrix state.
void vk_commit(uint32_t count);

/// Convenience: copy `count` pre-built vertices from `data` and draw immediately.
/// Equivalent to: memcpy(vk_reserve_verts(count), data, count*24); vk_commit(count);
void vk_draw_verts(const void *data, uint32_t count);

// ---- Chunk (persistent vertex) buffers ----

/// Associate `count` pre-built vertices with chunk slot `id`.
/// `id` is the same integer that anGenBuffers hands out on the C++ side.
/// Allocates or replaces the device buffer at that slot.
void vk_chunk_set(uint32_t id, const void *data, uint32_t count);

/// Draw a chunk from slot `id` during the active render pass.
void vk_chunk_draw(uint32_t id, uint32_t count);

/// Free the device buffer at slot `id`.
void vk_chunk_free(uint32_t id);

// ---- Matrix read-back (for frustum culling) ----

/// Write the current projection matrix (column-major, 16 floats) into out.
void vk_get_projection_matrix(float *out);

/// Write the current modelview matrix (column-major, 16 floats) into out.
void vk_get_modelview_matrix(float *out);

// ---- Render passes ----

void vk_pass_opaque(void);
void vk_pass_alpha_test(void);
void vk_pass_transparent(void);
void vk_pass_gui(void);
void vk_pass_items(void);

#ifdef __cplusplus
}
#endif

#endif // MCPE_VK_H__
