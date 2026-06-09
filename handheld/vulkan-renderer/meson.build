# handheld/vulkan-renderer/meson.build
# Build the Vulkan renderer Rust library using ash for Vulkan bindings.

# ---- Find tools ----

cbindgen = find_program('cbindgen', required: true)

# ---- Dependencies ----

ash_dep = dependency('ash-0-rs')

vulkan_dep = dependency('vulkan')

# ---- Build the Rust static library ----

vulkan_sources = files(
    'src/lib.rs',
)

vulkan_lib = static_library('vulkan_renderer',
    sources: vulkan_sources,
    rust_abi: 'c',
    dependencies: [ash_dep],
    install: true,
)

# ---- Generate C header via cbindgen (at configure time) ----

header_out = meson.current_source_dir() / '..' / 'src' / 'client' / 'renderer' / 'vulkan_renderer.h'

run_command(
    cbindgen,
    '--lang', 'c',
    '--crate', 'vulkan_renderer',
    '--output', header_out,
    # '--config', meson.current_source_dir() / 'cbindgen.toml',
    meson.current_source_dir() / 'src/lib.rs',
    check: true,
)

message('Generated C header: ' + header_out)

# ---- Expose to parent build ----

vulkan_header_inc = include_directories('.')
vulkan_lib = [vulkan_lib]
