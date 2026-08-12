# HTML/Wasm build (Emscripten)

The web client uses Emscripten's GLES 1 compatibility layer (`-sLEGACY_GL_EMULATION`) over WebGL. It does **not** build or use gl4es, and it does not use CMake.

```sh
source ~/emsdk/emsdk_env.sh
meson setup build-web --cross-file cross/emscripten.ini \
  -Dweb=true -Dbuild_server=false --buildtype=release
meson compile -C build-web
```

The output is `build-web/handheld/index.html`, with `mcpe_sdl3.js`, `mcpe_sdl3.wasm`, its pthread worker script, and the preloaded `mcpe_sdl3.data` beside it. This is a pthread build so level generation remains asynchronous. It requires cross-origin isolation (`COOP` and `COEP`) for `SharedArrayBuffer`; do **not** use `python3 -m http.server`.

```sh
python3 web/server.py --directory build-web/handheld --port 8080
```

Open `http://localhost:8080/`. Verify `crossOriginIsolated` is `true` in DevTools. Deployment must send `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` on every response.

The link flags enable SDL3 and libpng from Emscripten ports, preload `data` at `/data`, use the built-in OpenAL/Web Audio implementation, enable GLES 1 fixed-function emulation, disable its unsafe optimizations, and run the game loop in Emscripten's primary pthread with its canvas transferred as an `OffscreenCanvas`. This keeps the browser UI thread responsive while levels generate. The build has a two-worker pool and allows Wasm memory growth.
