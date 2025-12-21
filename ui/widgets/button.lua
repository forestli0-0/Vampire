-- Button Widget
-- Interactive clickable button with hover/press states

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local Button = setmetatable({}, {__index = Widget})
Button.__index = Button

-------------------------------------------
-- Constructor
-------------------------------------------

function Button.new(opts)
    opts = opts or {}
    if opts.focusable == nil then opts.focusable = true end

    
    local self = setmetatable(Widget.new(opts), Button)
    
    -- Text
    self.text = opts.text or ""
    self.textColor = opts.textColor or theme.colors.text
    self.textAlign = opts.textAlign or 'center'
    
    -- Icon (placeholder: colored square)
    self.icon = opts.icon  -- icon key or nil
    self.iconColor = opts.iconColor or theme.colors.accent
    self.iconSize = opts.iconSize or 12
    
    -- Colors
    self.normalColor = opts.normalColor or theme.colors.button_normal
    self.hoverColor = opts.hoverColor or theme.colors.button_hover
    self.pressedColor = opts.pressedColor or theme.colors.button_pressed
    self.disabledColor = opts.disabledColor or theme.colors.button_disabled
    self.borderColor = opts.borderColor or theme.colors.button_border
    self.borderHoverColor = opts.borderHoverColor or theme.colors.button_border_hover
    
    -- Style
    self.borderWidth = opts.borderWidth or 1
    self.cornerRadius = opts.cornerRadius or 2
    self.padding = opts.padding or theme.sizes.padding_normal
    
    -- Animation state
    self.hoverT = 0        -- 0 = normal, 1 = hovered
    self.pressT = 0        -- Flash effect on press
    self.scaleAnim = 1.0   -- Scale animation
    
    -- Size defaults
    if self.w == 0 then
        self.w = opts.w or theme.sizes.button_min_width
    end
    if self.h == 0 then
        self.h = opts.h or theme.sizes.button_height
    end
    
    return self
end

-------------------------------------------
-- Update
-------------------------------------------

function Button:update(dt)
    Widget.update(self, dt)
    
    -- Animate hover transition
    local targetHover = (self.hovered or self.focused) and 1 or 0
    local hoverSpeed = 1 / theme.animation.hover_duration
    if self.hoverT < targetHover then
        self.hoverT = math.min(1, self.hoverT + dt * hoverSpeed)
    elseif self.hoverT > targetHover then
        self.hoverT = math.max(0, self.hoverT - dt * hoverSpeed)
    end
    
    -- Animate press flash
    if self.pressT > 0 then
        self.pressT = math.max(0, self.pressT - dt / theme.animation.press_duration)
    end
    
    -- Animate scale
    local targetScale = self.pressed and 0.96 or (self.hovered and 1.02 or 1.0)
    self.scaleAnim = self.scaleAnim + (targetScale - self.scaleAnim) * math.min(1, dt * 15)
end

-------------------------------------------
-- Drawing
-------------------------------------------

