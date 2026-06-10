raknet_legacy = get_option('raknet_legacy_protocol')
_rust_args = raknet_legacy ? ['--cfg', 'feature="legacy_protocol"'] : []

raknet_sys_lib = static_library(
    'raknet_sys',
    '../raknet-sys/src/lib.rs',
    rust_abi: 'c',
    rust_args: _rust_args,
    override_options: ['rust_std=2021'],
)

cbindgen = find_program('cbindgen', required: true)
raknet_headers = custom_target(
    'raknet_headers',
    input: '../raknet-sys/src/lib.rs',
    output: 'raknet_headers.h',
    command: [cbindgen, '--lang', 'c++', '-o', '@OUTPUT@', '@INPUT@'],
)

raknet_cpp_lib = static_library(
    'raknet_cpp',
    ['RakPeerRust.cpp', raknet_headers],
    include_directories: common_include,
    cpp_pch: 'pch/raknet_pch.h',
)

raknet_dep = declare_dependency(
    link_with: [raknet_sys_lib, raknet_cpp_lib],
    include_directories: common_include,
)