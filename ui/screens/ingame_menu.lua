-- =============================================================================
-- IN-GAME MENU (局内菜单)
-- Tab key toggleable menu for viewing stats, equipped MODs, and inventory
-- Layout inspired by Warframe MOD screen
-- =============================================================================

local ingameMenu = {}

local mods = require('mods')
local ui = require('ui')
local core = require('ui.core')
local theme = require('ui.theme')
local scaling = require('ui.scaling')
local Widget = require('ui.widgets.widget')
local Button = require('ui.widgets.button')
local Text = require('ui.widgets.text')
local Slot = require('ui.widgets.slot')
local Panel = require('ui.widgets.panel')
local pets = require('pets')

-- State
local state = nil
local root = nil
local isOpen = false
local currentTab = 'warframe'  -- 'warframe', 'weapons', 'companion'
local selectedWeaponKey = nil
local inventoryScroll = 0  -- Scroll offset for inventory

-- Layout constants
local SCREEN_W = scaling.LOGICAL_WIDTH   -- 640
local SCREEN_H = scaling.LOGICAL_HEIGHT  -- 360

-- New layout: Left=stats (compact), Center/Right=equipped mods (large), Bottom=inventory (scroll)
local LAYOUT = {
    -- Stats panel (left, compact)
    statsX = 15,
    statsY = 50,
    statsW = 120,
    statsLineH = 11,
    
    -- Equipped MODs (center-right, prominent)
    equippedX = 150,
    equippedY = 50,
    slotSize = 52,
    slotGap = 6,
    
    -- Inventory (bottom, scrollable)
    invY = 200,
    invSlotSize = 44,
    invSlotGap = 4,
    invCols = 10,
    invVisibleRows = 2,
}

-- =============================================================================
-- HELPERS
-- =============================================================================

local function getColor(rarity)
    local def = mods.RARITY[rarity]
    return def and def.color or {0.7, 0.7, 0.7}
end

local function getModName(category, modKey)
    local catalog = mods.getCatalog(category)
    if catalog and catalog[modKey] then
        return catalog[modKey].name or modKey
    end
    return modKey
end

local function getModShortName(category, modKey)
    local name = getModName(category, modKey)
    if name then
        local len = #name
        if len >= 6 then
            local first = name:sub(1, 3)
            local second = name:sub(4, 6)
            if first:byte(1) and first:byte(1) >= 128 and second:byte(1) and second:byte(1) >= 128 then
                return first .. second
            end
        end
        if len <= 4 then return name end
        return name:sub(1, 4)
    end
    return "???"
end

local function getModDesc(category, modKey)
    local catalog = mods.getCatalog(category)
    if catalog and catalog[modKey] then
        return catalog[modKey].desc or ""
    end
    return ""
end

local STAT_ABBREVS = {
    maxHp = "HP", armor = "AR", maxShield = "SH", maxEnergy = "EN",
    speed = "SP", abilityStrength = "STR", abilityEfficiency = "EFF",
    abilityDuration = "DUR", abilityRange = "RNG", energyRegen = "REG",
    damage = "DMG", critChance = "CC", critMult = "CD", fireRate = "FR",
    multishot = "MS", statusChance = "SC", magSize = "MAG", reloadSpeed = "RLD",
    meleeDamage = "MEL", healthLink = "HLK", armorLink = "ALK"
}

local function getStatAbbrev(category, modKey)
    local catalog = mods.getCatalog(category)
    if catalog and catalog[modKey] then
        local stat = catalog[modKey].stat
        return STAT_ABBREVS[stat] or "+"
    end
    return "+"
end

-- =============================================================================
-- MOD SLOT WIDGET (Interactive with drag-drop support)
-- =============================================================================

local ModSlot = setmetatable({}, {__index = Slot})
ModSlot.__index = ModSlot

function ModSlot.new(opts)
    opts = opts or {}
    opts.focusable = true
    opts.draggable = opts.draggable ~= false  -- Enable by default
    opts.acceptDrop = opts.acceptDrop ~= false  -- Enable by default
    
    local self = setmetatable(Slot.new(opts), ModSlot)
    
    self.modData = opts.modData
    self.category = opts.category or 'warframe'
    self.slotType = opts.slotType or 'equipped'  -- 'equipped' or 'inventory'
    self.slotIndex = opts.slotIndex or 0
    self.isLarge = opts.isLarge or false
    
    return self
end

