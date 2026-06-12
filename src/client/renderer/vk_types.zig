//! vk_types.zig
//! Minimal hand-written Vulkan + SDL3 type/constant/function-pointer layer.
//!
//! We use zig translate-c for the SDL3 surface creation helper (a single
//! SDL_Vulkan_CreateSurface call) and keep everything else as explicit Zig
//! types. This avoids shipping external zig-zon packages while remaining 100%
//! compatible with Zig 0.17-dev master.

const std = @import("std");

// ---------------------------------------------------------------------------
// Platform handle types
// ---------------------------------------------------------------------------
pub const VkInstance = ?*opaque {};
pub const VkPhysicalDevice = ?*opaque {};
pub const VkDevice = ?*opaque {};
pub const VkQueue = ?*opaque {};
pub const VkSurfaceKHR = u64; // non-dispatchable handle
pub const VkSwapchainKHR = u64;
pub const VkImage = u64;
pub const VkImageView = u64;
pub const VkFramebuffer = u64;
pub const VkRenderPass = u64;
pub const VkPipeline = u64;
pub const VkPipelineLayout = u64;
pub const VkDescriptorSetLayout = u64;
pub const VkDescriptorPool = u64;
pub const VkDescriptorSet = u64;
pub const VkShaderModule = u64;
pub const VkBuffer = u64;
pub const VkDeviceMemory = u64;
pub const VkFence = u64;
pub const VkSemaphore = u64;
pub const VkCommandPool = u64;
pub const VkCommandBuffer = ?*opaque {};
pub const VkSampler = u64;
pub const VkDeviceSize = u64;

pub const VK_MAX_EXTENSION_NAME_SIZE = 256;
pub const VkExtensionProperties = extern struct {
    extensionName: [VK_MAX_EXTENSION_NAME_SIZE]u8,
    specVersion: u32,
};

// ---------------------------------------------------------------------------
// Enums / flags (just the values we reference)
// ---------------------------------------------------------------------------
pub const VkResult = i32;
pub const VK_SUCCESS: VkResult = 0;
pub const VK_NOT_READY: VkResult = 1;
pub const VK_TIMEOUT: VkResult = 2;
pub const VK_EVENT_SET: VkResult = 3;
pub const VK_EVENT_RESET: VkResult = 4;
pub const VK_INCOMPLETE: VkResult = 5;
pub const VK_SUBOPTIMAL_KHR: VkResult = 1000001003;
pub const VK_ERROR_OUT_OF_DATE_KHR: VkResult = -1000001004;

pub const VkFormat = u32;
pub const VK_FORMAT_UNDEFINED: VkFormat = 0;
pub const VK_FORMAT_B8G8R8A8_SRGB: VkFormat = 50;
pub const VK_FORMAT_R8G8B8A8_UNORM: VkFormat = 37;
pub const VK_FORMAT_R32G32_SFLOAT: VkFormat = 103;
pub const VK_FORMAT_R32G32B32_SFLOAT: VkFormat = 106;
pub const VK_FORMAT_R8G8B8A8_UINT: VkFormat = 41;
pub const VK_FORMAT_D32_SFLOAT: VkFormat = 126;
pub const VK_FORMAT_D24_UNORM_S8_UINT: VkFormat = 129;

pub const VkColorSpaceKHR = u32;
pub const VK_COLOR_SPACE_SRGB_NONLINEAR_KHR: VkColorSpaceKHR = 0;

pub const VkPresentModeKHR = u32;
pub const VK_PRESENT_MODE_FIFO_KHR: VkPresentModeKHR = 2;
pub const VK_PRESENT_MODE_MAILBOX_KHR: VkPresentModeKHR = 1;
pub const VK_PRESENT_MODE_IMMEDIATE_KHR: VkPresentModeKHR = 0;

pub const VkImageLayout = u32;
pub const VK_IMAGE_LAYOUT_UNDEFINED: VkImageLayout = 0;
pub const VK_IMAGE_LAYOUT_PRESENT_SRC_KHR: VkImageLayout = 1000001002;
pub const VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL: VkImageLayout = 2;
pub const VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL: VkImageLayout = 3;
pub const VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: VkImageLayout = 7;
pub const VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: VkImageLayout = 5;

pub const VkAttachmentLoadOp = u32;
pub const VK_ATTACHMENT_LOAD_OP_LOAD: VkAttachmentLoadOp = 0;
pub const VK_ATTACHMENT_LOAD_OP_CLEAR: VkAttachmentLoadOp = 1;
pub const VK_ATTACHMENT_LOAD_OP_DONT_CARE: VkAttachmentLoadOp = 2;

pub const VkAttachmentStoreOp = u32;
pub const VK_ATTACHMENT_STORE_OP_STORE: VkAttachmentStoreOp = 0;
pub const VK_ATTACHMENT_STORE_OP_DONT_CARE: VkAttachmentStoreOp = 1;

pub const VkSampleCountFlagBits = u32;
pub const VK_SAMPLE_COUNT_1_BIT: VkSampleCountFlagBits = 1;

pub const VkPipelineBindPoint = u32;
pub const VK_PIPELINE_BIND_POINT_GRAPHICS: VkPipelineBindPoint = 0;

pub const VkPipelineCreateFlags = u32;
pub const VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT: VkPipelineCreateFlags = 0x00000001;

pub const VkDescriptorType = u32;
pub const VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER: VkDescriptorType = 6;
pub const VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: VkDescriptorType = 1;

pub const VkShaderStageFlagBits = u32;
pub const VK_SHADER_STAGE_VERTEX_BIT: VkShaderStageFlagBits = 0x00000001;
pub const VK_SHADER_STAGE_FRAGMENT_BIT: VkShaderStageFlagBits = 0x00000010;

pub const VkVertexInputRate = u32;
pub const VK_VERTEX_INPUT_RATE_VERTEX: VkVertexInputRate = 0;

pub const VkPrimitiveTopology = u32;
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: VkPrimitiveTopology = 3;

pub const VkPolygonMode = u32;
pub const VK_POLYGON_MODE_FILL: VkPolygonMode = 0;

pub const VkCullModeFlagBits = u32;
pub const VK_CULL_MODE_NONE: VkCullModeFlagBits = 0;
pub const VK_CULL_MODE_BACK_BIT: VkCullModeFlagBits = 2;

pub const VkFrontFace = u32;
pub const VK_FRONT_FACE_COUNTER_CLOCKWISE: VkFrontFace = 1;

