# Lua Plugin API Reference

The Lua plugin system allows creating custom entities and renderers in Lua,
with full access to OpenGL ES rendering, custom textures, and dmabuf import
for embedding native surfaces (e.g. Wayland windows) into the game world.

## Quick Start

Place `.lua` files in `data/plugins/`. They are automatically loaded on startup.

```lua
-- Register a custom entity type
local typeId = mcpe.registerEntityType("my_entity", {
    width  = 1.0,
    height = 2.0,
    renderer = "my_renderer",
    onTick = function(self) end,
})

-- Register a custom renderer
mcpe.registerRenderer("my_renderer", {
    render = function(entity, x, y, z, rot, a)
        -- Custom OpenGL rendering here
    end,
})

-- Spawn an entity
local entity = mcpe.spawnEntity(typeId, 128, 70, 128)
```

## API Reference

### `mcpe` Global Table

#### Entity Types

**`mcpe.registerEntityType(name, config)`** → `typeId`

Registers a new entity type. Returns the assigned type ID (200–254).

| Config field | Type     | Default  | Description                              |
|-------------|----------|----------|------------------------------------------|
| `width`     | number   | 0.6      | Bounding box width                       |
| `height`    | number   | 1.8      | Bounding box height                      |
| `baseType`  | string   | "entity" | Either `"entity"` or `"mob"`             |
| `renderer`  | string   | ""       | Name of renderer to use                  |
| `onInit`    | function | nil      | `function(self)` called on entity spawn  |
| `onTick`    | function | nil      | `function(self)` called each tick        |
| `onRemove`  | function | nil      | `function(self)` called on removal       |
| `onInteract`| function | nil      | `function(self, player)` returns bool    |
| `onHurt`    | function | nil      | `function(self, source, damage)` ret bool|
| `onSave`    | function | nil      | `function(self)` called before NBT save  |
| `onLoad`    | function | nil      | `function(self)` called after NBT load   |

#### Renderers

**`mcpe.registerRenderer(name, config)`** → `boolean`

| Config field      | Type     | Description                        |
|-------------------|----------|------------------------------------|
| `render`          | function | `function(entity, x, y, z, rot, a)`|
| `onGraphicsReset` | function | Called on GL context loss           |

#### Spawning

**`mcpe.spawnEntity(typeId, x, y, z)`** → `entityTable`

Creates and spawns a new entity of the given type at world position (x, y, z).
Returns the entity's Lua table, or `nil` on failure.

#### Hooks

**`mcpe.on(event, callback)`**

| Event           | Callback signature    | Description                  |
|-----------------|-----------------------|------------------------------|
| `"tick"`        | `function(dt)`        | Called every game tick       |
| `"render_world"`| `function(a)`         | Called during world render   |
| `"load"`        | `function()`          | Called after plugins load    |
| `"shutdown"`    | `function()`          | Called on game shutdown      |

### Entity Table Methods

Every Lua entity has these methods:

| Method                  | Returns          | Description                         |
|-------------------------|------------------|-------------------------------------|
| `entity:getPos()`       | x, y, z          | World position                      |
| `entity:setPos(x,y,z)`  | —                | Set world position                  |
| `entity:getRotation()`  | yRot, xRot       | Yaw and pitch in degrees            |
| `entity:setRotation(y,x)`| —               | Set rotation                        |
| `entity:getMotion()`    | xd, yd, zd       | Velocity vector                     |
| `entity:setMotion(x,y,z)`| —               | Set velocity                        |
| `entity:isAlive()`      | boolean          | Whether entity is not removed       |
| `entity:remove()`       | —                | Mark entity for removal             |
| `entity:getTypeId()`    | integer          | Entity type ID                      |
| `entity:getEntityId()`  | integer          | Unique entity instance ID           |
| `entity:getWidth()`     | number           | Bounding box width                  |
| `entity:getHeight()`    | number           | Bounding box height                 |
| `entity:setOnFire(ticks)`| —               | Set on-fire duration                |
| `entity:getOnFire()`    | integer          | Remaining fire ticks                |
| `entity:isOnGround()`   | boolean          | Whether touching ground             |
| `entity:getTicks()`     | integer          | Age in ticks                        |

### GL Functions (`mcpe.gl`)

Thin wrappers around OpenGL ES 1.1 functions:

| Function                                    |
|---------------------------------------------|
| `mcpe.gl.pushMatrix()`                      |
| `mcpe.gl.popMatrix()`                       |
| `mcpe.gl.translate(x, y, z)`                |
| `mcpe.gl.rotate(angle, x, y, z)`            |
| `mcpe.gl.scale(x, y, z)`                    |
| `mcpe.gl.color(r, g, b [, a])`              |
| `mcpe.gl.enable(cap)`                       |
| `mcpe.gl.disable(cap)`                      |
| `mcpe.gl.blendFunc(src, dst)`               |
| `mcpe.gl.depthFunc(func)`                   |
| `mcpe.gl.depthMask(flag)`                   |
| `mcpe.gl.bindTexture(texId)`                |
| `mcpe.gl.cullFace(mode)`                    |
| `mcpe.gl.alphaFunc(func, ref)`              |
| `mcpe.gl.texParameteri(pname, param)`       |

