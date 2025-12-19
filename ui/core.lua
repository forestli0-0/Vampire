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

-- Drag state
core.dragging = nil        -- Currently dragged widget
core.dragData = nil        -- Data being dragged (from source widget)
core.dragStartX = 0        -- Where drag started
core.dragStartY = 0
core.dragOffsetX = 0       -- Offset from widget origin to grab point
core.dragOffsetY = 0
core.dragThreshold = 4     -- Pixels to move before drag starts
core.dragPending = nil     -- Widget that might start dragging
core.dropTarget = nil      -- Current valid drop target
core.dragPreview = nil     -- Custom drag preview function

-------------------------------------------
-- Initialization
-------------------------------------------

function core.init()
    scaling.recalculate()
    -- Load fonts
    theme.loadFonts()
    
    core.time = 0
    core.hover = nil
    core.focus = nil
    core.pressed = nil
    core.dragging = nil
    core.dragData = nil
    core.dragPending = nil
    core.dropTarget = nil
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
    if widget and not widget.focusable then return end
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
    if core.tooltipWidget and core.tooltipWidget.tooltip and not core.dragging then
        core.drawTooltip(core.tooltipWidget.tooltip, core.mouseX, core.mouseY)
    end
    
    -- Draw drag preview on top of everything
    if core.dragging then
        core.drawDragPreview()
    end
    
    -- Pop scaling transform
    scaling.pop()
end

function core.drawDragPreview()
    if not core.dragging then return end
    
    local x = core.mouseX - core.dragOffsetX
    local y = core.mouseY - core.dragOffsetY
    
    -- Use custom preview if provided
    if core.dragPreview then
        core.dragPreview(core.dragData, x, y, core.dragging)
        return
    end
    
    -- Default preview: semi-transparent copy of widget
    love.graphics.push()
    love.graphics.translate(x - core.dragging.x, y - core.dragging.y)
    
    -- Draw with transparency
    love.graphics.setColor(1, 1, 1, 0.7)
    
    local gx, gy = core.dragging:getGlobalPosition()
    local w, h = core.dragging.w, core.dragging.h
    
    -- Draw ghost rectangle
    love.graphics.setColor(theme.colors.accent[1], theme.colors.accent[2], theme.colors.accent[3], 0.5)
    love.graphics.rectangle('fill', gx, gy, w, h, 2, 2)
    love.graphics.setColor(theme.colors.accent[1], theme.colors.accent[2], theme.colors.accent[3], 0.9)
    love.graphics.rectangle('line', gx, gy, w, h, 2, 2)
    
    -- Draw drag data label if available
    if core.dragData and type(core.dragData) == 'table' and core.dragData.label then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf(core.dragData.label, gx, gy + h/2 - 7, w, 'center')
    end
    
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

function core.drawTooltip(text, x, y)
    if not text or text == "" then return end
    
    -- Save current font to restore later (prevents font state pollution)
    local prevFont = love.graphics.getFont()
    
    -- Use theme font to ensure Chinese support
    local font = theme.getFont('normal') or prevFont
    love.graphics.setFont(font)
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
    
    -- Restore previous font
    if prevFont then
        love.graphics.setFont(prevFont)
    end
end

-------------------------------------------
-- Input Handlers
-------------------------------------------

function core.mousemoved(x, y, dx, dy)
    if not core.enabled then return false end
    
    -- Handle nil dx/dy (can happen when called without delta values)
    dx = dx or 0
    dy = dy or 0
    
    local lx, ly = scaling.toLogical(x, y)
    local ldx, ldy = dx / scaling.getScale(), dy / scaling.getScale()
    
    -- Check if we should start dragging (pending drag + threshold)
    if core.dragPending and not core.dragging then
        local distX = math.abs(lx - core.dragStartX)
        local distY = math.abs(ly - core.dragStartY)
        if distX > core.dragThreshold or distY > core.dragThreshold then
            core.startDrag(core.dragPending, lx, ly)
        end
    end
    
    -- Update drag
    if core.dragging then
        -- Find drop target
        local newDropTarget = core.findDropTarget(lx, ly)
        
        if newDropTarget ~= core.dropTarget then
            -- Drop target changed
            if core.dropTarget and core.dropTarget.onDragLeave then
                core.dropTarget:onDragLeave(core.dragData, core.dragging)
            end
            core.dropTarget = newDropTarget
            if core.dropTarget and core.dropTarget.onDragEnter then
                core.dropTarget:onDragEnter(core.dragData, core.dragging)
            end
        end
        
        -- Notify dragging widget
        if core.dragging.onDragMove then
            core.dragging:onDragMove(lx, ly, ldx, ldy)
        end
        
        return true
    end
    
    -- Regular drag (widget that handles onDrag)
    if core.pressed and core.pressed.onDrag then
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
        
        -- Check if widget is draggable
        if button == 1 and widget.draggable then
            core.dragPending = widget
            core.dragStartX = lx
            core.dragStartY = ly
            -- Calculate offset from widget origin
            local gx, gy = widget:getGlobalPosition()
            core.dragOffsetX = lx - gx
            core.dragOffsetY = ly - gy
        end
        
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
    
    -- Handle drag drop
    if core.dragging and button == 1 then
        local dropped = false
        local dragSource = core.dragging -- Cache locally in case setRoot clears global state
        
        if core.dropTarget then
            -- Notify drop target
            if core.dropTarget.onDrop then
                dropped = core.dropTarget:onDrop(core.dragData, dragSource, lx, ly)
            end
            if core.dropTarget and core.dropTarget.onDragLeave then
                core.dropTarget:onDragLeave(core.dragData, dragSource)
            end
        end
        
        -- Notify source widget
        if dragSource and dragSource.onDragEnd then
            dragSource:onDragEnd(dropped, core.dropTarget, lx, ly)
        end
        
        -- Clear drag state
        core.dragging = nil
        core.dragData = nil
        core.dragPending = nil
        core.dropTarget = nil
        core.dragPreview = nil
        
        return true
    end
    
    -- Clear pending drag
    core.dragPending = nil
    
    local wasPressed = core.pressed
    core.pressed = nil
    
    if wasPressed then
        if wasPressed.onRelease then
            wasPressed:onRelease(button, lx, ly)
        end
        
        -- Check if release was on same widget (click) - only if not dragging
        if not core.dragging and wasPressed.contains and wasPressed:contains(lx, ly) then
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
    
    local function isDescendant(root, widget)
        local curr = widget
        while curr do
            if curr == root then return true end
            curr = curr.parent
        end
        return false
    end
    
    -- Enter/Space to activate focused widget
    if (key == 'return' or key == 'space') and core.focus then
        -- Validate focus is still active in current hierarchy
        if core.root and not isDescendant(core.root, core.focus) then
            core.focus = nil
            return false
        end
        
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

