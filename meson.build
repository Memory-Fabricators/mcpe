project(
    'mcpe',
    ['c', 'cpp', 'rust'],
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

lua_dep = dependency('lua')

build_client = get_option('build_client')

common_include = include_directories('handheld/src')

subdir('vk')

subdir('handheld')
