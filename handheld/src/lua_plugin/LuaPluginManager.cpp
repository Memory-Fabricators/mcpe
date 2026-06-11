#include "LuaPluginManager.h"
#include "LuaEntity.h"
#ifdef SDL3
#include "LuaEntityRenderer.h"
#endif

#include "../SharedConstants.h"
#include "../platform/log.h"
#ifdef SDL3
#include "../client/Minecraft.h"
#include "../client/renderer/Textures.h"
#include "../client/renderer/Tesselator.h"
#include "../client/renderer/gles.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#endif
#include "../world/level/Level.h"
#include "../world/entity/EntityRendererId.h"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>

// ---- EGL dmabuf constants (may not be in system headers) ----
#ifdef SDL3

#ifndef EGL_LINUX_DMA_BUF_EXT
#define EGL_LINUX_DMA_BUF_EXT 0x3270
#endif
#ifndef EGL_LINUX_DRM_FOURCC_EXT
#define EGL_LINUX_DRM_FOURCC_EXT 0x3271
#endif
#ifndef EGL_DMA_BUF_PLANE0_FD_EXT
#define EGL_DMA_BUF_PLANE0_FD_EXT 0x3272
#endif
#ifndef EGL_DMA_BUF_PLANE0_OFFSET_EXT
#define EGL_DMA_BUF_PLANE0_OFFSET_EXT 0x3273
#endif
#ifndef EGL_DMA_BUF_PLANE0_PITCH_EXT
#define EGL_DMA_BUF_PLANE0_PITCH_EXT 0x3274
#endif
#endif // SDL3

// ---- Helper: add a C function to the table at top of stack ----
static void l_addCFunc(lua_State *L, const char *name, lua_CFunction fn) {
  lua_pushcfunction(L, fn);
  lua_setfield(L, -2, name);
}

static void l_addIntConst(lua_State *L, const char *name, int val) {
  lua_pushinteger(L, val);
  lua_setfield(L, -2, name);
}

// ---- Forward declarations ----
static int l_mcpe_registerEntityType(lua_State *L);
static int l_mcpe_registerRenderer(lua_State *L);
static int l_mcpe_spawnEntity(lua_State *L);
#ifdef SDL3
static int l_glPushMatrix(lua_State *L);
static int l_glPopMatrix(lua_State *L);
static int l_glTranslatef(lua_State *L);
static int l_glRotatef(lua_State *L);
static int l_glScalef(lua_State *L);
static int l_glColor4f(lua_State *L);
static int l_glEnable(lua_State *L);
static int l_glDisable(lua_State *L);
static int l_glBlendFunc(lua_State *L);
static int l_glDepthFunc(lua_State *L);
static int l_glDepthMask(lua_State *L);
static int l_glBindTexture2D(lua_State *L);
static int l_glCullFace(lua_State *L);
static int l_glAlphaFunc(lua_State *L);
static int l_glTexParameteri(lua_State *L);
static int l_mcpe_bindTexture(lua_State *L);
static int l_mcpe_bindTextureId(lua_State *L);
static int l_mcpe_createEmptyTexture(lua_State *L);
static int l_mcpe_updateTexture(lua_State *L);
static int l_mcpe_createTextureFromDmabuf(lua_State *L);
static int l_tess_begin(lua_State *L);
static int l_tess_draw(lua_State *L);
static int l_tess_end(lua_State *L);
static int l_tess_vertex(lua_State *L);
static int l_tess_vertexUV(lua_State *L);
static int l_tess_color4f(lua_State *L);
static int l_tess_color3f(lua_State *L);
static int l_tess_tex(lua_State *L);
static int l_tess_offset(lua_State *L);
static int l_tess_addOffset(lua_State *L);
static int l_tess_noColor(lua_State *L);
static int l_tess_enableColor(lua_State *L);
#endif
static int l_mcpe_on(lua_State *L);
static int l_mcpe_log(lua_State *L);
static int l_mcpe_getTime(lua_State *L);

// ---- Static helpers ----

