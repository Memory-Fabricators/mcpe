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

class MinecraftApp : public Minecraft {
public:
#ifndef STANDALONE_SERVER
  MinecraftApp(SDL_Window *window);
#else
  MinecraftApp();
#endif

  ~MinecraftApp();

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
#ifndef STANDALONE_SERVER
  SDL_Window *_window;
#endif

  bool _verbose;
  int _frames;
  int _lastTickMs;

  static bool _hasInitedStatics;
};

#endif // NINECRAFTAPP_H__
