#ifndef NET_MINECRAFT_LUA_PLUGIN__LuaNativeBridge_H__
#define NET_MINECRAFT_LUA_PLUGIN__LuaNativeBridge_H__

// LuaNativeBridge — allows C/C++ native code to extend the Lua plugin API
// with custom functions accessible from Lua scripts.
//
// Usage from C++:
//   LuaNativeBridge::registerFunction("pollWindowFrame", l_native_pollWindowFrame);
//
// Then in Lua:
//   local fd, w, h, fmt, stride = mcpe.native.pollWindowFrame(windowId)

struct lua_State;

typedef int (*LuaNativeCFunction)(lua_State *L);

class LuaNativeBridge {
public:
  // Register a native C function under mcpe.native.<name>
  // Returns true on success. Must be called after LuaPluginManager::init().
  static bool registerFunction(const char *name, LuaNativeCFunction fn);

  // Register a native C function that takes a userdata pointer as context
  static bool registerFunctionWithContext(const char *name,
                                           LuaNativeCFunction fn,
                                           void *context);

  // Push the mcpe.native table onto the Lua stack (creates if needed)
  // Returns true if the table is on top of the stack.
  static bool pushNativeTable(lua_State *L);
};

#endif // NET_MINECRAFT_LUA_PLUGIN__LuaNativeBridge_H__
