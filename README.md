# MCPE 0.6.1 Alpha (but better)

## Changes

- Fixed multiplayer
- Added a direct connect option
- Ported to SDL3
- Migrated to the Meson build system
- Added a username field

## Building from Source

You will need Meson (>=1.12), Ninja and a GLESv1 translation layer (or native device support).
You can install my Zig 0.17-based libANGLE replacement at `https://github.com/tinted-software/angle_zig` for the easiest route.

```bash
meson setup build
meson compile -C build
# Start the server
./build/mcpe_dedicated
# Start the client
./build/mcpe_sdl3
```

## HTML/Wasm (Emscripten)

See [docs/emscripten.md](docs/emscripten.md) for the Meson-only web build.
