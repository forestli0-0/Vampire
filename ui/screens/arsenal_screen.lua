-- Arsenal Screen
-- Warframe-style MOD configuration interface
-- Supports both keyboard navigation and mouse/drag-drop

local ui = require('ui')
local theme = ui.theme

local arsenalScreen = {}

-- Screen state
local root = nil
local state = nil  -- Game state reference

-- UI Elements
local weaponSlots = {}      -- 3 weapon slot buttons
local modSlots = {}         -- 8 MOD slots (2x4 grid)
local modCards = {}         -- MOD library cards
local statsPanel = nil
local capacityBar = nil
local selectedModCard = nil -- Currently selected MOD for keyboard nav
local scrollOffset = 0      -- MOD library scroll

-- Layout constants - TWO COLUMN DESIGN
-- Left column: weapon selector, stats, class/pet buttons
-- Right column: capacity, MOD grid, MOD library
local LAYOUT = {
    -- Screen
    screenW = 640,
    screenH = 360,
    titleY = 8,
    
    -- Left column (narrow)
    leftX = 12,
    leftW = 160,
    
    -- Right column (wide - for MODs)
    rightX = 180,
    rightW = 448,  -- 640 - 180 - 12
    
    -- MOD grid
    modSlotSize = 48,
    modSlotSpacing = 4,
    modGridCols = 4,
    modGridRows = 2,
    
    -- MOD library (in right column, below grid)
    libraryCardW = 68,
    libraryCardH = 70,
    libraryCardSpacing = 4,
    
    -- Colors
    panelBg = {0.08, 0.08, 0.12, 0.95},
    slotEmpty = {0.12, 0.12, 0.16, 0.9},
    slotFilled = {0.18, 0.22, 0.28, 0.95},
    capacityBg = {0.1, 0.1, 0.14, 0.9},
    capacityFill = {0.3, 0.7, 0.9, 1},
    capacityFull = {0.9, 0.3, 0.3, 1},
}

-------------------------------------------
-- Helper Functions
-------------------------------------------

local function getWeaponLoadout(gameState, weaponKey)
    local profile = gameState.profile
    if not profile then return nil end
    profile.weaponMods = profile.weaponMods or {}
    profile.weaponMods[weaponKey] = profile.weaponMods[weaponKey] or {equippedMods = {}, modOrder = {}}
    return profile.weaponMods[weaponKey]
end

local function getEquippedMods(gameState, weaponKey)
    local loadout = getWeaponLoadout(gameState, weaponKey)
    if not loadout then return {} end
    return loadout.modOrder or {}
end

local function getModDef(gameState, modKey)
    return gameState.catalog and gameState.catalog[modKey]
end

local function isModOwned(gameState, modKey)
    local profile = gameState.profile
    return profile and profile.ownedMods and profile.ownedMods[modKey]
end

local function isModEquipped(gameState, weaponKey, modKey)
    local loadout = getWeaponLoadout(gameState, weaponKey)
    return loadout and loadout.equippedMods and loadout.equippedMods[modKey]
end

local function getModRank(gameState, modKey)
    local profile = gameState.profile
    return (profile and profile.modRanks and profile.modRanks[modKey]) or 1
end

local function getCurrentWeaponKey(gameState)
    return (gameState.profile and gameState.profile.modTargetWeapon) or 'wand'
end

local function getWeaponDef(gameState, weaponKey)
    return gameState.catalog and gameState.catalog[weaponKey]
end

local function calculateCapacity(gameState, weaponKey)
    local loadout = getWeaponLoadout(gameState, weaponKey)
    if not loadout then return 0, 30 end
    
    local used = 0
    for modKey, equipped in pairs(loadout.equippedMods or {}) do
        if equipped then
            local def = getModDef(gameState, modKey)
            local cost = (def and def.cost) or 4
            local rank = getModRank(gameState, modKey)
            -- Warframe Mod Cost: Base + Rank (assuming rank 1 is base)
            -- If rank serves as 0-based level + 1, then rank-1 is the added cost
            used = used + cost + (rank - 1)
        end
    end
    
    local maxCapacity = 30  -- Base capacity
    return used, maxCapacity
end

-------------------------------------------
-- MOD Card Widget (for library)
-------------------------------------------

local ModCard = setmetatable({}, {__index = ui.Widget})
ModCard.__index = ModCard