function ModSlot:drawContent(gx, gy, w, h)
    if not self.modData then return end
    
    local prevFont = love.graphics.getFont()
    
    local modKey = self.modData.key
    local category = self.modData.category or self.category
    local rank = self.modData.rank or 0
    local rarity = self.modData.rarity or 'COMMON'
    
    local color = getColor(rarity)
    local abbrev = getStatAbbrev(category, modKey)
    local shortName = getModShortName(category, modKey)
    
    -- Background gradient
    love.graphics.setColor(color[1] * 0.35, color[2] * 0.35, color[3] * 0.35, 0.9)
    love.graphics.rectangle('fill', gx + 2, gy + 2, w - 4, h - 4, 3, 3)
    
    -- Stat abbreviation (top) - larger for equipped slots
    love.graphics.setColor(color[1], color[2], color[3], 1)
    local font = self.isLarge and (theme.getFont('normal') or prevFont) or (theme.getFont('small') or prevFont)
    love.graphics.setFont(font)
    love.graphics.printf(abbrev, gx, gy + 3, w, 'center')
    
    -- Short name (center)
    love.graphics.setColor(1, 1, 1, 1)
    local nameFont = self.isLarge and (theme.getFont('normal') or prevFont) or (theme.getFont('small') or prevFont)
    love.graphics.setFont(nameFont)
    love.graphics.printf(shortName, gx, gy + h/2 - 4, w, 'center')
    
    -- Rank dots (bottom)
    local dotSize = self.isLarge and 4 or 3
    local dotSpacing = self.isLarge and 7 or 5
    local totalDotsW = 5 * dotSpacing
    local startX = gx + (w - totalDotsW) / 2
    local dotY = gy + h - (self.isLarge and 10 or 7)
    
    for i = 0, 4 do
        local dx = startX + i * dotSpacing
        if i <= rank then
            love.graphics.setColor(color[1], color[2], color[3], 1)
        else
            love.graphics.setColor(0.25, 0.25, 0.3, 0.6)
        end
        love.graphics.circle('fill', dx + dotSize/2, dotY, dotSize/2)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    
    if prevFont then
        love.graphics.setFont(prevFont)
    end
end

function ModSlot:getDragData()
    if not self.modData then return false end
    
    return {
        type = 'mod',
        modData = self.modData,
        source = self,
        slotType = self.slotType,
        slotIndex = self.slotIndex,
        category = self.category,
        label = getModName(self.modData.category or self.category, self.modData.key)
    }
end

function ModSlot:canAcceptDrop(dragData, sourceWidget)
    if not dragData or dragData.type ~= 'mod' then return false end
    return dragData.category == self.category or 
           (dragData.modData and dragData.modData.category == self.category)
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function ingameMenu.init(s)
    state = s
end

function ingameMenu.isActive()
    return isOpen
end

function ingameMenu.show()
    if not state then return end
    isOpen = true
    inventoryScroll = 0
    
    if state.inventory and state.inventory.weaponSlots then
        local ranged = state.inventory.weaponSlots.ranged
        local melee = state.inventory.weaponSlots.melee
        selectedWeaponKey = (ranged and ranged.key) or (melee and melee.key)
    end
    
    ingameMenu.buildUI()
end

function ingameMenu.hide()
    isOpen = false
    root = nil
    
    -- Restore HUD after menu closes
    local hud = require('ui.screens.hud')
    hud.init(state)
    core.enabled = true
end

function ingameMenu.toggle(s)
    if s then state = s end
    if isOpen then
        ingameMenu.hide()
    else
        ingameMenu.show()
    end
end

function ingameMenu.update(dt)
    if not isOpen then return end
    core.update(dt)
end

function ingameMenu.draw()
    if not isOpen or not root then return end
    -- Use core.draw() which handles scaling and drag preview correctly
    core.draw()
end

-- =============================================================================
-- UI BUILDING
-- =============================================================================

