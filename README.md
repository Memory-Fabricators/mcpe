# MCPE 0.6.1 Alpha (but better)

## Changes

- Fixed multiplayer
- Added a direct connect option
- Ported to SDL3
- Added the CMake build system
- Added a userame field

## Developing With Nix

```bash
nix develop
bazel build //:mcpe_dedicated //:mcpe_sdl3
# Start the server
bazel run //:mcpe_dedicated
# Start the client
bazel run //:mcpe_sdl3
```

Use `bazel build --config=release //:mcpe_sdl3` for an optimized build. Native builds require SDL3, OpenAL Soft, libpng, and GLES 1 development libraries. Set `--define=gl4es=true` to link against gl4es instead of GLES 1.

## HTML/Wasm (Emscripten)

See [docs/emscripten.md](docs/emscripten.md) for the Bazel web build.