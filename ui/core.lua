-- UI Core module
-- Central event dispatcher and widget management

local scaling = require('ui.scaling')
local theme = require('ui.theme')

local core = {}

-------------------------------------------
-- State
-------------------------------------------
core.root = nil           -- Root container widget
core.hover = nil          -- Currently hovered widget
core.focus = nil          -- Currently focused widget (keyboard)
core.pressed = nil        -- Currently pressed widget
core.time = 0             -- Global timer for animations
core.enabled = true       -- Whether UI system is active
core.tooltipWidget = nil  -- Current tooltip to display
core.tooltipTimer = 0     -- Timer for tooltip delay

-- Input state
core.mouseX = 0
core.mouseY = 0
core.mousePressed = {false, false, false}  -- Left, right, middle

-------------------------------------------
-- Initialization
-------------------------------------------

function core.init()
    scaling.recalculate()
    core.time = 0
    core.hover = nil
    core.focus = nil
    core.pressed = nil
end

-------------------------------------------
-- Widget Registry (for easy access)
-------------------------------------------
local widgets = {}

function core.register(id, widget)
    widgets[id] = widget
end

function core.unregister(id)
    widgets[id] = nil
end

function core.get(id)
    return widgets[id]
end

-------------------------------------------
-- Focus Management
-------------------------------------------

function core.setFocus(widget)
    if core.focus == widget then return end
    
    local oldFocus = core.focus
    core.focus = widget
    
    if oldFocus and oldFocus.onBlur then
        oldFocus:onBlur()
    end
    if widget and widget.onFocus then
        widget:onFocus()
    end
end

function core.clearFocus()
    core.setFocus(nil)
end

-------------------------------------------
-- Hit Testing
-------------------------------------------

local function hitTest(widget, x, y)
    if not widget or not widget.visible or not widget.enabled then
        return nil
    end
    
    -- Check children first (reverse order for proper z-order)
    if widget.children then
        for i = #widget.children, 1, -1 do
            local child = widget.children[i]
            local hit = hitTest(child, x, y)
            if hit then return hit end
        end
    end
    
    -- Check self
    if widget.contains and widget:contains(x, y) then
        return widget
    end
    
    return nil
end

-------------------------------------------
-- Update
-------------------------------------------

function core.update(dt)
    if not core.enabled then return end
    
    core.time = core.time + dt
    
    -- Update mouse position
    core.mouseX, core.mouseY = scaling.getMousePosition()
    
    -- Update hover state
    local newHover = nil
    if core.root then
        newHover = hitTest(core.root, core.mouseX, core.mouseY)
    end
    
    if newHover ~= core.hover then
        -- Hover changed
        if core.hover and core.hover.onHoverEnd then
            core.hover:onHoverEnd()
        end
        core.hover = newHover
        if core.hover and core.hover.onHoverStart then
            core.hover:onHoverStart()
        end
        
        -- Reset tooltip timer
        core.tooltipTimer = 0
        core.tooltipWidget = nil
    else
        -- Same hover, update tooltip timer
        if core.hover and core.hover.tooltip then
            core.tooltipTimer = core.tooltipTimer + dt
            if core.tooltipTimer >= theme.animation.tooltip_delay then
                core.tooltipWidget = core.hover
            end
        end
    end
    
    -- Update widget tree
    if core.root then
        core.root:update(dt)
    end
end

-------------------------------------------
-- Drawing
-------------------------------------------

function core.draw()
    if not core.enabled then return end
    if not core.root then return end
    
    -- Draw letterbox bars first
    scaling.drawLetterbox()
    
    -- Push scaling transform
    scaling.push()
    
    -- Draw widget tree
    core.root:draw()
    
    -- Draw tooltip on top
    if core.tooltipWidget and core.tooltipWidget.tooltip then
        core.drawTooltip(core.tooltipWidget.tooltip, core.mouseX, core.mouseY)
    end
    
    -- Pop scaling transform
    scaling.pop()
end

function core.drawTooltip(text, x, y)
    if not text or text == "" then return end
    
    local font = love.graphics.getFont()
    local padding = theme.sizes.padding_normal
    local maxWidth = theme.sizes.tooltip_max_width
    
    -- Measure text
    local _, lines = font:getWrap(text, maxWidth - padding * 2)
    local lineHeight = font:getHeight()
    local textHeight = #lines * lineHeight
    
    local w = maxWidth
    local h = textHeight + padding * 2
    
    -- Position tooltip (avoid edges)
    local tx = x + 12
    local ty = y + 12
    
    if tx + w > scaling.LOGICAL_WIDTH - 4 then
        tx = x - w - 4
    end
    if ty + h > scaling.LOGICAL_HEIGHT - 4 then
        ty = y - h - 4
    end
    tx = math.max(4, tx)
    ty = math.max(4, ty)
    
    -- Draw background
    theme.setColor(theme.colors.tooltip_bg)
    love.graphics.rectangle('fill', tx, ty, w, h)
    
    -- Draw border
    theme.setColor(theme.colors.tooltip_border)
    love.graphics.rectangle('line', tx, ty, w, h)
    
    -- Draw text
    theme.setColor(theme.colors.text)
    love.graphics.printf(text, tx + padding, ty + padding, maxWidth - padding * 2, 'left')
    
    love.graphics.setColor(1, 1, 1, 1)