pub const VkCompareOp = u32;
pub const VK_COMPARE_OP_LESS: VkCompareOp = 1;
pub const VK_COMPARE_OP_LESS_OR_EQUAL: VkCompareOp = 3;
pub const VK_COMPARE_OP_ALWAYS: VkCompareOp = 7;

pub const VkBorderColor = u32;
pub const VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK: VkBorderColor = 0;
pub const VK_BORDER_COLOR_INT_TRANSPARENT_BLACK: VkBorderColor = 1;
pub const VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK: VkBorderColor = 2;
pub const VK_BORDER_COLOR_INT_OPAQUE_BLACK: VkBorderColor = 3;
pub const VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE: VkBorderColor = 4;
pub const VK_BORDER_COLOR_INT_OPAQUE_WHITE: VkBorderColor = 5;

pub const VkBlendFactor = u32;
pub const VK_BLEND_FACTOR_ZERO: VkBlendFactor = 0;
pub const VK_BLEND_FACTOR_ONE: VkBlendFactor = 1;
pub const VK_BLEND_FACTOR_SRC_ALPHA: VkBlendFactor = 6;
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: VkBlendFactor = 7;
pub const VK_BLEND_FACTOR_DST_COLOR: VkBlendFactor = 4;
pub const VK_BLEND_FACTOR_SRC_COLOR: VkBlendFactor = 2;

pub const VkBlendOp = u32;
pub const VK_BLEND_OP_ADD: VkBlendOp = 0;

pub const VkCommandBufferLevel = u32;
pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY: VkCommandBufferLevel = 0;

pub const VkCommandBufferUsageFlagBits = u32;
pub const VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: VkCommandBufferUsageFlagBits = 0x00000001;

pub const VkBufferUsageFlagBits = u32;
pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: VkBufferUsageFlagBits = 0x00000080;
pub const VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT: VkBufferUsageFlagBits = 0x00000010;
pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: VkBufferUsageFlagBits = 0x00000001;
pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT: VkBufferUsageFlagBits = 0x00000002;

pub const VkMemoryPropertyFlagBits = u32;
pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT: VkMemoryPropertyFlagBits = 0x00000002;
pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT: VkMemoryPropertyFlagBits = 0x00000004;
pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: VkMemoryPropertyFlagBits = 0x00000001;

pub const VkImageUsageFlagBits = u32;
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: VkImageUsageFlagBits = 0x00000010;
pub const VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT: VkImageUsageFlagBits = 0x00000020;
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: VkImageUsageFlagBits = 0x00000002;
pub const VK_IMAGE_USAGE_SAMPLED_BIT: VkImageUsageFlagBits = 0x00000004;

pub const VkImageAspectFlagBits = u32;
pub const VK_IMAGE_ASPECT_COLOR_BIT: VkImageAspectFlagBits = 0x00000001;
pub const VK_IMAGE_ASPECT_DEPTH_BIT: VkImageAspectFlagBits = 0x00000002;

pub const VkSharingMode = u32;
pub const VK_SHARING_MODE_EXCLUSIVE: VkSharingMode = 0;

pub const VkImageViewType = u32;
pub const VK_IMAGE_VIEW_TYPE_2D: VkImageViewType = 1;

pub const VkImageTiling = u32;
pub const VK_IMAGE_TILING_OPTIMAL: VkImageTiling = 0;
pub const VK_IMAGE_TILING_LINEAR: VkImageTiling = 1;

pub const VkImageType = u32;
pub const VK_IMAGE_TYPE_2D: VkImageType = 1;

pub const VkFilter = u32;
pub const VK_FILTER_NEAREST: VkFilter = 0;
pub const VK_FILTER_LINEAR: VkFilter = 1;

pub const VkSamplerMipmapMode = u32;
pub const VK_SAMPLER_MIPMAP_MODE_NEAREST: VkSamplerMipmapMode = 0;
pub const VK_SAMPLER_MIPMAP_MODE_LINEAR: VkSamplerMipmapMode = 1;

pub const VkSamplerAddressMode = u32;
pub const VK_SAMPLER_ADDRESS_MODE_REPEAT: VkSamplerAddressMode = 0;
pub const VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE: VkSamplerAddressMode = 2;

pub const VkPipelineStageFlagBits = u32;
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: VkPipelineStageFlagBits = 0x00000400;
pub const VK_PIPELINE_STAGE_TRANSFER_BIT: VkPipelineStageFlagBits = 0x00001000;
pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: VkPipelineStageFlagBits = 0x00000001;
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: VkPipelineStageFlagBits = 0x00000080;

pub const VkAccessFlagBits = u32;
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: VkAccessFlagBits = 0x00000100;
pub const VK_ACCESS_TRANSFER_WRITE_BIT: VkAccessFlagBits = 0x00001000;
pub const VK_ACCESS_SHADER_READ_BIT: VkAccessFlagBits = 0x00000020;

pub const VkDependencyFlagBits = u32;

pub const VkQueueFlagBits = u32;
pub const VK_QUEUE_GRAPHICS_BIT: VkQueueFlagBits = 0x00000001;

// ---------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------
pub const VkExtent2D = extern struct {
    width: u32,
    height: u32,
};

pub const VkExtent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32,
};

pub const VkOffset2D = extern struct {
    x: i32,
    y: i32,
};

pub const VkRect2D = extern struct {
    offset: VkOffset2D,
    extent: VkExtent2D,
};

pub const VkViewport = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    minDepth: f32,
    maxDepth: f32,
};

pub const VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

pub const VkClearDepthStencilValue = extern struct {
    depth: f32,
    stencil: u32,
};

pub const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

pub const VkApplicationInfo = extern struct {
    sType: u32 = 0, // VK_STRUCTURE_TYPE_APPLICATION_INFO
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8,
    applicationVersion: u32,
    pEngineName: ?[*:0]const u8,
    engineVersion: u32,
    apiVersion: u32,
};

pub const VkInstanceCreateInfo = extern struct {
    sType: u32 = 1, // VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pApplicationInfo: ?*const VkApplicationInfo,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ?[*]const [*:0]const u8,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
};

pub const VkDeviceQueueCreateInfo = extern struct {
    sType: u32 = 2, // VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueFamilyIndex: u32,
    queueCount: u32,
    pQueuePriorities: *const f32,
};

