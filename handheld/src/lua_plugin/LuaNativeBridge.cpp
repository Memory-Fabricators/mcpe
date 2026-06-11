#include "LuaNativeBridge.h"
#include "LuaPluginManager.h"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

bool LuaNativeBridge::pushNativeTable(lua_State *L) {
  lua_getglobal(L, "mcpe");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return false;
  }
  lua_getfield(L, -1, "native");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, "native");
  }
  lua_remove(L, -2);
  return true;
}

bool LuaNativeBridge::registerFunction(const char *name, LuaNativeCFunction fn) {
  lua_State *L = LuaPluginManager::instance().getLuaState();
  if (!L) return false;

  if (!pushNativeTable(L)) return false;

  lua_pushcfunction(L, fn);
  lua_setfield(L, -2, name);

  lua_pop(L, 1);
  return true;
}

bool LuaNativeBridge::registerFunctionWithContext(const char *name,
                                                   LuaNativeCFunction fn,
                                                   void *context) {
  lua_State *L = LuaPluginManager::instance().getLuaState();
  if (!L) return false;

  if (!pushNativeTable(L)) return false;

  lua_pushlightuserdata(L, context);
  lua_pushcclosure(L, fn, 1);
  lua_setfield(L, -2, name);

  lua_pop(L, 1);
  return true;
}
