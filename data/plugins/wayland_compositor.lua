-- wayland_compositor.lua — Advanced plugin template for embedding Wayland
-- surfaces into the game world via dmabuf import.
--
-- This plugin shows the architecture for:
--   1. Registering a "wayland_window" entity type
--   2. Using a C-side helper that manages a Wayland compositor
--   3. Importing dmabuf file descriptors as GL textures
--   4. Rendering live desktop windows as in-world surfaces
--
-- The C side would:
--   - Start a Wayland compositor (via wlroots or similar)
--   - Expose a C function callable from Lua: mcpe.native.getDmabufFd(windowId)
--   - Return dmabuf fds, widths, heights, formats when surfaces update
--
-- The Lua side:
--   - Polls for new dmabuf fds each tick
--   - Creates/updates GL textures from dmabufs
--   - Renders the textures on in-world quads

-- ============================================================
-- Wayland window renderer
-- ============================================================
mcpe.registerRenderer("wayland_window_renderer", {
  render = function(entity, x, y, z, rot, a)
    local texId = entity._dmabuf_tex
    if not texId or texId == 0 then
      -- No texture yet; draw a placeholder
      mcpe.gl.disable(mcpe.GL_CULL_FACE)
      mcpe.gl.disable(mcpe.GL_TEXTURE_2D)
      mcpe.gl.depthMask(false)
      mcpe.gl.enable(mcpe.GL_BLEND)
      mcpe.gl.blendFunc(mcpe.GL_SRC_ALPHA, mcpe.GL_ONE_MINUS_SRC_ALPHA)

      mcpe.gl.pushMatrix()
      mcpe.gl.translate(x, y, z)
      mcpe.gl.rotate(180 - rot, 0, 1, 0)

      local w = entity:getWidth() / 2
      local h = entity:getHeight()
      mcpe.gl.color(0.2, 0.2, 0.3, 0.8)

      local t = mcpe.tesselator
      t:begin(mcpe.GL_QUADS)
      t:vertex(-w, h, 0)
      t:vertex(-w, 0, 0)
      t:vertex( w, 0, 0)
      t:vertex( w, h, 0)
      t:draw()

      mcpe.gl.popMatrix()
      mcpe.gl.depthMask(true)
      mcpe.gl.enable(mcpe.GL_TEXTURE_2D)
      mcpe.gl.enable(mcpe.GL_CULL_FACE)
      mcpe.gl.disable(mcpe.GL_BLEND)
      return
    end

    -- Render the dmabuf-backed texture
    mcpe.gl.disable(mcpe.GL_CULL_FACE)
    mcpe.gl.enable(mcpe.GL_BLEND)
    mcpe.gl.blendFunc(mcpe.GL_SRC_ALPHA, mcpe.GL_ONE_MINUS_SRC_ALPHA)
    mcpe.gl.depthMask(false)

    mcpe.gl.pushMatrix()
    mcpe.gl.translate(x, y, z)
    mcpe.gl.rotate(180 - rot, 0, 1, 0)

    mcpe.gl.color(1, 1, 1, 1)
    mcpe.bindTextureId(texId)

    local w = entity:getWidth() / 2
    local h = entity:getHeight()
    local t = mcpe.tesselator
    t:begin(mcpe.GL_QUADS)
    t:color(1, 1, 1, 1)
    t:tex(0, 0); t:vertex(-w, h, 0)
    t:tex(0, 1); t:vertex(-w, 0, 0)
    t:tex(1, 1); t:vertex( w, 0, 0)
    t:tex(1, 0); t:vertex( w, h, 0)
    t:draw()

    mcpe.gl.popMatrix()

    mcpe.gl.depthMask(true)
    mcpe.gl.disable(mcpe.GL_BLEND)
    mcpe.gl.enable(mcpe.GL_CULL_FACE)
  end,

  onGraphicsReset = function()
    mcpe.log("info", "wayland_window_renderer: graphics reset — textures invalidated")
  end
})

-- ============================================================
-- Wayland Window entity type
-- ============================================================
mcpe.registerEntityType("wayland_window", {
  width  = 1.6,
  height = 0.9,
  renderer = "wayland_window_renderer",

  onInit = function(self)
    self._dmabuf_tex = 0
    self._window_id = nil
    mcpe.log("info", "WaylandWindow entity created (id=" .. self:getEntityId() .. ")")
  end,

  onTick = function(self)
    -- If this entity is associated with a Wayland window, poll for new frames
    --
    -- In a real implementation, you'd call into the C-side compositor:
    --   local fd, width, height, format, stride =
    --       mcpe.native.pollWindowFrame(self._window_id)
    --
    -- Then import the dmabuf:
    --   if fd >= 0 then
    --     if self._dmabuf_tex ~= 0 then
    --       -- Reuse texture: glDeleteTextures equivalent?
    --     end
    --     self._dmabuf_tex = mcpe.createTextureFromDmabuf(
    --         width, height, format, fd, stride, 0)
    --     mcpe.log("info", "Imported dmabuf as GL texture " .. self._dmabuf_tex)
    --   end
  end,

  onRemove = function(self)
    mcpe.log("info", "WaylandWindow entity removed")
    -- Cleanup: close Wayland window, delete GL texture
  end,

  onInteract = function(self, player)
    -- Send keyboard/mouse events to the Wayland window
    mcpe.log("info", "Wayland window interacted — forward input to compositor")
    return true
  end
})

-- ============================================================
-- Global hooks
-- ============================================================
mcpe.on("load", function()
  mcpe.log("info", "Wayland compositor plugin loaded")
  -- In a real plugin, you'd initialize the Wayland compositor here
  -- and spawn initial window entities.
end)

mcpe.on("tick", function(dt)
  -- Global tick: poll the Wayland compositor for new events
  -- Dispatch input events to focused window entities
end)

mcpe.on("shutdown", function()
  mcpe.log("info", "Wayland compositor plugin shutting down")
  -- Shut down the Wayland compositor
end)
