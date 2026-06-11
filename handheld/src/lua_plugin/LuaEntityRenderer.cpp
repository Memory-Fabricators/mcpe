#include "LuaEntityRenderer.h"
#include "LuaEntity.h"
#include "LuaPluginManager.h"
#include "../platform/log.h"
#include "../world/entity/Mob.h"
#include "../client/renderer/Tesselator.h"
#include "../client/renderer/gles.h"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

LuaEntityRenderer::LuaEntityRenderer() : _type(nullptr) {}

LuaEntityRenderer::~LuaEntityRenderer() {}

void LuaEntityRenderer::setRendererType(const LuaRendererType *type) {
  _type = type;
}

void LuaEntityRenderer::render(Entity *entity, float x, float y, float z,
                                float rot, float a) {
  if (!_type || _type->renderRef == LUA_NOREF) return;

  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L) return;

  bool hasTable = mgr.pushEntityTable(entity);

  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->renderRef);

  if (hasTable) {
    lua_pushvalue(L, -2);
    lua_pushnumber(L, x);
    lua_pushnumber(L, y);
    lua_pushnumber(L, z);
    lua_pushnumber(L, rot);
    lua_pushnumber(L, a);

    if (lua_pcall(L, 6, 0, 0) != 0) {
      LOGE("Lua renderer '%s' error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
  } else {
    lua_pushnil(L);
    lua_pushlightuserdata(L, entity);
    lua_pushnumber(L, x);
    lua_pushnumber(L, y);
    lua_pushnumber(L, z);
    lua_pushnumber(L, rot);
    lua_pushnumber(L, a);

    if (lua_pcall(L, 7, 0, 0) != 0) {
      LOGE("Lua renderer '%s' error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
      lua_pop(L, 1);
    }
  }
}

void LuaEntityRenderer::onGraphicsReset() {
  if (!_type || _type->onGraphicsResetRef == LUA_NOREF) return;

  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L) return;

  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onGraphicsResetRef);
  if (lua_pcall(L, 0, 0, 0) != 0) {
    LOGE("Lua renderer '%s' onGraphicsReset error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
  }
}