static LuaPluginManager *getMgr(lua_State *L) {
  lua_getfield(L, LUA_REGISTRYINDEX, "mcpe_plugin_mgr");
  auto *mgr = (LuaPluginManager *)lua_touserdata(L, -1);
  lua_pop(L, 1);
  return mgr;
}

static float getTableFloat(lua_State *L, int idx, const char *key, float def = 0.0f) {
  lua_getfield(L, idx, key);
  float v = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : def;
  lua_pop(L, 1);
  return v;
}

static std::string getTableString(lua_State *L, int idx, const char *key, const char *def = "") {
  lua_getfield(L, idx, key);
  std::string v = lua_isstring(L, -1) ? lua_tostring(L, -1) : def;
  lua_pop(L, 1);
  return v;
}

static int storeFuncRef(lua_State *L, int idx, const char *key) {
  lua_getfield(L, idx, key);
  if (lua_isfunction(L, -1)) {
    return luaL_ref(L, LUA_REGISTRYINDEX);
  }
  lua_pop(L, 1);
  return LUA_NOREF;
}

// ---- LuaPluginManager implementation ----

LuaPluginManager &LuaPluginManager::instance() {
  static LuaPluginManager s;
  return s;
}

LuaPluginManager::LuaPluginManager()
  : L(nullptr), _level(nullptr), _minecraft(nullptr), _textures(nullptr),
    _nextEntityId(LUA_ENTITY_ID_BASE),
    _tickRef(LUA_NOREF), _renderWorldRef(LUA_NOREF),
    _loadRef(LUA_NOREF), _shutdownRef(LUA_NOREF)
{
}

LuaPluginManager::~LuaPluginManager() {
  if (L) shutdown();
}

void LuaPluginManager::init(Level *level, Minecraft *minecraft, Textures *textures) {
  _level     = level;
  _minecraft = minecraft;
  _textures  = textures;

  L = luaL_newstate();
  luaL_openlibs(L);

  lua_pushlightuserdata(L, this);
  lua_setfield(L, LUA_REGISTRYINDEX, "mcpe_plugin_mgr");

  registerCFunctions();
}