### GL Constants (on `mcpe` table)

`GL_TEXTURE_2D`, `GL_BLEND`, `GL_ALPHA_TEST`, `GL_DEPTH_TEST`, `GL_CULL_FACE`,
`GL_COLOR_MATERIAL`, `GL_SRC_ALPHA`, `GL_ONE_MINUS_SRC_ALPHA`, `GL_ONE`,
`GL_ZERO`, `GL_LEQUAL`, `GL_EQUAL`, `GL_NEVER`, `GL_LESS`, `GL_GREATER`,
`GL_FRONT`, `GL_BACK`, `GL_FRONT_AND_BACK`, `GL_TRIANGLES`, `GL_TRIANGLE_STRIP`,
`GL_TRIANGLE_FAN`, `GL_QUADS`, `GL_LINEAR`, `GL_NEAREST`, `GL_TEXTURE_MIN_FILTER`,
`GL_TEXTURE_MAG_FILTER`, `GL_TEXTURE_WRAP_S`, `GL_TEXTURE_WRAP_T`,
`GL_CLAMP_TO_EDGE`, `GL_REPEAT`, `GL_RGBA`, `GL_UNSIGNED_BYTE`

### Tesselator (`mcpe.tesselator`)

Immediate-mode vertex submission modeled after the game's Tesselator:

| Function                                  |
|-------------------------------------------|
| `mcpe.tesselator.begin([mode])`           |
| `mcpe.tesselator.vertex(x, y, z)`         |
| `mcpe.tesselator.vertexUV(x, y, z, u, v)` |
| `mcpe.tesselator.color(r, g, b [, a])`    |
| `mcpe.tesselator.color3(r, g, b)`         |
| `mcpe.tesselator.tex(u, v)`               |
| `mcpe.tesselator.offset(x, y, z)`         |
| `mcpe.tesselator.addOffset(x, y, z)`      |
| `mcpe.tesselator.noColor()`               |
| `mcpe.tesselator.enableColor()`           |
| `mcpe.tesselator.draw()`                  |
| `mcpe.tesselator.end()`                   |

### Textures

| Function                                          | Description                            |
|---------------------------------------------------|----------------------------------------|
| `mcpe.bindTexture(name)` → texId                  | Bind a game texture by resource name   |
| `mcpe.bindTextureId(texId)`                       | Bind a raw GL texture ID               |
| `mcpe.createTexture(w, h)` → texId                | Create an empty RGBA texture           |
| `mcpe.updateTexture(texId, x, y, w, h, data)`     | Upload RGBA pixel data to a texture    |
| `mcpe.createTextureFromDmabuf(w, h, fourcc, fd, stride, offset)` → texId | Import dmabuf as GL texture |

### Native Extensions (`mcpe.native`)

C/C++ code can register custom functions via `LuaNativeBridge`:

```cpp
#include "lua_plugin/LuaNativeBridge.h"

static int l_pollWindowFrame(lua_State *L) {
    // ... call dmabuf_bridge_poll_frame ...
    return 4; // number of return values
}

// In your initialization:
LuaNativeBridge::registerFunction("pollWindowFrame", l_pollWindowFrame);
```

Then from Lua:
```lua
local fd, width, height, format = mcpe.native.pollWindowFrame(windowId)
```

### Utility

| Function                    | Description                      |
|-----------------------------|----------------------------------|
| `mcpe.log(level, msg)`      | Log message (info/warn/error)    |
| `mcpe.getTime()` → seconds  | Current epoch time               |
| `mcpe.ENTITY_ID_BASE`       | 200, first Lua entity type ID    |

## Wayland dmabuf Integration

The `LuaDmabufBridge` C API provides a thread-safe bridge between a Wayland
compositor and the game. See `LuaDmabufBridge.h` for the C interface.

**Architecture:**
1. A Wayland compositor runs in a separate thread (e.g. using wlroots)
2. When a surface produces a new frame, the compositor calls `dmabuf_bridge_push_frame()`
3. Lua polls for new frames via a native function registered with `LuaNativeBridge`
4. The dmabuf fd is imported as a GL texture using `mcpe.createTextureFromDmabuf()`
5. The texture is rendered on an in-world custom entity

## Building

The Lua dependency is automatically detected by meson. Ensure one of these
packages is installed: `lua`, `lua5.4`, `lua-5.4`, or `luajit`.

```bash
# Nix (already in flake.nix):
nix develop

# Build:
meson setup build
ninja -C build

# Plugins are loaded from data/plugins/ relative to the working directory
# or from $prefix/share/mcpe/plugins/
```
