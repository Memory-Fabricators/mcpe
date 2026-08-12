project(
    'mcpe',
    ['c', 'cpp', 'objcpp'],
    version: '0.1.0',
    default_options: [
        'cpp_std=c++23',
        'rust_std=2024',
        'buildtype=debugoptimized',
        'warning_level=3',
        'default_library=static',
    ],
    meson_version: '>=1.9.0',
)

build_client = get_option('build_client')
build_server = get_option('build_server')
build_web = get_option('web')

if build_web and host_machine.system() != 'emscripten'
    error(
        'The web option requires an Emscripten cross file (see docs/emscripten.md).',
    )
endif

common_include = include_directories('handheld/src')

subdir('handheld')