function ModCard.new(opts)
    opts = opts or {}
    opts.focusable = true
    opts.draggable = true
    
    local self = setmetatable(ui.Widget.new(opts), ModCard)
    
    self.modKey = opts.modKey
    self.modDef = opts.modDef
    self.owned = opts.owned or false
    self.equipped = opts.equipped or false
    self.rank = opts.rank or 1
    self.maxRank = (opts.modDef and opts.modDef.maxLevel) or 1
    self.cost = (opts.modDef and opts.modDef.cost) or 4
    
    -- Visual
    self.hoverT = 0
    self.selectedT = 0
    self.selected = false
    
    -- Colors based on mod type/element
    self.baseColor = opts.color or {0.25, 0.35, 0.45, 1}
    
    self.w = opts.w or LAYOUT.libraryCardW
    self.h = opts.h or LAYOUT.libraryCardH
    
    return self
end

function ModCard:onActivate()
    if self.owned then
        -- Trigger equip action
        self:emit('activate_mod', self)
    end
end


function ModCard:update(dt)
    ui.Widget.update(self, dt)
    
    local targetHover = (self.hovered or self.focused) and 1 or 0
    self.hoverT = self.hoverT + (targetHover - self.hoverT) * math.min(1, dt * 12)
    
    local targetSelect = self.selected and 1 or 0
    self.selectedT = self.selectedT + (targetSelect - self.selectedT) * math.min(1, dt * 10)
end

