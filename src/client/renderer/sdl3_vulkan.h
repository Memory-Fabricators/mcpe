/*
 * Minimal aggregate header used by zig translate-c to produce SDL3 + Vulkan
 * bindings.  We define VK_NO_PROTOTYPES so every Vulkan entry-point is loaded
 * at runtime through the SDL3 / vkGetInstanceProcAddr machinery – exactly like
 * a real Vulkan loader would do.
 */
#define VK_NO_PROTOTYPES 1

#include <vulkan/vulkan.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