function ingameMenu.buildUI()
    root = Widget.new({x = 0, y = 0, w = SCREEN_W, h = SCREEN_H})
    root.visible = true
    root.enabled = true
    
    -- Dark overlay background
    local bg = Panel.new({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        bgColor = {0.02, 0.02, 0.05, 0.94}
    })
    root:addChild(bg)
    
    -- Title (top center)
    local title = Text.new({
        x = SCREEN_W / 2 - 40, y = 6,
        text = "⏸ 暂停",
        color = {0.9, 0.95, 1.0, 1}
    })
    root:addChild(title)
    
    -- Tabs (top left)
    ingameMenu.buildTabs(root)
    
    -- Weapon selector (for weapons tab)
    if currentTab == 'weapons' then
        ingameMenu.buildWeaponSelector(root)
    end
    
    -- Left: Stats Panel (compact)
    ingameMenu.buildStatsPanel(root)
    
    -- Center-Right: Equipped MODs (prominent)
    ingameMenu.buildEquippedMods(root)
    
    -- Bottom: Inventory (scrollable)
    ingameMenu.buildInventory(root)
    
    -- Action buttons (bottom right)
    ingameMenu.buildActionButtons(root)
    
    -- Instructions (bottom center)
    local instructions = Text.new({
        x = 20, y = SCREEN_H - 14, w = SCREEN_W - 40,
        text = "左键拖拽 | 右键快捷装卸 | [Tab] 关闭 | [R] 返回军械库",
        color = {0.4, 0.4, 0.5, 1},
        font = theme.getFont('small')
    })
    root:addChild(instructions)
    
    core.setRoot(root)
    core.enabled = true
end

function ingameMenu.buildTabs(parent)
    local tabY = 24
    local tabs = {
        {key = 'warframe', name = '[1] 战甲'},
        {key = 'weapons', name = '[2] 武器'},
        {key = 'companion', name = '[3] 同伴'}
    }
    
    local tabX = 15
    for _, tab in ipairs(tabs) do
        local isActive = (currentTab == tab.key)
        local tabKey = tab.key
        
        local btn = Button.new({
            x = tabX, y = tabY,
            w = 70, h = 18,
            text = tab.name,
            normalColor = isActive and {0.25, 0.45, 0.7, 1} or {0.12, 0.12, 0.16, 0.9},
            hoverColor = {0.35, 0.55, 0.8, 1},
            textColor = isActive and {1, 1, 1, 1} or {0.55, 0.55, 0.65, 1}
        })
        btn:on('click', function()
            currentTab = tabKey
            inventoryScroll = 0
            ingameMenu.buildUI()
        end)
        parent:addChild(btn)
        tabX = tabX + 75
    end
end

function ingameMenu.buildWeaponSelector(parent)
    local weaponY = LAYOUT.statsY - 2
    local weaponX = LAYOUT.statsX
    
    local slots = state.inventory and state.inventory.weaponSlots or {}
    
    for slotType, slotData in pairs(slots) do
        local weaponKey = slotData and slotData.key
        if weaponKey then
            local def = state.catalog and state.catalog[weaponKey]
            local name = def and def.name or weaponKey
            if #name > 5 then name = name:sub(1, 4) .. ".." end
            local isSelected = (selectedWeaponKey == weaponKey)
            local wKey = weaponKey
            
            local btn = Button.new({
                x = weaponX, y = weaponY,
                w = 55, h = 16,
                text = name,
                normalColor = isSelected and {0.35, 0.55, 0.3, 1} or {0.15, 0.15, 0.18, 0.9},
                hoverColor = {0.45, 0.65, 0.4, 1},
                textColor = {1, 1, 1, 1}
            })
            btn:on('click', function()
                selectedWeaponKey = wKey
                ingameMenu.buildUI()
            end)
            parent:addChild(btn)
            weaponX = weaponX + 60
        end
    end
end