function ModCard:drawSelf()
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    
    -- Background
    local bgColor = self.baseColor
    if not self.owned then
        bgColor = {0.15, 0.15, 0.15, 0.7}
    elseif self.equipped then
        bgColor = theme.lerpColor(self.baseColor, {0.2, 0.5, 0.3, 1}, 0.5)
    end
    
    -- Hover brightening
    if self.hoverT > 0 then
        bgColor = theme.lerpColor(bgColor, theme.lighten(bgColor, 0.15), self.hoverT)
    end
    
    -- Draw card background
    love.graphics.setColor(bgColor)
    love.graphics.rectangle('fill', gx, gy, w, h, 3, 3)
    
    -- Selection border
    if self.selectedT > 0 or self.focused then
        local borderAlpha = math.max(self.selectedT, self.focused and 0.8 or 0)
        love.graphics.setColor(0.4, 0.8, 1, borderAlpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle('line', gx - 1, gy - 1, w + 2, h + 2, 4, 4)
        love.graphics.setLineWidth(1)
    end
    
    -- Drop highlight
    if self.dropHighlight then
        love.graphics.setColor(0.3, 0.9, 0.5, 0.4)
        love.graphics.rectangle('fill', gx, gy, w, h, 3, 3)
    end
    
    -- Cost (top right)
    love.graphics.setColor(0.9, 0.9, 0.5, 0.9)
    love.graphics.print(tostring(self.cost), gx + w - 14, gy + 3)
    
    -- Mod name (centered)
    local name = (self.modDef and self.modDef.name) or self.modKey or "???"
    if #name > 10 then name = string.sub(name, 1, 9) .. ".." end
    
    if self.owned then
        love.graphics.setColor(1, 1, 1, 1)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
    end
    love.graphics.printf(name, gx + 2, gy + h/2 - 8, w - 4, 'center')
    
    -- Rank dots (bottom)
    if self.maxRank > 1 then
        local dotSize = 4
        local dotSpacing = 6
        local totalWidth = (self.maxRank - 1) * dotSpacing + dotSize
        local startX = gx + (w - totalWidth) / 2
        local dotY = gy + h - 12
        
        for i = 1, self.maxRank do
            local dx = startX + (i - 1) * dotSpacing
            if i <= self.rank then
                love.graphics.setColor(0.9, 0.85, 0.4, 1)
            else
                love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
            end
            love.graphics.circle('fill', dx + dotSize/2, dotY, dotSize/2)
        end
    end
    
    -- Equipped indicator
    if self.equipped then
        love.graphics.setColor(0.3, 0.9, 0.4, 0.9)
        love.graphics.print("E", gx + 3, gy + 3)
    end
    
    -- Locked overlay
    if not self.owned then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle('fill', gx, gy, w, h, 3, 3)
        love.graphics.setColor(0.6, 0.6, 0.6, 0.8)
        love.graphics.printf("LOCKED", gx, gy + h/2 - 6, w, 'center')
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function ModCard:getDragData()
    if not self.owned then return false end
    return {
        type = 'mod',
        modKey = self.modKey,
        modDef = self.modDef,
        source = self,
        label = (self.modDef and self.modDef.name) or self.modKey
    }
end

-------------------------------------------
-- Build UI - LEFT COLUMN
-------------------------------------------

local function buildLeftColumn(gameState, parent)
    local x = LAYOUT.leftX
    local y = 32
    
    -- Weapon selector
    local currentWeapon = getCurrentWeaponKey(gameState)
    local weaponDef = getWeaponDef(gameState, currentWeapon)
    local weaponName = (weaponDef and weaponDef.name) or currentWeapon
    if #weaponName > 12 then weaponName = string.sub(weaponName, 1, 11) .. ".." end
    
    local weaponLabel = ui.Text.new({
        x = x, y = y,
        text = "武器(Tab)",
        color = theme.colors.text_dim
    })
    parent:addChild(weaponLabel)
    y = y + 14
    
    local weaponBtn = ui.Button.new({
        x = x, y = y,
        w = LAYOUT.leftW - 4, h = 22,
        text = weaponName,
        tooltip = "按 Tab 切换武器"
    })
    parent:addChild(weaponBtn)
    y = y + 30
    
    -- Stats panel
    local panelW = LAYOUT.leftW - 4
    local panel = ui.Panel.new({
        x = x, y = y,
        w = panelW, h = 90,
        bgColor = LAYOUT.panelBg,
        borderColor = theme.colors.panel_border,
        borderWidth = 1,
        cornerRadius = 3
    })
    parent:addChild(panel)
    
    -- Format helper
    local function fmt(v) 
        if type(v) == 'number' then
            if v == math.floor(v) then return string.format("%d", v) end
            return string.format("%.1f", v)
        end
        return tostring(v)
    end
    
    local stats = {
        {"伤害:", weaponDef and weaponDef.damage or 10, ""},
        {"暴击:", (weaponDef and weaponDef.critChance or 0.1) * 100, "%"},
        {"倍率:", weaponDef and weaponDef.critMult or 2.0, "x"},
        {"攻速:", weaponDef and weaponDef.fireRate or 1.0, "/s"},
    }
    
    for i, s in ipairs(stats) do
        local sy = 6 + (i - 1) * 20
        -- Label with explicit width to prevent wrap
        panel:addChild(ui.Text.new({
            x = 8, y = sy,
            w = 80, 
            text = s[1],
            color = theme.colors.text_dim
        }))
        -- Value with explicit width
        panel:addChild(ui.Text.new({
            x = 70, y = sy,
            w = 80,
            text = fmt(s[2]) .. s[3],
            color = theme.colors.text
        }))
    end
    
    statsPanel = panel
    y = y + 96
    
    -- Class button
    local classKey = gameState.player and gameState.player.class or 'warrior'
    local classDef = gameState.classes and gameState.classes[classKey]
    local className = (classDef and classDef.name) or classKey
    if #className > 6 then className = string.sub(className, 1, 5) .. ".." end
    
    local classBtn = ui.Button.new({
        x = x, y = y,
        w = LAYOUT.leftW - 4, h = 20,
        text = "职业: " .. className,
        tooltip = "按 C 切换职业"
    })
    parent:addChild(classBtn)
    y = y + 24
    
    -- Pet button
    local petKey = (gameState.profile and gameState.profile.startPetKey) or 'pet_magnet'
    local petDef = gameState.catalog and gameState.catalog[petKey]
    local petName = (petDef and petDef.name) or petKey
    if #petName > 6 then petName = string.sub(petName, 1, 5) .. ".." end
    
    local petBtn = ui.Button.new({
        x = x, y = y,
        w = LAYOUT.leftW - 4, h = 20,
        text = "宠物: " .. petName,
        tooltip = "按 P/O 切换宠物"
    })
    parent:addChild(petBtn)
    y = y + 28
    
    -- Start button
    local startBtn = ui.Button.new({
        x = x, y = y,
        w = LAYOUT.leftW - 4, h = 26,
        text = "开始 (Enter)",
        normalColor = {0.2, 0.5, 0.3, 1},
        hoverColor = {0.3, 0.6, 0.4, 1}
    })
    startBtn:on('click', function()
        arsenalScreen.startRun(gameState)
    end)
    parent:addChild(startBtn)
end

-------------------------------------------
-- Build UI - RIGHT COLUMN
-------------------------------------------

local function buildRightColumn(gameState, parent)
    local x = LAYOUT.rightX
    local y = 32
    
    -- Capacity bar
    local currentWeapon = getCurrentWeaponKey(gameState)
    local used, max = calculateCapacity(gameState, currentWeapon)
    local gridW = LAYOUT.modSlotSize * LAYOUT.modGridCols + LAYOUT.modSlotSpacing * (LAYOUT.modGridCols - 1)
    
    local capLabel = ui.Text.new({
        x = x, y = y,
        w = 200, -- Explicit width preventing wrap
        text = string.format("容量: %d/%d", used, max),
        color = used > max and theme.colors.danger or theme.colors.text
    })
    parent:addChild(capLabel)
    y = y + 24 -- More spacing (was 20)
    
    capacityBar = ui.Bar.new({
        x = x, y = y,
        w = gridW, h = 6,
        value = used, maxValue = max,
        bgColor = LAYOUT.capacityBg,
        fillColor = used > max and LAYOUT.capacityFull or LAYOUT.capacityFill,
        cornerRadius = 2
    })
    parent:addChild(capacityBar)
    y = y + 16
    
    -- MOD grid (8 slots, 2 rows × 4 cols)
    local equippedOrder = getEquippedMods(gameState, currentWeapon)
    modSlots = {}
    
    for row = 1, LAYOUT.modGridRows do
        for col = 1, LAYOUT.modGridCols do
            local idx = (row - 1) * LAYOUT.modGridCols + col
            local slotX = x + (col - 1) * (LAYOUT.modSlotSize + LAYOUT.modSlotSpacing)
            local slotY = y + (row - 1) * (LAYOUT.modSlotSize + LAYOUT.modSlotSpacing)
            
            local modKey = equippedOrder[idx]
            local modDef = modKey and getModDef(gameState, modKey)
            
            local slot = ui.Slot.new({
                x = slotX, y = slotY,
                w = LAYOUT.modSlotSize, h = LAYOUT.modSlotSize,
                content = modKey,
                iconColor = modDef and {0.3, 0.5, 0.7, 1} or nil,
                sublabel = modKey and ("R" .. getModRank(gameState, modKey)) or nil,
                tooltip = modDef and modDef.name or nil,
                acceptDrop = true,
                draggable = modKey ~= nil
            })
            
            slot.slotIndex = idx
            slot:on('drop', function(self, dragData, source)
                if dragData.type == 'mod' then
                    arsenalScreen.equipModToSlot(gameState, dragData.modKey, self.slotIndex)
                end
            end)
            slot:on('rightClick', function(self)
                if self.content then
                    arsenalScreen.unequipMod(gameState, self.content)
                end
            end)
            
            parent:addChild(slot)
            table.insert(modSlots, slot)
        end
    end
    
    y = y + LAYOUT.modGridRows * (LAYOUT.modSlotSize + LAYOUT.modSlotSpacing) + 8
    
    -- MOD library label
    local libLabel = ui.Text.new({
        x = x, y = y,
        text = "MOD库 (E装备)",
        color = theme.colors.text_dim
    })
    parent:addChild(libLabel)
    y = y + 14
    
    -- MOD library cards (in right column only!)
    local modList = gameState.arsenal and gameState.arsenal.modList or {}
    modCards = {}
    
    local cardX = x
    local cardY = y
    local maxX = LAYOUT.screenW - 12 - LAYOUT.libraryCardW
    local cardsPerRow = math.floor((LAYOUT.rightW - 8) / (LAYOUT.libraryCardW + LAYOUT.libraryCardSpacing))
    
    for i, modKey in ipairs(modList) do
        local modDef = getModDef(gameState, modKey)
        local owned = isModOwned(gameState, modKey)
        local equipped = isModEquipped(gameState, currentWeapon, modKey)
        local rank = getModRank(gameState, modKey)
        
        local card = ModCard.new({
            x = cardX, y = cardY,
            w = LAYOUT.libraryCardW, h = LAYOUT.libraryCardH,
            modKey = modKey,
            modDef = modDef,
            owned = owned,
            equipped = equipped,
            rank = rank
        })
        
        card.cardIndex = i
        card:on('click', function(self)
            if selectedModCard then selectedModCard.selected = false end
            self.selected = true
            selectedModCard = self
            ui.core.setFocus(self) -- Sync focus
        end)
        
        card:on('activate_mod', function(self)
            -- Handle Enter/Space on focused card
            local arsenal = require('arsenal')
            arsenal.toggleEquip(gameState, self.modKey)
            arsenalScreen.rebuild(gameState)
        end)

        
        parent:addChild(card)
        table.insert(modCards, card)
        
        -- Next position
        cardX = cardX + LAYOUT.libraryCardW + LAYOUT.libraryCardSpacing
        if cardX > maxX then
            cardX = x
            cardY = cardY + LAYOUT.libraryCardH + LAYOUT.libraryCardSpacing
        end
    end
end

-------------------------------------------
-- Public API
-------------------------------------------

function arsenalScreen.init(gameState)
    state = gameState
    arsenalScreen.rebuild(gameState)
end

function arsenalScreen.rebuild(gameState)
    state = gameState
    
    -- Create root
    root = ui.Widget.new({x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH})
    root.visible = true
    root.enabled = true
    
    -- Background
    local bg = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH,
        bgColor = {0.05, 0.05, 0.08, 0.98}
    })
    root:addChild(bg)
    
    -- Title
    local title = ui.Text.new({
        x = 0, y = LAYOUT.titleY, w = LAYOUT.screenW,
        text = "军 械 库",
        color = theme.colors.accent,
        align = 'center',
        outline = true
    })
    root:addChild(title)
    
    -- Build two columns (no overlap!)
    buildLeftColumn(gameState, root)
    buildRightColumn(gameState, root)
    
    -- Set as UI root
    ui.core.setRoot(root)
    ui.core.enabled = true
    
    -- Select first mod card for keyboard nav
    if #modCards > 0 then
        modCards[1].selected = true
        selectedModCard = modCards[1]
        ui.core.setFocus(modCards[1]) -- Sync focus
    end
