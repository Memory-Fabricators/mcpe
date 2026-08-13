# HTML/Wasm build (Emscripten)

The web client uses Emscripten's GLES 1 compatibility layer (`-sLEGACY_GL_EMULATION`) over WebGL. It does **not** build or use gl4es.

```sh
source ~/emsdk/emsdk_env.sh
bazel build --config=web //:web
```

Bazel writes `index.html`, `mcpe_sdl3.js`, `mcpe_sdl3.wasm`, the pthread worker script, and preloaded `mcpe_sdl3.data` to `bazel-bin/`. This is a pthread build so level generation remains asynchronous. It requires cross-origin isolation (`COOP` and `COEP`) for `SharedArrayBuffer`; do **not** use `python3 -m http.server`.

```sh
python3 web/server.py --directory bazel-bin --port 8080
```

Open `http://localhost:8080/`. Verify `crossOriginIsolated` is `true` in DevTools. Deployment must send `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` on every response.

The link flags enable SDL3 and libpng from Emscripten ports, preload `data` at `/data`, use the built-in OpenAL/Web Audio implementation, enable GLES 1 fixed-function emulation, disable its unsafe optimizations, and run the game loop in Emscripten's primary pthread with its canvas transferred as an `OffscreenCanvas`. This keeps the browser UI thread responsive while levels generate. The build has a two-worker pool and allows Wasm memory growth.
