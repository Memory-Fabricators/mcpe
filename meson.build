project(
    'mcpe',
    ['c', 'cpp', 'objcpp'],
    version: '0.1.0',
    default_options: [
        'cpp_std=c++23',
        'buildtype=debugoptimized',
        'warning_level=3',
        'default_library=static',
    ],
    meson_version: '>=1.9.0',
)

build_client = get_option('build_client')

common_include = include_directories('handheld/src')

subdir('handheld')