pub const VkPhysicalDeviceFeatures = extern struct {
    robustBufferAccess: u32 = 0,
    fullDrawIndexUint32: u32 = 0,
    imageCubeArray: u32 = 0,
    independentBlend: u32 = 0,
    geometryShader: u32 = 0,
    tessellationShader: u32 = 0,
    sampleRateShading: u32 = 0,
    dualSrcBlend: u32 = 0,
    logicOp: u32 = 0,
    multiDrawIndirect: u32 = 0,
    drawIndirectFirstInstance: u32 = 0,
    depthClamp: u32 = 0,
    depthBiasClamp: u32 = 0,
    fillModeNonSolid: u32 = 0,
    depthBounds: u32 = 0,
    wideLines: u32 = 0,
    largePoints: u32 = 0,
    alphaToOne: u32 = 0,
    multiViewport: u32 = 0,
    samplerAnisotropy: u32 = 0,
    textureCompressionETC2: u32 = 0,
    textureCompressionASTC_LDR: u32 = 0,
    textureCompressionBC: u32 = 0,
    occlusionQueryPrecise: u32 = 0,
    pipelineStatisticsQuery: u32 = 0,
    vertexPipelineStoresAndAtomics: u32 = 0,
    fragmentStoresAndAtomics: u32 = 0,
    shaderTessellationAndGeometryPointSize: u32 = 0,
    shaderImageGatherExtended: u32 = 0,
    shaderStorageImageExtendedFormats: u32 = 0,
    shaderStorageImageMultisample: u32 = 0,
    shaderStorageImageReadWithoutFormat: u32 = 0,
    shaderStorageImageWriteWithoutFormat: u32 = 0,
    shaderUniformBufferArrayDynamicIndexing: u32 = 0,
    shaderSampledImageArrayDynamicIndexing: u32 = 0,
    shaderStorageBufferArrayDynamicIndexing: u32 = 0,
    shaderStorageImageArrayDynamicIndexing: u32 = 0,
    shaderClipDistance: u32 = 0,
    shaderCullDistance: u32 = 0,
    shaderFloat64: u32 = 0,
    shaderInt64: u32 = 0,
    shaderInt16: u32 = 0,
    shaderResourceResidency: u32 = 0,
    shaderResourceMinLod: u32 = 0,
    sparseBinding: u32 = 0,
    sparseResidencyBuffer: u32 = 0,
    sparseResidencyImage2D: u32 = 0,
    sparseResidencyImage3D: u32 = 0,
    sparseResidency2Samples: u32 = 0,
    sparseResidency4Samples: u32 = 0,
    sparseResidency8Samples: u32 = 0,
    sparseResidency16Samples: u32 = 0,
    sparseResidencyAliased: u32 = 0,
    variableMultisampleRate: u32 = 0,
    inheritedQueries: u32 = 0,
};

pub const VkDeviceCreateInfo = extern struct {
    sType: u32 = 3, // VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueCreateInfoCount: u32,
    pQueueCreateInfos: [*]const VkDeviceQueueCreateInfo,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
    pEnabledFeatures: ?*const VkPhysicalDeviceFeatures,
};

pub const VkSwapchainCreateInfoKHR = extern struct {
    sType: u32 = 1000001000, // VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    surface: VkSurfaceKHR,
    minImageCount: u32,
    imageFormat: VkFormat,
    imageColorSpace: VkColorSpaceKHR,
    imageExtent: VkExtent2D,
    imageArrayLayers: u32 = 1,
    imageUsage: u32,
    imageSharingMode: VkSharingMode,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    preTransform: u32,
    compositeAlpha: u32,
    presentMode: VkPresentModeKHR,
    clipped: u32 = 1,
    oldSwapchain: VkSwapchainKHR = 0,
};

pub const VkImageViewCreateInfo = extern struct {
    sType: u32 = 15, // VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    image: VkImage,
    viewType: VkImageViewType,
    format: VkFormat,
    components: VkComponentMapping,
    subresourceRange: VkImageSubresourceRange,
};

pub const VkComponentMapping = extern struct {
    r: u32 = 0, // VK_COMPONENT_SWIZZLE_IDENTITY
    g: u32 = 0,
    b: u32 = 0,
    a: u32 = 0,
};

pub const VkImageSubresourceRange = extern struct {
    aspectMask: u32,
    baseMipLevel: u32 = 0,
    levelCount: u32 = 1,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 1,
};

pub const VkAttachmentDescription = extern struct {
    flags: u32 = 0,
    format: VkFormat,
    samples: VkSampleCountFlagBits,
    loadOp: VkAttachmentLoadOp,
    storeOp: VkAttachmentStoreOp,
    stencilLoadOp: VkAttachmentLoadOp,
    stencilStoreOp: VkAttachmentStoreOp,
    initialLayout: VkImageLayout,
    finalLayout: VkImageLayout,
};

pub const VkAttachmentReference = extern struct {
    attachment: u32,
    layout: VkImageLayout,
};

pub const VkSubpassDescription = extern struct {
    flags: u32 = 0,
    pipelineBindPoint: VkPipelineBindPoint,
    inputAttachmentCount: u32 = 0,
    pInputAttachments: ?[*]const VkAttachmentReference = null,
    colorAttachmentCount: u32,
    pColorAttachments: [*]const VkAttachmentReference,
    pResolveAttachments: ?[*]const VkAttachmentReference = null,
    pDepthStencilAttachment: ?*const VkAttachmentReference,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments: ?[*]const u32 = null,
};

pub const VkSubpassDependency = extern struct {
    srcSubpass: u32,
    dstSubpass: u32,
    srcStageMask: u32,
    dstStageMask: u32,
    srcAccessMask: u32,
    dstAccessMask: u32,
    dependencyFlags: u32 = 0,
};

pub const VK_SUBPASS_EXTERNAL: u32 = 0xFFFFFFFF;

pub const VkRenderPassCreateInfo = extern struct {
    sType: u32 = 38, // VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    attachmentCount: u32,
    pAttachments: [*]const VkAttachmentDescription,
    subpassCount: u32,
    pSubpasses: [*]const VkSubpassDescription,
    dependencyCount: u32,
    pDependencies: [*]const VkSubpassDependency,
};

pub const VkFramebufferCreateInfo = extern struct {
    sType: u32 = 37, // VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    renderPass: VkRenderPass,
    attachmentCount: u32,
    pAttachments: [*]const VkImageView,
    width: u32,
    height: u32,
    layers: u32 = 1,
};

