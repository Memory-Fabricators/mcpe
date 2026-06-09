#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * Opaque handle returned to C++.
 */
typedef struct VulkanRenderer {
  uint8_t _private[0];
} VulkanRenderer;

struct VulkanRenderer *vulkan_renderer_new(void *window);

void vulkan_renderer_destroy(struct VulkanRenderer *ptr);

void vulkan_renderer_draw_frame(struct VulkanRenderer *ptr);

extern void *dlopen(const char *path, int32_t mode);

extern void *dlsym(void *handle, const char *symbol);
