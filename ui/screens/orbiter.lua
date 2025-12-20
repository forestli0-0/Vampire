-- =============================================================================
-- ORBITER SCREEN (飞船整备界面)
-- Warframe-style Roguelike: Configure MODs between rooms
-- Supports: Drag & Drop, Right-click quick actions, Enhanced readability
-- =============================================================================

local orbiter = {}

local mods = require('mods')
local modsModel = require('ui.mods_model')
local ui = require('ui')
local core = require('ui.core')
local theme = require('ui.theme')
local scaling = require('ui.scaling')
local Widget = require('ui.widgets.widget')
local Button = require('ui.widgets.button')
local Text = require('ui.widgets.text')
local Slot = require('ui.widgets.slot')
local Panel = require('ui.widgets.panel')
local hud = require('ui.screens.hud')

local state = nil
local root = nil
local currentTab = 'warframe'  -- 'warframe', 'weapons', 'companion'
local selectedWeaponKey = nil
local selectedInventoryMod = nil  -- {index, modData}
local selectedSlotIndex = nil

-- Widget references for updates
local modSlots = {}      -- Equipment slots (8)
local invSlots = {}      -- Inventory slots
local statsTexts = {}    -- Bonus stats display

-- Layout constants - use logical resolution
local SCREEN_W = scaling.LOGICAL_WIDTH   -- 640
local SCREEN_H = scaling.LOGICAL_HEIGHT  -- 360
local PANEL_X = 20
local PANEL_Y = 50
local SLOT_SIZE = 44      -- Smaller for 640x360
local SLOT_GAP = 4
local INV_COLS = 6

-- =============================================================================
-- HELPERS
-- =============================================================================

local function getModCost(category, modKey, rank)
    local catalog = mods.getCatalog(category)
    if catalog and catalog[modKey] and catalog[modKey].cost then
        rank = math.max(0, math.min(5, rank or 0))
        return catalog[modKey].cost[rank + 1] or 4
    end
    return 4
end

-- =============================================================================
-- CUSTOM MOD SLOT WIDGET (Enhanced readability)
-- =============================================================================

local ModSlot = setmetatable({}, {__index = Slot})
ModSlot.__index = ModSlot

function ModSlot.new(opts)
    opts = opts or {}
    opts.focusable = true
    opts.draggable = opts.draggable ~= false
    opts.acceptDrop = opts.acceptDrop ~= false
    
    local self = setmetatable(Slot.new(opts), ModSlot)
    
    -- MOD-specific data
    self.modData = opts.modData
    self.category = opts.category or 'warframe'
    self.slotType = opts.slotType or 'equipped'
    self.slotIndex = opts.slotIndex or 0
    
    return self
end

function ModSlot:drawContent(gx, gy, w, h)
    if not self.modData then return end
    
    -- Save current font to restore later (prevents font state pollution)
    local prevFont = love.graphics.getFont()
    
    local modKey = self.modData.key
    local category = self.modData.category or self.category
    local rank = self.modData.rank or 0
    local rarity = self.modData.rarity or 'COMMON'
    
    local color = modsModel.getColor(rarity)
    local abbrev = modsModel.getStatAbbrev(category, modKey)
    local shortName = modsModel.getModShortName(category, modKey)
    
    -- Background gradient based on rarity
    love.graphics.setColor(color[1] * 0.3, color[2] * 0.3, color[3] * 0.3, 0.8)
    love.graphics.rectangle('fill', gx + 2, gy + 2, w - 4, h - 4, 2, 2)
    
    -- Stat abbreviation (top)
    love.graphics.setColor(color[1], color[2], color[3], 0.9)
    local font = theme.getFont('small') or prevFont
    love.graphics.setFont(font)
    love.graphics.printf(abbrev, gx, gy + 2, w, 'center')
    
    -- Short name (center)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(shortName, gx, gy + h/2 - 5, w, 'center')
    
    -- Rank dots (bottom)
    local dotSize = 3
    local dotSpacing = 5
    local totalDotsW = 5 * dotSpacing
    local startX = gx + (w - totalDotsW) / 2
    local dotY = gy + h - 8
    
    for i = 0, 4 do
        local dx = startX + i * dotSpacing
        if i <= rank then
            love.graphics.setColor(color[1], color[2], color[3], 1)
        else
            love.graphics.setColor(0.3, 0.3, 0.3, 0.6)
        end
        love.graphics.circle('fill', dx + dotSize/2, dotY, dotSize/2)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Restore previous font
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
        label = modsModel.getModName(self.modData.category or self.category, self.modData.key)
    }