pub const VkShaderModuleCreateInfo = extern struct {
    sType: u32 = 16, // VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    codeSize: usize,
    pCode: [*]const u32,
};

pub const VkDescriptorSetLayoutBinding = extern struct {
    binding: u32,
    descriptorType: VkDescriptorType,
    descriptorCount: u32,
    stageFlags: u32,
    pImmutableSamplers: ?[*]const VkSampler = null,
};

pub const VkDescriptorSetLayoutCreateInfo = extern struct {
    sType: u32 = 32, // VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    bindingCount: u32,
    pBindings: [*]const VkDescriptorSetLayoutBinding,
};

pub const VkDescriptorPoolSize = extern struct {
    type: VkDescriptorType,
    descriptorCount: u32,
};

pub const VkDescriptorPoolCreateInfo = extern struct {
    sType: u32 = 33, // VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    maxSets: u32,
    poolSizeCount: u32,
    pPoolSizes: [*]const VkDescriptorPoolSize,
};

pub const VkDescriptorSetAllocateInfo = extern struct {
    sType: u32 = 34, // VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
    pNext: ?*const anyopaque = null,
    descriptorPool: VkDescriptorPool,
    descriptorSetCount: u32,
    pSetLayouts: [*]const VkDescriptorSetLayout,
};

pub const VkWriteDescriptorSet = extern struct {
    sType: u32 = 35, // VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
    pNext: ?*const anyopaque = null,
    dstSet: VkDescriptorSet,
    dstBinding: u32,
    dstArrayElement: u32 = 0,
    descriptorCount: u32,
    descriptorType: VkDescriptorType,
    pImageInfo: ?[*]const VkDescriptorImageInfo = null,
    pBufferInfo: ?[*]const VkDescriptorBufferInfo = null,
    pTexelBufferView: ?[*]const u64 = null,
};

pub const VkDescriptorBufferInfo = extern struct {
    buffer: VkBuffer,
    offset: VkDeviceSize,
    range: VkDeviceSize,
};

pub const VkDescriptorImageInfo = extern struct {
    sampler: VkSampler,
    imageView: VkImageView,
    imageLayout: VkImageLayout,
};

pub const VkPipelineLayoutCreateInfo = extern struct {
    sType: u32 = 30, // VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    setLayoutCount: u32,
    pSetLayouts: [*]const VkDescriptorSetLayout,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: ?*const anyopaque = null,
};

pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType: u32 = 18, // VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    stage: VkShaderStageFlagBits,
    module: VkShaderModule,
    pName: [*:0]const u8,
    pSpecializationInfo: ?*const anyopaque = null,
};

pub const VkVertexInputBindingDescription = extern struct {
    binding: u32,
    stride: u32,
    inputRate: VkVertexInputRate,
};

pub const VkVertexInputAttributeDescription = extern struct {
    location: u32,
    binding: u32,
    format: VkFormat,
    offset: u32,
};

pub const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: u32 = 19, // VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    vertexBindingDescriptionCount: u32,
    pVertexBindingDescriptions: [*]const VkVertexInputBindingDescription,
    vertexAttributeDescriptionCount: u32,
    pVertexAttributeDescriptions: [*]const VkVertexInputAttributeDescription,
};

pub const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: u32 = 20, // VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    topology: VkPrimitiveTopology,
    primitiveRestartEnable: u32 = 0,
};

pub const VkPipelineViewportStateCreateInfo = extern struct {
    sType: u32 = 22, // VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    viewportCount: u32,
    pViewports: ?[*]const VkViewport = null, // dynamic
    scissorCount: u32,
    pScissors: ?[*]const VkRect2D = null, // dynamic
};

pub const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType: u32 = 23, // VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    depthClampEnable: u32 = 0,
    rasterizerDiscardEnable: u32 = 0,
    polygonMode: VkPolygonMode,
    cullMode: u32,
    frontFace: VkFrontFace,
    depthBiasEnable: u32 = 0,
    depthBiasConstantFactor: f32 = 0,
    depthBiasClamp: f32 = 0,
    depthBiasSlopeFactor: f32 = 0,
    lineWidth: f32 = 1.0,
};

pub const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType: u32 = 24, // VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    rasterizationSamples: VkSampleCountFlagBits,
    sampleShadingEnable: u32 = 0,
    minSampleShading: f32 = 1.0,
    pSampleMask: ?*const u32 = null,
    alphaToCoverageEnable: u32 = 0,
    alphaToOneEnable: u32 = 0,
};

pub const VkPipelineDepthStencilStateCreateInfo = extern struct {
    sType: u32 = 25, // VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    depthTestEnable: u32,
    depthWriteEnable: u32,
    depthCompareOp: VkCompareOp,
    depthBoundsTestEnable: u32 = 0,
    stencilTestEnable: u32 = 0,
    front: VkStencilOpState = .{},
    back: VkStencilOpState = .{},
    minDepthBounds: f32 = 0.0,
    maxDepthBounds: f32 = 1.0,
};

pub const VkStencilOpState = extern struct {
    failOp: u32 = 0,
    passOp: u32 = 0,
    depthFailOp: u32 = 0,
    compareOp: u32 = 0,
    compareMask: u32 = 0,
    writeMask: u32 = 0,
    reference: u32 = 0,
};

pub const VkPipelineColorBlendAttachmentState = extern struct {
    blendEnable: u32,
    srcColorBlendFactor: VkBlendFactor,
    dstColorBlendFactor: VkBlendFactor,
    colorBlendOp: VkBlendOp,
    srcAlphaBlendFactor: VkBlendFactor,
    dstAlphaBlendFactor: VkBlendFactor,
    alphaBlendOp: VkBlendOp,
    colorWriteMask: u32, // VkColorComponentFlags
};

pub const VK_COLOR_COMPONENT_R_BIT: u32 = 0x1;
pub const VK_COLOR_COMPONENT_G_BIT: u32 = 0x2;
pub const VK_COLOR_COMPONENT_B_BIT: u32 = 0x4;
pub const VK_COLOR_COMPONENT_A_BIT: u32 = 0x8;
pub const VK_COLOR_COMPONENT_ALL: u32 = 0xF;

pub const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType: u32 = 26, // VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    logicOpEnable: u32 = 0,
    logicOp: u32 = 0,
    attachmentCount: u32,
    pAttachments: [*]const VkPipelineColorBlendAttachmentState,
    blendConstants: [4]f32 = .{ 0, 0, 0, 0 },
};

