-- Arsenal Screen
-- Warframe-style MOD configuration interface
-- Supports both keyboard navigation and mouse/drag-drop

local ui = require('ui')
local theme = ui.theme
local mods = require('systems.mods')
local modsModel = require('ui.mods_model')

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

local function getCurrentCategory(gameState)
    return (gameState.profile and gameState.profile.modTargetCategory) or 'weapons'
end

local function getLoadout(gameState, category, weaponKey)
    local profile = gameState.profile
    if not profile then return nil end
    if category == 'weapons' then
        profile.weaponMods = profile.weaponMods or {}
        profile.weaponMods[weaponKey] = profile.weaponMods[weaponKey] or {slots = {}}
        return profile.weaponMods[weaponKey]
    elseif category == 'warframe' then
        profile.warframeMods = profile.warframeMods or {slots = {}}
        profile.warframeMods.slots = profile.warframeMods.slots or {}
        return profile.warframeMods
    elseif category == 'companion' then
        profile.companionMods = profile.companionMods or {slots = {}}
        profile.companionMods.slots = profile.companionMods.slots or {}
        return profile.companionMods
    end
    return nil
end

local function getEquippedMods(gameState, category, weaponKey)
    local loadout = getLoadout(gameState, category, weaponKey)
    if not loadout then return {} end
    return loadout.slots or {}
end

local function getModCatalog(category)
    return mods.getCatalog(category or 'weapons') or {}
end

local function getModDef(gameState, category, modKey)
    local catalog = getModCatalog(category)
    return catalog[modKey]
end

local function isModOwned(gameState, modKey)
    local profile = gameState.profile
    return profile and profile.ownedMods and profile.ownedMods[modKey]
end

local function isModEquipped(gameState, category, weaponKey, modKey)
    local loadout = getLoadout(gameState, category, weaponKey)
    if not (loadout and loadout.slots) then return false end
    for _, key in pairs(loadout.slots) do
        if key == modKey then return true end
    end
    return false
end

local function getModRank(gameState, modKey)
    local profile = gameState.profile
    local r = (profile and profile.modRanks and profile.modRanks[modKey]) or 0
    r = tonumber(r) or 0
    return math.max(0, math.floor(r))
end

local function getMaxRank(def)
    local len = 0
    if def and type(def.cost) == 'table' then len = #def.cost end
    if len == 0 and def and type(def.value) == 'table' then len = #def.value end
    if len == 0 then return 0 end
    return math.max(0, len - 1)
end

local function getRankCost(def, rank)
    if def and type(def.cost) == 'table' then
        return def.cost[rank + 1] or 0
    end
    return 0
end

local function getCurrentWeaponKey(gameState)
    return (gameState.profile and gameState.profile.modTargetWeapon) or 'wand'
end

local function getWeaponDef(gameState, weaponKey)
    return gameState.catalog and gameState.catalog[weaponKey]
end

