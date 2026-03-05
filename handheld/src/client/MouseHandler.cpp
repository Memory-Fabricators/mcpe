#include "MouseHandler.h"
#include "player/input/ITurnInput.h"
#include <iostream>

#ifdef SDL3
#include <SDL3/SDL.h>
#endif

MouseHandler::MouseHandler(ITurnInput *turnInput)
    : _turnInput(turnInput), _window(nullptr) {}

void MouseHandler::setWindow(SDL_Window *window) { _window = window; }

MouseHandler::MouseHandler() : _turnInput(0), _window(nullptr) {}

MouseHandler::~MouseHandler() {}

void MouseHandler::setTurnInput(ITurnInput *turnInput) {
  _turnInput = turnInput;
}

void MouseHandler::grab() {
  xd = 0;
  yd = 0;

#if defined(SDL3)
  if (_window == nullptr)
    return;

  if (!SDL_SetWindowRelativeMouseMode(_window, true)) {
    const char *err = SDL_GetError();
    if (err && *err) {
      std::cout << "Relative mode enable failed: " << err << '\n';
    }
  }

  if (!SDL_SetWindowMouseGrab(_window, true)) {
    const char *err = SDL_GetError();
    if (err && *err) {
      std::cout << "Grab failed: " << err << '\n';
    }
  }

  SDL_HideCursor();
  SDL_CaptureMouse(true);
#endif
}

void MouseHandler::release() {
#if defined(SDL3)
  if (_window == nullptr)
    return;

  if (!SDL_SetWindowRelativeMouseMode(_window, false)) {
    const char *err = SDL_GetError();
    if (err && *err) {
      std::cout << "Relative mode disable failed: " << err << '\n';
    }
  }

  if (!SDL_SetWindowMouseGrab(_window, false)) {
    const char *err = SDL_GetError();
    if (err && *err) {
      std::cout << "Release failed: " << err << '\n';
    }
  }

  SDL_ShowCursor();
  SDL_CaptureMouse(false);
#endif
}

void MouseHandler::poll() {
  if (_turnInput != 0) {
    TurnDelta td = _turnInput->getTurnDelta();
    xd = td.x;
    yd = td.y;
  }
}