pub const VkDynamicState = u32;
pub const VK_DYNAMIC_STATE_VIEWPORT: VkDynamicState = 0;
pub const VK_DYNAMIC_STATE_SCISSOR: VkDynamicState = 1;

pub const VkPipelineDynamicStateCreateInfo = extern struct {
    sType: u32 = 27, // VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    dynamicStateCount: u32,
    pDynamicStates: [*]const VkDynamicState,
};

pub const VkGraphicsPipelineCreateInfo = extern struct {
    sType: u32 = 28, // VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    stageCount: u32,
    pStages: [*]const VkPipelineShaderStageCreateInfo,
    pVertexInputState: *const VkPipelineVertexInputStateCreateInfo,
    pInputAssemblyState: *const VkPipelineInputAssemblyStateCreateInfo,
    pTessellationState: ?*const anyopaque = null,
    pViewportState: *const VkPipelineViewportStateCreateInfo,
    pRasterizationState: *const VkPipelineRasterizationStateCreateInfo,
    pMultisampleState: *const VkPipelineMultisampleStateCreateInfo,
    pDepthStencilState: ?*const VkPipelineDepthStencilStateCreateInfo,
    pColorBlendState: *const VkPipelineColorBlendStateCreateInfo,
    pDynamicState: ?*const VkPipelineDynamicStateCreateInfo,
    layout: VkPipelineLayout,
    renderPass: VkRenderPass,
    subpass: u32,
    basePipelineHandle: VkPipeline = 0,
    basePipelineIndex: i32 = -1,
};

pub const VkCommandPoolCreateInfo = extern struct {
    sType: u32 = 39, // VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueFamilyIndex: u32,
};

pub const VkCommandBufferAllocateInfo = extern struct {
    sType: u32 = 40, // VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
    pNext: ?*const anyopaque = null,
    commandPool: VkCommandPool,
    level: VkCommandBufferLevel,
    commandBufferCount: u32,
};

pub const VkCommandBufferBeginInfo = extern struct {
    sType: u32 = 42, // VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
    pNext: ?*const anyopaque = null,
    flags: u32,
    pInheritanceInfo: ?*const anyopaque = null,
};

pub const VkRenderPassBeginInfo = extern struct {
    sType: u32 = 43, // VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
    pNext: ?*const anyopaque = null,
    renderPass: VkRenderPass,
    framebuffer: VkFramebuffer,
    renderArea: VkRect2D,
    clearValueCount: u32,
    pClearValues: [*]const VkClearValue,
};

pub const VkSubmitInfo = extern struct {
    sType: u32 = 4, // VK_STRUCTURE_TYPE_SUBMIT_INFO
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32,
    pWaitSemaphores: ?[*]const VkSemaphore,
    pWaitDstStageMask: ?[*]const u32,
    commandBufferCount: u32,
    pCommandBuffers: [*]const VkCommandBuffer,
    signalSemaphoreCount: u32,
    pSignalSemaphores: ?[*]const VkSemaphore,
};

pub const VkPresentInfoKHR = extern struct {
    sType: u32 = 1000001001, // VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32,
    pWaitSemaphores: [*]const VkSemaphore,
    swapchainCount: u32,
    pSwapchains: [*]const VkSwapchainKHR,
    pImageIndices: [*]const u32,
    pResults: ?[*]VkResult = null,
};

pub const VkFenceCreateInfo = extern struct {
    sType: u32 = 8, // VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const VK_FENCE_CREATE_SIGNALED_BIT: u32 = 0x00000001;

pub const VkSemaphoreCreateInfo = extern struct {
    sType: u32 = 9, // VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const VkBufferCreateInfo = extern struct {
    sType: u32 = 12, // VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    size: VkDeviceSize,
    usage: u32,
    sharingMode: VkSharingMode,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
};

pub const VkMemoryRequirements = extern struct {
    size: VkDeviceSize,
    alignment: VkDeviceSize,
    memoryTypeBits: u32,
};

pub const VkMemoryAllocateInfo = extern struct {
    sType: u32 = 5, // VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
    pNext: ?*const anyopaque = null,
    allocationSize: VkDeviceSize,
    memoryTypeIndex: u32,
};

pub const VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32,
    memoryTypes: [32]VkMemoryType,
    memoryHeapCount: u32,
    memoryHeaps: [16]VkMemoryHeap,
};

pub const VkMemoryType = extern struct {
    propertyFlags: u32,
    heapIndex: u32,
};

pub const VkMemoryHeap = extern struct {
    size: VkDeviceSize,
    flags: u32,
};

pub const VkPhysicalDeviceProperties = extern struct {
    apiVersion: u32,
    driverVersion: u32,
    vendorID: u32,
    deviceID: u32,
    deviceType: u32,
    deviceName: [256]u8,
    pipelineCacheUUID: [16]u8,
    limits: VkPhysicalDeviceLimits,
    sparseProperties: VkPhysicalDeviceSparseProperties,
};

