-- UI Scaling module
-- Handles 640x360 logical resolution with integer scaling

local scaling = {}

-- Logical resolution (game design resolution)
scaling.LOGICAL_WIDTH = 640
scaling.LOGICAL_HEIGHT = 360

-- Cached values (updated on resize)
local cachedScale = nil
local cachedOffsetX = nil
local cachedOffsetY = nil

--- Recalculate cached scale and offset values
function scaling.recalculate()
    if not love or not love.graphics then return end
    
    local w, h = love.graphics.getDimensions()
    
    -- Calculate integer scale factor
    local scaleX = math.floor(w / scaling.LOGICAL_WIDTH)
    local scaleY = math.floor(h / scaling.LOGICAL_HEIGHT)
    cachedScale = math.max(1, math.min(scaleX, scaleY))
    
    -- Calculate letterbox offsets (centered)
    cachedOffsetX = math.floor((w - scaling.LOGICAL_WIDTH * cachedScale) / 2)
    cachedOffsetY = math.floor((h - scaling.LOGICAL_HEIGHT * cachedScale) / 2)
end

--- Get current integer scale factor
---@return number scale Integer scale (1, 2, 3, etc.)
function scaling.getScale()
    if not cachedScale then scaling.recalculate() end
    return cachedScale or 1
end

--- Get letterbox offset
---@return number offsetX, number offsetY Pixel offset from screen edge
function scaling.getOffset()
    if not cachedOffsetX then scaling.recalculate() end
    return cachedOffsetX or 0, cachedOffsetY or 0
end

--- Get logical dimensions
---@return number width, number height Logical resolution
function scaling.getLogicalDimensions()
    return scaling.LOGICAL_WIDTH, scaling.LOGICAL_HEIGHT
end

--- Convert screen coordinates to logical coordinates
---@param screenX number Screen X position
---@param screenY number Screen Y position
---@return number logicalX, number logicalY Logical coordinates
function scaling.toLogical(screenX, screenY)
    local scale = scaling.getScale()
    local ox, oy = scaling.getOffset()
    local lx = (screenX - ox) / scale
    local ly = (screenY - oy) / scale
    return lx, ly
end

--- Convert logical coordinates to screen coordinates
---@param logicalX number Logical X position
---@param logicalY number Logical Y position
---@return number screenX, number screenY Screen coordinates
function scaling.toScreen(logicalX, logicalY)
    local scale = scaling.getScale()
    local ox, oy = scaling.getOffset()
    local sx = logicalX * scale + ox
    local sy = logicalY * scale + oy
    return sx, sy
end

--- Check if logical coordinates are within bounds
---@param lx number Logical X
---@param ly number Logical Y
---@return boolean inBounds
function scaling.inBounds(lx, ly)
    return lx >= 0 and lx < scaling.LOGICAL_WIDTH and
           ly >= 0 and ly < scaling.LOGICAL_HEIGHT
end

--- Push transform: sets up graphics state for logical coordinate rendering
function scaling.push()
    if not love or not love.graphics then return end
    
    love.graphics.push()
    local ox, oy = scaling.getOffset()
    local scale = scaling.getScale()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
end

--- Pop transform: restores previous graphics state
function scaling.pop()
    if not love or not love.graphics then return end
    love.graphics.pop()
end

--- Draw letterbox bars (black borders when aspect ratio differs)
function scaling.drawLetterbox()
    if not love or not love.graphics then return end
    
    local w, h = love.graphics.getDimensions()
    local ox, oy = scaling.getOffset()
    local scale = scaling.getScale()
    local logW = scaling.LOGICAL_WIDTH * scale
    local logH = scaling.LOGICAL_HEIGHT * scale
    
    love.graphics.setColor(0, 0, 0, 1)
    
    -- Top bar
    if oy > 0 then
        love.graphics.rectangle('fill', 0, 0, w, oy)
    end
    -- Bottom bar
    if oy > 0 then
        love.graphics.rectangle('fill', 0, oy + logH, w, oy + 1)
    end
    -- Left bar
    if ox > 0 then
        love.graphics.rectangle('fill', 0, 0, ox, h)
    end
    -- Right bar
    if ox > 0 then
        love.graphics.rectangle('fill', ox + logW, 0, ox + 1, h)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

--- Get mouse position in logical coordinates
---@return number lx, number ly Logical mouse position
function scaling.getMousePosition()
    if not love or not love.mouse then return 0, 0 end
    local mx, my = love.mouse.getPosition()
    return scaling.toLogical(mx, my)
end

return scaling