end

function ModSlot:canAcceptDrop(dragData, sourceWidget)
    if not dragData or dragData.type ~= 'mod' then return false end
    return dragData.category == self.category or 
           (dragData.modData and dragData.modData.category == self.category)
end

-- =============================================================================
-- UI BUILDING
-- =============================================================================

function orbiter.init(s)
    state = s
    
    if not state.runMods then
        mods.initRunMods(state)
    end
    
    if state.inventory and state.inventory.weaponSlots then
        local ranged = state.inventory.weaponSlots.ranged
        local melee = state.inventory.weaponSlots.melee
        selectedWeaponKey = (ranged and ranged.key) or (melee and melee.key)
    end
    
    orbiter.buildUI()
end

function orbiter.buildUI()
    root = Widget.new({x = 0, y = 0, w = SCREEN_W, h = SCREEN_H})
    root.visible = true
    root.enabled = true
    
    -- Background
    local bg = Panel.new({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        bgColor = {0.06, 0.06, 0.1, 1}
    })
    root:addChild(bg)
    
    -- Title
    local title = Text.new({
        x = 0, y = 8, w = SCREEN_W,
        text = "ORBITER - 飞船整备",
        color = {0.9, 0.95, 1.0, 1},
        align = 'center'
    })
    root:addChild(title)
    
    -- Tab buttons
    orbiter.buildTabs(root)
    
    -- Weapon selector (for weapons tab)
    if currentTab == 'weapons' then
        orbiter.buildWeaponSelector(root)
    end
    
    -- MOD slots section
    orbiter.buildModSlots(root)
    
    -- Inventory section
    orbiter.buildInventory(root)
    
    -- Stats panel (right side)
    orbiter.buildStatsPanel(root)
    
    -- Action buttons
    orbiter.buildActionButtons(root)
    
    -- Instructions
    local instructions = Text.new({
        x = 0, y = SCREEN_H - 16, w = SCREEN_W,
        text = "左键拖拽 | 右键快速装卸 | ESC 退出",
        color = {0.45, 0.45, 0.55, 1},
        align = 'center'
    })
    root:addChild(instructions)
    
    core.setRoot(root)
    core.enabled = true
end

function orbiter.buildTabs(parent)
    local tabY = 28
    local tabs = {
        {key = 'warframe', name = '角色MOD'},
        {key = 'weapons', name = '武器MOD'},
        {key = 'companion', name = '守护MOD'}
    }
    
    local tabX = PANEL_X
    for _, tab in ipairs(tabs) do
        local isActive = (currentTab == tab.key)
        local tabKey = tab.key
        
        local btn = Button.new({
            x = tabX, y = tabY,
            w = 80, h = 22,
            text = tab.name,
            normalColor = isActive and {0.3, 0.5, 0.8, 1} or {0.2, 0.2, 0.3, 1},
            hoverColor = {0.4, 0.6, 0.9, 1},
            textColor = isActive and {1, 1, 1, 1} or {0.7, 0.7, 0.8, 1}
        })
        btn:on('click', function()
            currentTab = tabKey
            selectedInventoryMod = nil
            selectedSlotIndex = nil
            orbiter.buildUI()
        end)
        parent:addChild(btn)
        tabX = tabX + 88
    end
end