void LuaPluginManager::registerCFunctions() {
  lua_newtable(L);

  l_addCFunc(L, "registerEntityType",    l_mcpe_registerEntityType);
  l_addCFunc(L, "registerRenderer",      l_mcpe_registerRenderer);
  l_addCFunc(L, "spawnEntity",           l_mcpe_spawnEntity);
  l_addCFunc(L, "on",                    l_mcpe_on);
  l_addCFunc(L, "log",                   l_mcpe_log);
  l_addCFunc(L, "getTime",               l_mcpe_getTime);
#ifdef SDL3
  l_addCFunc(L, "bindTexture",           l_mcpe_bindTexture);
  l_addCFunc(L, "bindTextureId",         l_mcpe_bindTextureId);
  l_addCFunc(L, "createTexture",         l_mcpe_createEmptyTexture);
  l_addCFunc(L, "updateTexture",         l_mcpe_updateTexture);
  l_addCFunc(L, "createTextureFromDmabuf", l_mcpe_createTextureFromDmabuf);

  // mcpe.gl
  lua_newtable(L);
  l_addCFunc(L, "pushMatrix",   l_glPushMatrix);
  l_addCFunc(L, "popMatrix",    l_glPopMatrix);
  l_addCFunc(L, "translate",    l_glTranslatef);
  l_addCFunc(L, "rotate",       l_glRotatef);
  l_addCFunc(L, "scale",        l_glScalef);
  l_addCFunc(L, "color",        l_glColor4f);
  l_addCFunc(L, "enable",       l_glEnable);
  l_addCFunc(L, "disable",      l_glDisable);
  l_addCFunc(L, "blendFunc",    l_glBlendFunc);
  l_addCFunc(L, "depthFunc",    l_glDepthFunc);
  l_addCFunc(L, "depthMask",    l_glDepthMask);
  l_addCFunc(L, "bindTexture",  l_glBindTexture2D);
  l_addCFunc(L, "cullFace",     l_glCullFace);
  l_addCFunc(L, "alphaFunc",    l_glAlphaFunc);
  l_addCFunc(L, "texParameteri", l_glTexParameteri);
  lua_setfield(L, -2, "gl");

  // mcpe.tesselator
  lua_newtable(L);
  l_addCFunc(L, "begin",        l_tess_begin);
  l_addCFunc(L, "draw",         l_tess_draw);
  l_addCFunc(L, "end",          l_tess_end);
  l_addCFunc(L, "vertex",       l_tess_vertex);
  l_addCFunc(L, "vertexUV",     l_tess_vertexUV);
  l_addCFunc(L, "color",        l_tess_color4f);
  l_addCFunc(L, "color3",       l_tess_color3f);
  l_addCFunc(L, "tex",          l_tess_tex);
  l_addCFunc(L, "offset",       l_tess_offset);
  l_addCFunc(L, "addOffset",    l_tess_addOffset);
  l_addCFunc(L, "noColor",      l_tess_noColor);
  l_addCFunc(L, "enableColor",  l_tess_enableColor);
  lua_setfield(L, -2, "tesselator");

  // GL constants
  l_addIntConst(L, "GL_TEXTURE_2D",           GL_TEXTURE_2D);
  l_addIntConst(L, "GL_BLEND",                GL_BLEND);
  l_addIntConst(L, "GL_ALPHA_TEST",           GL_ALPHA_TEST);
  l_addIntConst(L, "GL_DEPTH_TEST",           GL_DEPTH_TEST);
  l_addIntConst(L, "GL_CULL_FACE",            GL_CULL_FACE);
  l_addIntConst(L, "GL_COLOR_MATERIAL",       GL_COLOR_MATERIAL);
  l_addIntConst(L, "GL_SRC_ALPHA",            GL_SRC_ALPHA);
  l_addIntConst(L, "GL_ONE_MINUS_SRC_ALPHA",  GL_ONE_MINUS_SRC_ALPHA);
  l_addIntConst(L, "GL_ONE",                  GL_ONE);
  l_addIntConst(L, "GL_ZERO",                 GL_ZERO);
  l_addIntConst(L, "GL_LEQUAL",               GL_LEQUAL);
  l_addIntConst(L, "GL_EQUAL",                GL_EQUAL);
  l_addIntConst(L, "GL_NEVER",                GL_NEVER);
  l_addIntConst(L, "GL_LESS",                 GL_LESS);
  l_addIntConst(L, "GL_GREATER",              GL_GREATER);
  l_addIntConst(L, "GL_FRONT",                GL_FRONT);
  l_addIntConst(L, "GL_BACK",                 GL_BACK);
  l_addIntConst(L, "GL_FRONT_AND_BACK",       GL_FRONT_AND_BACK);
  l_addIntConst(L, "GL_TRIANGLES",            GL_TRIANGLES);
  l_addIntConst(L, "GL_TRIANGLE_STRIP",       GL_TRIANGLE_STRIP);
  l_addIntConst(L, "GL_TRIANGLE_FAN",         GL_TRIANGLE_FAN);
  l_addIntConst(L, "GL_QUADS",                GL_QUADS);
  l_addIntConst(L, "GL_LINEAR",               GL_LINEAR);
  l_addIntConst(L, "GL_NEAREST",              GL_NEAREST);
  l_addIntConst(L, "GL_TEXTURE_MIN_FILTER",   GL_TEXTURE_MIN_FILTER);
  l_addIntConst(L, "GL_TEXTURE_MAG_FILTER",   GL_TEXTURE_MAG_FILTER);
  l_addIntConst(L, "GL_TEXTURE_WRAP_S",       GL_TEXTURE_WRAP_S);
  l_addIntConst(L, "GL_TEXTURE_WRAP_T",       GL_TEXTURE_WRAP_T);
  l_addIntConst(L, "GL_CLAMP_TO_EDGE",        GL_CLAMP_TO_EDGE);
  l_addIntConst(L, "GL_REPEAT",               GL_REPEAT);
  l_addIntConst(L, "GL_RGBA",                 GL_RGBA);
  l_addIntConst(L, "GL_UNSIGNED_BYTE",        GL_UNSIGNED_BYTE);
#endif // SDL3

  l_addIntConst(L, "ENTITY_ID_BASE", LUA_ENTITY_ID_BASE);

  lua_setglobal(L, "mcpe");
}

