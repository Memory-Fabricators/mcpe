#ifndef APP_H__
#define APP_H__

// #ifdef STANDALONE_SERVER
// #define NO_EGL
// #endif

#include "AppPlatform.h"
#include "platform/log.h"
#ifndef STANDALONE_SERVER
#include <SDL3/SDL.h>
#include <SDL3/SDL_opengles.h>
#endif

typedef struct AppContext {
#ifndef STANDALONE_SERVER
  SDL_Window *window;
  SDL_GLContext context;
  bool doRender;
#endif
  AppPlatform *platform;
} AppContext;

class App {
public:
  App() : _finished(false), _inited(false) { _context.platform = 0; }
  virtual ~App() {}

  void init(AppContext &c) {
    _context = c;
    init();
    _inited = true;
  }
  bool isInited() { return _inited; }

  virtual AppPlatform *platform() { return _context.platform; }

  void onGraphicsReset(AppContext &c) {
    _context = c;
    onGraphicsReset();
  }

  virtual void audioEngineOn() {}
  virtual void audioEngineOff() {}

  virtual void destroy() {}

  virtual void loadState(void *state, int stateSize) {}
  virtual bool saveState(void **state, int *stateSize) { return false; }

  void swapBuffers() {
#ifndef STANDALONE_SERVER
    if (_context.doRender)
      SDL_GL_SwapWindow(_context.window);
#endif
  }

  virtual void draw() {}
  virtual void update() {}; // = 0;
  virtual void setSize(int width, int height) {}

  virtual void quit() { _finished = true; }
  virtual bool wantToQuit() { return _finished; }
  virtual bool handleBack(bool isDown) { return false; }

protected:
  virtual void init() {}
  // virtual void onGraphicsLost() = 0;
  virtual void onGraphicsReset() = 0;

private:
  bool _inited;
  bool _finished;
  AppContext _context;
};

#endif // APP_H__
