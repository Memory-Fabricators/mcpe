# MCPE 0.6.1 Alpha (but better)

## Changes

- Fixed multiplayer
- Added a direct connect option
- Ported to SDL3
- Added the CMake build system
- Added a username field

## Developing With Nix

```bash
nix develop
meson setup build
# Start the server
./build/mcpe_dedicated
# Start the client
./build/mcpe_sdl3
```