-------------------------------------------
-- Drag and Drop
-------------------------------------------

--- Start dragging a widget
---@param widget table The widget to drag
---@param x number Logical X position
---@param y number Logical Y position
function core.startDrag(widget, x, y)
    if not widget then return end
    if core.dragging then return end  -- Already dragging
    
    -- Get drag data from widget
    local dragData = nil
    if widget.getDragData then
        dragData = widget:getDragData()
    else
        dragData = widget.dragData or {source = widget}
    end
    
    if dragData == false then
        -- Widget refused to start drag
        core.dragPending = nil
        return
    end
    
    core.dragging = widget
    core.dragData = dragData
    core.dragPending = nil
    
    -- Hide tooltip while dragging
    core.tooltipWidget = nil
    core.tooltipTimer = 0
    
    -- Notify widget
    if widget.onDragStart then
        widget:onDragStart(dragData, x, y)
    end
    
    -- Emit event
    widget:emit('dragStart', dragData, x, y)
end

--- Find a valid drop target at position
---@param x number Logical X
---@param y number Logical Y
---@return table|nil Drop target widget or nil
function core.findDropTarget(x, y)
    if not core.root then return nil end
    if not core.dragging then return nil end
    
    local function findDroppable(widget)
        if not widget or not widget.visible or not widget.enabled then
            return nil
        end
        
        -- Check children first (reverse order)
        if widget.children then
            for i = #widget.children, 1, -1 do
                local child = widget.children[i]
                local found = findDroppable(child)
                if found then return found end
            end
        end
        
        -- Check self - must be different from source and accept drops
        if widget ~= core.dragging and widget.acceptDrop and widget:contains(x, y) then
            -- Check if widget accepts this drag data
            local accepts = true
            if widget.canAcceptDrop then
                accepts = widget:canAcceptDrop(core.dragData, core.dragging)
            end
            if accepts then
                return widget
            end
        end
        
        return nil
    end
    
    return findDroppable(core.root)
end

--- Cancel current drag operation
function core.cancelDrag()
    if not core.dragging then return end
    
    -- Notify source
    if core.dragging.onDragEnd then
        core.dragging:onDragEnd(false, nil, core.mouseX, core.mouseY)
    end
    
    -- Clear state
    core.dragging = nil
    core.dragData = nil
    core.dragPending = nil
    core.dropTarget = nil
    core.dragPreview = nil
end

--- Check if currently dragging
---@return boolean
function core.isDragging()
    return core.dragging ~= nil
end

--- Get current drag data
---@return table|nil
function core.getDragData()
    return core.dragData
end

--- Set custom drag preview renderer
---@param fn function(dragData, x, y, sourceWidget)
function core.setDragPreview(fn)
    core.dragPreview = fn
end

function core.setRoot(rootWidget)
    if core.root == rootWidget then return end
    
    -- Clear focus when switching root to prevent ghost inputs
    -- This is critical for preventing keyboard shortcuts from being consumed by destroyed widgets
    core.clearFocus()
    core.hover = nil
    core.pressed = nil
    core.dragging = nil
    core.tooltipWidget = nil  -- Clear tooltip to prevent ghost tooltips
    core.tooltipTimer = 0
    
    core.root = rootWidget
    
    -- Resize new root to fit screen if needed
    if rootWidget and rootWidget.w == 0 then
        rootWidget.w = love.graphics.getWidth() / scaling.getScale()
        rootWidget.h = love.graphics.getHeight() / scaling.getScale()
    end
end

return core
