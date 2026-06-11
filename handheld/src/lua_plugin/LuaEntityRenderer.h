#ifndef NET_MINECRAFT_LUA_PLUGIN__LuaEntityRenderer_H__
#define NET_MINECRAFT_LUA_PLUGIN__LuaEntityRenderer_H__

#include "../client/renderer/entity/EntityRenderer.h"
#include <string>

class LuaEntity;
struct LuaRendererType;

class LuaEntityRenderer : public EntityRenderer {
public:
  LuaEntityRenderer();
  virtual ~LuaEntityRenderer();

  void setRendererType(const LuaRendererType *type);

  virtual void render(Entity *entity, float x, float y, float z, float rot,
                      float a) override;
  virtual void onGraphicsReset() override;

private:
  const LuaRendererType *_type;
};

#endif
