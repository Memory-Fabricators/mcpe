#ifndef NET_MINECRAFT_LUA_PLUGIN__LuaDmabufBridge_H__
#define NET_MINECRAFT_LUA_PLUGIN__LuaDmabufBridge_H__

// LuaDmabufBridge — C-side interface for a Wayland compositor to feed
// dmabuf-backed window frames into the game as Lua-accessible textures.
//
// Architecture:
//
//   ┌──────────────────────────────────────────────────┐
//   │  Wayland Compositor Thread (C, e.g. wlroots)     │
//   │  - Manages Wayland clients and surfaces           │
//   │  - Renders surfaces to dma-buf buffers            │
//   │  - Calls dmabuf_bridge_push_frame() on new frames │
//   └───────────────────┬──────────────────────────────┘
//                       │ dmabuf fd, metadata
//   ┌───────────────────▼──────────────────────────────┐
//   │  LuaDmabufBridge (lock-free ring buffer)         │
//   │  - Thread-safe queue of pending dmabuf frames    │
//   └───────────────────┬──────────────────────────────┘
//                       │ polled from Lua
//   ┌───────────────────▼──────────────────────────────┐
//   │  Lua (mcpe.native.pollWindowFrame)               │
//   │  - Gets dmabuf fd, creates GL texture via EGL    │
//   │  - Renders texture on in-world entity            │
//   └──────────────────────────────────────────────────┘
//
// Usage from the compositor thread (C):
//
//   dmabuf_frame frame = {
//       .window_id = win_id,
//       .fd = dmabuf_fd,
//       .width = w, .height = h,
//       .format = DRM_FORMAT_XRGB8888,
//       .stride = stride,
//       .offset = 0,
//   };
//   dmabuf_bridge_push_frame(&frame);
//
// Usage from Lua:
//
//   local frame = mcpe.native.pollWindowFrame(windowId)
//   if frame then
//       local tex = mcpe.createTextureFromDmabuf(
//           frame.width, frame.height, frame.format,
//           frame.fd, frame.stride, frame.offset)
//       ...
//   end

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Maximum number of pending dmabuf frames per window
#define DMABUF_BRIDGE_MAX_FRAMES 4
#define DMABUF_BRIDGE_MAX_WINDOWS 32

// A single dmabuf frame from a Wayland surface
typedef struct dmabuf_frame {
  uint32_t window_id;   // Opaque window identifier
  int      fd;          // dma-buf file descriptor (ownership transferred)
  int      width;
  int      height;
  uint32_t format;      // DRM fourcc (e.g., DRM_FORMAT_XRGB8888)
  uint32_t stride;
  uint32_t offset;
  uint64_t timestamp;   // Monotonic timestamp in microseconds
  int      frame_number; // Monotonically increasing
} dmabuf_frame_t;

// Initialize the dmabuf bridge. Call once from the main thread before
// starting the compositor.
void dmabuf_bridge_init(void);

// Shut down the dmabuf bridge. Call from the main thread.
void dmabuf_bridge_shutdown(void);

// Push a new frame from the compositor thread.
// Ownership of frame->fd is transferred to the bridge.
// Returns 0 on success, -1 if the queue is full.
int dmabuf_bridge_push_frame(const dmabuf_frame_t *frame);

// Poll for the latest frame for a given window.
// Called from the game thread (Lua context).
// Returns 0 if a frame was available (populates *out_frame),
// -1 if no frame is available.
// On success, ownership of out_frame->fd is transferred to the caller.
int dmabuf_bridge_poll_frame(uint32_t window_id, dmabuf_frame_t *out_frame);

// Release a frame that was previously polled.
// Closes the fd and frees resources.
void dmabuf_bridge_release_frame(dmabuf_frame_t *frame);

#ifdef __cplusplus
}
#endif

#endif // NET_MINECRAFT_LUA_PLUGIN__LuaDmabufBridge_H__
