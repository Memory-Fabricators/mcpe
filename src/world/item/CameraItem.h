#ifndef NET_MINECRAFT_WORLD_ITEM__CameraItem_H__
#define NET_MINECRAFT_WORLD_ITEM__CameraItem_H__

#include "../entity/item/TripodCamera.h"
#include "../entity/player/Player.h"
#include "../level/Level.h"
#include "Item.h"
#include "ItemInstance.h"

class CameraItem : public Item {
  typedef Item super;

public:
  CameraItem(int id) : super(id) {}

  ItemInstance *use(ItemInstance *itemInstance, Level *level, Player *player) {
    level->addEntity(
        new TripodCamera(level, player, player->x, player->y, player->z));
    return itemInstance;
  }
};

#endif /*NET_MINECRAFT_WORLD_ITEM__CameraItem_H__*/
