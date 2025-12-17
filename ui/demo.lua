-- UI Demo module
-- Press F8 to toggle UI demo overlay
-- Demonstrates all UI widgets

local ui = require('ui')
local theme = ui.theme

local demo = {}
local demoRoot = nil
local demoEnabled = false

-------------------------------------------
-- Demo Setup
-------------------------------------------

local function createDemo()
    -- Root container
    local root = ui.Widget.new({x = 0, y = 0, w = 640, h = 360})
    root.visible = true
    root.enabled = true
    
    -- Semi-transparent backdrop
    local backdrop = ui.Panel.new({
        x = 0, y = 0, w = 640, h = 360,
        bgColor = {0.05, 0.05, 0.08, 0.85}
    })
    root:addChild(backdrop)
    
    -- Title
    local title = ui.Text.new({
        x = 0, y = 20, w = 640,
        text = "UI SYSTEM DEMO",
        color = theme.colors.accent,
        align = 'center',
        outline = true,
        outlineColor = {0, 0, 0, 0.8}
    })
    root:addChild(title)
    
    local subtitle = ui.Text.new({
        x = 0, y = 40, w = 640,
        text = "F8 to close | Tab to navigate | Drag slots to swap items",
        color = theme.colors.text_dim,
        align = 'center'
    })
    root:addChild(subtitle)
    
    -- === Left Column: Buttons ===
    local colX = 40
    local colY = 80
    
    local btnLabel = ui.Text.new({
        x = colX, y = colY,
        text = "Buttons:",
        color = theme.colors.text
    })
    root:addChild(btnLabel)
    colY = colY + 20
    
    local btn1 = ui.Button.new({
        x = colX, y = colY, w = 100, h = 24,
        text = "Normal",
        tooltip = "This is a normal button"
    })
    btn1:on('click', function()
        print("Button 1 clicked!")
    end)
    root:addChild(btn1)
    colY = colY + 30
    
    local btn2 = ui.Button.new({
        x = colX, y = colY, w = 100, h = 24,
        text = "With Icon",
        icon = true,
        iconColor = theme.colors.success,
        tooltip = "Button with icon placeholder"
    })
    root:addChild(btn2)
    colY = colY + 30
    
    local btn3 = ui.Button.new({
        x = colX, y = colY, w = 100, h = 24,
        text = "Disabled",
        enabled = false
    })
    root:addChild(btn3)
    colY = colY + 30
    
    local btn4 = ui.Button.new({
        x = colX, y = colY, w = 100, h = 24,
        text = "Danger",
        normalColor = theme.colors.danger,
        hoverColor = theme.lighten(theme.colors.danger, 0.1),
        tooltip = "A dangerous action!"
    })
    root:addChild(btn4)
    
    -- === Middle Column: Bars ===
    colX = 180
    colY = 80
    
    local barLabel = ui.Text.new({
        x = colX, y = colY,
        text = "Bars:",
        color = theme.colors.text
    })
    root:addChild(barLabel)
    colY = colY + 20
    
    -- HP Bar
    local hpBar = ui.Bar.new({
        x = colX, y = colY, w = 140, h = 12,
        value = 75, maxValue = 100,
        bgColor = theme.colors.hp_bg,
        fillColor = theme.colors.hp_fill,
        lowColor = theme.colors.danger,
        lowThreshold = 0.25,
        showText = true,
        textFormat = 'both',
        cornerRadius = 2
    })
    root:addChild(hpBar)
    colY = colY + 22
    
    -- Energy Bar
    local energyBar = ui.Bar.new({
        x = colX, y = colY, w = 140, h = 8,
        value = 60, maxValue = 100,
        bgColor = theme.colors.energy_bg,
        fillColor = theme.colors.energy_fill,
        showText = true,
        textFormat = 'percent'
    })
    root:addChild(energyBar)
    colY = colY + 18
    
    -- XP Bar
    local xpBar = ui.Bar.new({
        x = colX, y = colY, w = 140, h = 6,
        value = 45, maxValue = 100,
        bgColor = theme.colors.xp_bg,
        fillColor = theme.colors.xp_fill
    })
    root:addChild(xpBar)
    colY = colY + 18
    
    -- Ammo Bar (segmented)
    local ammoBar = ui.Bar.new({
        x = colX, y = colY, w = 140, h = 10,
        value = 8, maxValue = 12,
        bgColor = theme.colors.ammo_bg,
        fillColor = theme.colors.ammo_fill,
        segments = 12,
        segmentGap = 2
    })
    root:addChild(ammoBar)
    colY = colY + 24
    
    -- Bar control buttons
    local damageBtn = ui.Button.new({
        x = colX, y = colY, w = 68, h = 20,
        text = "-20 HP"
    })
    damageBtn:on('click', function()
        hpBar:setValue(hpBar:getValue() - 20)
        hpBar:flash(theme.colors.danger)
    end)
    root:addChild(damageBtn)
    
    local healBtn = ui.Button.new({
        x = colX + 72, y = colY, w = 68, h = 20,
        text = "+20 HP"
    })
    healBtn:on('click', function()
        hpBar:setValue(hpBar:getValue() + 20)
        hpBar:flash(theme.colors.success)
    end)
    root:addChild(healBtn)
    
    -- === Right Column: Slots (with Drag & Drop) ===
    colX = 360
    colY = 80
    
    local slotLabel = ui.Text.new({
        x = colX, y = colY,
        text = "Slots (drag to swap):",
        color = theme.colors.text
    })
    root:addChild(slotLabel)
    colY = colY + 20
    
    local selectedSlot = nil
    local slots = {}
    
    -- First row of draggable slots
    local slotColors = {theme.colors.accent, theme.colors.warning, theme.colors.success, theme.colors.danger}
    for i = 1, 4 do
        local slot = ui.Slot.new({
            x = colX + (i - 1) * 40, y = colY,
            w = 36, h = 36,
            content = (i <= 2) and ("item" .. i) or nil,
            iconColor = slotColors[i],
            tooltip = (i <= 2) and ("Slot " .. i .. " - Drag me!") or ("Slot " .. i .. " - Drop here"),
            sublabel = (i == 1) and "Lv3" or ((i == 2) and "Lv1" or nil)
        })
        slot:on('click', function(self)
            if selectedSlot then selectedSlot:setSelected(false) end
            self:setSelected(true)
            selectedSlot = self
            print("Slot " .. i .. " clicked")
        end)
        slot:on('drop', function(self, dragData, source)
            print("Dropped " .. tostring(dragData.content) .. " onto slot " .. i)
        end)
        root:addChild(slot)
        table.insert(slots, slot)
    end
    colY = colY + 42
    
    -- Second row of slots
    for i = 5, 8 do
        local slot = ui.Slot.new({
            x = colX + (i - 5) * 40, y = colY,
            w = 36, h = 36,
            content = (i == 5) and "item5" or nil,
            iconColor = (i == 5) and {0.8, 0.5, 0.9, 1} or slotColors[(i-4)],
            tooltip = "Slot " .. i
        })
        slot:on('drop', function(self, dragData, source)
            print("Dropped " .. tostring(dragData.content) .. " onto slot " .. i)
        end)
        root:addChild(slot)
        table.insert(slots, slot)
    end
    colY = colY + 50
    
    -- Locked slot
    local lockedSlot = ui.Slot.new({
        x = colX, y = colY,
        w = 36, h = 36,
        locked = true,
        tooltip = "This slot is locked"
    })
    root:addChild(lockedSlot)
    
    -- === Bottom: Panels ===
    colX = 40
    colY = 250
    
    local panelLabel = ui.Text.new({
        x = colX, y = colY,
        text = "Panels:",
        color = theme.colors.text
    })
    root:addChild(panelLabel)
    colY = colY + 20
    
    local panel1 = ui.Panel.new({
        x = colX, y = colY, w = 100, h = 60,
        bgColor = theme.colors.panel_bg,
        borderColor = theme.colors.panel_border,
        borderWidth = 1,
        cornerRadius = 4
    })
    root:addChild(panel1)
    
    local panel2 = ui.Panel.new({
        x = colX + 110, y = colY, w = 100, h = 60,
        bgColor = theme.colors.panel_bg_light,
        shadow = true,
        shadowOffset = 3,
        cornerRadius = 4
    })
    root:addChild(panel2)
    
    -- === Text with typing animation ===
    colX = 360
    colY = 250
    
    local typingText = ui.Text.new({
        x = colX, y = colY, w = 240,
        text = "This text types out character by character...",
        color = theme.colors.text,
        outline = true
    })
    typingText:startTyping(25)
    root:addChild(typingText)
    
    local retypeBtn = ui.Button.new({
        x = colX, y = colY + 30, w = 80, h = 20,
        text = "Retype"
    })
    retypeBtn:on('click', function()
        typingText:startTyping(25)
    end)
    root:addChild(retypeBtn)
    
    return root
end

-------------------------------------------
-- Public API
-------------------------------------------

function demo.init()
    demoRoot = nil
    demoEnabled = false
end

function demo.toggle()
    demoEnabled = not demoEnabled
    
    if demoEnabled then
        if not demoRoot then
            demoRoot = createDemo()
        end
        demoRoot.visible = true
        ui.core.setRoot(demoRoot)
        ui.core.enabled = true
    else
        ui.core.setRoot(nil)
        ui.core.enabled = false
    end
    
    return demoEnabled
end

function demo.isEnabled()
    return demoEnabled
end

function demo.keypressed(key)
    if key == 'f8' then
        demo.toggle()
        return true
    end
    return false
end

return demo
