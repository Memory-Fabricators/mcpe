#include "LuaEntity.h"
#include "LuaPluginManager.h"
#include "../nbt/CompoundTag.h"
#include "../platform/log.h"
#include "../world/entity/EntityRendererId.h"
#include "../world/entity/player/Player.h"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

// ---- Entity metatable setup ----

static LuaEntity *checkLuaEntity(lua_State *L, int idx) {
  lua_getfield(L, idx, "_ptr");
  auto *ptr = (LuaEntity *)lua_touserdata(L, -1);
  lua_pop(L, 1);
  return ptr;
}

static void l_pushCFunc(lua_State *L, const char *name, lua_CFunction fn) {
  lua_pushcfunction(L, fn);
  lua_setfield(L, -2, name);
}

// Forward declare the entity instance methods (defined in LuaPluginManager.cpp
// and re-declared here as extern — they're in the same translation unit context
// via LuaPluginManager.cpp's statics, but we need our own copies for this TU)
static int l_entity_getPos(lua_State *L);
static int l_entity_setPos(lua_State *L);
static int l_entity_getRotation(lua_State *L);
static int l_entity_setRotation(lua_State *L);
static int l_entity_getMotion(lua_State *L);
static int l_entity_setMotion(lua_State *L);
static int l_entity_getAlive(lua_State *L);
static int l_entity_remove(lua_State *L);
static int l_entity_getTypeId(lua_State *L);
static int l_entity_getEntityId(lua_State *L);
static int l_entity_getWidth(lua_State *L);
static int l_entity_getHeight(lua_State *L);
static int l_entity_setOnFire(lua_State *L);
static int l_entity_getOnFire(lua_State *L);
static int l_entity_getOnGround(lua_State *L);
static int l_entity_getTicks(lua_State *L);

static void ensureEntityMetaTable(lua_State *L) {
  lua_getfield(L, LUA_REGISTRYINDEX, "LuaEntity_meta");
  if (lua_istable(L, -1)) {
    lua_pop(L, 1);
    return;
  }
  lua_pop(L, 1);

  lua_newtable(L);

  lua_newtable(L);
  l_pushCFunc(L, "getPos",       l_entity_getPos);
  l_pushCFunc(L, "setPos",       l_entity_setPos);
  l_pushCFunc(L, "getRotation",  l_entity_getRotation);
  l_pushCFunc(L, "setRotation",  l_entity_setRotation);
  l_pushCFunc(L, "getMotion",    l_entity_getMotion);
  l_pushCFunc(L, "setMotion",    l_entity_setMotion);
  l_pushCFunc(L, "isAlive",      l_entity_getAlive);
  l_pushCFunc(L, "remove",       l_entity_remove);
  l_pushCFunc(L, "getTypeId",    l_entity_getTypeId);
  l_pushCFunc(L, "getEntityId",  l_entity_getEntityId);
  l_pushCFunc(L, "getWidth",     l_entity_getWidth);
  l_pushCFunc(L, "getHeight",    l_entity_getHeight);
  l_pushCFunc(L, "setOnFire",    l_entity_setOnFire);
  l_pushCFunc(L, "getOnFire",    l_entity_getOnFire);
  l_pushCFunc(L, "isOnGround",   l_entity_getOnGround);
  l_pushCFunc(L, "getTicks",     l_entity_getTicks);
  lua_setfield(L, -2, "__index");

  lua_pushcfunction(L, [](lua_State *L2) -> int {
    lua_getfield(L2, 1, "_ptr");
    lua_pop(L2, 1);
    return 0;
  });
  lua_setfield(L, -2, "__gc");

  lua_setfield(L, LUA_REGISTRYINDEX, "LuaEntity_meta");
}

// ---- Entity instance methods ----

static int l_entity_getPos(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (!e) return 0;
  lua_pushnumber(L, e->x); lua_pushnumber(L, e->y); lua_pushnumber(L, e->z);
  return 3;
}

static int l_entity_setPos(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (!e) return 0;
  e->setPos((float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4));
  return 0;
}

static int l_entity_getRotation(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (!e) return 0;
  lua_pushnumber(L, e->yRot); lua_pushnumber(L, e->xRot);
  return 2;
}

