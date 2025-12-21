-- UI Module Entry Point
-- Combines all UI components into a single module

local ui = {}

-- Core modules
ui.scaling = require('ui.scaling')
ui.theme = require('ui.theme')
ui.core = require('ui.core')

-- Widgets
ui.Widget = require('ui.widgets.widget')
ui.Panel = require('ui.widgets.panel')
ui.Button = require('ui.widgets.button')
ui.Bar = require('ui.widgets.bar')
ui.Slot = require('ui.widgets.slot')
ui.Text = require('ui.widgets.text')
ui.Tooltip = require('ui.widgets.tooltip')
ui.ScrollContainer = require('ui.widgets.scroll_container')

-------------------------------------------
-- Convenience Functions
-------------------------------------------


--- Initialize the UI system
function ui.init()
    ui.core.init()
end

--- Update all UI components
---@param dt number Delta time
function ui.update(dt)
    ui.core.update(dt)
end

--- Draw all UI components
function ui.draw()
    ui.core.draw()
end

--- Draw emissive UI highlights only
function ui.drawEmissive()
    if ui.core.drawEmissive then
        ui.core.drawEmissive()
    end
end

--- Set the root widget
---@param widget table Root widget
function ui.setRoot(widget)
    ui.core.setRoot(widget)
end

--- Get the root widget
---@return table|nil Root widget
function ui.getRoot()
    return ui.core.getRoot()
end

--- Handle window resize
---@param w number New width
---@param h number New height
function ui.resize(w, h)
    ui.core.resize(w, h)
end

-------------------------------------------
-- Input Forwarding
-------------------------------------------

--- Forward mouse moved event
---@return boolean consumed Whether UI consumed the event
function ui.mousemoved(x, y, dx, dy)
    return ui.core.mousemoved(x, y, dx, dy)
end

--- Forward mouse pressed event
---@return boolean consumed Whether UI consumed the event
function ui.mousepressed(x, y, button)
    return ui.core.mousepressed(x, y, button)
end

--- Forward mouse released event
---@return boolean consumed Whether UI consumed the event
function ui.mousereleased(x, y, button)
    return ui.core.mousereleased(x, y, button)
end

--- Forward key pressed event
---@return boolean consumed Whether UI consumed the event
function ui.keypressed(key, scancode, isrepeat)
    return ui.core.keypressed(key, scancode, isrepeat)
end

--- Forward text input event
function ui.textinput(text)
    return ui.core.textinput(text)
end

--- Forward mouse wheel event
function ui.wheelmoved(x, y)
    return ui.core.wheelmoved(x, y)
end


-------------------------------------------
-- Utility Constructors
-------------------------------------------

--- Create a new Panel
---@param opts table Options
---@return table Panel widget
function ui.newPanel(opts)
    return ui.Panel.new(opts)
end

--- Create a new Button
---@param opts table Options
---@return table Button widget
function ui.newButton(opts)
    return ui.Button.new(opts)
end

--- Create a new Bar
---@param opts table Options
---@return table Bar widget
function ui.newBar(opts)
    return ui.Bar.new(opts)
end

--- Create a new Slot
---@param opts table Options
---@return table Slot widget
function ui.newSlot(opts)
    return ui.Slot.new(opts)
end

--- Create a new Text
---@param opts table Options
---@return table Text widget
function ui.newText(opts)
    return ui.Text.new(opts)
end

--- Create a new Tooltip
---@param opts table Options
---@return table Tooltip widget
function ui.newTooltip(opts)
    return ui.Tooltip.new(opts)
end

--- Create a new ScrollContainer
---@param opts table Options
---@return table ScrollContainer widget
function ui.newScrollContainer(opts)
    return ui.ScrollContainer.new(opts)
end


-------------------------------------------
-- Layout Helpers
-------------------------------------------

--- Create a horizontal row of widgets
---@param widgets table Array of widgets
---@param spacing number Space between widgets
---@param x number Starting X position
---@param y number Y position
function ui.layoutRow(widgets, spacing, x, y)
    spacing = spacing or ui.theme.sizes.padding_normal
    local currentX = x or 0
    
    for _, widget in ipairs(widgets) do
        widget.x = currentX
        widget.y = y or 0
        currentX = currentX + widget.w + spacing
    end
end

--- Create a vertical column of widgets
---@param widgets table Array of widgets
---@param spacing number Space between widgets
---@param x number X position
---@param y number Starting Y position
function ui.layoutColumn(widgets, spacing, x, y)
    spacing = spacing or ui.theme.sizes.padding_normal
    local currentY = y or 0
    
    for _, widget in ipairs(widgets) do
        widget.x = x or 0
        widget.y = currentY
        currentY = currentY + widget.h + spacing
    end
end

--- Create a grid of widgets
---@param widgets table Array of widgets
---@param cols number Number of columns
---@param cellW number Cell width
---@param cellH number Cell height
---@param x number Starting X
---@param y number Starting Y
---@param spacing number Space between cells
function ui.layoutGrid(widgets, cols, cellW, cellH, x, y, spacing)
    spacing = spacing or ui.theme.sizes.padding_normal
    x = x or 0
    y = y or 0
    
    for i, widget in ipairs(widgets) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        widget.x = x + col * (cellW + spacing)
        widget.y = y + row * (cellH + spacing)
    end
end

-------------------------------------------
-- Drag and Drop
-------------------------------------------

--- Check if currently dragging
---@return boolean
function ui.isDragging()
    return ui.core.isDragging()
end

--- Get current drag data
---@return table|nil
function ui.getDragData()
    return ui.core.getDragData()
end

--- Cancel current drag operation
function ui.cancelDrag()
    ui.core.cancelDrag()
end

--- Set custom drag preview renderer
---@param fn function(dragData, x, y, sourceWidget)
function ui.setDragPreview(fn)
    ui.core.setDragPreview(fn)
end

return ui