end

-------------------------------------------
-- Input Handlers
-------------------------------------------

function core.mousemoved(x, y, dx, dy)
    if not core.enabled then return false end
    
    -- Position is already tracked in update()
    -- This is called for any additional move handling
    
    if core.pressed and core.pressed.onDrag then
        local lx, ly = scaling.toLogical(x, y)
        local ldx, ldy = dx / scaling.getScale(), dy / scaling.getScale()
        core.pressed:onDrag(lx, ly, ldx, ldy)
        return true
    end
    
    return false
end

function core.mousepressed(x, y, button)
    if not core.enabled then return false end
    
    local lx, ly = scaling.toLogical(x, y)
    
    -- Check if click is within UI bounds
    if not scaling.inBounds(lx, ly) then
        return false
    end
    
    core.mousePressed[button] = true
    
    -- Hit test
    local widget = nil
    if core.root then
        widget = hitTest(core.root, lx, ly)
    end
    
    if widget then
        core.pressed = widget
        core.setFocus(widget)
        
        if widget.onPress then
            widget:onPress(button, lx, ly)
        end
        
        return true
    else
        core.clearFocus()
    end
    
    return false
end

function core.mousereleased(x, y, button)
    if not core.enabled then return false end
    
    local lx, ly = scaling.toLogical(x, y)
    core.mousePressed[button] = false
    
    local wasPressed = core.pressed
    core.pressed = nil
    
    if wasPressed then
        if wasPressed.onRelease then
            wasPressed:onRelease(button, lx, ly)
        end
        
        -- Check if release was on same widget (click)
        if wasPressed.contains and wasPressed:contains(lx, ly) then
            if button == 1 and wasPressed.onClick then
                wasPressed:onClick(lx, ly)
            elseif button == 2 and wasPressed.onRightClick then
                wasPressed:onRightClick(lx, ly)
            end
        end
        
        return true
    end
    
    return false
end

function core.keypressed(key, scancode, isrepeat)
    if not core.enabled then return false end
    
    -- Tab navigation
    if key == 'tab' then
        core.focusNext(love.keyboard.isDown('lshift', 'rshift'))
        return true
    end
    
    -- Escape to clear focus
    if key == 'escape' then
        if core.focus then
            core.clearFocus()
            return true
        end
    end
    
    -- Enter/Space to activate focused widget
    if (key == 'return' or key == 'space') and core.focus then
        if core.focus.onActivate then
            core.focus:onActivate()
            return true
        elseif core.focus.onClick then
            core.focus:onClick(0, 0)
            return true
        end
    end
    
    -- Arrow key navigation
    if key == 'up' or key == 'down' or key == 'left' or key == 'right' then
        if core.focus and core.focus.onArrowKey then
            return core.focus:onArrowKey(key)
        end
    end
    
    -- Pass to focused widget
    if core.focus and core.focus.onKeyPressed then
        return core.focus:onKeyPressed(key, scancode, isrepeat)
    end
    
    return false
end

function core.textinput(text)
    if not core.enabled then return false end
    
    if core.focus and core.focus.onTextInput then
        return core.focus:onTextInput(text)
    end
    
    return false
end

-------------------------------------------
-- Focus Navigation
-------------------------------------------

local function collectFocusable(widget, list)
    if not widget or not widget.visible or not widget.enabled then
        return
    end
    
    if widget.focusable then
        table.insert(list, widget)
    end
    
    if widget.children then
        for _, child in ipairs(widget.children) do
            collectFocusable(child, list)
        end
    end
end

function core.focusNext(reverse)
    if not core.root then return end
    
    local focusable = {}
    collectFocusable(core.root, focusable)
    
    if #focusable == 0 then return end
    
    local currentIdx = 0
    for i, w in ipairs(focusable) do
        if w == core.focus then
            currentIdx = i
            break
        end
    end
    
    local nextIdx
    if reverse then
        nextIdx = currentIdx - 1
        if nextIdx < 1 then nextIdx = #focusable end
    else
        nextIdx = currentIdx + 1
        if nextIdx > #focusable then nextIdx = 1 end
    end
    
    core.setFocus(focusable[nextIdx])
end

-------------------------------------------
-- Utility
-------------------------------------------

function core.setRoot(widget)
    core.root = widget
end

function core.getRoot()
    return core.root
end

function core.isHovered(widget)
    return core.hover == widget
end

function core.isFocused(widget)
    return core.focus == widget
end

function core.isPressed(widget)
    return core.pressed == widget
end

function core.getTime()
    return core.time
end

-- Called on window resize
function core.resize(w, h)
    scaling.recalculate()
end

return core