static int l_entity_setRotation(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (!e) return 0;
  e->yRot = e->yRotO = (float)luaL_checknumber(L, 2);
  e->xRot = e->xRotO = (float)luaL_checknumber(L, 3);
  return 0;
}

static int l_entity_getMotion(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (!e) return 0;
  lua_pushnumber(L, e->xd); lua_pushnumber(L, e->yd); lua_pushnumber(L, e->zd);
  return 3;
}

static int l_entity_setMotion(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (!e) return 0;
  e->xd = (float)luaL_checknumber(L, 2);
  e->yd = (float)luaL_checknumber(L, 3);
  e->zd = (float)luaL_checknumber(L, 4);
  return 0;
}

static int l_entity_getAlive(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushboolean(L, e ? e->isAlive() : 0);
  return 1;
}

static int l_entity_remove(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (e) e->remove();
  return 0;
}

static int l_entity_getTypeId(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushinteger(L, e ? e->getEntityTypeId() : -1);
  return 1;
}

static int l_entity_getEntityId(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushinteger(L, e ? e->entityId : -1);
  return 1;
}

static int l_entity_getWidth(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushnumber(L, e ? e->bbWidth : 0.0);
  return 1;
}

static int l_entity_getHeight(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushnumber(L, e ? e->bbHeight : 0.0);
  return 1;
}

static int l_entity_setOnFire(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  if (e) e->onFire = (int)luaL_checkinteger(L, 2);
  return 0;
}

static int l_entity_getOnFire(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushinteger(L, e ? e->onFire : 0);
  return 1;
}

static int l_entity_getOnGround(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushboolean(L, e ? e->onGround : 0);
  return 1;
}

static int l_entity_getTicks(lua_State *L) {
  auto *e = checkLuaEntity(L, 1);
  lua_pushinteger(L, e ? e->tickCount : 0);
  return 1;
}

// ---- LuaEntity ----

LuaEntity::LuaEntity(Level *level, const LuaEntityType *type)
  : Entity(level), _type(type), _typeId(type->typeId), _tableRef(LUA_NOREF)
{
  setSize(type->width, type->height);
  entityRendererId = ER_LUA_CUSTOM_RENDERER;
}

LuaEntity::~LuaEntity() {
  if (_tableRef != LUA_NOREF) {
    auto &mgr = LuaPluginManager::instance();
    lua_State *L = mgr.getLuaState();
    if (L) {
      lua_rawgeti(L, LUA_REGISTRYINDEX, _tableRef);
      if (lua_istable(L, -1)) {
        lua_pushnil(L);
        lua_setfield(L, -2, "_ptr");
      }
      lua_pop(L, 1);
      luaL_unref(L, LUA_REGISTRYINDEX, _tableRef);
    }
    _tableRef = LUA_NOREF;
  }
}

bool LuaEntity::pushTable() {
  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L || !_type) return false;

  if (_tableRef == LUA_NOREF) {
    ensureEntityMetaTable(L);

    lua_newtable(L);
    lua_getfield(L, LUA_REGISTRYINDEX, "LuaEntity_meta");
    lua_setmetatable(L, -2);

    lua_pushlightuserdata(L, this);
    lua_setfield(L, -2, "_ptr");

    lua_pushstring(L, _type->name.c_str());
    lua_setfield(L, -2, "typeName");

    lua_pushinteger(L, _typeId);
    lua_setfield(L, -2, "typeId");

    _tableRef = luaL_ref(L, LUA_REGISTRYINDEX);
  }

  lua_rawgeti(L, LUA_REGISTRYINDEX, _tableRef);
  return true;
}

