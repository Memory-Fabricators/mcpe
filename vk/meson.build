# vk/meson.build — MCPE Vulkan renderer (included via subdir())

ash_dep = dependency('ash', fallback: ['ash', 'ash_dep'])
glam_dep = dependency('glam', fallback: ['glam', 'glam_dep'])

vk_lib = static_library(
  'mcpe_vk',
  'src/lib.rs',
  dependencies: [ash_dep, glam_dep],
  rust_abi: 'c',
)

vk_dep = declare_dependency(
  link_with: vk_lib,
  include_directories: include_directories('include'),
)
