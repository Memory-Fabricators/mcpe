#ifndef NET_MINECRAFT_CLIENT__MouseHandler_H__
#define NET_MINECRAFT_CLIENT__MouseHandler_H__

// package net.minecraft.client;

#include "App.h"

class ITurnInput;

class MouseHandler {
public:
  MouseHandler(ITurnInput *turnInput);
  void setWindow(SDL_Window *ctx);
  MouseHandler();
  ~MouseHandler();

  void setTurnInput(ITurnInput *turnInput);

  void grab();
  void release();

  void poll();

  float xd, yd;

private:
  int toSkip;
  SDL_Window *_window;
  ITurnInput *_turnInput;
};

#endif /*NET_MINECRAFT_CLIENT__MouseHandler_H__*/
