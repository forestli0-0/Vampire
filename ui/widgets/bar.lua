-- Bar Widget
-- Progress/health/energy bars with animated fill

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local Bar = setmetatable({}, {__index = Widget})
Bar.__index = Bar

-------------------------------------------
-- Constructor
-------------------------------------------

function Bar.new(opts)
    opts = opts or {}
    
    local self = setmetatable(Widget.new(opts), Bar)
    
    -- Value
    self.value = opts.value or 0
    self.maxValue = opts.maxValue or 100
    self.displayValue = self.value  -- For animation
    
    -- Colors
    self.bgColor = opts.bgColor or theme.colors.hp_bg
    self.fillColor = opts.fillColor or theme.colors.hp_fill
    self.lowColor = opts.lowColor            -- Optional: color when low
    self.lowThreshold = opts.lowThreshold or 0.25  -- When to use lowColor
    self.borderColor = opts.borderColor or nil
    self.borderWidth = opts.borderWidth or 0
    
    -- Style
    self.cornerRadius = opts.cornerRadius or 0
    self.direction = opts.direction or 'right'  -- 'right', 'left', 'up', 'down'
    self.showText = opts.showText or false
    self.textFormat = opts.textFormat or 'value'  -- 'value', 'percent', 'both'
    self.textColor = opts.textColor or theme.colors.text
    
    -- Segments (for ammo display)
    self.segments = opts.segments or 0  -- 0 = continuous
    self.segmentGap = opts.segmentGap or 1
    
    -- Animation
    self.animSpeed = opts.animSpeed or (1 / theme.animation.bar_fill_duration)
    
    -- Effects
    self.shakeAmount = 0
    self.shakeTimer = 0
    self.flashTimer = 0
    self.flashColor = opts.flashColor or {1, 1, 1, 0.5}
    
    -- Size defaults
    if self.w == 0 then self.w = 100 end
    if self.h == 0 then self.h = theme.sizes.bar_height end
    
    return self
end

-------------------------------------------
-- Update
-------------------------------------------

function Bar:update(dt)
    Widget.update(self, dt)
    
    -- Animate display value towards actual value
    local target = self.value
    if self.displayValue ~= target then
        local diff = target - self.displayValue
        local speed = self.animSpeed * self.maxValue
        local change = diff * math.min(1, dt * 10)
        
        -- Also apply minimum speed
        if math.abs(change) < speed * dt then
            if diff > 0 then
                change = math.min(diff, speed * dt)
            else
                change = math.max(diff, -speed * dt)
            end
        end
        
        self.displayValue = self.displayValue + change
        
        -- Snap if close enough
        if math.abs(self.displayValue - target) < 0.1 then
            self.displayValue = target
        end
    end
    
    -- Update shake
    if self.shakeTimer > 0 then
        self.shakeTimer = self.shakeTimer - dt
        if self.shakeTimer <= 0 then
            self.shakeAmount = 0
        end
    end
    
    -- Update flash
    if self.flashTimer > 0 then
        self.flashTimer = self.flashTimer - dt
    end
end

-------------------------------------------
-- Drawing
-------------------------------------------