// ---- Plugin loading ----

void LuaPluginManager::loadPlugins(const std::string &pluginDir) {
  namespace fs = std::filesystem;
  if (!fs::exists(pluginDir)) {
    LOGW("Plugin directory %s does not exist\n", pluginDir.c_str());
    return;
  }
  for (const auto &entry : fs::directory_iterator(pluginDir)) {
    if (entry.path().extension() == ".lua") {
      loadPlugin(entry.path().string());
    }
  }
  callLuaHook("load");
}

bool LuaPluginManager::loadPlugin(const std::string &path) {
  std::ifstream file(path);
  if (!file.is_open()) {
    LOGE("Cannot open plugin file: %s\n", path.c_str());
    return false;
  }
  std::stringstream buf;
  buf << file.rdbuf();
  std::string code = buf.str();

  if (luaL_loadstring(L, code.c_str()) != 0) {
    LOGE("Lua parse error in %s: %s\n", path.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
    return false;
  }
  if (lua_pcall(L, 0, 0, 0) != 0) {
    LOGE("Lua runtime error in %s: %s\n", path.c_str(), lua_tostring(L, -1));
    lua_pop(L, 1);
    return false;
  }
  LOGI("Loaded Lua plugin: %s\n", path.c_str());
  return true;
}

void LuaPluginManager::tick(float dt) {
  if (_tickRef == LUA_NOREF) return;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _tickRef);
  lua_pushnumber(L, dt);
  if (lua_pcall(L, 1, 0, 0) != 0) {
    LOGE("Lua tick hook error: %s\n", lua_tostring(L, -1));
    lua_pop(L, 1);
  }
}

void LuaPluginManager::callRenderHook(float a) {
  if (_renderWorldRef == LUA_NOREF) return;
  lua_rawgeti(L, LUA_REGISTRYINDEX, _renderWorldRef);
  lua_pushnumber(L, a);
  if (lua_pcall(L, 1, 0, 0) != 0) {
    LOGE("Lua render_world hook error: %s\n", lua_tostring(L, -1));
    lua_pop(L, 1);
  }
}

void LuaPluginManager::shutdown() {
  if (!L) return;
  callLuaHook("shutdown");
  lua_close(L);
  L = nullptr;
}

void LuaPluginManager::callLuaHook(const char *hookName) {
  lua_getglobal(L, "mcpe");
  if (!lua_istable(L, -1)) { lua_pop(L, 1); return; }
  lua_getfield(L, -1, "_hooks");
  if (!lua_istable(L, -1)) { lua_pop(L, 2); return; }
  lua_getfield(L, -1, hookName);
  if (lua_isfunction(L, -1)) {
    if (lua_pcall(L, 0, 0, 0) != 0) {
      LOGE("Lua hook '%s' error: %s\n", hookName, lua_tostring(L, -1));
      lua_pop(L, 1);
    }
  } else {
    lua_pop(L, 1);
  }
  lua_pop(L, 2);
}

// ---- Entity type registry ----

int LuaPluginManager::nextEntityTypeId() {
  if (_nextEntityId > LUA_ENTITY_ID_MAX) {
    LOGE("Lua entity type ID overflow!\n");
    return -1;
  }
  return _nextEntityId++;
}

