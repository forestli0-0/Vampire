-- Panel Widget
-- Background container with optional border

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local Panel = setmetatable({}, {__index = Widget})
Panel.__index = Panel

-------------------------------------------
-- Constructor
-------------------------------------------

function Panel.new(opts)
    opts = opts or {}
    
    local self = setmetatable(Widget.new(opts), Panel)
    
    -- Panel style
    self.bgColor = opts.bgColor or theme.colors.panel_bg
    self.borderColor = opts.borderColor or theme.colors.panel_border
    self.borderWidth = opts.borderWidth or 0
    self.cornerRadius = opts.cornerRadius or 0
    
    -- Shadow
    self.shadow = opts.shadow or false
    self.shadowOffset = opts.shadowOffset or 2
    self.shadowColor = opts.shadowColor or {0, 0, 0, 0.3}
    
    -- Animation support
    self.alpha = opts.alpha or 1.0
    
    return self
end

-------------------------------------------
-- Drawing
-------------------------------------------

function Panel:drawSelf()
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    
    if w <= 0 or h <= 0 then return end
    
    -- Draw shadow
    if self.shadow then
        local ox, oy = self.shadowOffset, self.shadowOffset
        love.graphics.setColor(
            self.shadowColor[1],
            self.shadowColor[2],
            self.shadowColor[3],
            (self.shadowColor[4] or 0.3) * self.alpha
        )
        if self.cornerRadius > 0 then
            love.graphics.rectangle('fill', gx + ox, gy + oy, w, h, self.cornerRadius, self.cornerRadius)
        else
            love.graphics.rectangle('fill', gx + ox, gy + oy, w, h)
        end
    end
    
    -- Draw background
    love.graphics.setColor(
        self.bgColor[1],
        self.bgColor[2],
        self.bgColor[3],
        (self.bgColor[4] or 1) * self.alpha
    )
    if self.cornerRadius > 0 then
        love.graphics.rectangle('fill', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
    else
        love.graphics.rectangle('fill', gx, gy, w, h)
    end
    
    -- Draw border
    if self.borderWidth > 0 then
        love.graphics.setColor(
            self.borderColor[1],
            self.borderColor[2],
            self.borderColor[3],
            (self.borderColor[4] or 1) * self.alpha
        )
        love.graphics.setLineWidth(self.borderWidth)
        if self.cornerRadius > 0 then
            love.graphics.rectangle('line', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
        else
            love.graphics.rectangle('line', gx, gy, w, h)
        end
        love.graphics.setLineWidth(1)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

-------------------------------------------
-- Style Methods
-------------------------------------------

function Panel:setBackgroundColor(color)
    self.bgColor = color
    return self
end

function Panel:setBorderColor(color)
    self.borderColor = color
    return self
end

function Panel:setBorderWidth(width)
    self.borderWidth = width
    return self
end

function Panel:setCornerRadius(radius)
    self.cornerRadius = radius
    return self
end

function Panel:setShadow(enabled, offset, color)
    self.shadow = enabled
    if offset then self.shadowOffset = offset end
    if color then self.shadowColor = color end
    return self
end

function Panel:setAlpha(alpha)
    self.alpha = alpha
    return self
end

-------------------------------------------
-- Animation Helpers
-------------------------------------------

function Panel:fadeIn(duration, callback)
    self.alpha = 0
    self.visible = true
    self:animate('alpha', 1, duration or theme.animation.fade_duration, theme.easing.outQuad, callback)
    return self
end

function Panel:fadeOut(duration, callback)
    self:animate('alpha', 0, duration or theme.animation.fade_duration, theme.easing.outQuad, function()
        self.visible = false
        if callback then callback(self) end
    end)
    return self
end

return Panel