end

function arsenalScreen.equipModToSlot(gameState, modKey, slotIndex)
    local arsenal = require('arsenal')
    
    -- Use existing arsenal logic
    arsenal.toggleEquip(gameState, modKey)
    
    -- Rebuild UI to reflect changes
    arsenalScreen.rebuild(gameState)
end

function arsenalScreen.unequipMod(gameState, modKey)
    local arsenal = require('arsenal')
    
    if isModEquipped(gameState, getCurrentWeaponKey(gameState), modKey) then
        arsenal.toggleEquip(gameState, modKey)
    end
    
    arsenalScreen.rebuild(gameState)
end

function arsenalScreen.startRun(gameState)
    local arsenal = require('arsenal')
    arsenal.startRun(gameState)
end

function arsenalScreen.keypressed(gameState, key)
    -- Let UI system handle Tab/Enter/Arrow keys first
    -- Let UI system handle Enter/Arrow keys first
    -- Note: We skip 'tab' here so it falls through to arsenal.lua for weapon switching
    if key ~= 'tab' and ui.core.enabled and ui.keypressed(key) then
        return true
    end
    
    -- E to equip selected mod
    if key == 'e' and selectedModCard and selectedModCard.owned then
        local arsenal = require('arsenal')
        arsenal.toggleEquip(gameState, selectedModCard.modKey)
        arsenalScreen.rebuild(gameState)
        return true
    end
    
    -- Arrow keys for mod selection (when UI doesn't consume)
    if key == 'left' or key == 'right' or key == 'up' or key == 'down' then
        local currentIdx = selectedModCard and selectedModCard.cardIndex or 1
        local newIdx = currentIdx
        
        local cols = math.floor((LAYOUT.rightW - 8) / (LAYOUT.libraryCardW + LAYOUT.libraryCardSpacing))
        
        if key == 'left' then newIdx = currentIdx - 1
        elseif key == 'right' then newIdx = currentIdx + 1
        elseif key == 'up' then newIdx = currentIdx - cols
        elseif key == 'down' then newIdx = currentIdx + cols
        end
        
        newIdx = math.max(1, math.min(#modCards, newIdx))
        if newIdx ~= currentIdx and modCards[newIdx] then
            if selectedModCard then selectedModCard.selected = false end
            modCards[newIdx].selected = true
            selectedModCard = modCards[newIdx]
            ui.core.setFocus(modCards[newIdx]) -- Sync focus
        end
        return true
    end
    
    return false
end

function arsenalScreen.update(gameState, dt)
    if ui.core.enabled then
        ui.update(dt)
    end
end

function arsenalScreen.draw(gameState)
    if ui.core.enabled and root then
        -- Set Chinese font for proper text rendering
        local font = theme.getFont('normal')
        if font then
            love.graphics.setFont(font)
        end
        ui.draw()
    end
end

function arsenalScreen.isActive()
    return ui.core.enabled and root ~= nil
end

return arsenalScreen
