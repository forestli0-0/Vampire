-- Tooltip Widget (standalone version)
-- For manual tooltip placement, not managed by core

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local Tooltip = setmetatable({}, {__index = Widget})
Tooltip.__index = Tooltip

-------------------------------------------
-- Constructor
-------------------------------------------

function Tooltip.new(opts)
    opts = opts or {}
    
    local self = setmetatable(Widget.new(opts), Tooltip)
    
    -- Content
    self.text = opts.text or ""
    self.title = opts.title or nil
    
    -- Style
    self.bgColor = opts.bgColor or theme.colors.tooltip_bg
    self.borderColor = opts.borderColor or theme.colors.tooltip_border
    self.textColor = opts.textColor or theme.colors.text
    self.titleColor = opts.titleColor or theme.colors.accent
    self.borderWidth = opts.borderWidth or 1
    self.padding = opts.padding or theme.sizes.padding_normal
    self.maxWidth = opts.maxWidth or theme.sizes.tooltip_max_width
    
    -- Animation
    self.alpha = 0
    self.targetAlpha = 0
    
    -- Auto-calculate size
    self:updateSize()
    
    return self
end

-------------------------------------------
-- Size Calculation
-------------------------------------------

function Tooltip:updateSize()
    local font = love.graphics.getFont()
    local pad = self.padding
    local maxW = self.maxWidth - pad * 2
    
    local titleHeight = 0
    if self.title and self.title ~= "" then
        titleHeight = font:getHeight() + 4
    end
    
    local _, lines = font:getWrap(self.text, maxW)
    local textHeight = #lines * font:getHeight()
    
    self.w = self.maxWidth
    self.h = titleHeight + textHeight + pad * 2
end

-------------------------------------------
-- Update
-------------------------------------------

function Tooltip:update(dt)
    Widget.update(self, dt)
    
    -- Fade animation
    local speed = 1 / theme.animation.tooltip_fade
    if self.alpha < self.targetAlpha then
        self.alpha = math.min(self.targetAlpha, self.alpha + dt * speed)
    elseif self.alpha > self.targetAlpha then
        self.alpha = math.max(self.targetAlpha, self.alpha - dt * speed)
    end
    
    -- Hide when fully faded
    if self.alpha <= 0 and self.targetAlpha <= 0 then
        self.visible = false
    end
end

-------------------------------------------
-- Drawing
-------------------------------------------

function Tooltip:drawSelf()
    if self.alpha <= 0 then return end
    
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    local pad = self.padding
    
    -- Draw background
    love.graphics.setColor(
        self.bgColor[1], self.bgColor[2], self.bgColor[3],
        (self.bgColor[4] or 1) * self.alpha
    )
    love.graphics.rectangle('fill', gx, gy, w, h)
    
    -- Draw border
    if self.borderWidth > 0 then
        love.graphics.setColor(
            self.borderColor[1], self.borderColor[2], self.borderColor[3],
            (self.borderColor[4] or 1) * self.alpha
        )
        love.graphics.setLineWidth(self.borderWidth)
        love.graphics.rectangle('line', gx, gy, w, h)
        love.graphics.setLineWidth(1)
    end
    
    -- Draw title
    local textY = gy + pad
    if self.title and self.title ~= "" then
        love.graphics.setColor(
            self.titleColor[1], self.titleColor[2], self.titleColor[3],
            self.alpha
        )
        love.graphics.print(self.title, gx + pad, textY)
        textY = textY + love.graphics.getFont():getHeight() + 4
    end
    
    -- Draw text
    love.graphics.setColor(
        self.textColor[1], self.textColor[2], self.textColor[3],
        self.alpha
    )
    love.graphics.printf(self.text, gx + pad, textY, w - pad * 2, 'left')
    
    love.graphics.setColor(1, 1, 1, 1)
end

-------------------------------------------
-- Methods
-------------------------------------------

function Tooltip:show(x, y)
    local scaling = require('ui.scaling')
    
    -- Position with edge clamping
    local tx = x or self.x
    local ty = y or self.y
    
    if tx + self.w > scaling.LOGICAL_WIDTH - 4 then
        tx = scaling.LOGICAL_WIDTH - self.w - 4
    end
    if ty + self.h > scaling.LOGICAL_HEIGHT - 4 then
        ty = scaling.LOGICAL_HEIGHT - self.h - 4
    end
    tx = math.max(4, tx)
    ty = math.max(4, ty)
    
    self.x = tx
    self.y = ty
    self.visible = true
    self.targetAlpha = 1
    
    return self
end

function Tooltip:hide()
    self.targetAlpha = 0
    return self
end

function Tooltip:setContent(text, title)
    self.text = text or ""
    self.title = title
    self:updateSize()
    return self
end

function Tooltip:isVisible()
    return self.visible and self.alpha > 0
end

return Tooltip