local function calculateCapacity(gameState, category, weaponKey)
    local loadout = getLoadout(gameState, category, weaponKey)
    if not loadout then return 0, 30 end
    
    local slots = {}
    for slotIdx, modKey in pairs(loadout.slots or {}) do
        if modKey then
            slots[slotIdx] = {key = modKey, rank = getModRank(gameState, modKey)}
        end
    end

    local used = mods.getTotalCost(slots, getModCatalog(category))
    local maxCapacity = (gameState.progression and gameState.progression.modCapacity) or 30
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
    self.rank = opts.rank or 0
    self.maxRank = getMaxRank(opts.modDef)
    
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
    local cost = getRankCost(self.modDef, self.rank or 0)
    love.graphics.setColor(0.9, 0.9, 0.5, 0.9)
    love.graphics.print(tostring(cost), gx + w - 14, gy + 3)
    
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
    if self.maxRank > 0 then
        local dotSize = 4
        local dotSpacing = 6
        local dotCount = self.maxRank + 1
        local totalWidth = (dotCount - 1) * dotSpacing + dotSize
        local startX = gx + (w - totalWidth) / 2
        local dotY = gy + h - 12
        
        for i = 1, dotCount do
            local dx = startX + (i - 1) * dotSpacing
            if i <= (self.rank + 1) then
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
    local category = getCurrentCategory(gameState)
    
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
    y = y + 26

    -- Mod category selector
    local catLabel = ui.Text.new({
        x = x, y = y,
        text = "MOD类别(1/2/3)",
        color = theme.colors.text_dim
    })
    parent:addChild(catLabel)
    y = y + 14

    local catName = (category == 'warframe' and "战甲") or (category == 'weapons' and "武器") or "宠物"
    local catBtn = ui.Button.new({
        x = x, y = y,
        w = LAYOUT.leftW - 4, h = 22,
        text = catName,
        tooltip = "1:战甲  2:武器  3:宠物"
    })
    catBtn:on('click', function()
        local arsenal = require('core.arsenal')
        local next = (category == 'warframe' and 'weapons') or (category == 'weapons' and 'companion') or 'warframe'
        arsenal.setModCategory(gameState, next)
        arsenalScreen.rebuild(gameState)
    end)
    parent:addChild(catBtn)
    y = y + 24
    
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
    y = y + 92
    
    -- Class button
    local classKey = gameState.player and gameState.player.class or 'volt'
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
    y = y + 22
    
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
    y = y + 24
    
    -- Start button
    local startBtn = ui.Button.new({
        x = x, y = y,
        w = LAYOUT.leftW - 4, h = 26,
        text = "开始测试 (Enter)",
        tooltip = "房间模式 (默认) | 按 F 进入探索任务",
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
    local category = getCurrentCategory(gameState)
    
    -- Capacity bar
    local currentWeapon = getCurrentWeaponKey(gameState)
    local used, max = calculateCapacity(gameState, category, currentWeapon)
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
    local equippedOrder = getEquippedMods(gameState, category, currentWeapon)
    modSlots = {}
    
    for row = 1, LAYOUT.modGridRows do
        for col = 1, LAYOUT.modGridCols do
            local idx = (row - 1) * LAYOUT.modGridCols + col
            local slotX = x + (col - 1) * (LAYOUT.modSlotSize + LAYOUT.modSlotSpacing)
            local slotY = y + (row - 1) * (LAYOUT.modSlotSize + LAYOUT.modSlotSpacing)
            
            local modKey = equippedOrder[idx]
            local modDef = modKey and getModDef(gameState, category, modKey)
            
            local slotTooltip = nil
            if modKey then
                slotTooltip = modsModel.buildModTooltip(category, modKey, getModRank(gameState, modKey))
            end
            local slot = ui.Slot.new({
                x = slotX, y = slotY,
                w = LAYOUT.modSlotSize, h = LAYOUT.modSlotSize,
                content = modKey,
                iconColor = modDef and {0.3, 0.5, 0.7, 1} or nil,
                sublabel = modKey and ("R" .. getModRank(gameState, modKey)) or nil,
                tooltip = slotTooltip,
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
    local catName = (category == 'warframe' and "战甲") or (category == 'weapons' and "武器") or "宠物"
    local libLabel = ui.Text.new({
        x = x, y = y,
        text = "MOD库 (E装备) - " .. catName,
        color = theme.colors.text_dim
    })
    parent:addChild(libLabel)
    y = y + 14
    
    -- MOD library scrollable container
    local scrollH = LAYOUT.screenH - y - 10
    local scrollContainer = ui.newScrollContainer({
        x = x, y = y,
        w = LAYOUT.rightW, h = scrollH,
        scrollbarVisible = true
    })
    parent:addChild(scrollContainer)
    
    -- MOD library cards (local coordinates within scroll container)
    local modList = gameState.arsenal and gameState.arsenal.modList or {}
    modCards = {}
    
    local cardX = 0 -- Local to scroll container
    local cardY = 0
    local maxX = LAYOUT.rightW - 12 - LAYOUT.libraryCardW
    local cardsPerRow = math.floor((LAYOUT.rightW - 8) / (LAYOUT.libraryCardW + LAYOUT.libraryCardSpacing))
    
    for i, modKey in ipairs(modList) do
        local modDef = getModDef(gameState, category, modKey)
        local owned = isModOwned(gameState, modKey)
        local equipped = isModEquipped(gameState, category, currentWeapon, modKey)
        local rank = getModRank(gameState, modKey)
        
        local cardTooltip = modsModel.buildModTooltip(category, modKey, rank)
        local card = ModCard.new({
            x = cardX, y = cardY,
            w = LAYOUT.libraryCardW, h = LAYOUT.libraryCardH,
            modKey = modKey,
            modDef = modDef,
            owned = owned,
            equipped = equipped,
            rank = rank,
            tooltip = cardTooltip
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
            local arsenal = require('core.arsenal')
            arsenal.toggleEquip(gameState, self.modKey)
            arsenalScreen.rebuild(gameState)
        end)
        card:on('rightClick', function(self)
            if not self.owned then return end
            local arsenal = require('core.arsenal')
            local category = getCurrentCategory(gameState)
            local weaponKey = getCurrentWeaponKey(gameState)
            if isModEquipped(gameState, category, weaponKey, self.modKey) then
                arsenal.unequipMod(gameState, self.modKey)
            else
                arsenal.toggleEquip(gameState, self.modKey)
            end
            arsenalScreen.rebuild(gameState)
        end)

        
        scrollContainer:addChild(card)
        table.insert(modCards, card)
        
        -- Next position
        cardX = cardX + LAYOUT.libraryCardW + LAYOUT.libraryCardSpacing
        if cardX > maxX then
            cardX = 0
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
        outline = true,
        glow = true,
        glowColor = theme.colors.accent,
        glowAlpha = 0.25
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
    local arsenal = require('core.arsenal')
    
    -- Slot-specific equip
    arsenal.equipToSlot(gameState, modKey, slotIndex)
    
    -- Rebuild UI to reflect changes
    arsenalScreen.rebuild(gameState)
end

function arsenalScreen.unequipMod(gameState, modKey)
    local arsenal = require('core.arsenal')
    
    arsenal.unequipMod(gameState, modKey)
    
    arsenalScreen.rebuild(gameState)
end

function arsenalScreen.startRun(gameState)
    local arsenal = require('core.arsenal')
    -- Explicitly pass the current mode to avoid ambiguity or residuals
    arsenal.startRun(gameState, {runMode = gameState.runMode or 'rooms'})
end

function arsenalScreen.keypressed(gameState, key)
    -- Let UI system handle Tab/Enter/Arrow keys first
    -- Let UI system handle Enter/Arrow keys first
    -- Note: We skip 'tab' here so it falls through to arsenal.lua for weapon switching
    if key ~= 'tab' and key ~= '1' and key ~= '2' and key ~= '3' and ui.core.enabled and ui.keypressed(key) then
        return true
    end
    
    -- E to equip selected mod
    if key == 'e' and selectedModCard and selectedModCard.owned then
        local arsenal = require('core.arsenal')
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