function ingameMenu.buildStatsPanel(parent)
    local panelX = LAYOUT.statsX
    local panelY = currentTab == 'weapons' and LAYOUT.statsY + 18 or LAYOUT.statsY
    
    -- Section header
    local header = Text.new({
        x = panelX, y = panelY,
        text = "◆ 属性",
        color = {0.7, 0.75, 0.85, 1},
        font = theme.getFont('small')
    })
    parent:addChild(header)
    
    local statsY = panelY + 12
    local p = state.player
    local stats = p and p.stats or {}
    
    local statLines = {}
    
    if currentTab == 'warframe' then
        table.insert(statLines, {label = "HP", value = string.format("%d/%d", math.floor(p.hp or 0), math.floor(p.maxHp or 100))})
        table.insert(statLines, {label = "护盾", value = string.format("%d/%d", math.floor(p.shield or 0), math.floor(p.maxShield or 100))})
        table.insert(statLines, {label = "能量", value = string.format("%d/%d", math.floor(p.energy or 0), math.floor(p.maxEnergy or 100))})
        table.insert(statLines, {label = "护甲", value = string.format("%d", stats.armor or 0)})
        table.insert(statLines, {label = "移速", value = string.format("%d", stats.moveSpeed or 180)})
        table.insert(statLines, {label = "强度", value = string.format("%.0f%%", (stats.abilityStrength or 1) * 100)})
        table.insert(statLines, {label = "效率", value = string.format("%.0f%%", (stats.abilityEfficiency or 1) * 100)})
        table.insert(statLines, {label = "范围", value = string.format("%.0f%%", (stats.abilityRange or 1) * 100)})
        table.insert(statLines, {label = "回能", value = string.format("%.1f/s", stats.energyRegen or 2)})
        
    elseif currentTab == 'weapons' then
        local weaponKey = selectedWeaponKey
        local weaponDef = state.catalog and state.catalog[weaponKey]
        local weaponData = state.inventory and state.inventory.weapons and state.inventory.weapons[weaponKey]
        
        if weaponDef then
            -- Calculate actual stats with all mods applied
            local weapons = require('weapons')
            local calculated = weapons.calculateStats(state, weaponKey)
            
            table.insert(statLines, {label = "伤害", value = string.format("%.0f", calculated.damage or 10)})
            table.insert(statLines, {label = "暴击", value = string.format("%.0f%%", (calculated.critChance or 0.1) * 100)})
            table.insert(statLines, {label = "倍率", value = string.format("%.1fx", (calculated.critMultiplier or calculated.critMult or 2.0))})
            
            -- Display as fire rate (reciprocal of CD)
            local fireRate = calculated.fireRate or (1 / (calculated.cd or 1))
            table.insert(statLines, {label = "射速", value = string.format("%.1f", fireRate)})
            
            if weaponData then
                local mag = weaponData.magazine or 0
                local maxMag = (calculated.maxMagazine) or calculated.magazine or mag
                table.insert(statLines, {label = "弹匣", value = string.format("%d/%d", mag, maxMag)})
                table.insert(statLines, {label = "储备", value = string.format("%d", weaponData.reserve or 0)})
            end
        else
            table.insert(statLines, {label = "武器", value = "无"})
        end
        
    elseif currentTab == 'companion' then
        local pet = pets.getActive(state)
        if pet then
            local petDef = state.catalog and state.catalog[pet.key]
            table.insert(statLines, {label = "名称", value = (petDef and petDef.name) or pet.key})
            table.insert(statLines, {label = "HP", value = string.format("%d/%d", math.floor(pet.hp or 0), math.floor(pet.maxHp or 50))})
            table.insert(statLines, {label = "攻击", value = string.format("%.0f", pet.damage or 10)})
        else
            table.insert(statLines, {label = "同伴", value = "无"})
        end
    end
    
    -- Use small font for stats
    local smallFont = theme.getFont('small')
    for i, line in ipairs(statLines) do
        local labelText = Text.new({
            x = panelX, y = statsY,
            text = line.label .. ":",
            color = {0.5, 0.55, 0.6, 1},
            font = smallFont
        })
        parent:addChild(labelText)
        
        local valueText = Text.new({
            x = panelX + 38, y = statsY,
            text = line.value,
            color = {0.85, 0.9, 0.95, 1},
            font = smallFont
        })
        parent:addChild(valueText)
        
        statsY = statsY + LAYOUT.statsLineH
    end
end