function orbiter.buildWeaponSelector(parent)
    local weaponY = 52
    local weaponX = PANEL_X
    
    local label = Text.new({
        x = weaponX, y = weaponY,
        text = "武器:",
        color = {0.7, 0.75, 0.8, 1}
    })
    parent:addChild(label)
    
    weaponX = weaponX + 40
    local slots = state.inventory and state.inventory.weaponSlots or {}
    
    for slotType, slotData in pairs(slots) do
        local weaponKey = slotData and slotData.key
        if weaponKey then
            local def = state.catalog and state.catalog[weaponKey]
            local name = def and def.name or weaponKey
            if #name > 6 then name = name:sub(1, 5) .. ".." end
            local isSelected = (selectedWeaponKey == weaponKey)
            local wKey = weaponKey
            
            local btn = Button.new({
                x = weaponX, y = weaponY - 2,
                w = 70, h = 20,
                text = name,
                normalColor = isSelected and {0.4, 0.6, 0.3, 1} or {0.25, 0.25, 0.3, 1},
                hoverColor = {0.5, 0.7, 0.4, 1},
                textColor = {1, 1, 1, 1}
            })
            btn:on('click', function()
                selectedWeaponKey = wKey
                selectedInventoryMod = nil
                selectedSlotIndex = nil
                orbiter.buildUI()
            end)
            parent:addChild(btn)
            weaponX = weaponX + 75
        end
    end
end

function orbiter.buildModSlots(parent)
    local slotsY = currentTab == 'weapons' and 72 or 52
    
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    local slotData = mods.getRunSlotData(state, category, key)
    local slotsData = slotData and slotData.slots or {}
    local capacity = slotData and slotData.capacity or 30
    local catalog = mods.getCatalog(category)
    local usedCapacity = mods.getTotalCost(slotsData, catalog)
    
    -- Section label with capacity
    local capColor = usedCapacity > capacity and {1, 0.4, 0.4, 1} or {0.6, 0.85, 0.6, 1}
    local sectionLabel = Text.new({
        x = PANEL_X, y = slotsY,
        text = string.format("已装备 (%d/%d)", usedCapacity, capacity),
        color = capColor
    })
    parent:addChild(sectionLabel)
    
    -- Slot grid (2 rows of 4)
    modSlots = {}
    local slotY = slotsY + 16
    
    for i = 1, 8 do
        local row = math.floor((i - 1) / 4)
        local col = (i - 1) % 4
        local slotMod = slotsData[i]
        
        local slotX = PANEL_X + col * (SLOT_SIZE + SLOT_GAP)
        local slotYPos = slotY + row * (SLOT_SIZE + SLOT_GAP)
        
        local hasContent = slotMod ~= nil
        local slotIdx = i
        local currentSlotMod = slotMod
        local color = hasContent and modsModel.getColor(slotMod.rarity) or {0.3, 0.3, 0.4}
        
        local slot = ModSlot.new({
            x = slotX, y = slotYPos,
            w = SLOT_SIZE, h = SLOT_SIZE,
            content = hasContent and slotMod.key or nil,
            modData = hasContent and slotMod or nil,
            category = category,
            slotType = 'equipped',
            slotIndex = slotIdx,
            selected = (selectedSlotIndex == i),
            emptyColor = {0.12, 0.12, 0.18, 0.9},
            filledColor = hasContent and {color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 0.9} or {0.15, 0.15, 0.2, 0.9},
            borderColor = hasContent and {color[1], color[2], color[3], 1} or {0.3, 0.3, 0.4, 1},
            selectedBorderColor = {1, 1, 0.3, 1},
            tooltip = hasContent and (modsModel.getModName(category, slotMod.key) .. ": " .. modsModel.getModDesc(category, slotMod.key)) or nil
        })
        
        -- Drop handler
        slot:on('drop', function(self, dragData, source)
            if dragData and dragData.type == 'mod' then
                local modData = dragData.modData
                
                if dragData.slotType == 'inventory' then
                    local success = mods.equipToRunSlot(state, category, key, slotIdx, modData.key, modData.rank)
                    if success then
                        for j, m in ipairs(state.runMods.inventory) do
                            if m == modData then
                                table.remove(state.runMods.inventory, j)
                                break
                            end
                        end
                        if state.playSfx then state.playSfx('gem') end
                    end
                elseif dragData.slotType == 'equipped' and dragData.slotIndex ~= slotIdx then
                    local otherMod = slotsData[dragData.slotIndex]
                    local myMod = slotsData[slotIdx]
                    slotsData[slotIdx] = otherMod
                    slotsData[dragData.slotIndex] = myMod
                    if state.playSfx then state.playSfx('gem') end
                end
                
                orbiter.buildUI()
            end
        end)
        
        -- Left click
        slot:on('click', function()
            if selectedInventoryMod then
                local invMod = selectedInventoryMod.modData
                local success = mods.equipToRunSlot(state, category, key, slotIdx, invMod.key, invMod.rank)
                if success then
                    table.remove(state.runMods.inventory, selectedInventoryMod.index)
                    selectedInventoryMod = nil
                    if state.playSfx then state.playSfx('gem') end
                end
                orbiter.buildUI()
            elseif currentSlotMod then
                if selectedSlotIndex == slotIdx then
                    selectedSlotIndex = nil
                else
                    selectedSlotIndex = slotIdx
                end
                orbiter.buildUI()
            else
                selectedSlotIndex = slotIdx
                orbiter.buildUI()
            end
        end)
        
        -- Right click - quick unequip
        slot:on('rightClick', function()
            if currentSlotMod then
                mods.unequipFromRunSlot(state, category, key, slotIdx)
                mods.addToRunInventory(state, currentSlotMod.key, category, currentSlotMod.rank, currentSlotMod.rarity)
                if state.playSfx then state.playSfx('gem') end
                orbiter.buildUI()
            elseif selectedInventoryMod then
                local invMod = selectedInventoryMod.modData
                local success = mods.equipToRunSlot(state, category, key, slotIdx, invMod.key, invMod.rank)
                if success then
                    table.remove(state.runMods.inventory, selectedInventoryMod.index)
                    selectedInventoryMod = nil
                    if state.playSfx then state.playSfx('gem') end
                end
                orbiter.buildUI()
            end
        end)
        
        parent:addChild(slot)
        modSlots[i] = slot
    end
