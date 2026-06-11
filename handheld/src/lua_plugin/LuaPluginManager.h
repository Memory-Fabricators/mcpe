#ifndef NET_MINECRAFT_LUA_PLUGIN__LuaPluginManager_H__
#define NET_MINECRAFT_LUA_PLUGIN__LuaPluginManager_H__

#include <cstdint>
#include <map>
#include <string>
#include <vector>
#include <functional>

struct lua_State;

class Level;
class Entity;
class Minecraft;
class Textures;
class Tesselator;

// Lua registry constants (defined in lauxlib.h)
#ifndef LUA_NOREF
#define LUA_NOREF (-2)
#endif
#ifndef LUA_REFNIL
#define LUA_REFNIL (-1)
#endif

// Represents a registered Lua entity type
struct LuaEntityType {
  std::string name;
  int typeId;
  float width;
  float height;
  int baseType;       // 0 = Entity, 1 = Mob
  std::string rendererName;

  int onInitRef;
  int onTickRef;
  int onRemoveRef;
  int onInteractRef;
  int onHurtRef;
  int onSaveRef;
  int onLoadRef;
  int queryRendererRef;
};

// Represents a registered Lua renderer
struct LuaRendererType {
  std::string name;
  int renderRef;
  int onGraphicsResetRef;
};

class LuaPluginManager {
public:
  static const int LUA_ENTITY_ID_BASE = 200;
  static const int LUA_ENTITY_ID_MAX  = 254;

  static LuaPluginManager &instance();

  void init(Level *level, Minecraft *minecraft, Textures *textures);
  void loadPlugins(const std::string &pluginDir);
  bool loadPlugin(const std::string &path);
  void tick(float dt);
  void shutdown();

  int  registerEntityType(const std::string &name, float width, float height,
                          int baseType, const std::string &rendererName);
  const LuaEntityType *getEntityType(int typeId) const;
  const LuaEntityType *getEntityType(const std::string &name) const;

  void registerRenderer(const std::string &name);
  const LuaRendererType *getRenderer(const std::string &name) const;

  Entity *createLuaEntity(int typeId, Level *level);
  bool pushEntityTable(Entity *entity);

  uint32_t createTextureFromDmabuf(int width, int height, int fourcc,
                                   int fd, int stride, int offset);
  uint32_t createEmptyTexture(int width, int height);
  void updateTexture(uint32_t tex, int x, int y, int w, int h,
                     const uint8_t *rgbaData);

  void callRenderHook(float a);

  lua_State *getLuaState() { return L; }
  Level     *getLevel()    { return _level; }
  Minecraft *getMinecraft() { return _minecraft; }
  Textures  *getTextures() { return _textures; }

  // Hook reference setters (for static Lua C functions)
  void setTickRef(int r)        { _tickRef = r; }
  void setRenderWorldRef(int r) { _renderWorldRef = r; }
  void setLoadRef(int r)        { _loadRef = r; }
  void setShutdownRef(int r)    { _shutdownRef = r; }

private:
  LuaPluginManager();
  ~LuaPluginManager();
  LuaPluginManager(const LuaPluginManager &) = delete;
  LuaPluginManager &operator=(const LuaPluginManager &) = delete;

  void registerCFunctions();
  int  nextEntityTypeId();
  void callLuaHook(const char *hookName);

  lua_State *L;
  Level      *_level;
  Minecraft  *_minecraft;
  Textures   *_textures;

  std::map<std::string, LuaEntityType> _entityTypes;
  std::map<int, LuaEntityType *> _entityTypesById;
  int _nextEntityId;

  std::map<std::string, LuaRendererType> _renderers;

  int _tickRef;
  int _renderWorldRef;
  int _loadRef;
  int _shutdownRef;
};

#endif