function ingameMenu.buildEquippedMods(parent)
    local panelX = LAYOUT.equippedX
    local panelY = LAYOUT.equippedY
    
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    local slotData = state.runMods and mods.getRunSlotData(state, category, key)
    local slotsData = slotData and slotData.slots or {}
    local capacity = slotData and slotData.capacity or 30
    local catalog = mods.getCatalog(category)
    local usedCapacity = mods.getTotalCost(slotsData, catalog)
    
    -- Section header with capacity
    local capColor = usedCapacity > capacity and {1, 0.4, 0.4, 1} or {0.5, 0.75, 0.5, 1}
    local header = Text.new({
        x = panelX, y = panelY - 2,
        text = string.format("◆ 已装备 (%d/%d)", usedCapacity, capacity),
        color = capColor
    })
    parent:addChild(header)
    
    -- 2 rows of 4 MOD slots (prominent size)
    local slotSize = LAYOUT.slotSize
    local slotGap = LAYOUT.slotGap
    local slotY = panelY + 16
    
    for i = 1, 8 do
        local row = math.floor((i - 1) / 4)
        local col = (i - 1) % 4
        local slotMod = slotsData[i]
        
        local slotX = panelX + col * (slotSize + slotGap)
        local slotYPos = slotY + row * (slotSize + slotGap)
        
        local hasContent = slotMod ~= nil
        local modColor = hasContent and getColor(slotMod.rarity) or {0.25, 0.25, 0.3}
        local slotIdx = i
        local currentSlotMod = slotMod
        
        local slot = ModSlot.new({
            x = slotX, y = slotYPos,
            w = slotSize, h = slotSize,
            content = hasContent and slotMod.key or nil,
            modData = hasContent and slotMod or nil,
            category = category,
            slotType = 'equipped',
            slotIndex = slotIdx,
            isLarge = true,
            emptyColor = {0.08, 0.08, 0.12, 0.9},
            filledColor = hasContent and {modColor[1] * 0.3, modColor[2] * 0.3, modColor[3] * 0.3, 0.95} or {0.1, 0.1, 0.14, 0.9},
            borderColor = hasContent and {modColor[1], modColor[2], modColor[3], 1} or {0.2, 0.2, 0.25, 1},
            borderWidth = hasContent and 2 or 1,
            tooltip = hasContent and (getModName(category, slotMod.key) .. ": " .. getModDesc(category, slotMod.key)) or nil
        })
        
        -- Drop handler
        slot:on('drop', function(self, dragData, source)
            if dragData and dragData.type == 'mod' then
                local modData = dragData.modData
                
                if dragData.slotType == 'inventory' then
                    -- Equip from inventory
                    local success = mods.equipToRunSlot(state, category, key, slotIdx, modData.key, modData.rank)
                    if success then
                        for j, m in ipairs(state.runMods.inventory) do
                            if m == modData then
                                table.remove(state.runMods.inventory, j)
                                break
                            end
                        end
                        mods.refreshActiveStats(state)
                        if state.playSfx then state.playSfx('gem') end
                    end
                elseif dragData.slotType == 'equipped' and dragData.slotIndex ~= slotIdx then
                    -- Swap equipped slots
                    local otherMod = slotsData[dragData.slotIndex]
                    local myMod = slotsData[slotIdx]
                    slotsData[slotIdx] = otherMod
                    slotsData[dragData.slotIndex] = myMod
                    mods.refreshActiveStats(state)
                    if state.playSfx then state.playSfx('gem') end
                end
                
                ingameMenu.buildUI()
            end
        end)
        
        -- Right click - quick unequip
        slot:on('rightClick', function()
            if currentSlotMod then
                mods.unequipFromRunSlot(state, category, key, slotIdx)
                mods.addToRunInventory(state, currentSlotMod.key, category, currentSlotMod.rank, currentSlotMod.rarity)
                mods.refreshActiveStats(state)
                if state.playSfx then state.playSfx('gem') end
                ingameMenu.buildUI()
            end
        end)
        
        parent:addChild(slot)
    end
end

