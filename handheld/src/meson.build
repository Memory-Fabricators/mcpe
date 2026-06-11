# handheld/src/meson.build — source collection from subdirectories

# ---- Collect sources from subdirs ----

raknet_sources = []
subdir('raknet')

world_sources = []
subdir('world')

# lua_plugin_sources = []
# lua_plugin_client_sources = []
# subdir('lua_plugin')

client_common_sources = []
client_only_sources = []
if build_client
    subdir('client')
endif

# ---- Top-level src/ files (common to both targets) ----

src_root_sources = files(
    'MinecraftApp.cpp',
    'Performance.cpp',
    'SharedConstants.cpp',
)

# ---- Small leaf domains (common to both targets) ----

locale_sources = files(
    'locale/I18n.cpp',
)

nbt_sources = files(
    'nbt/Tag.cpp',
)

network_common_sources = files(
    'network/NATPunchHandler.cpp',
    'network/NetEventCallback.cpp',
    'network/PHPDirectoryServer2.cpp',
    'network/Packet.cpp',
    'network/RakNetInstance.cpp',
    'network/ServerSideNetworkHandler.cpp',
    'network/command/CommandServer.cpp',
)

network_client_sources = []
if build_client
    network_client_sources += files(
        'network/ClientSideNetworkHandler.cpp',
    )
endif

platform_common_sources = files(
    'platform/time.cpp',
    'platform/input/Mouse.cpp',
)

platform_client_sources = []
if build_client
    platform_client_sources += files(
        'platform/audio/SoundSystemAL.cpp',
        'platform/input/Controller.cpp',
        'platform/input/Keyboard.cpp',
        'platform/input/Multitouch.cpp',
    )
endif

server_sources = files(
    'server/ArgumentsSettings.cpp',
    'server/CreatorLevel.cpp',
    'server/ServerLevel.cpp',
    'server/ServerPlayer.cpp',
)

util_common_sources = files(
    'util/DataIO.cpp',
    'util/Mth.cpp',
    'util/PerfTimer.cpp',
    'util/StringUtils.cpp',
)

util_client_sources = []
if build_client
    util_client_sources += files(
        'util/PerfRenderer.cpp',
    )
    if host_machine.system() == 'darwin'
        util_client_sources += files(
            'world/level/storage/MoveFolder.mm',
        )
    endif
endif

# ---- Assembled source lists for each target ----

# Core sources shared by both dedicated server and client
core_sources = (
    src_root_sources + locale_sources + nbt_sources + network_common_sources + platform_common_sources + raknet_sources + server_sources + util_common_sources + world_sources + client_common_sources
)

# Client-only source additions
if build_client
    client_extra_sources = (
        client_only_sources + network_client_sources + platform_client_sources + util_client_sources
    )
endif