int LuaPluginManager::registerEntityType(const std::string &name, float width,
                                          float height, int baseType,
                                          const std::string &rendererName) {
  if (_entityTypes.count(name) > 0) {
    LOGE("Lua entity type '%s' already registered\n", name.c_str());
    return -1;
  }
  int id = nextEntityTypeId();
  if (id < 0) return -1;

  LuaEntityType et;
  et.name         = name;
  et.typeId       = id;
  et.width        = width;
  et.height       = height;
  et.baseType     = baseType;
  et.rendererName = rendererName;
  et.onInitRef    = LUA_NOREF;
  et.onTickRef    = LUA_NOREF;
  et.onRemoveRef  = LUA_NOREF;
  et.onInteractRef= LUA_NOREF;
  et.onHurtRef    = LUA_NOREF;
  et.onSaveRef    = LUA_NOREF;
  et.onLoadRef    = LUA_NOREF;
  et.queryRendererRef = LUA_NOREF;

  _entityTypes[name] = et;
  _entityTypesById[id] = &_entityTypes[name];
  return id;
}

const LuaEntityType *LuaPluginManager::getEntityType(int typeId) const {
  auto it = _entityTypesById.find(typeId);
  return (it != _entityTypesById.end()) ? it->second : nullptr;
}

const LuaEntityType *LuaPluginManager::getEntityType(const std::string &name) const {
  auto it = _entityTypes.find(name);
  return (it != _entityTypes.end()) ? &it->second : nullptr;
}

void LuaPluginManager::registerRenderer(const std::string &name) {
  if (_renderers.count(name) > 0) return;
  LuaRendererType rt;
  rt.name               = name;
  rt.renderRef          = LUA_NOREF;
  rt.onGraphicsResetRef = LUA_NOREF;
  _renderers[name] = rt;
}

const LuaRendererType *LuaPluginManager::getRenderer(const std::string &name) const {
  auto it = _renderers.find(name);
  return (it != _renderers.end()) ? &it->second : nullptr;
}

Entity *LuaPluginManager::createLuaEntity(int typeId, Level *level) {
  const LuaEntityType *type = getEntityType(typeId);
  if (!type) return nullptr;
  return new LuaEntity(level, type);
}

bool LuaPluginManager::pushEntityTable(Entity *entity) {
  if (!entity) return false;
  auto *le = dynamic_cast<LuaEntity *>(entity);
  if (!le) return false;
  return le->pushTable();
}

// ---- Texture helpers ----
#ifdef SDL3

