# handheld/meson.build — builds mcpe executables from src/ libraries

# ---- Dependencies ----

# OpenAL headers are needed by common sources (SoundEngine.h is included
# unconditionally from CreatorMode.cpp etc.)
openal_dep = dependency('openal')
dedicated_deps = [openal_dep]

client_deps = []
client_cpp_args = []

if build_client
    sdl3_dep = dependency('sdl3')
    libpng_dep = dependency('libpng')

    client_deps += [sdl3_dep, openal_dep, libpng_dep]

    gles_dep = dependency('glesv1_cm')
    client_deps += gles_dep

    if host_machine.system() == 'darwin'
        foundation_dep = dependency('appleframeworks', modules: ['Foundation'])
        client_deps += foundation_dep
    endif

    client_cpp_args += [
        '-DSDL3',
        '-DOPENGL_ES',
        '-DGL_GLES_PROTOTYPES=1',
        '-DGL_GLEXT_PROTOTYPES=1',
        '-DMCPE_INSTALL_DATA_DIR="@0@/share/mcpe"'.format(get_option('prefix')),
    ]
endif

# ---- Source collection ----

subdir('src')

# ---- Dedicated server ----

mcpe_dedicated = executable(
    'mcpe_dedicated',
    'src/main_dedicated.cpp',
    core_sources,
    include_directories: common_include,
    cpp_args: ['-DSTANDALONE_SERVER'],
    dependencies: dedicated_deps,
    install: true,
)

# ---- Client ----

if build_client
    mcpe_sdl3 = executable(
        'mcpe_sdl3',
        'src/main.cpp',
        core_sources,
        client_extra_sources,
        include_directories: common_include,
        cpp_args: client_cpp_args,
        dependencies: client_deps,
        install: true,
    )
endif

# ---- Install data directory ----

install_subdir(
    meson.project_source_root() / 'data',
    install_dir: get_option('datadir') / 'mcpe',
    strip_directory: true,
)