function ingameMenu.buildInventory(parent)
    local invY = LAYOUT.invY
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    
    local inventory = state.runMods and mods.getRunInventoryByCategory(state, category) or {}
    
    -- Section header
    local header = Text.new({
        x = 15, y = invY,
        text = string.format("◆ 背包 (%d)", #inventory),
        color = {0.7, 0.75, 0.85, 1}
    })
    parent:addChild(header)
    
    -- Scrollable container for inventory
    local slotSize = LAYOUT.invSlotSize
    local gap = LAYOUT.invSlotGap
    local cols = LAYOUT.invCols
    
    local scrollW = cols * (slotSize + gap) + 20
    local scrollH = SCREEN_H - invY - 55
    
    local scrollContainer = ui.newScrollContainer({
        x = 15, y = invY + 14,
        w = scrollW, h = scrollH,
        scrollbarVisible = true
    })
    parent:addChild(scrollContainer)
    
    -- Calculate content height
    local totalRows = math.ceil(#inventory / cols)
    local contentH = totalRows * (slotSize + gap)
    
    -- Add MOD slots to scroll container
    for idx, modData in ipairs(inventory) do
        local row = math.floor((idx - 1) / cols)
        local col = (idx - 1) % cols
        local slotX = col * (slotSize + gap)
        local slotYPos = row * (slotSize + gap)
        
        local modColor = getColor(modData.rarity)
        
        -- Find actual index in global inventory
        local actualIdx = 0
        for i, m in ipairs(state.runMods.inventory) do
            if m == modData then
                actualIdx = i
                break
            end
        end
        
        local capturedModData = modData
        local capturedIdx = actualIdx
        
        local slot = ModSlot.new({
            x = slotX, y = slotYPos,
            w = slotSize, h = slotSize,
            content = modData.key,
            modData = modData,
            category = category,
            slotType = 'inventory',
            slotIndex = capturedIdx,
            isLarge = false,
            emptyColor = {modColor[1] * 0.15, modColor[2] * 0.15, modColor[3] * 0.15, 0.9},
            filledColor = {modColor[1] * 0.25, modColor[2] * 0.25, modColor[3] * 0.25, 0.9},
            borderColor = {modColor[1], modColor[2], modColor[3], 1},
            tooltip = getModName(modData.category, modData.key) .. ": " .. getModDesc(modData.category, modData.key)
        })
        
        -- Right click - quick equip to first empty slot
        slot:on('rightClick', function()
            local slotData = mods.getRunSlotData(state, category, key)
            local slotsData = slotData and slotData.slots or {}
            
            -- Find first empty slot
            local targetSlot = nil
            for i = 1, 8 do
                if not slotsData[i] then
                    targetSlot = i
                    break
                end
            end
            
            if targetSlot then
                local success = mods.equipToRunSlot(state, category, key, targetSlot, capturedModData.key, capturedModData.rank)
                if success then
                    table.remove(state.runMods.inventory, capturedIdx)
                    if state.playSfx then state.playSfx('gem') end
                end
                ingameMenu.buildUI()
            end
        end)
        
        scrollContainer:addChild(slot)
    end
end

function ingameMenu.buildActionButtons(parent)
    local buttonY = SCREEN_H - 36
    
    -- Continue button (center)
    local continueBtn = Button.new({
        x = SCREEN_W / 2 - 55, y = buttonY,
        w = 110, h = 22,
        text = "继续游戏",
        normalColor = {0.2, 0.45, 0.3, 1},
        hoverColor = {0.3, 0.6, 0.4, 1},
        textColor = {1, 1, 1, 1}
    })
    continueBtn:on('click', function()
        ingameMenu.hide()
    end)
    parent:addChild(continueBtn)
    
    -- Return to Arsenal button (right)
    local arsenalBtn = Button.new({
        x = SCREEN_W - 115, y = buttonY,
        w = 100, h = 22,
        text = "返回军械库 [R]",
        normalColor = {0.45, 0.22, 0.18, 1},
        hoverColor = {0.6, 0.32, 0.28, 1},
        textColor = {1, 1, 1, 1}
    })
    arsenalBtn:on('click', function()
        ingameMenu.hide()
        state.init()
        local arsenal = require('arsenal')
        arsenal.init(state)
        state.gameState = 'ARSENAL'
        arsenal.show(state)
    end)
    parent:addChild(arsenalBtn)
end

-- =============================================================================
-- INPUT HANDLING
-- =============================================================================

function ingameMenu.keypressed(key)
    if not isOpen then return false end
    
    -- Close menu
    if key == 'tab' or key == 'escape' then
        ingameMenu.hide()
        return true
    end
    
    -- Continue
    if key == 'return' or key == 'kpenter' then
        ingameMenu.hide()
        return true
    end
    
    -- Return to Arsenal
    if key == 'r' then
        ingameMenu.hide()
        state.init()
        local arsenal = require('arsenal')
        arsenal.init(state)
        state.gameState = 'ARSENAL'
        arsenal.show(state)
        return true
    end
    
    -- Tab switching
    if key == '1' then
        currentTab = 'warframe'
        inventoryScroll = 0
        ingameMenu.buildUI()
        return true
    elseif key == '2' then
        currentTab = 'weapons'
        inventoryScroll = 0
        ingameMenu.buildUI()
        return true
    elseif key == '3' then
        currentTab = 'companion'
        inventoryScroll = 0
        ingameMenu.buildUI()
        return true
    end

    
    return true  -- Consume all keys while menu is open
end

function ingameMenu.mousepressed(x, y, button)
    if not isOpen then return false end
    core.mousepressed(x, y, button)
    return true
end

function ingameMenu.mousereleased(x, y, button)
    if not isOpen then return false end
    core.mousereleased(x, y, button)
    return true
end

function ingameMenu.mousemoved(x, y, dx, dy)
    if not isOpen then return false end
    core.mousemoved(x, y, dx, dy)
    return true
end

function ingameMenu.wheelmoved(x, y)
    if not isOpen then return false end
    -- Forward to core for ScrollContainer handling
    core.wheelmoved(x, y)
    return true
end

return ingameMenu
