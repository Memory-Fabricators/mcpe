#ifndef NINECRAFTAPP_H__
#define NINECRAFTAPP_H__

#include "App.h"
#include "client/Minecraft.h"
#include "world/Pos.h"
#include "world/level/storage/MemoryLevelStorage.h"
#include <string>

class Level;
class LocalPlayer;
class ExternalFileLevelStorageSource;

class NinecraftApp : public Minecraft {
public:
  NinecraftApp(SDL_Window *window);
  ~NinecraftApp();

  void init();
  void teardown();

  void update();

  virtual bool handleBack(bool isDown);

protected:
  void onGraphicsReset();

private:
  void initGLStates();
  void restartServer();

  void updateStats();

  // void writeDemoFile();
  // bool hasPlayedDemo();

#ifndef ANDROID_PUBLISH
  void testCreationAndDestruction();
  void testJoiningAndDestruction();
#endif /*ANDROID_PUBLISH*/
  SDL_Window *_window;

  bool _verbose;
  int _frames;
  int _lastTickMs;

  static bool _hasInitedStatics;
};

#endif // NINECRAFTAPP_H__
