#ifndef NET_MINECRAFT_CLIENT_GUI_SCREENS__ChooseLevelScreen_H__
#define NET_MINECRAFT_CLIENT_GUI_SCREENS__ChooseLevelScreen_H__

#include "../../../world/level/storage/LevelStorageSource.h"
#include "../Screen.h"

class ChooseLevelScreen : public Screen {
public:
  void init();

protected:
  std::string getUniqueLevelName(const std::string &level);

private:
  void loadLevelSource();

  LevelSummaryList levels;
};

#endif /*NET_MINECRAFT_CLIENT_GUI_SCREENS__ChooseLevelScreen_H__*/