function Button:drawSelf()
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    
    if w <= 0 or h <= 0 then return end
    
    -- Calculate scaled bounds (centered)
    local scale = self.scaleAnim
    local sw = w * scale
    local sh = h * scale
    local sx = gx + (w - sw) / 2
    local sy = gy + (h - sh) / 2
    
    -- Determine background color
    local bgColor
    if not self.enabled then
        bgColor = self.disabledColor
    elseif self.pressed or self.pressT > 0 then
        bgColor = theme.lerpColor(self.pressedColor, self.hoverColor, 1 - self.pressT)
    else
        bgColor = theme.lerpColor(self.normalColor, self.hoverColor, self.hoverT)
    end
    
    -- Determine border color
    local borderCol = theme.lerpColor(self.borderColor, self.borderHoverColor, self.hoverT)
    
    -- Draw background
    theme.setColor(bgColor)
    if self.cornerRadius > 0 then
        love.graphics.rectangle('fill', sx, sy, sw, sh, self.cornerRadius, self.cornerRadius)
    else
        love.graphics.rectangle('fill', sx, sy, sw, sh)
    end
    
    -- Draw border
    if self.borderWidth > 0 then
        theme.setColor(borderCol)
        love.graphics.setLineWidth(self.borderWidth)
        if self.cornerRadius > 0 then
            love.graphics.rectangle('line', sx, sy, sw, sh, self.cornerRadius, self.cornerRadius)
        else
            love.graphics.rectangle('line', sx, sy, sw, sh)
        end
        love.graphics.setLineWidth(1)
    end
    
    -- Draw focus indicator
    if self.focused and self.enabled then
        love.graphics.setColor(theme.colors.accent[1], theme.colors.accent[2], theme.colors.accent[3], 0.4)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle('line', sx - 2, sy - 2, sw + 4, sh + 4, self.cornerRadius + 1, self.cornerRadius + 1)
        love.graphics.setLineWidth(1)
    end
    
    -- Calculate content area
    local contentX = sx + self.padding
    local contentW = sw - self.padding * 2
    local contentY = sy
    local contentH = sh
    
    -- Draw icon
    local iconOffset = 0
    if self.icon then
        local iconX = contentX
        local iconY = sy + (sh - self.iconSize) / 2
        
        if self.enabled then
            theme.setColor(self.iconColor)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.rectangle('fill', iconX, iconY, self.iconSize, self.iconSize)
        iconOffset = self.iconSize + 4
    end
    
    -- Draw text
    if self.text and self.text ~= "" then
        if self.enabled then
            theme.setColor(self.textColor)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        
        local textX = contentX + iconOffset
        local textW = contentW - iconOffset
        local font = love.graphics.getFont()
        local textY = sy + (sh - font:getHeight()) / 2
        
        love.graphics.printf(self.text, textX, textY, textW, self.textAlign)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function Button:drawEmissiveSelf()
    if not self.enabled then return end

    local glowT = math.max(self.hoverT or 0, self.pressT or 0, (self.focused and 1 or 0))
    if glowT <= 0.001 then return end

    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    if w <= 0 or h <= 0 then return end

    local scale = self.scaleAnim or 1
    local sw = w * scale
    local sh = h * scale
    local sx = gx + (w - sw) / 2
    local sy = gy + (h - sh) / 2

    local borderCol = theme.lerpColor(self.borderColor, self.borderHoverColor, self.hoverT or 0)
    if self.focused then borderCol = theme.colors.accent end

    local alpha = 0.12 + 0.38 * glowT
    local expand = 1.5

    love.graphics.setBlendMode('add')
    love.graphics.setColor(borderCol[1], borderCol[2], borderCol[3], alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle('line', sx - expand, sy - expand, sw + expand * 2, sh + expand * 2, self.cornerRadius + 1, self.cornerRadius + 1)
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1, 1)
end

-------------------------------------------
-- Events
-------------------------------------------

function Button:onPress(button, x, y)
    Widget.onPress(self, button, x, y)
    self.pressT = 1
end

function Button:onClick(x, y)
    if not self.enabled then return end
    Widget.onClick(self, x, y)
end

function Button:onActivate()
    if not self.enabled then return end
    self.pressT = 1
    Widget.onActivate(self)
    -- Also trigger click for keyboard activation
    self:emit('click', 0, 0)
end

-------------------------------------------
-- Setters
-------------------------------------------

function Button:setText(text)
    self.text = text
    return self
end

function Button:setIcon(icon, color)
    self.icon = icon
    if color then self.iconColor = color end
    return self
end

function Button:setTextColor(color)
    self.textColor = color
    return self
end

function Button:setColors(normal, hover, pressed, disabled)
    if normal then self.normalColor = normal end
    if hover then self.hoverColor = hover end
    if pressed then self.pressedColor = pressed end
    if disabled then self.disabledColor = disabled end
    return self
end

return Button