end

function orbiter.buildInventory(parent)
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    
    local baseY = currentTab == 'weapons' and 72 or 52
    local invY = baseY + 16 + 2 * (SLOT_SIZE + SLOT_GAP) + 8
    
    local inventory = mods.getRunInventoryByCategory(state, category)
    
    local invLabel = Text.new({
        x = PANEL_X, y = invY,
        text = string.format("背包 (%d)", #inventory),
        color = {0.8, 0.85, 0.9, 1}
    })
    parent:addChild(invLabel)
    
    invSlots = {}
    local invGridY = invY + 14
    
    -- Inventory scrollable container
    local scrollW = INV_COLS * (SLOT_SIZE + SLOT_GAP)
    local scrollH = SCREEN_H - invGridY - 24
    local scrollContainer = ui.newScrollContainer({
        x = PANEL_X, y = invGridY,
        w = scrollW, h = scrollH,
        scrollbarVisible = true
    })
    parent:addChild(scrollContainer)
    
    for idx, modData in ipairs(inventory) do
        local row = math.floor((idx - 1) / INV_COLS)
        local col = (idx - 1) % INV_COLS
        
        local invX = col * (SLOT_SIZE + SLOT_GAP)
        local invYPos = row * (SLOT_SIZE + SLOT_GAP)
        
        local actualIdx = 0
        for i, m in ipairs(state.runMods.inventory) do
            if m == modData then
                actualIdx = i
                break
            end
        end
        
        local isSelected = selectedInventoryMod and selectedInventoryMod.index == actualIdx
        local modColor = modsModel.getColor(modData.rarity)
        local capturedModData = modData
        local capturedIdx = actualIdx
        
        local slot = ModSlot.new({
            x = invX, y = invYPos,
            w = SLOT_SIZE, h = SLOT_SIZE,
            content = modData.key,
            modData = modData,
            category = category,
            slotType = 'inventory',
            slotIndex = capturedIdx,
            selected = isSelected,
            emptyColor = {modColor[1] * 0.15, modColor[2] * 0.15, modColor[3] * 0.15, 0.9},
            filledColor = {modColor[1] * 0.25, modColor[2] * 0.25, modColor[3] * 0.25, 0.9},
            borderColor = isSelected and {1, 1, 0.3, 1} or {modColor[1], modColor[2], modColor[3], 1},
            selectedBorderColor = {1, 1, 0.3, 1},
            tooltip = modsModel.getModName(modData.category, modData.key) .. ": " .. modsModel.getModDesc(modData.category, modData.key)
        })
        
        slot:on('click', function()
            if selectedInventoryMod and selectedInventoryMod.index == capturedIdx then
                selectedInventoryMod = nil
            elseif selectedSlotIndex then
                local success = mods.equipToRunSlot(state, category, key, selectedSlotIndex, capturedModData.key, capturedModData.rank)
                if success then
                    table.remove(state.runMods.inventory, capturedIdx)
                    selectedSlotIndex = nil
                    if state.playSfx then state.playSfx('gem') end
                end
                orbiter.buildUI()
                return
            else
                selectedInventoryMod = {index = capturedIdx, modData = capturedModData}
            end
            orbiter.buildUI()
        end)
        
        slot:on('rightClick', function()
            local slotData = mods.getRunSlotData(state, category, key)
            local slotsData = slotData and slotData.slots or {}
            
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
            elseif selectedSlotIndex and slotsData[selectedSlotIndex] then
                local oldMod = slotsData[selectedSlotIndex]
                mods.unequipFromRunSlot(state, category, key, selectedSlotIndex)
                local success = mods.equipToRunSlot(state, category, key, selectedSlotIndex, capturedModData.key, capturedModData.rank)
                if success then
                    table.remove(state.runMods.inventory, capturedIdx)
                    mods.addToRunInventory(state, oldMod.key, category, oldMod.rank, oldMod.rarity)
                    selectedSlotIndex = nil
                    if state.playSfx then state.playSfx('gem') end
                end
            end
            orbiter.buildUI()
        end)
        
        scrollContainer:addChild(slot)
        invSlots[idx] = slot
    end

end

function orbiter.buildStatsPanel(parent)
    local statsX = SCREEN_W / 2 + 30
    local statsY = 30
    
    -- Decorative line
    local line = Panel.new({
        x = SCREEN_W / 2 + 10, y = 28,
        w = 1, h = SCREEN_H - 60,
        bgColor = {0.25, 0.35, 0.5, 0.4}
    })
    parent:addChild(line)
    
    -- Stats header
    local header = Text.new({
        x = statsX, y = statsY,
        text = "属性加成",
        color = {0.85, 0.9, 1.0, 1}
    })
    parent:addChild(header)
    
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    local slotData = mods.getRunSlotData(state, category, key)
    local slotsData = slotData and slotData.slots or {}
    local catalog = mods.getCatalog(category)
    
    local bonuses = {}
    for _, slotMod in ipairs(slotsData) do
        if slotMod then
            local def = catalog and catalog[slotMod.key]
            if def then
                local stat = def.stat
                local rank = slotMod.rank or 0
                local value = def.value and def.value[rank + 1] or 0
                bonuses[stat] = (bonuses[stat] or 0) + value
            end
        end
    end
    
    local statNames = {
        maxHp = "HP", armor = "护甲", maxShield = "护盾", maxEnergy = "能量",
        speed = "移速", abilityStrength = "技能强度", abilityEfficiency = "技能效率",
        abilityDuration = "技能时长", abilityRange = "技能范围", energyRegen = "能量回复",
        damage = "伤害", critChance = "暴击率", critMult = "暴击倍率",
        fireRate = "射速", multishot = "多重", statusChance = "异常率",
        magSize = "弹匣", reloadSpeed = "换弹", meleeDamage = "近战伤害",
        healthLink = "HP继承", armorLink = "护甲继承", meleeLeeech = "近战吸血"
    }
    
    local bonusY = statsY + 18
    statsTexts = {}
    
    if next(bonuses) then
        for stat, value in pairs(bonuses) do
            local name = statNames[stat] or stat
            local display = string.format("%s +%.0f%%", name, value * 100)
            local text = Text.new({
                x = statsX, y = bonusY,
                text = display,
                color = {0.5, 1.0, 0.5, 1}
            })
            parent:addChild(text)
            table.insert(statsTexts, text)
            bonusY = bonusY + 14
        end
    else
        local noBonus = Text.new({
            x = statsX, y = bonusY,
            text = "(装备MOD获得加成)",
            color = {0.45, 0.45, 0.5, 1}
        })
        parent:addChild(noBonus)
    end
    
    -- Selected mod info
    if selectedInventoryMod then
        local modData = selectedInventoryMod.modData
        local infoY = SCREEN_H - 100
        
        local nameText = Text.new({
            x = statsX, y = infoY,
            text = modsModel.getModName(modData.category, modData.key),
            color = modsModel.getColor(modData.rarity)
        })
        parent:addChild(nameText)
        
        local descText = Text.new({
            x = statsX, y = infoY + 14,
            text = modsModel.getModDesc(modData.category, modData.key),
            color = {0.65, 0.65, 0.75, 1}
        })
        parent:addChild(descText)
        
        local costText = Text.new({
            x = statsX, y = infoY + 28,
            text = string.format("Lv%d | 消耗%d", modData.rank or 0, getModCost(modData.category, modData.key, modData.rank)),
            color = {0.55, 0.75, 1.0, 1}
        })
        parent:addChild(costText)
    end
    
    -- Gold and HP display
    local goldText = Text.new({
        x = SCREEN_W - 100, y = SCREEN_H - 60,
        text = "金: " .. tostring(state.runCurrency or 0),
        color = {1, 0.9, 0.4, 1}
    })
    parent:addChild(goldText)
    
    local p = state.player or {}
    local stats = p.stats or {}
    local maxHp = stats.maxHp or p.maxHp or 100
    local curHp = p.hp or 0
    local hpPct = curHp / maxHp
    local hpColor
    if hpPct > 0.5 then
        hpColor = {0.4, 1, 0.4, 1}
    elseif hpPct > 0.25 then
        hpColor = {1, 0.8, 0.3, 1}
    else
        hpColor = {1, 0.4, 0.4, 1}
    end
    
    local hpText = Text.new({
        x = SCREEN_W - 100, y = SCREEN_H - 75,
        text = string.format("HP: %d/%d", math.floor(curHp), math.floor(maxHp)),
        color = hpColor
    })
    parent:addChild(hpText)
end

function orbiter.buildActionButtons(parent)
    local buttonY = SCREEN_H - 40
    
    -- Heal button
    local healCost = 30 + (state.rooms and state.rooms.roomIndex or 1) * 5
    local p = state.player or {}
    local stats = p.stats or {}
    local maxHp = stats.maxHp or p.maxHp or 100
    local canHeal = ((p.hp or 0) < maxHp) and (state.runCurrency or 0) >= healCost
    
    local healBtn = Button.new({
        x = PANEL_X, y = buttonY,
        w = 90, h = 24,
        text = "回血(" .. healCost .. "G)",
        normalColor = canHeal and {0.25, 0.45, 0.25, 1} or {0.15, 0.15, 0.15, 1},
        hoverColor = canHeal and {0.35, 0.6, 0.35, 1} or {0.15, 0.15, 0.15, 1},
        textColor = canHeal and {1, 1, 1, 1} or {0.4, 0.4, 0.4, 1}
    })
    healBtn:on('click', function()
        if canHeal then
            state.runCurrency = (state.runCurrency or 0) - healCost
            local heal = math.floor(maxHp * 0.5)
            p.hp = math.min(maxHp, (p.hp or 0) + heal)
            if state.playSfx then state.playSfx('gem') end
            orbiter.buildUI()
        end
    end)
    parent:addChild(healBtn)
    
    -- Refill ammo button
    local ammoCost = 20
    local canRefill = (state.runCurrency or 0) >= ammoCost
    
    local ammoBtn = Button.new({
        x = PANEL_X + 95, y = buttonY,
        w = 90, h = 24,
        text = "弹药(" .. ammoCost .. "G)",
        normalColor = canRefill and {0.25, 0.35, 0.45, 1} or {0.15, 0.15, 0.15, 1},
        hoverColor = canRefill and {0.35, 0.45, 0.6, 1} or {0.15, 0.15, 0.15, 1},
        textColor = canRefill and {1, 1, 1, 1} or {0.4, 0.4, 0.4, 1}
    })
    ammoBtn:on('click', function()
        if canRefill then
            state.runCurrency = (state.runCurrency or 0) - ammoCost
            for weaponKey, w in pairs(state.inventory and state.inventory.weapons or {}) do
                if w.reserve ~= nil then
                    local def = state.catalog and state.catalog[weaponKey]
                    local maxRes = (def and def.base and def.base.maxReserve) or 120
                    w.reserve = maxRes
                end
            end
            if state.playSfx then state.playSfx('gem') end
            orbiter.buildUI()
        end
    end)
    parent:addChild(ammoBtn)
    
    -- Continue button
    local continueBtn = Button.new({
        x = SCREEN_W - 110, y = buttonY,
        w = 100, h = 28,
        text = "继续战斗 >>",
        normalColor = {0.2, 0.4, 0.6, 1},
        hoverColor = {0.3, 0.55, 0.8, 1},
        textColor = {1, 1, 1, 1}
    })
    continueBtn:on('click', function()
        orbiter.exit()
    end)
    parent:addChild(continueBtn)
end

-- =============================================================================
-- EXIT AND APPLY MODS
-- =============================================================================

function orbiter.exit()
    local p = state.player
    if not p then
        state.gameState = 'PLAYING'
        return
    end
    
    local stats = p.stats or {}
    if not state._basePlayerStats then
        state._basePlayerStats = {
            maxHp = stats.maxHp or p.maxHp or 100,
            maxShield = stats.maxShield or p.maxShield or 0,
            maxEnergy = stats.maxEnergy or p.maxEnergy or 100,
            armor = stats.armor or 0,
            moveSpeed = stats.moveSpeed or 180,
            might = stats.might or 1.0,
            energyRegen = stats.energyRegen or 0
        }
    end
    
    local base = state._basePlayerStats
    
    local baseStats = {
        maxHp = base.maxHp,
        maxShield = base.maxShield,
        maxEnergy = base.maxEnergy,
        armor = base.armor,
        speed = base.moveSpeed,
        moveSpeed = base.moveSpeed,
        might = base.might,
        abilityStrength = 0,
        abilityEfficiency = 0,
        abilityDuration = 0,
        abilityRange = 0,
        energyRegen = base.energyRegen
    }
    
    local modded = mods.applyRunWarframeMods(state, baseStats)
    
    if modded.maxHp then 
        local oldMaxHp = p.maxHp or 100
        p.maxHp = math.floor(modded.maxHp)
        if p.maxHp > oldMaxHp then
            p.hp = math.min(p.maxHp, p.hp + (p.maxHp - oldMaxHp))
        end
    end
    if modded.maxShield then p.maxShield = math.floor(modded.maxShield) end
    if modded.maxEnergy then p.maxEnergy = math.floor(modded.maxEnergy) end
    
    if p.stats then
        if modded.maxHp then p.stats.maxHp = math.floor(modded.maxHp) end
        if modded.maxShield then p.stats.maxShield = math.floor(modded.maxShield) end
        if modded.maxEnergy then p.stats.maxEnergy = math.floor(modded.maxEnergy) end
        if modded.armor then p.stats.armor = modded.armor end
        if modded.moveSpeed then p.stats.moveSpeed = modded.moveSpeed end
        if modded.speed then p.stats.moveSpeed = modded.speed end
        if modded.might then p.stats.might = modded.might end
        
        p.stats.abilityStrength = 1.0 + (modded.abilityStrength or 0)
        p.stats.abilityEfficiency = 1.0 + (modded.abilityEfficiency or 0)
        p.stats.abilityDuration = 1.0 + (modded.abilityDuration or 0)
        p.stats.abilityRange = 1.0 + (modded.abilityRange or 0)
        if modded.energyRegen then p.stats.energyRegen = modded.energyRegen end
    end
    
    print("[ORBITER] Applied run MODs")
    
    -- Recompute pet stats to apply companion mods
    local pets = require('pets')
    pets.recompute(state)
    
    -- Reset UI to HUD before returning to gameplay
    hud.init(state)
    
    state.gameState = 'PLAYING'
end

-- =============================================================================
-- INPUT HANDLING
-- =============================================================================

function orbiter.keypressed(key)
    if key == 'escape' or key == 'tab' then
        orbiter.exit()
        return true
    end
    return core.keypressed(key)
end

function orbiter.mousepressed(x, y, button)
    return core.mousepressed(x, y, button)
end

function orbiter.mousereleased(x, y, button)
    return core.mousereleased(x, y, button)
end

function orbiter.mousemoved(x, y, dx, dy)
    return core.mousemoved(x, y, dx, dy)
end

-- =============================================================================
-- UPDATE AND DRAW
-- =============================================================================

function orbiter.update(dt)
    core.update(dt)
end

function orbiter.draw()
    core.draw()
end

return orbiter
