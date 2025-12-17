-- Slot Widget
-- Inventory slot for weapons/MODs with selection states

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local Slot = setmetatable({}, {__index = Widget})
Slot.__index = Slot

-------------------------------------------
-- Constructor
-------------------------------------------

function Slot.new(opts)
    opts = opts or {}
    opts.focusable = true
    
    local self = setmetatable(Widget.new(opts), Slot)
    
    -- Content
    self.content = opts.content or nil  -- Content key/data
    self.icon = opts.icon or nil        -- Icon image or nil
    self.iconColor = opts.iconColor or theme.colors.accent
    self.label = opts.label or nil      -- Optional text label
    self.sublabel = opts.sublabel or nil  -- Secondary label (e.g., "Lv3")
    
    -- State
    self.selected = opts.selected or false
    self.locked = opts.locked or false
    
    -- Colors
    self.emptyColor = opts.emptyColor or theme.colors.slot_empty
    self.filledColor = opts.filledColor or theme.colors.slot_filled
    self.selectedColor = opts.selectedColor or theme.colors.slot_selected
    self.borderColor = opts.borderColor or theme.colors.slot_border
    self.selectedBorderColor = opts.selectedBorderColor or theme.colors.slot_border_selected
    self.lockedColor = opts.lockedColor or {0.2, 0.2, 0.2, 0.8}
    
    -- Style
    self.borderWidth = opts.borderWidth or 1
    self.cornerRadius = opts.cornerRadius or 2
    self.iconPadding = opts.iconPadding or 4
    
    -- Animation
    self.hoverT = 0
    self.selectT = self.selected and 1 or 0
    self.pulseT = 0
    
    -- Size default
    if self.w == 0 then self.w = theme.sizes.slot_size end
    if self.h == 0 then self.h = theme.sizes.slot_size end
    
    return self
end

-------------------------------------------
-- Update
-------------------------------------------

function Slot:update(dt)
    Widget.update(self, dt)
    
    -- Hover animation
    local targetHover = (self.hovered or self.focused) and 1 or 0
    local hoverSpeed = 1 / theme.animation.hover_duration
    if self.hoverT < targetHover then
        self.hoverT = math.min(1, self.hoverT + dt * hoverSpeed)
    elseif self.hoverT > targetHover then
        self.hoverT = math.max(0, self.hoverT - dt * hoverSpeed)
    end
    
    -- Selection animation
    local targetSelect = self.selected and 1 or 0
    if self.selectT < targetSelect then
        self.selectT = math.min(1, self.selectT + dt * 8)
    elseif self.selectT > targetSelect then
        self.selectT = math.max(0, self.selectT - dt * 8)
    end
    
    -- Pulse animation (for selected slots)
    if self.selected then
        self.pulseT = self.pulseT + dt * 3
    end
end

-------------------------------------------
-- Drawing
-------------------------------------------

function Slot:drawSelf()
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    
    if w <= 0 or h <= 0 then return end
    
    -- Determine background color
    local bgColor
    if self.locked then
        bgColor = self.lockedColor
    elseif self.content then
        bgColor = theme.lerpColor(self.filledColor, self.selectedColor, self.selectT)
    else
        bgColor = self.emptyColor
    end
    
    -- Apply hover brightening
    if self.hoverT > 0 and not self.locked then
        bgColor = theme.lerpColor(bgColor, theme.lighten(bgColor, 0.1), self.hoverT)
    end
    
    -- Draw background
    theme.setColor(bgColor)
    if self.cornerRadius > 0 then
        love.graphics.rectangle('fill', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
    else
        love.graphics.rectangle('fill', gx, gy, w, h)
    end
    
    -- Draw border
    local borderCol = self.borderColor
    if self.selected then
        borderCol = theme.lerpColor(self.borderColor, self.selectedBorderColor, self.selectT)
    end
    if self.focused then
        borderCol = theme.colors.accent
    end
    
    theme.setColor(borderCol)
    love.graphics.setLineWidth(self.borderWidth)
    if self.cornerRadius > 0 then
        love.graphics.rectangle('line', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
    else
        love.graphics.rectangle('line', gx, gy, w, h)
    end
    love.graphics.setLineWidth(1)
    
    -- Draw selection pulse
    if self.selected and self.pulseT > 0 then
        local pulse = (math.sin(self.pulseT) + 1) * 0.5 * 0.15
        love.graphics.setColor(
            self.selectedBorderColor[1],
            self.selectedBorderColor[2],
            self.selectedBorderColor[3],
            pulse
        )
        love.graphics.rectangle('fill', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
    end
    
    -- Draw content
    if self.content and not self.locked then
        self:drawContent(gx, gy, w, h)
    end
    
    -- Draw lock overlay
    if self.locked then
        love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
        love.graphics.printf("🔒", gx, gy + h/2 - 8, w, 'center')
    end
    
    -- Draw labels
    if self.label and not self.locked then
        theme.setColor(theme.colors.text)
        local font = love.graphics.getFont()
        love.graphics.printf(self.label, gx, gy + h + 2, w, 'center')
    end
    
    if self.sublabel and self.content and not self.locked then
        love.graphics.setColor(0.6, 0.8, 1, 0.9)
        local font = love.graphics.getFont()
        love.graphics.print(self.sublabel, gx + w - font:getWidth(self.sublabel) - 2, gy + 2)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function Slot:drawContent(gx, gy, w, h)
    local pad = self.iconPadding
    local iconW = w - pad * 2
    local iconH = h - pad * 2
    local iconX = gx + pad
    local iconY = gy + pad
    
    -- Draw icon (placeholder: colored rectangle)
    if self.icon then
        -- For now, just draw colored rectangle
        -- Later: support actual image icons
        theme.setColor(self.iconColor)
        love.graphics.rectangle('fill', iconX, iconY, iconW, iconH)
    else
        -- Default placeholder
        love.graphics.setColor(0.4, 0.4, 0.5, 0.6)
        love.graphics.rectangle('fill', iconX, iconY, iconW, iconH)
    end
end

-------------------------------------------
-- State Methods
-------------------------------------------

function Slot:setContent(content, icon, color)
    self.content = content
    if icon ~= nil then self.icon = icon end
    if color then self.iconColor = color end
    return self
end

function Slot:clearContent()
    self.content = nil
    self.icon = nil
    return self
end

function Slot:setSelected(selected)
    self.selected = selected
    return self
end

function Slot:setLocked(locked)
    self.locked = locked
    return self
end

function Slot:setLabel(label, sublabel)
    self.label = label
    if sublabel ~= nil then self.sublabel = sublabel end
    return self
end

function Slot:isEmpty()
    return self.content == nil
end

-------------------------------------------
-- Events
-------------------------------------------

function Slot:onClick(x, y)
    if self.locked then return end
    Widget.onClick(self, x, y)
end

function Slot:onActivate()
    if self.locked then return end
    Widget.onActivate(self)
    self:emit('click', 0, 0)
end

return Slot