uint32_t LuaPluginManager::createTextureFromDmabuf(int width, int height,
                                                     int fourcc, int fd,
                                                     int stride, int offset) {
  // Get extension function pointers at runtime
  PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES =
      (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress("glEGLImageTargetTexture2DOES");
  if (!glEGLImageTargetTexture2DOES) {
    LOGE("glEGLImageTargetTexture2DOES not available\n");
    return 0;
  }

  PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR_fn =
      (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
  PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR_fn =
      (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
  if (!eglCreateImageKHR_fn || !eglDestroyImageKHR_fn) {
    LOGE("EGL_image functions not available\n");
    return 0;
  }

  EGLint attribs[] = {
    EGL_WIDTH,                    width,
    EGL_HEIGHT,                   height,
    EGL_LINUX_DRM_FOURCC_EXT,     fourcc,
    EGL_DMA_BUF_PLANE0_FD_EXT,    fd,
    EGL_DMA_BUF_PLANE0_OFFSET_EXT, offset,
    EGL_DMA_BUF_PLANE0_PITCH_EXT, stride,
    EGL_NONE
  };

  EGLDisplay dpy = eglGetCurrentDisplay();
  EGLImageKHR image = eglCreateImageKHR_fn(dpy, EGL_NO_CONTEXT,
                                            EGL_LINUX_DMA_BUF_EXT,
                                            (EGLClientBuffer)nullptr, attribs);
  if (image == EGL_NO_IMAGE_KHR) {
    LOGE("Failed to create EGLImage from dmabuf (err=0x%x)\n", eglGetError());
    return 0;
  }

  uint32_t tex = 0;
  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindTexture(GL_TEXTURE_2D, 0);

  eglDestroyImageKHR_fn(dpy, image);
  return tex;
}

uint32_t LuaPluginManager::createEmptyTexture(int width, int height) {
  uint32_t tex = 0;
  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
               GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindTexture(GL_TEXTURE_2D, 0);
  return tex;
}

void LuaPluginManager::updateTexture(uint32_t tex, int x, int y, int w, int h,
                                     const uint8_t *rgbaData) {
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rgbaData);
  glBindTexture(GL_TEXTURE_2D, 0);
}
#else
uint32_t LuaPluginManager::createTextureFromDmabuf(int, int, int, int, int, int) {
  LOGW("createTextureFromDmabuf called on server build — no-op\n");
  return 0;
}
uint32_t LuaPluginManager::createEmptyTexture(int, int) {
  LOGW("createEmptyTexture called on server build — no-op\n");
  return 0;
}
void LuaPluginManager::updateTexture(uint32_t, int, int, int, int, const uint8_t *) {
  LOGW("updateTexture called on server build — no-op\n");
}
#endif // SDL3

// ====================================================================
// Lua C function implementations
// ====================================================================

static LuaEntity *checkLuaEntity(lua_State *L, int idx) {
  lua_getfield(L, idx, "_ptr");
  auto *ptr = (LuaEntity *)lua_touserdata(L, -1);
  lua_pop(L, 1);
  return ptr;
}

// mcpe.registerEntityType(name, config)
static int l_mcpe_registerEntityType(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  luaL_checktype(L, 2, LUA_TTABLE);

  float width  = getTableFloat(L, 2, "width", 0.6f);
  float height = getTableFloat(L, 2, "height", 1.8f);
  std::string baseTypeStr = getTableString(L, 2, "baseType", "entity");
  int baseType = (baseTypeStr == "mob") ? 1 : 0;
  std::string rendererName = getTableString(L, 2, "renderer", "");

  auto *mgr = getMgr(L);
  int typeId = mgr->registerEntityType(name, width, height, baseType, rendererName);
  if (typeId < 0) {
    lua_pushnil(L);
    lua_pushstring(L, "Failed to register entity type");
    return 2;
  }

  LuaEntityType *et = const_cast<LuaEntityType *>(mgr->getEntityType(name));
  if (et) {
    et->onInitRef     = storeFuncRef(L, 2, "onInit");
    et->onTickRef     = storeFuncRef(L, 2, "onTick");
    et->onRemoveRef   = storeFuncRef(L, 2, "onRemove");
    et->onInteractRef = storeFuncRef(L, 2, "onInteract");
    et->onHurtRef     = storeFuncRef(L, 2, "onHurt");
    et->onSaveRef     = storeFuncRef(L, 2, "onSave");
    et->onLoadRef     = storeFuncRef(L, 2, "onLoad");
    et->queryRendererRef = storeFuncRef(L, 2, "queryRenderer");
  }

  lua_pushinteger(L, typeId);
  return 1;
}

// mcpe.registerRenderer(name, config)
static int l_mcpe_registerRenderer(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  luaL_checktype(L, 2, LUA_TTABLE);

  auto *mgr = getMgr(L);
  mgr->registerRenderer(name);
  LuaRendererType *rt = const_cast<LuaRendererType *>(mgr->getRenderer(name));
  if (!rt) {
    lua_pushnil(L);
    lua_pushstring(L, "Failed to register renderer");
    return 2;
  }

  rt->renderRef          = storeFuncRef(L, 2, "render");
  rt->onGraphicsResetRef = storeFuncRef(L, 2, "onGraphicsReset");

  lua_pushboolean(L, 1);
  return 1;
}

// mcpe.spawnEntity(typeId, x, y, z)
static int l_mcpe_spawnEntity(lua_State *L) {
  int typeId = (int)luaL_checkinteger(L, 1);
  float x = (float)luaL_optnumber(L, 2, 0.0);
  float y = (float)luaL_optnumber(L, 3, 0.0);
  float z = (float)luaL_optnumber(L, 4, 0.0);

  Level *level = getMgr(L)->getLevel();
  if (!level) { lua_pushnil(L); return 1; }

  Entity *e = getMgr(L)->createLuaEntity(typeId, level);
  if (!e) { lua_pushnil(L); return 1; }

  e->setPos(x, y, z);
  level->addEntity(e);

  auto *le = dynamic_cast<LuaEntity *>(e);
  if (le && le->pushTable()) {
    return 1;
  }
  lua_pushnil(L);
  return 1;
}

// ---- GL wrappers ----
#ifdef SDL3

static int l_glPushMatrix(lua_State *)      { glPushMatrix(); return 0; }
static int l_glPopMatrix(lua_State *)       { glPopMatrix(); return 0; }

static int l_glTranslatef(lua_State *L) {
  glTranslatef((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3));
  return 0;
}

static int l_glRotatef(lua_State *L) {
  glRotatef((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4));
  return 0;
}

static int l_glScalef(lua_State *L) {
  glScalef((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3));
  return 0;
}

static int l_glColor4f(lua_State *L) {
  glColor4f((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), (float)luaL_optnumber(L, 4, 1.0f));
  return 0;
}

static int l_glEnable(lua_State *L)     { glEnable((GLenum)luaL_checkinteger(L, 1)); return 0; }
static int l_glDisable(lua_State *L)    { glDisable((GLenum)luaL_checkinteger(L, 1)); return 0; }
static int l_glBlendFunc(lua_State *L)  { glBlendFunc((GLenum)luaL_checkinteger(L, 1), (GLenum)luaL_checkinteger(L, 2)); return 0; }
static int l_glDepthFunc(lua_State *L)  { glDepthFunc((GLenum)luaL_checkinteger(L, 1)); return 0; }
static int l_glDepthMask(lua_State *L)  { glDepthMask((GLboolean)lua_toboolean(L, 1)); return 0; }
static int l_glBindTexture2D(lua_State *L) { glBindTexture(GL_TEXTURE_2D, (GLuint)luaL_checkinteger(L, 1)); return 0; }
static int l_glCullFace(lua_State *L)   { glCullFace((GLenum)luaL_checkinteger(L, 1)); return 0; }
static int l_glAlphaFunc(lua_State *L)  { glAlphaFunc((GLenum)luaL_checkinteger(L, 1), (GLclampf)luaL_checknumber(L, 2)); return 0; }
static int l_glTexParameteri(lua_State *L) { glTexParameteri(GL_TEXTURE_2D, (GLenum)luaL_checkinteger(L, 1), (GLint)luaL_checkinteger(L, 2)); return 0; }

// ---- Texture binding ----

static int l_mcpe_bindTexture(lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  Textures *tex = getMgr(L)->getTextures();
  if (tex && name) {
    TextureId id = tex->loadAndBindTexture(name);
    lua_pushinteger(L, id);
  } else {
    lua_pushnil(L);
  }
  return 1;
}

static int l_mcpe_bindTextureId(lua_State *L) {
  glBindTexture(GL_TEXTURE_2D, (GLuint)luaL_checkinteger(L, 1));
  return 0;
}

static int l_mcpe_createEmptyTexture(lua_State *L) {
  int w = (int)luaL_checkinteger(L, 1);
  int h = (int)luaL_checkinteger(L, 2);
  uint32_t tex = getMgr(L)->createEmptyTexture(w, h);
  lua_pushinteger(L, tex);
  return 1;
}

static int l_mcpe_updateTexture(lua_State *L) {
  uint32_t tex = (uint32_t)luaL_checkinteger(L, 1);
  int x = (int)luaL_checkinteger(L, 2);
  int y = (int)luaL_checkinteger(L, 3);
  int w = (int)luaL_checkinteger(L, 4);
  int h = (int)luaL_checkinteger(L, 5);
  size_t len;
  const char *data = luaL_checklstring(L, 6, &len);
  getMgr(L)->updateTexture(tex, x, y, w, h, (const uint8_t *)data);
  return 0;
}

static int l_mcpe_createTextureFromDmabuf(lua_State *L) {
  int w      = (int)luaL_checkinteger(L, 1);
  int h      = (int)luaL_checkinteger(L, 2);
  int fourcc = (int)luaL_checkinteger(L, 3);
  int fd     = (int)luaL_checkinteger(L, 4);
  int stride = (int)luaL_checkinteger(L, 5);
  int offset = (int)luaL_optinteger(L, 6, 0);
  uint32_t tex = getMgr(L)->createTextureFromDmabuf(w, h, fourcc, fd, stride, offset);
  lua_pushinteger(L, tex);
  return 1;
}

// ---- Tesselator ----

static int l_tess_begin(lua_State *L) {
  if (lua_gettop(L) >= 1)
    Tesselator::instance.begin((int)luaL_checkinteger(L, 1));
  else
    Tesselator::instance.begin();
  return 0;
}

static int l_tess_draw(lua_State *)        { Tesselator::instance.draw(); return 0; }
static int l_tess_end(lua_State *)          { Tesselator::instance.end(true, 0); return 0; }

static int l_tess_vertex(lua_State *L) {
  float x = (float)luaL_checknumber(L, 1);
  float y = (float)luaL_checknumber(L, 2);
  float z = (float)luaL_checknumber(L, 3);
  if (lua_gettop(L) >= 5) {
    Tesselator::instance.vertexUV(x, y, z, (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5));
  } else {
    Tesselator::instance.vertex(x, y, z);
  }
  return 0;
}

static int l_tess_vertexUV(lua_State *L) {
  Tesselator::instance.vertexUV(
      (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2),
      (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4),
      (float)luaL_checknumber(L, 5));
  return 0;
}

static int l_tess_color4f(lua_State *L) {
  Tesselator::instance.color((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2),
                             (float)luaL_checknumber(L, 3), (float)luaL_optnumber(L, 4, 1.0f));
  return 0;
}

static int l_tess_color3f(lua_State *L) {
  Tesselator::instance.color((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3));
  return 0;
}

static int l_tess_tex(lua_State *L) {
  Tesselator::instance.tex((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2));
  return 0;
}

static int l_tess_offset(lua_State *L) {
  Tesselator::instance.offset((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3));
  return 0;
}

static int l_tess_addOffset(lua_State *L) {
  Tesselator::instance.addOffset((float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3));
  return 0;
}

static int l_tess_noColor(lua_State *)      { Tesselator::instance.noColor(); return 0; }
static int l_tess_enableColor(lua_State *)  { Tesselator::instance.enableColor(); return 0; }
#endif // SDL3

// ---- Event hooks ----

static int l_mcpe_on(lua_State *L) {
  const char *event = luaL_checkstring(L, 1);
  luaL_checktype(L, 2, LUA_TFUNCTION);

  // Store in mcpe._hooks
  lua_getglobal(L, "mcpe");
  lua_getfield(L, -1, "_hooks");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, "_hooks");
  }
  lua_pushvalue(L, 2);
  lua_setfield(L, -2, event);

  // Registry reference
  lua_pushvalue(L, 2);
  int ref = luaL_ref(L, LUA_REGISTRYINDEX);

  auto *mgr = getMgr(L);
  if (strcmp(event, "tick") == 0)
    mgr->setTickRef(ref);
  else if (strcmp(event, "render_world") == 0)
    mgr->setRenderWorldRef(ref);
  else if (strcmp(event, "load") == 0)
    mgr->setLoadRef(ref);
  else if (strcmp(event, "shutdown") == 0)
    mgr->setShutdownRef(ref);

  lua_pop(L, 2);
  return 0;
}

// ---- Logging ----

static int l_mcpe_log(lua_State *L) {
  const char *level = luaL_optstring(L, 1, "info");
  const char *msg   = luaL_checkstring(L, 2);
  if (strcmp(level, "error") == 0)      LOGE("[Lua] %s\n", msg);
  else if (strcmp(level, "warn") == 0)  LOGW("[Lua] %s\n", msg);
  else                                  LOGI("[Lua] %s\n", msg);
  return 0;
}

static int l_mcpe_getTime(lua_State *L) {
  lua_pushnumber(L, getEpochTimeS());
  return 1;
}