void LuaEntity::tick() {
  super::tick();

  if (!_type) return;
  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L || _type->onTickRef == LUA_NOREF) return;

  if (!pushTable()) return;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onTickRef);
  lua_pushvalue(L, -2);
  if (lua_pcall(L, 1, 0, 0) != 0) {
    LOGE("Lua entity '%s' onTick error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
}

void LuaEntity::remove() {
  super::remove();

  if (!_type) return;
  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L || _type->onRemoveRef == LUA_NOREF) return;

  if (!pushTable()) return;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onRemoveRef);
  lua_pushvalue(L, -2);
  if (lua_pcall(L, 1, 0, 0) != 0) {
    LOGE("Lua entity '%s' onRemove error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
}

void LuaEntity::reset() {
  super::reset();

  if (!_type) return;
  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L || _type->onInitRef == LUA_NOREF) return;

  if (!pushTable()) return;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onInitRef);
  lua_pushvalue(L, -2);
  if (lua_pcall(L, 1, 0, 0) != 0) {
    LOGE("Lua entity '%s' onInit error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
}

bool LuaEntity::interact(Player *player) {
  if (!_type || _type->onInteractRef == LUA_NOREF) return false;

  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L) return false;

  if (!pushTable()) return false;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onInteractRef);
  lua_pushvalue(L, -2);
  lua_pushlightuserdata(L, player);
  lua_pushstring(L, "Player");

  if (lua_pcall(L, 3, 1, 0) != 0) {
    LOGE("Lua entity '%s' onInteract error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
    lua_pop(L, 1);
    return false;
  }
  bool result = lua_toboolean(L, -1);
  lua_pop(L, 2);
  return result;
}

bool LuaEntity::hurt(Entity *source, int damage) {
  markHurt();
  if (!_type || _type->onHurtRef == LUA_NOREF) return false;

  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();
  if (!L) return false;

  if (!pushTable()) return false;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onHurtRef);
  lua_pushvalue(L, -2);
  lua_pushlightuserdata(L, source);
  lua_pushinteger(L, damage);

  if (lua_pcall(L, 3, 1, 0) != 0) {
    LOGE("Lua entity '%s' onHurt error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
    lua_pop(L, 1);
    return false;
  }
  bool result = lua_toboolean(L, -1);
  lua_pop(L, 2);
  return result;
}

bool LuaEntity::save(CompoundTag *entityTag) {
  if (!_type) return super::save(entityTag);

  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();

  if (L && _type->onSaveRef != LUA_NOREF) {
    if (pushTable()) {
      lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onSaveRef);
      lua_pushvalue(L, -2);
      if (lua_pcall(L, 1, 0, 0) != 0) {
        LOGE("Lua entity '%s' onSave error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
        lua_pop(L, 1);
      }
      lua_pop(L, 1);
    }
  }

  entityTag->putString("lua_type", _type->name);
  return super::save(entityTag);
}

bool LuaEntity::load(CompoundTag *entityTag) {
  auto &mgr = LuaPluginManager::instance();
  lua_State *L = mgr.getLuaState();

  if (L && _type && _type->onLoadRef != LUA_NOREF) {
    if (pushTable()) {
      lua_rawgeti(L, LUA_REGISTRYINDEX, _type->onLoadRef);
      lua_pushvalue(L, -2);
      if (lua_pcall(L, 1, 0, 0) != 0) {
        LOGE("Lua entity '%s' onLoad error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
        lua_pop(L, 1);
      }
      lua_pop(L, 1);
    }
  }

  return super::load(entityTag);
}

EntityRendererId LuaEntity::queryEntityRenderer() {
  if (_type && _type->queryRendererRef != LUA_NOREF) {
    auto &mgr = LuaPluginManager::instance();
    lua_State *L = mgr.getLuaState();
    if (L && pushTable()) {
      lua_rawgeti(L, LUA_REGISTRYINDEX, _type->queryRendererRef);
      lua_pushvalue(L, -2);
      if (lua_pcall(L, 1, 1, 0) == 0) {
        if (lua_isinteger(L, -1)) {
          EntityRendererId id = (EntityRendererId)lua_tointeger(L, -1);
          lua_pop(L, 2);
          return id;
        }
        lua_pop(L, 1);
      } else {
        LOGE("Lua entity '%s' queryRenderer error: %s\n", _type->name.c_str(), lua_tostring(L, -1));
        lua_pop(L, 1);
      }
      lua_pop(L, 1);
    }
  }
  return ER_LUA_CUSTOM_RENDERER;
}
