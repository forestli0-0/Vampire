-- Text Widget
-- Styled text with outline/shadow support and typing animation

local Widget = require('ui.widgets.widget')
local theme = require('ui.theme')

local Text = setmetatable({}, {__index = Widget})
Text.__index = Text

-------------------------------------------
-- Constructor
-------------------------------------------

function Text.new(opts)
    opts = opts or {}
    
    local self = setmetatable(Widget.new(opts), Text)
    
    -- Text content
    self.text = opts.text or ""
    self.displayText = self.text  -- For typing animation
    
    -- Style
    self.color = opts.color or theme.colors.text
    self.align = opts.align or 'left'  -- 'left', 'center', 'right'
    self.font = opts.font or nil       -- nil = use default
    
    -- Outline
    self.outline = opts.outline or false
    self.outlineColor = opts.outlineColor or theme.colors.text_shadow
    self.outlineWidth = opts.outlineWidth or 1
    
    -- Shadow
    self.shadow = opts.shadow or false
    self.shadowColor = opts.shadowColor or {0, 0, 0, 0.6}
    self.shadowOffset = opts.shadowOffset or 1
    
    -- Typing animation
    self.typing = false
    self.typingSpeed = opts.typingSpeed or 30  -- Characters per second
    self.typingProgress = 0
    self.typingCallback = nil
    
    -- Auto-size to text if no size specified
    if self.w == 0 and self.text ~= "" then
        self.w = self:measureWidth()
    end
    if self.h == 0 then
        self.h = self:measureHeight()
    end
    
    return self
end

-------------------------------------------
-- Update
-------------------------------------------

function Text:update(dt)
    Widget.update(self, dt)
    
    -- Update typing animation
    if self.typing then
        self.typingProgress = self.typingProgress + dt * self.typingSpeed
        local charCount = math.floor(self.typingProgress)
        
        if charCount >= #self.text then
            self.displayText = self.text
            self.typing = false
            if self.typingCallback then
                self.typingCallback(self)
                self.typingCallback = nil
            end
        else
            self.displayText = string.sub(self.text, 1, charCount)
        end
    end
end

-------------------------------------------
-- Drawing
-------------------------------------------

function Text:drawSelf()
    if self.displayText == "" then return end
    
    local gx, gy = self:getGlobalPosition()
    local w = self.w > 0 and self.w or nil
    
    local prevFont = love.graphics.getFont()
    if self.font then
        love.graphics.setFont(self.font)
    end
    
    local text = self.displayText
    
    -- Draw shadow
    if self.shadow then
        theme.setColor(self.shadowColor)
        local ox, oy = self.shadowOffset, self.shadowOffset
        if w then
            love.graphics.printf(text, gx + ox, gy + oy, w, self.align)
        else
            love.graphics.print(text, gx + ox, gy + oy)
        end
    end
    
    -- Draw outline
    if self.outline then
        theme.setColor(self.outlineColor)
        local ow = self.outlineWidth
        local offsets = {
            {-ow, 0}, {ow, 0}, {0, -ow}, {0, ow},
            {-ow, -ow}, {-ow, ow}, {ow, -ow}, {ow, ow}
        }
        for _, o in ipairs(offsets) do
            if w then
                love.graphics.printf(text, gx + o[1], gy + o[2], w, self.align)
            else
                love.graphics.print(text, gx + o[1], gy + o[2])
            end
        end
    end
    
    -- Draw main text
    theme.setColor(self.color)
    if w then
        love.graphics.printf(text, gx, gy, w, self.align)
    else
        love.graphics.print(text, gx, gy)
    end
    
    -- Draw typing cursor
    if self.typing and math.floor(love.timer.getTime() * 2) % 2 == 0 then
        local cursorX = gx + self:measurePartialWidth(self.displayText)
        love.graphics.setColor(self.color[1], self.color[2], self.color[3], 0.8)
        love.graphics.rectangle('fill', cursorX + 1, gy, 2, self:measureHeight())
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    
    if self.font then
        love.graphics.setFont(prevFont)
    end
end

-------------------------------------------
-- Measurement
-------------------------------------------

function Text:measureWidth(text)
    text = text or self.text
    local font = self.font or love.graphics.getFont()
    return font:getWidth(text)
end

function Text:measurePartialWidth(text)
    local font = self.font or love.graphics.getFont()
    return font:getWidth(text)
end

function Text:measureHeight()
    local font = self.font or love.graphics.getFont()
    return font:getHeight()
end

function Text:getWrappedHeight(width)
    local font = self.font or love.graphics.getFont()
    local _, lines = font:getWrap(self.text, width)
    return #lines * font:getHeight()
end

-------------------------------------------
-- Content Methods
-------------------------------------------

function Text:setText(text, instant)
    self.text = text or ""
    if instant or not self.typing then
        self.displayText = self.text
    end
    return self
end

function Text:append(text)
    self.text = self.text .. (text or "")
    if not self.typing then
        self.displayText = self.text
    end
    return self
end

-------------------------------------------
-- Style Methods
-------------------------------------------

function Text:setColor(color)
    self.color = color
    return self
end

function Text:setAlign(align)
    self.align = align
    return self
end

function Text:setFont(font)
    self.font = font
    return self
end

function Text:setOutline(enabled, color, width)
    self.outline = enabled
    if color then self.outlineColor = color end
    if width then self.outlineWidth = width end
    return self
end

function Text:setShadow(enabled, color, offset)
    self.shadow = enabled
    if color then self.shadowColor = color end
    if offset then self.shadowOffset = offset end
    return self
end

-------------------------------------------
-- Typing Animation
-------------------------------------------

function Text:startTyping(speed, callback)
    self.typing = true
    self.typingProgress = 0
    self.displayText = ""
    if speed then self.typingSpeed = speed end
    self.typingCallback = callback
    return self
end

function Text:skipTyping()
    if self.typing then
        self.typing = false
        self.displayText = self.text
        if self.typingCallback then
            self.typingCallback(self)
            self.typingCallback = nil
        end
    end
    return self
end

function Text:isTyping()
    return self.typing
end

return Text
