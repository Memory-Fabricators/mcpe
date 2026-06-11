-- example.lua — Demonstrates the Lua plugin API for custom entities and renderers
--
-- This example creates a "floating screen" entity that renders a custom
-- textured quad in-world. It shows the basic plugin structure:
--   1. Register a custom renderer
--   2. Register a custom entity type that uses that renderer
--   3. Hook into game events

-- ============================================================
-- Custom Renderer: renders a 2x2 floating screen
-- ============================================================
mcpe.registerRenderer("floating_screen_renderer", {
  render = function(entity, x, y, z, rot, a)
    -- Setup GL state for our custom rendering
    mcpe.gl.disable(mcpe.GL_CULL_FACE)
    mcpe.gl.enable(mcpe.GL_BLEND)
    mcpe.gl.blendFunc(mcpe.GL_SRC_ALPHA, mcpe.GL_ONE_MINUS_SRC_ALPHA)
    mcpe.gl.depthMask(false)

    mcpe.gl.pushMatrix()
    mcpe.gl.translate(x, y, z)

    -- Face the camera (billboard effect)
    mcpe.gl.rotate(180 - rot, 0, 1, 0)

    -- Draw a 2x2 quad with the custom texture
    local w = entity:getWidth() / 2
    local h = entity:getHeight()

    mcpe.bindTexture("terrain.png")  -- fallback; override with your own

    mcpe.gl.color(1, 1, 1, 0.9)
    mcpe.gl.enable(mcpe.GL_TEXTURE_2D)

    local t = mcpe.tesselator
    t:begin(mcpe.GL_QUADS)
    t:tex(0, 0); t:vertex(-w,  h, 0)
    t:tex(0, 1); t:vertex(-w,  0, 0)
    t:tex(1, 1); t:vertex( w,  0, 0)
    t:tex(1, 0); t:vertex( w,  h, 0)
    t:draw()

    mcpe.gl.popMatrix()

    mcpe.gl.depthMask(true)
    mcpe.gl.disable(mcpe.GL_BLEND)
    mcpe.gl.enable(mcpe.GL_CULL_FACE)
  end,

  onGraphicsReset = function()
    mcpe.log("info", "floating_screen_renderer: graphics reset")
  end
})

-- ============================================================
-- Custom Entity Type: Floating Screen
-- ============================================================
mcpe.registerEntityType("floating_screen", {
  width  = 2.0,
  height = 2.0,
  renderer = "floating_screen_renderer",

  onInit = function(self)
    mcpe.log("info", "FloatingScreen entity initialized (id=" .. self:getEntityId() .. ")")
  end,

  onTick = function(self)
    -- Slowly rotate
    local yRot, xRot = self:getRotation()
    self:setRotation(yRot + 0.5, xRot)
  end,

  onRemove = function(self)
    mcpe.log("info", "FloatingScreen entity removed")
  end,

  onInteract = function(self, player)
    mcpe.log("info", "FloatingScreen interacted by player!")
    return true  -- prevent default interaction
  end,

  onHurt = function(self, source, damage)
    mcpe.log("info", "FloatingScreen hurt for " .. damage .. " damage")
    return false  -- allow default hurt processing
  end
})

-- ============================================================
-- Global hooks
-- ============================================================
mcpe.on("load", function()
  mcpe.log("info", "Example plugin loaded! Spawning a floating screen...")
  -- Spawn a floating screen entity at the world center
  local entity = mcpe.spawnEntity(mcpe.ENTITY_ID_BASE, 128, 70, 128)
  if entity then
    mcpe.log("info", "Spawned floating screen entity")
  end
end)

mcpe.on("shutdown", function()
  mcpe.log("info", "Example plugin shutting down")
end)