pub const VkPhysicalDeviceLimits = extern struct {
    maxImageDimension1D: u32,
    maxImageDimension2D: u32,
    maxImageDimension3D: u32,
    maxImageDimensionCube: u32,
    maxImageArrayLayers: u32,
    maxTexelBufferElements: u32,
    maxUniformBufferRange: u32,
    maxStorageBufferRange: u32,
    maxPushConstantsSize: u32,
    maxMemoryAllocationCount: u32,
    maxSamplerAllocationCount: u32,
    bufferImageGranularity: VkDeviceSize,
    sparseAddressSpaceSize: VkDeviceSize,
    maxBoundDescriptorSets: u32,
    maxPerStageDescriptorSamplers: u32,
    maxPerStageDescriptorUniformBuffers: u32,
    maxPerStageDescriptorStorageBuffers: u32,
    maxPerStageDescriptorSampledImages: u32,
    maxPerStageDescriptorStorageImages: u32,
    maxPerStageDescriptorInputAttachments: u32,
    maxPerStageResources: u32,
    maxDescriptorSetSamplers: u32,
    maxDescriptorSetUniformBuffers: u32,
    maxDescriptorSetUniformBuffersDynamic: u32,
    maxDescriptorSetStorageBuffers: u32,
    maxDescriptorSetStorageBuffersDynamic: u32,
    maxDescriptorSetSampledImages: u32,
    maxDescriptorSetStorageImages: u32,
    maxDescriptorSetInputAttachments: u32,
    maxVertexInputAttributes: u32,
    maxVertexInputBindings: u32,
    maxVertexInputAttributeOffset: u32,
    maxVertexInputBindingStride: u32,
    maxVertexOutputComponents: u32,
    maxTessellationGenerationLevel: u32,
    maxTessellationPatchSize: u32,
    maxTessellationControlPerVertexInputComponents: u32,
    maxTessellationControlPerVertexOutputComponents: u32,
    maxTessellationControlPerPatchOutputComponents: u32,
    maxTessellationControlTotalOutputComponents: u32,
    maxTessellationEvaluationInputComponents: u32,
    maxTessellationEvaluationOutputComponents: u32,
    maxGeometryShaderInvocations: u32,
    maxGeometryInputComponents: u32,
    maxGeometryOutputComponents: u32,
    maxGeometryOutputVertices: u32,
    maxGeometryTotalOutputComponents: u32,
    maxFragmentInputComponents: u32,
    maxFragmentOutputAttachments: u32,
    maxFragmentDualSrcAttachments: u32,
    maxFragmentCombinedOutputResources: u32,
    maxComputeSharedMemorySize: u32,
    maxComputeWorkGroupCount: [3]u32,
    maxComputeWorkGroupInvocations: u32,
    maxComputeWorkGroupSize: [3]u32,
    subPixelPrecisionBits: u32,
    subTexelPrecisionBits: u32,
    mipmapPrecisionBits: u32,
    maxDrawIndexedIndexValue: u32,
    maxDrawIndirectCount: u32,
    maxSamplerLodBias: f32,
    maxSamplerAnisotropy: f32,
    maxViewports: u32,
    maxViewportDimensions: [2]u32,
    viewportBoundsRange: [2]f32,
    viewportSubPixelBits: u32,
    minMemoryMapAlignment: usize,
    minTexelBufferOffsetAlignment: VkDeviceSize,
    minUniformBufferOffsetAlignment: VkDeviceSize,
    minStorageBufferOffsetAlignment: VkDeviceSize,
    minTexelOffset: i32,
    maxTexelOffset: u32,
    minTexelGatherOffset: i32,
    maxTexelGatherOffset: u32,
    minInterpolationOffset: f32,
    maxInterpolationOffset: f32,
    subPixelInterpolationOffsetBits: u32,
    maxFramebufferWidth: u32,
    maxFramebufferHeight: u32,
    maxFramebufferLayers: u32,
    framebufferColorSampleCounts: u32,
    framebufferDepthSampleCounts: u32,
    framebufferStencilSampleCounts: u32,
    framebufferNoAttachmentsSampleCounts: u32,
    maxColorAttachments: u32,
    sampledImageColorSampleCounts: u32,
    sampledImageIntegerSampleCounts: u32,
    sampledImageDepthSampleCounts: u32,
    sampledImageStencilSampleCounts: u32,
    storageImageSampleCounts: u32,
    maxSampleMaskWords: u32,
    timestampComputeAndGraphics: u32,
    timestampPeriod: f32,
    maxClipDistances: u32,
    maxCullDistances: u32,
    maxCombinedClipAndCullDistances: u32,
    discreteQueuePriorities: u32,
    pointSizeRange: [2]f32,
    lineWidthRange: [2]f32,
    pointSizeGranularity: f32,
    lineWidthGranularity: f32,
    strictLines: u32,
    standardSampleLocations: u32,
    optimalBufferCopyOffsetAlignment: VkDeviceSize,
    optimalBufferCopyRowPitchAlignment: VkDeviceSize,
    nonCoherentAtomSize: VkDeviceSize,
};

pub const VkPhysicalDeviceSparseProperties = extern struct {
    residencyStandard2DBlockShape: u32,
    residencyStandard2DMultisampleBlockShape: u32,
    residencyStandard3DBlockShape: u32,
    residencyAlignedMipSize: u32,
    residencyNonResidentStrict: u32,
};

pub const VkQueueFamilyProperties = extern struct {
    queueFlags: u32,
    queueCount: u32,
    timestampValidBits: u32,
    minImageTransferGranularity: VkExtent3D,
};

pub const VkSurfaceCapabilitiesKHR = extern struct {
    minImageCount: u32,
    maxImageCount: u32,
    currentExtent: VkExtent2D,
    minImageExtent: VkExtent2D,
    maxImageExtent: VkExtent2D,
    maxImageArrayLayers: u32,
    supportedTransforms: u32,
    currentTransform: u32,
    supportedCompositeAlpha: u32,
    supportedUsageFlags: u32,
};

pub const VkSurfaceFormatKHR = extern struct {
    format: VkFormat,
    colorSpace: VkColorSpaceKHR,
};

