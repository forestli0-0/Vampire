-- Base Widget class
-- Foundation for all UI components

local theme = require('ui.theme')

local Widget = {}
Widget.__index = Widget

-------------------------------------------
-- Constructor
-------------------------------------------

function Widget.new(opts)
    opts = opts or {}
    
    local self = setmetatable({}, Widget)
    
    -- Position and size
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.w = opts.w or 0
    self.h = opts.h or 0
    
    -- State
    self.visible = opts.visible ~= false
    self.enabled = opts.enabled ~= false
    self.focusable = opts.focusable or false
    
    -- Interaction state (managed by core)
    self.hovered = false
    self.focused = false
    self.pressed = false
    
    -- Hierarchy
    self.parent = nil
    self.children = {}
    
    -- Animation state
    self.animations = {}
    
    -- Optional tooltip
    self.tooltip = opts.tooltip
    
    -- Event callbacks
    self.callbacks = {}
    
    -- Custom data
    self.data = opts.data
    
    return self
end

-------------------------------------------
-- Hierarchy
-------------------------------------------

function Widget:addChild(child)
    if not child then return self end
    
    child.parent = self
    table.insert(self.children, child)
    
    return self
end

function Widget:removeChild(child)
    if not child then return self end
    
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            break
        end
    end
    
    return self
end

function Widget:clearChildren()
    for _, child in ipairs(self.children) do
        child.parent = nil
    end
    self.children = {}
    return self
end

function Widget:getGlobalPosition()
    local x, y = self.x, self.y
    local p = self.parent
    while p do
        x = x + p.x
        y = y + p.y
        p = p.parent
    end
    return x, y
end

-------------------------------------------
-- Hit Testing
-------------------------------------------

function Widget:contains(px, py)
    local gx, gy = self:getGlobalPosition()
    return px >= gx and px < gx + self.w and
           py >= gy and py < gy + self.h
end

function Widget:getBounds()
    local gx, gy = self:getGlobalPosition()
    return gx, gy, self.w, self.h
end

-------------------------------------------
-- Update & Draw
-------------------------------------------

function Widget:update(dt)
    -- Update animations
    self:updateAnimations(dt)
    
    -- Update children
    for _, child in ipairs(self.children) do
        if child.visible then
            child:update(dt)
        end
    end
end

function Widget:draw()
    if not self.visible then return end
    
    -- Override in subclasses
    self:drawSelf()
    
    -- Draw children
    for _, child in ipairs(self.children) do
        if child.visible then
            child:draw()
        end
    end
end

function Widget:drawSelf()
    -- Override in subclasses
    -- Default: draw a debug rectangle
    if self.w > 0 and self.h > 0 then
        local gx, gy = self:getGlobalPosition()
        love.graphics.setColor(0.3, 0.3, 0.3, 0.5)
        love.graphics.rectangle('fill', gx, gy, self.w, self.h)
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        love.graphics.rectangle('line', gx, gy, self.w, self.h)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-------------------------------------------
-- Animation System
-------------------------------------------

function Widget:animate(property, target, duration, easing, callback)
    easing = easing or theme.easing.outQuad
    duration = duration or 0.2
    
    local current = self[property]
    if current == nil then return self end
    
    self.animations[property] = {
        startValue = current,
        targetValue = target,
        duration = duration,
        elapsed = 0,
        easing = easing,
        callback = callback
    }
    
    return self
end

function Widget:updateAnimations(dt)
    for prop, anim in pairs(self.animations) do
        anim.elapsed = anim.elapsed + dt
        local t = math.min(1, anim.elapsed / anim.duration)
        local eased = anim.easing(t)
        
        local startVal = anim.startValue
        local targetVal = anim.targetValue
        
        -- Handle different value types
        if type(startVal) == 'number' then
            self[prop] = startVal + (targetVal - startVal) * eased
        elseif type(startVal) == 'table' then
            -- Color interpolation
            self[prop] = theme.lerpColor(startVal, targetVal, eased)
        end
        
        -- Animation complete
        if t >= 1 then
            self[prop] = targetVal
            self.animations[prop] = nil
            if anim.callback then
                anim.callback(self)
            end
        end
    end
end

function Widget:stopAnimation(property)
    if property then
        self.animations[property] = nil
    else
        self.animations = {}
    end
    return self
end

function Widget:isAnimating(property)
    if property then
        return self.animations[property] ~= nil
    end
    return next(self.animations) ~= nil
end

-------------------------------------------
-- Events
-------------------------------------------

function Widget:on(event, callback)
    self.callbacks[event] = callback
    return self
end

function Widget:emit(event, ...)
    local cb = self.callbacks[event]
    if cb then
        cb(self, ...)
    end
end

-- Called when mouse enters widget
function Widget:onHoverStart()
    self.hovered = true
    self:emit('hoverStart')
end

-- Called when mouse leaves widget
function Widget:onHoverEnd()
    self.hovered = false
    self:emit('hoverEnd')
end

-- Called on mouse press
function Widget:onPress(button, x, y)
    self.pressed = true
    self:emit('press', button, x, y)
end

-- Called on mouse release
function Widget:onRelease(button, x, y)
    self.pressed = false
    self:emit('release', button, x, y)
end

-- Called on left click (press + release on same widget)
function Widget:onClick(x, y)
    self:emit('click', x, y)
end

-- Called on right click
function Widget:onRightClick(x, y)
    self:emit('rightClick', x, y)
end

-- Called when widget gains focus
function Widget:onFocus()
    self.focused = true
    self:emit('focus')
end

-- Called when widget loses focus
function Widget:onBlur()
    self.focused = false
    self:emit('blur')
end

-- Called when Enter/Space pressed on focused widget
function Widget:onActivate()
    self:emit('activate')
end

-------------------------------------------
-- Utility
-------------------------------------------

function Widget:setPosition(x, y)
    self.x = x
    self.y = y
    return self
end

function Widget:setSize(w, h)
    self.w = w
    self.h = h
    return self
end

function Widget:setBounds(x, y, w, h)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    return self
end

function Widget:setVisible(visible)
    self.visible = visible
    return self
end

function Widget:setEnabled(enabled)
    self.enabled = enabled
    return self
end

function Widget:setTooltip(text)
    self.tooltip = text
    return self
end

function Widget:center()
    local scaling = require('ui.scaling')
    self.x = (scaling.LOGICAL_WIDTH - self.w) / 2
    self.y = (scaling.LOGICAL_HEIGHT - self.h) / 2
    return self
end

function Widget:centerX()
    local scaling = require('ui.scaling')
    self.x = (scaling.LOGICAL_WIDTH - self.w) / 2
    return self
end

function Widget:centerY()
    local scaling = require('ui.scaling')
    self.y = (scaling.LOGICAL_HEIGHT - self.h) / 2
    return self
end

return Widget
