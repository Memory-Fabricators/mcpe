#ifndef NET_MINECRAFT_LUA_PLUGIN__LuaEntity_H__
#define NET_MINECRAFT_LUA_PLUGIN__LuaEntity_H__

#include "../world/entity/Entity.h"
#include "LuaPluginManager.h"

class CompoundTag;
class Player;

class LuaEntity : public Entity {
  typedef Entity super;
public:
  LuaEntity(Level *level, const LuaEntityType *type);
  virtual ~LuaEntity();

  virtual void tick() override;
  virtual void remove() override;
  virtual bool interact(Player *player) override;
  virtual bool hurt(Entity *source, int damage) override;
  virtual bool save(CompoundTag *entityTag) override;
  virtual bool load(CompoundTag *entityTag) override;
  virtual void reset() override;

  virtual int getEntityTypeId() const override { return _typeId; }
  virtual EntityRendererId queryEntityRenderer() override;

  bool pushTable();
  const LuaEntityType *getLuaType() const { return _type; }

private:
  void readAdditionalSaveData(CompoundTag *tag) override {}
  void addAdditonalSaveData(CompoundTag *tag) override {}

  const LuaEntityType *_type;
  int _typeId;
  int _tableRef;
};

#endif