pub const VkImageCreateInfo = extern struct {
    sType: u32 = 14, // VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    imageType: VkImageType,
    format: VkFormat,
    extent: VkExtent3D,
    mipLevels: u32 = 1,
    arrayLayers: u32 = 1,
    samples: VkSampleCountFlagBits = VK_SAMPLE_COUNT_1_BIT,
    tiling: VkImageTiling,
    usage: u32,
    sharingMode: VkSharingMode = VK_SHARING_MODE_EXCLUSIVE,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    initialLayout: VkImageLayout = VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const VkSamplerCreateInfo = extern struct {
    sType: u32 = 31, // VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    magFilter: VkFilter,
    minFilter: VkFilter,
    mipmapMode: VkSamplerMipmapMode,
    addressModeU: VkSamplerAddressMode,
    addressModeV: VkSamplerAddressMode,
    addressModeW: VkSamplerAddressMode,
    mipLodBias: f32 = 0,
    anisotropyEnable: u32 = 0,
    maxAnisotropy: f32 = 1,
    compareEnable: u32 = 0,
    compareOp: VkCompareOp = VK_COMPARE_OP_LESS,
    minLod: f32 = 0,
    maxLod: f32 = 0,
    borderColor: u32 = 0,
    unnormalizedCoordinates: u32 = 0,
};

pub const VkImageMemoryBarrier = extern struct {
    sType: u32 = 45, // VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
    pNext: ?*const anyopaque = null,
    srcAccessMask: u32,
    dstAccessMask: u32,
    oldLayout: VkImageLayout,
    newLayout: VkImageLayout,
    srcQueueFamilyIndex: u32 = VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: u32 = VK_QUEUE_FAMILY_IGNORED,
    image: VkImage,
    subresourceRange: VkImageSubresourceRange,
};

pub const VK_QUEUE_FAMILY_IGNORED: u32 = 0xFFFFFFFF;

pub const VkBufferImageCopy = extern struct {
    bufferOffset: VkDeviceSize,
    bufferRowLength: u32,
    bufferImageHeight: u32,
    imageSubresource: VkImageSubresourceLayers,
    imageOffset: VkOffset3D,
    imageExtent: VkExtent3D,
};

pub const VkImageSubresourceLayers = extern struct {
    aspectMask: u32,
    mipLevel: u32 = 0,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 1,
};

pub const VkOffset3D = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

// ---------------------------------------------------------------------------
// Function pointer table  (populated at runtime from vkGetInstanceProcAddr)
// ---------------------------------------------------------------------------
pub const VkFuncs = struct {
    // Core instance
    vkDestroyInstance: *const fn (VkInstance, ?*const anyopaque) callconv(.c) void,
    vkEnumeratePhysicalDevices: *const fn (VkInstance, *u32, ?[*]VkPhysicalDevice) callconv(.c) VkResult,
    vkEnumerateDeviceExtensionProperties: *const fn (VkPhysicalDevice, ?[*:0]const u8, *u32, ?[*]VkExtensionProperties) callconv(.c) VkResult,
    vkGetPhysicalDeviceProperties: *const fn (VkPhysicalDevice, *VkPhysicalDeviceProperties) callconv(.c) void,
    vkGetPhysicalDeviceQueueFamilyProperties: *const fn (VkPhysicalDevice, *u32, ?[*]VkQueueFamilyProperties) callconv(.c) void,
    vkGetPhysicalDeviceMemoryProperties: *const fn (VkPhysicalDevice, *VkPhysicalDeviceMemoryProperties) callconv(.c) void,
    vkGetPhysicalDeviceFeatures: *const fn (VkPhysicalDevice, *VkPhysicalDeviceFeatures) callconv(.c) void,
    vkGetPhysicalDeviceSurfaceSupportKHR: *const fn (VkPhysicalDevice, u32, VkSurfaceKHR, *u32) callconv(.c) VkResult,
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR: *const fn (VkPhysicalDevice, VkSurfaceKHR, *VkSurfaceCapabilitiesKHR) callconv(.c) VkResult,
    vkGetPhysicalDeviceSurfaceFormatsKHR: *const fn (VkPhysicalDevice, VkSurfaceKHR, *u32, ?[*]VkSurfaceFormatKHR) callconv(.c) VkResult,
    vkGetPhysicalDeviceSurfacePresentModesKHR: *const fn (VkPhysicalDevice, VkSurfaceKHR, *u32, ?[*]VkPresentModeKHR) callconv(.c) VkResult,
    vkCreateDevice: *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const anyopaque, *VkDevice) callconv(.c) VkResult,
    vkDestroySurfaceKHR: *const fn (VkInstance, VkSurfaceKHR, ?*const anyopaque) callconv(.c) void,
    // Core device
    vkGetDeviceProcAddr: *const fn (VkDevice, [*:0]const u8) callconv(.c) ?*const anyopaque,
    vkDestroyDevice: *const fn (VkDevice, ?*const anyopaque) callconv(.c) void,
    vkGetDeviceQueue: *const fn (VkDevice, u32, u32, *VkQueue) callconv(.c) void,
    vkCreateSwapchainKHR: *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const anyopaque, *VkSwapchainKHR) callconv(.c) VkResult,
    vkDestroySwapchainKHR: *const fn (VkDevice, VkSwapchainKHR, ?*const anyopaque) callconv(.c) void,
    vkGetSwapchainImagesKHR: *const fn (VkDevice, VkSwapchainKHR, *u32, ?[*]VkImage) callconv(.c) VkResult,
    vkAcquireNextImageKHR: *const fn (VkDevice, VkSwapchainKHR, u64, VkSemaphore, VkFence, *u32) callconv(.c) VkResult,
    vkQueuePresentKHR: *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) VkResult,
    vkQueueSubmit: *const fn (VkQueue, u32, *const VkSubmitInfo, VkFence) callconv(.c) VkResult,
    vkQueueWaitIdle: *const fn (
        VkQueue,
    ) callconv(.c) VkResult,
    vkDeviceWaitIdle: *const fn (
        VkDevice,
    ) callconv(.c) VkResult,
    vkCreateImageView: *const fn (VkDevice, *const VkImageViewCreateInfo, ?*const anyopaque, *VkImageView) callconv(.c) VkResult,
    vkDestroyImageView: *const fn (VkDevice, VkImageView, ?*const anyopaque) callconv(.c) void,
    vkCreateRenderPass: *const fn (VkDevice, *const VkRenderPassCreateInfo, ?*const anyopaque, *VkRenderPass) callconv(.c) VkResult,
    vkDestroyRenderPass: *const fn (VkDevice, VkRenderPass, ?*const anyopaque) callconv(.c) void,
    vkCreateFramebuffer: *const fn (VkDevice, *const VkFramebufferCreateInfo, ?*const anyopaque, *VkFramebuffer) callconv(.c) VkResult,
    vkDestroyFramebuffer: *const fn (VkDevice, VkFramebuffer, ?*const anyopaque) callconv(.c) void,
    vkCreateShaderModule: *const fn (VkDevice, *const VkShaderModuleCreateInfo, ?*const anyopaque, *VkShaderModule) callconv(.c) VkResult,
    vkDestroyShaderModule: *const fn (VkDevice, VkShaderModule, ?*const anyopaque) callconv(.c) void,
    vkCreateDescriptorSetLayout: *const fn (VkDevice, *const VkDescriptorSetLayoutCreateInfo, ?*const anyopaque, *VkDescriptorSetLayout) callconv(.c) VkResult,
    vkDestroyDescriptorSetLayout: *const fn (VkDevice, VkDescriptorSetLayout, ?*const anyopaque) callconv(.c) void,
    vkCreateDescriptorPool: *const fn (VkDevice, *const VkDescriptorPoolCreateInfo, ?*const anyopaque, *VkDescriptorPool) callconv(.c) VkResult,
    vkDestroyDescriptorPool: *const fn (VkDevice, VkDescriptorPool, ?*const anyopaque) callconv(.c) void,
    vkAllocateDescriptorSets: *const fn (VkDevice, *const VkDescriptorSetAllocateInfo, [*]VkDescriptorSet) callconv(.c) VkResult,
    vkUpdateDescriptorSets: *const fn (VkDevice, u32, [*]const VkWriteDescriptorSet, u32, ?*const anyopaque) callconv(.c) void,
    vkCreatePipelineLayout: *const fn (VkDevice, *const VkPipelineLayoutCreateInfo, ?*const anyopaque, *VkPipelineLayout) callconv(.c) VkResult,
    vkDestroyPipelineLayout: *const fn (VkDevice, VkPipelineLayout, ?*const anyopaque) callconv(.c) void,
    vkCreateGraphicsPipelines: *const fn (VkDevice, u64, u32, [*]const VkGraphicsPipelineCreateInfo, ?*const anyopaque, [*]VkPipeline) callconv(.c) VkResult,
    vkDestroyPipeline: *const fn (VkDevice, VkPipeline, ?*const anyopaque) callconv(.c) void,
    vkCreateCommandPool: *const fn (VkDevice, *const VkCommandPoolCreateInfo, ?*const anyopaque, *VkCommandPool) callconv(.c) VkResult,
    vkDestroyCommandPool: *const fn (VkDevice, VkCommandPool, ?*const anyopaque) callconv(.c) void,
    vkAllocateCommandBuffers: *const fn (VkDevice, *const VkCommandBufferAllocateInfo, [*]VkCommandBuffer) callconv(.c) VkResult,
    vkFreeCommandBuffers: *const fn (VkDevice, VkCommandPool, u32, [*]const VkCommandBuffer) callconv(.c) void,
    vkBeginCommandBuffer: *const fn (VkCommandBuffer, *const VkCommandBufferBeginInfo) callconv(.c) VkResult,
    vkEndCommandBuffer: *const fn (VkCommandBuffer) callconv(.c) VkResult,
    vkCmdBeginRenderPass: *const fn (VkCommandBuffer, *const VkRenderPassBeginInfo, u32) callconv(.c) void,
    vkCmdEndRenderPass: *const fn (VkCommandBuffer) callconv(.c) void,
    vkCmdBindPipeline: *const fn (VkCommandBuffer, VkPipelineBindPoint, VkPipeline) callconv(.c) void,
    vkCmdBindVertexBuffers: *const fn (VkCommandBuffer, u32, u32, [*]const VkBuffer, [*]const VkDeviceSize) callconv(.c) void,
    vkCmdBindDescriptorSets: *const fn (VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, u32, u32, [*]const VkDescriptorSet, u32, ?[*]const u32) callconv(.c) void,
    vkCmdDraw: *const fn (VkCommandBuffer, u32, u32, u32, u32) callconv(.c) void,
    vkCmdSetViewport: *const fn (VkCommandBuffer, u32, u32, [*]const VkViewport) callconv(.c) void,
    vkCmdSetScissor: *const fn (VkCommandBuffer, u32, u32, [*]const VkRect2D) callconv(.c) void,
    vkCmdPipelineBarrier: *const fn (VkCommandBuffer, u32, u32, u32, u32, ?*const anyopaque, u32, ?*const anyopaque, u32, ?[*]const VkImageMemoryBarrier) callconv(.c) void,
    vkCmdCopyBufferToImage: *const fn (VkCommandBuffer, VkBuffer, VkImage, VkImageLayout, u32, [*]const VkBufferImageCopy) callconv(.c) void,
    vkCreateFence: *const fn (VkDevice, *const VkFenceCreateInfo, ?*const anyopaque, *VkFence) callconv(.c) VkResult,
    vkDestroyFence: *const fn (VkDevice, VkFence, ?*const anyopaque) callconv(.c) void,
    vkWaitForFences: *const fn (VkDevice, u32, [*]const VkFence, u32, u64) callconv(.c) VkResult,
    vkResetFences: *const fn (VkDevice, u32, [*]const VkFence) callconv(.c) VkResult,
    vkCreateSemaphore: *const fn (VkDevice, *const VkSemaphoreCreateInfo, ?*const anyopaque, *VkSemaphore) callconv(.c) VkResult,
    vkDestroySemaphore: *const fn (VkDevice, VkSemaphore, ?*const anyopaque) callconv(.c) void,
    vkCreateBuffer: *const fn (VkDevice, *const VkBufferCreateInfo, ?*const anyopaque, *VkBuffer) callconv(.c) VkResult,
    vkDestroyBuffer: *const fn (VkDevice, VkBuffer, ?*const anyopaque) callconv(.c) void,
    vkGetBufferMemoryRequirements: *const fn (VkDevice, VkBuffer, *VkMemoryRequirements) callconv(.c) void,
    vkAllocateMemory: *const fn (VkDevice, *const VkMemoryAllocateInfo, ?*const anyopaque, *VkDeviceMemory) callconv(.c) VkResult,
    vkFreeMemory: *const fn (VkDevice, VkDeviceMemory, ?*const anyopaque) callconv(.c) void,
    vkBindBufferMemory: *const fn (VkDevice, VkBuffer, VkDeviceMemory, VkDeviceSize) callconv(.c) VkResult,
    vkMapMemory: *const fn (VkDevice, VkDeviceMemory, VkDeviceSize, VkDeviceSize, u32, *?*anyopaque) callconv(.c) VkResult,
    vkUnmapMemory: *const fn (VkDevice, VkDeviceMemory) callconv(.c) void,
    vkCreateImage: *const fn (VkDevice, *const VkImageCreateInfo, ?*const anyopaque, *VkImage) callconv(.c) VkResult,
    vkDestroyImage: *const fn (VkDevice, VkImage, ?*const anyopaque) callconv(.c) void,
    vkGetImageMemoryRequirements: *const fn (VkDevice, VkImage, *VkMemoryRequirements) callconv(.c) void,
    vkBindImageMemory: *const fn (VkDevice, VkImage, VkDeviceMemory, VkDeviceSize) callconv(.c) VkResult,
    vkCreateSampler: *const fn (VkDevice, *const VkSamplerCreateInfo, ?*const anyopaque, *VkSampler) callconv(.c) VkResult,
    vkDestroySampler: *const fn (VkDevice, VkSampler, ?*const anyopaque) callconv(.c) void,
    vkResetCommandPool: *const fn (VkDevice, VkCommandPool, u32) callconv(.c) VkResult,
};

/// SDL3 window handle (opaque pointer)
pub const SDL_Window = opaque {};
/// SDL3 bool type
pub const SDL_bool = bool;
