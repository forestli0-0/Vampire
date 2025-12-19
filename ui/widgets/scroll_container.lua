-- ScrollContainer Widget
-- A container that allows scrolling its content
-- Supports vertical scrolling and optional scrollbar

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local ScrollContainer = setmetatable({}, {__index = Widget})
ScrollContainer.__index = ScrollContainer

-------------------------------------------
-- Constructor
-------------------------------------------

function ScrollContainer.new(opts)
    opts = opts or {}
    local self = setmetatable(Widget.new(opts), ScrollContainer)
    
    -- Scroll state
    self.scrollX = opts.scrollX or 0
    self.scrollY = opts.scrollY or 0
    self.targetScrollY = self.scrollY
    
    -- Config
    self.scrollSpeed = opts.scrollSpeed or 40
    self.smoothScroll = opts.smoothScroll ~= false
    self.scrollbarVisible = opts.scrollbarVisible ~= false
    self.scrollbarWidth = opts.scrollbarWidth or 6
    
    -- Content boundaries (calculated)
    self.contentWidth = 0
    self.contentHeight = 0
    
    return self
end

-------------------------------------------
-- Update
-------------------------------------------

function ScrollContainer:update(dt)
    -- Calculate content size based on children
    local maxW, maxH = 0, 0
    for _, child in ipairs(self.children) do
        maxW = math.max(maxW, child.x + child.w)
        maxH = math.max(maxH, child.y + child.h)
    end
    self.contentWidth = maxW
    self.contentHeight = maxH
    
    -- Smooth scroll interpolation
    if self.smoothScroll then
        local lerp = math.min(1, dt * 15)
        self.scrollY = self.scrollY + (self.targetScrollY - self.scrollY) * lerp
    else
        self.scrollY = self.targetScrollY
    end
    
    -- Clamp scroll
    local maxScroll = math.max(0, self.contentHeight - self.h)
    self.targetScrollY = math.max(0, math.min(maxScroll, self.targetScrollY))
    
    -- Update children (adjust their position based on scroll)
    -- Note: We don't actually move children's .x/.y, we just draw them shifted.
    Widget.update(self, dt)
end

-------------------------------------------
-- Drawing
-------------------------------------------

function ScrollContainer:draw()
    if not self.visible then return end
    
    local gx, gy = self:getGlobalPosition()
    
    -- Draw background
    self:drawSelf()
    
    -- Set clipping scissor
    -- We need to account for scale
    local scaling = require('ui.scaling')
    local sc = scaling.getScale()
    local sx, sy = scaling.toScreen(gx, gy)
    local sw, sh = self.w * sc, self.h * sc
    
    -- Get current scissor to restore
    local prevX, prevY, prevW, prevH = love.graphics.getScissor()
    
    love.graphics.setScissor(sx, sy, sw, sh)
    
    -- Draw children with offset
    love.graphics.push()
    love.graphics.translate(0, -self.scrollY)
    
    for _, child in ipairs(self.children) do
        if child.visible then
            -- We manually check visibility for performance (optional)
            local cy = child.y - self.scrollY
            if cy + child.h > 0 and cy < self.h then
                child:draw()
            end
        end
    end
    
    love.graphics.pop()
    
    -- Restore scissor
    love.graphics.setScissor(prevX, prevY, prevW, prevH)
    
    -- Draw scrollbar
    if self.scrollbarVisible and self.contentHeight > self.h then
        self:drawScrollbar(gx, gy)
    end
end

function ScrollContainer:drawScrollbar(gx, gy)
    local x = gx + self.w - self.scrollbarWidth - 2
    local y = gy + 2
    local h = self.h - 4
    
    -- Track
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.rectangle('fill', x, y, self.scrollbarWidth, h, 2, 2)
    
    -- Thumb
    local thumbH = math.max(10, (self.h / self.contentHeight) * h)
    local maxScroll = self.contentHeight - self.h
    local thumbY = y + (self.scrollY / maxScroll) * (h - thumbH)
    
    theme.setColor(theme.colors.accent)
    love.graphics.rectangle('fill', x, thumbY, self.scrollbarWidth, thumbH, 2, 2)
    
    love.graphics.setColor(1, 1, 1, 1)
end

-------------------------------------------
-- Events
-------------------------------------------

function ScrollContainer:onWheel(x, y)
    self.targetScrollY = self.targetScrollY - y * self.scrollSpeed
    return true
end

function ScrollContainer:contains(px, py)
    -- Important: hit detection must account for scroll offset if we were 
    -- passing it down to children, but hitTest usually calls contains on children.
    -- The core hitTest uses logical coordinates.
    -- However, children of ScrollContainer are drawn offset.
    -- So we need to override how children are hit-tested?
    -- No, core.lua:hitTest calls widget.children in order.
    -- If ScrollContainer contains a child, hitTest will call child:contains(x, y).
    -- But child:contains(x, y) uses child:getGlobalPosition() which doesn't know about ScrollContainer offset.
    
    -- We need to fix hit detection for children.
    return Widget.contains(self, px, py)
end

-- Override to adjust hit testing for children
function ScrollContainer:hitTest(x, y)
    if not self.visible or not self.enabled then return nil end
    if not self:contains(x, y) then return nil end
    
    -- Check children with scroll offset
    local core = require('ui.core')
    for i = #self.children, 1, -1 do
        local child = self.children[i]
        if child.visible and child.enabled then
            -- Translate mouse coordinate into scrolled space
            local lx = x
            local ly = y + self.scrollY
            
            local hit = core.hitTest(child, lx, ly)
            if hit then return hit end
        end
    end
    
    return self
end


return ScrollContainer