function Bar:drawSelf()
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    
    if w <= 0 or h <= 0 then return end
    
    -- Apply shake
    local shakeX, shakeY = 0, 0
    if self.shakeAmount > 0 then
        shakeX = (math.random() - 0.5) * self.shakeAmount * 2
        shakeY = (math.random() - 0.5) * self.shakeAmount * 2
    end
    gx = gx + shakeX
    gy = gy + shakeY
    
    -- Draw background
    theme.setColor(self.bgColor)
    if self.cornerRadius > 0 then
        love.graphics.rectangle('fill', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
    else
        love.graphics.rectangle('fill', gx, gy, w, h)
    end
    
    -- Calculate fill ratio
    local ratio = 0
    if self.maxValue > 0 then
        ratio = math.max(0, math.min(1, self.displayValue / self.maxValue))
    end
    
    -- Determine fill color
    local fillCol = self.fillColor
    if self.lowColor and ratio <= self.lowThreshold then
        local t = ratio / self.lowThreshold
        fillCol = theme.lerpColor(self.lowColor, self.fillColor, t)
    end
    
    -- Draw fill
    if ratio > 0 then
        if self.segments > 0 then
            self:drawSegmented(gx, gy, w, h, ratio, fillCol)
        else
            self:drawContinuous(gx, gy, w, h, ratio, fillCol)
        end
    end
    
    -- Draw flash overlay
    if self.flashTimer > 0 then
        local flashAlpha = self.flashTimer * 3  -- Fade out quickly
        love.graphics.setColor(
            self.flashColor[1],
            self.flashColor[2],
            self.flashColor[3],
            (self.flashColor[4] or 0.5) * flashAlpha
        )
        if self.cornerRadius > 0 then
            love.graphics.rectangle('fill', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
        else
            love.graphics.rectangle('fill', gx, gy, w, h)
        end
    end
    
    -- Draw border
    if self.borderWidth > 0 and self.borderColor then
        theme.setColor(self.borderColor)
        love.graphics.setLineWidth(self.borderWidth)
        if self.cornerRadius > 0 then
            love.graphics.rectangle('line', gx, gy, w, h, self.cornerRadius, self.cornerRadius)
        else
            love.graphics.rectangle('line', gx, gy, w, h)
        end
        love.graphics.setLineWidth(1)
    end
    
    -- Draw text
    if self.showText then
        local textStr = self:getTextString()
        if textStr then
            theme.setColor(self.textColor)
            local font = love.graphics.getFont()
            local textY = gy + (h - font:getHeight()) / 2
            love.graphics.printf(textStr, gx, textY, w, 'center')
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function Bar:drawContinuous(gx, gy, w, h, ratio, color)
    theme.setColor(color)
    
    local fillW, fillH, fillX, fillY = w * ratio, h, gx, gy
    
    if self.direction == 'left' then
        fillX = gx + w - fillW
    elseif self.direction == 'up' then
        fillW, fillH = w, h * ratio
        fillY = gy + h - fillH
    elseif self.direction == 'down' then
        fillW, fillH = w, h * ratio
    end
    
    if self.cornerRadius > 0 then
        love.graphics.rectangle('fill', fillX, fillY, fillW, fillH, self.cornerRadius, self.cornerRadius)
    else
        love.graphics.rectangle('fill', fillX, fillY, fillW, fillH)
    end
end

function Bar:drawSegmented(gx, gy, w, h, ratio, color)
    local segCount = self.segments
    local gap = self.segmentGap
    local totalGaps = gap * (segCount - 1)
    local segW = (w - totalGaps) / segCount
    
    local filledSegs = math.ceil(ratio * segCount)
    
    for i = 1, segCount do
        local segX = gx + (i - 1) * (segW + gap)
        
        if i <= filledSegs then
            theme.setColor(color)
        else
            love.graphics.setColor(
                self.bgColor[1] * 1.3,
                self.bgColor[2] * 1.3,
                self.bgColor[3] * 1.3,
                self.bgColor[4] or 1
            )
        end
        
        love.graphics.rectangle('fill', segX, gy, segW, h)
    end
end

function Bar:getTextString()
    if self.textFormat == 'percent' then
        local pct = 0
        if self.maxValue > 0 then
            pct = math.floor(self.value / self.maxValue * 100)
        end
        return pct .. "%"
    elseif self.textFormat == 'both' then
        return string.format("%d/%d", math.floor(self.value), math.floor(self.maxValue))
    else  -- 'value'
        return tostring(math.floor(self.value))
    end
end

-------------------------------------------
-- Value Methods
-------------------------------------------

function Bar:setValue(value, instant)
    local oldValue = self.value
    self.value = math.max(0, math.min(self.maxValue, value))
    
    if instant then
        self.displayValue = self.value
    end
    
    -- Trigger damage shake on decrease
    if value < oldValue and not instant then
        self:shake(2, 0.15)
    end
    
    return self
end

function Bar:setMaxValue(maxValue)
    self.maxValue = maxValue
    self.value = math.min(self.value, maxValue)
    return self
end

function Bar:getValue()
    return self.value
end

function Bar:getRatio()
    if self.maxValue <= 0 then return 0 end
    return self.value / self.maxValue
end

-------------------------------------------
-- Effects
-------------------------------------------

function Bar:shake(amount, duration)
    self.shakeAmount = amount or 2
    self.shakeTimer = duration or 0.2
    return self
end

function Bar:flash(color, duration)
    if color then self.flashColor = color end
    self.flashTimer = duration or 0.15
    return self
end

-------------------------------------------
-- Style Setters
-------------------------------------------

function Bar:setColors(bg, fill, low)
    if bg then self.bgColor = bg end
    if fill then self.fillColor = fill end
    if low then self.lowColor = low end
    return self
end

function Bar:setShowText(show, format)
    self.showText = show
    if format then self.textFormat = format end
    return self
end

function Bar:setSegments(count, gap)
    self.segments = count
    if gap then self.segmentGap = gap end
    return self
end

return Bar
