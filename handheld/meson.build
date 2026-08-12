# handheld/meson.build — builds mcpe executables from src/ libraries

# ---- Dependencies ----

# The native build uses system/wrap dependencies. Emscripten supplies SDL3,
# libpng, OpenAL and GLES headers through its sysroot and ports instead.
dedicated_deps = []
client_deps = []
client_cpp_args = []
client_link_args = []

if build_web
    client_cpp_args += [
        '-pthread',
        '-DSDL3',
        '-DOPENGL_ES',
        '-DGL_GLES_PROTOTYPES=1',
        '-DGL_GLEXT_PROTOTYPES=1',
        '-DMCPE_WEB',
        '-DMCPE_INSTALL_DATA_DIR="/data"',
    ]
    client_link_args += [
        '--use-port=sdl3',
        '--use-port=libpng',
        '-sLEGACY_GL_EMULATION',
        '-sGL_UNSAFE_OPTS=0',
        '-pthread',
        '-sPTHREAD_POOL_SIZE=2',
        '-sPROXY_TO_PTHREAD',
        '-sOFFSCREENCANVAS_SUPPORT=1',
        '-sOFFSCREENCANVASES_TO_PTHREAD=#canvas',
        '-sALLOW_MEMORY_GROWTH=1',
        '-sFORCE_FILESYSTEM=1',
        '--preload-file',
        meson.project_source_root() / 'data@/data',
    ]
else
    # OpenAL headers are included by shared gameplay sources.
    openal_dep = dependency('openal')
    dedicated_deps += openal_dep

    if build_client
        sdl3_dep = dependency('sdl3')
        libpng_dep = dependency('libpng')
        gles_dep = dependency('glesv1_cm')
        client_deps += [sdl3_dep, openal_dep, libpng_dep, gles_dep]

        if host_machine.system() == 'darwin'
            client_deps += dependency('appleframeworks', modules: ['Foundation'])
        endif

        client_cpp_args += [
            '-DSDL3',
            '-DOPENGL_ES',
            '-DGL_GLES_PROTOTYPES=1',
            '-DGL_GLEXT_PROTOTYPES=1',
            '-DMCPE_INSTALL_DATA_DIR="@0@/share/mcpe"'.format(
                get_option('prefix'),
            ),
        ]
    endif
endif

# ---- Source collection ----

subdir('src')

# ---- Dedicated server ----
if build_server and not build_web
    mcpe_dedicated = executable(
        'mcpe_dedicated',
        'src/main_dedicated.cpp',
        core_sources,
        include_directories: common_include,
        cpp_args: ['-DSTANDALONE_SERVER'],
        dependencies: dedicated_deps,
        install: true,
    )
endif

# ---- Client ----

if build_web
    configure_file(
        input: meson.project_source_root() / 'web' / 'index.html',
        output: 'index.html',
        copy: true,
    )
endif

if build_client
    mcpe_sdl3 = executable(
        'mcpe_sdl3',
        'src/main.cpp',
        core_sources,
        client_extra_sources,
        include_directories: common_include,
        cpp_args: client_cpp_args,
        dependencies: client_deps,
        link_args: client_link_args,
        install: true,
    )
endif

# ---- Install data directory ----
if not build_web
    install_subdir(
        meson.project_source_root() / 'data',
        install_dir: get_option('datadir') / 'mcpe',
        strip_directory: true,
    )
endif
