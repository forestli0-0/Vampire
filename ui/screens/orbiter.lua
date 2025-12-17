-- =============================================================================
-- ORBITER SCREEN (飞船整备界面)
-- Warframe-style Roguelike: Configure MODs between rooms
-- =============================================================================

local orbiter = {}

local mods = require('mods')
local Widget = require('ui.widgets.widget')
local Button = require('ui.widgets.button')
local Text = require('ui.widgets.text')
local Slot = require('ui.widgets.slot')

local state = nil
local widgets = {}
local currentTab = 'warframe'  -- 'warframe', 'weapons', 'companion'
local selectedWeaponKey = nil
local selectedInventoryMod = nil  -- {index, modData}
local selectedSlotIndex = nil

-- Layout constants
local PANEL_X = 40
local PANEL_Y = 80
local PANEL_WIDTH = 340
local SLOT_SIZE = 50
local SLOT_GAP = 8

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

local function getModDesc(category, modKey)
    local catalog = mods.getCatalog(category)
    if catalog and catalog[modKey] then
        return catalog[modKey].desc or ""
    end
    return ""
end

local function getModCost(category, modKey, rank)
    local catalog = mods.getCatalog(category)
    if catalog and catalog[modKey] and catalog[modKey].cost then
        rank = math.max(0, math.min(5, rank or 0))
        return catalog[modKey].cost[rank + 1] or 4
    end
    return 4
end

-- Helper to create button with click handler
local function createButton(opts, onClick)
    local btn = Button.new({
        x = opts.x or 0,
        y = opts.y or 0,
        w = opts.w or opts.width or 100,
        h = opts.h or opts.height or 30,
        text = opts.text or "",
        normalColor = opts.normalColor or opts.bgColor or {0.2, 0.2, 0.3, 1},
        hoverColor = opts.hoverColor or {0.3, 0.4, 0.5, 1},
        textColor = opts.textColor or {1, 1, 1, 1}
    })
    if onClick then
        btn:on('click', onClick)
    end
    return btn
end

-- Helper to create slot with click handler
local function createSlot(opts, onClick)
    local slot = Slot.new({
        x = opts.x or 0,
        y = opts.y or 0,
        w = opts.w or opts.width or SLOT_SIZE,
        h = opts.h or opts.height or SLOT_SIZE,
        content = opts.content,
        label = opts.label,
        sublabel = opts.sublabel,
        emptyColor = opts.emptyColor or opts.bgColor or {0.15, 0.15, 0.2, 0.8},
        filledColor = opts.filledColor or opts.bgColor or {0.2, 0.2, 0.3, 0.8},
        borderColor = opts.borderColor or {0.3, 0.3, 0.4, 1},
        selected = opts.selected or false
    })
    if onClick then
        slot:on('click', onClick)
    end
    return slot
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function orbiter.init(s)
    state = s
    widgets = {}
    
    -- Initialize runMods if not present
    if not state.runMods then
        mods.initRunMods(state)
    end
    
    -- Determine default weapon key
    if state.inventory and state.inventory.weaponSlots then
        selectedWeaponKey = state.inventory.weaponSlots.ranged or state.inventory.weaponSlots.melee
    end
    
    orbiter.buildUI()
end

function orbiter.buildUI()
    widgets = {}
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    
    -- Title (using simple text - Text widget may not render correctly, we'll draw manually)
    
    -- Tab buttons
    local tabY = 60
    local tabs = {
        {key = 'warframe', name = '角色MOD'},
        {key = 'weapons', name = '武器MOD'},
        {key = 'companion', name = '守护者MOD'}
    }
    
    local tabX = PANEL_X
    for _, tab in ipairs(tabs) do
        local isActive = (currentTab == tab.key)
        local tabKey = tab.key
        local btn = createButton({
            x = tabX, y = tabY,
            w = 100, h = 30,
            text = tab.name,
            normalColor = isActive and {0.3, 0.5, 0.8, 1} or {0.2, 0.2, 0.3, 1},
            hoverColor = {0.4, 0.6, 0.9, 1},
            textColor = isActive and {1, 1, 1, 1} or {0.7, 0.7, 0.8, 1}
        }, function()
            currentTab = tabKey
            selectedInventoryMod = nil
            selectedSlotIndex = nil
            orbiter.buildUI()
        end)
        table.insert(widgets, btn)
        tabX = tabX + 110
    end
    
    -- Weapon selector (only for weapons tab)
    if currentTab == 'weapons' then
        local weaponY = tabY + 45
        local weaponX = PANEL_X + 80
        local slots = state.inventory and state.inventory.weaponSlots or {}
        for slotType, weaponKey in pairs(slots) do
            if weaponKey then
                local def = state.catalog and state.catalog[weaponKey]
                local name = def and def.name or weaponKey
                local isSelected = (selectedWeaponKey == weaponKey)
                local wKey = weaponKey
                
                local btn = createButton({
                    x = weaponX, y = weaponY,
                    w = 100, h = 26,
                    text = name,
                    normalColor = isSelected and {0.4, 0.6, 0.3, 1} or {0.25, 0.25, 0.3, 1},
                    hoverColor = {0.5, 0.7, 0.4, 1},
                    textColor = {1, 1, 1, 1}
                }, function()
                    selectedWeaponKey = wKey
                    selectedInventoryMod = nil
                    selectedSlotIndex = nil
                    orbiter.buildUI()
                end)
                table.insert(widgets, btn)
                weaponX = weaponX + 110
            end
        end
    end
    
    -- MOD Slots section
    local slotsY = currentTab == 'weapons' and (tabY + 85) or (tabY + 50)
    
    -- Get slot data
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    local slotData = mods.getRunSlotData(state, category, key)
    local slotsData = slotData and slotData.slots or {}
    local capacity = slotData and slotData.capacity or 30
    local catalog = mods.getCatalog(category)
    local usedCapacity = mods.getTotalCost(slotsData, catalog)
    
    -- Slot grid (2 rows of 4)
    local slotY = slotsY + 50
    for i = 1, 8 do
        local row = math.floor((i - 1) / 4)
        local col = (i - 1) % 4
        local slotMod = slotsData[i]
        
        local slotX = PANEL_X + col * (SLOT_SIZE + SLOT_GAP)
        local slotYPos = slotY + row * (SLOT_SIZE + SLOT_GAP)
        
        local hasContent = slotMod ~= nil
        local slotIdx = i
        local currentSlotMod = slotMod
        
        local slot = Slot.new({
            x = slotX, y = slotYPos,
            w = SLOT_SIZE, h = SLOT_SIZE,
            content = hasContent and slotMod.key or nil,
            sublabel = hasContent and ("R" .. (slotMod.rank or 0)) or nil,
            selected = (selectedSlotIndex == i),
            emptyColor = {0.12, 0.12, 0.18, 0.9},
            filledColor = hasContent and {getColor(slotMod.rarity)[1] * 0.35, getColor(slotMod.rarity)[2] * 0.35, getColor(slotMod.rarity)[3] * 0.35, 0.9} or {0.15, 0.15, 0.2, 0.9},
            borderColor = hasContent and {getColor(slotMod.rarity)[1], getColor(slotMod.rarity)[2], getColor(slotMod.rarity)[3], 1} or {0.3, 0.3, 0.4, 1},
            selectedBorderColor = {1, 1, 0.3, 1}
        })
        
        slot:on('click', function()
            if selectedInventoryMod then
                -- Equip selected inventory mod to this slot
                local invMod = selectedInventoryMod.modData
                local success = mods.equipToRunSlot(state, category, key, slotIdx, invMod.key, invMod.rank)
                if success then
                    -- Remove from inventory
                    table.remove(state.runMods.inventory, selectedInventoryMod.index)
                    selectedInventoryMod = nil
                    if state.playSfx then state.playSfx('gem') end
                end
                orbiter.buildUI()
            elseif currentSlotMod then
                -- Unequip this slot
                mods.unequipFromRunSlot(state, category, key, slotIdx)
                -- Add back to inventory
                mods.addToRunInventory(state, currentSlotMod.key, category, currentSlotMod.rank, currentSlotMod.rarity)
                orbiter.buildUI()
            else
                selectedSlotIndex = slotIdx
                orbiter.buildUI()
            end
        end)
        
        table.insert(widgets, slot)
    end
    
    -- Inventory section
    local invY = slotY + 2 * (SLOT_SIZE + SLOT_GAP) + 25
    
    -- Filter inventory by current category
    local inventory = mods.getRunInventoryByCategory(state, category)
    
    -- Inventory grid
    local invGridY = invY + 35
    local invCols = 6
    for idx, modData in ipairs(inventory) do
        local row = math.floor((idx - 1) / invCols)
        local col = (idx - 1) % invCols
        
        local invX = PANEL_X + col * (SLOT_SIZE + SLOT_GAP)
        local invYPos = invGridY + row * (SLOT_SIZE + SLOT_GAP)
        
        -- Find actual index in full inventory for removal
        local actualIdx = 0
        for i, m in ipairs(state.runMods.inventory) do
            if m == modData then
                actualIdx = i
                break
            end
        end
        
        local isSelected = selectedInventoryMod and selectedInventoryMod.index == actualIdx
        local modColor = getColor(modData.rarity)
        local capturedModData = modData
        local capturedIdx = actualIdx
        
        local slot = Slot.new({
            x = invX, y = invYPos,
            w = SLOT_SIZE, h = SLOT_SIZE,
            content = modData.key,
            sublabel = "R" .. (modData.rank or 0),
            selected = isSelected,
            emptyColor = {modColor[1] * 0.2, modColor[2] * 0.2, modColor[3] * 0.2, 0.9},
            filledColor = {modColor[1] * 0.3, modColor[2] * 0.3, modColor[3] * 0.3, 0.9},
            borderColor = isSelected and {1, 1, 0.3, 1} or {modColor[1], modColor[2], modColor[3], 1},
            selectedBorderColor = {1, 1, 0.3, 1}
        })
        
        slot:on('click', function()
            if selectedInventoryMod and selectedInventoryMod.index == capturedIdx then
                selectedInventoryMod = nil
            else
                selectedInventoryMod = {index = capturedIdx, modData = capturedModData}
            end
            orbiter.buildUI()
        end)
        
        table.insert(widgets, slot)
        
        -- Max 30 mods visible
        if idx >= 30 then break end
    end
    
    -- Action buttons
    local buttonY = screenH - 80
    
    -- Heal button (costs gold)
    local healCost = 30 + (state.rooms and state.rooms.roomIndex or 1) * 5
    local canHeal = (state.player.hp < state.player.maxHp) and (state.runCurrency or 0) >= healCost
    
    local healBtn = createButton({
        x = PANEL_X, y = buttonY,
        w = 130, h = 36,
        text = "回复HP (" .. healCost .. "G)",
        normalColor = canHeal and {0.25, 0.45, 0.25, 1} or {0.15, 0.15, 0.15, 1},
        hoverColor = canHeal and {0.35, 0.6, 0.35, 1} or {0.15, 0.15, 0.15, 1},
        textColor = canHeal and {1, 1, 1, 1} or {0.4, 0.4, 0.4, 1}
    }, function()
        if canHeal then
            state.runCurrency = (state.runCurrency or 0) - healCost
            local heal = math.floor(state.player.maxHp * 0.5)
            state.player.hp = math.min(state.player.maxHp, state.player.hp + heal)
            if state.playSfx then state.playSfx('gem') end
            orbiter.buildUI()
        end
    end)
    table.insert(widgets, healBtn)
    
    -- Refill ammo button
    local ammoCost = 20
    local canRefill = (state.runCurrency or 0) >= ammoCost
    
    local ammoBtn = createButton({
        x = PANEL_X + 140, y = buttonY,
        w = 130, h = 36,
        text = "补充弹药 (" .. ammoCost .. "G)",
        normalColor = canRefill and {0.25, 0.35, 0.45, 1} or {0.15, 0.15, 0.15, 1},
        hoverColor = canRefill and {0.35, 0.45, 0.6, 1} or {0.15, 0.15, 0.15, 1},
        textColor = canRefill and {1, 1, 1, 1} or {0.4, 0.4, 0.4, 1}
    }, function()
        if canRefill then
            state.runCurrency = (state.runCurrency or 0) - ammoCost
            -- Refill all weapons
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
    table.insert(widgets, ammoBtn)
    
    -- Continue button
    local continueBtn = createButton({
        x = screenW - 180, y = buttonY,
        w = 150, h = 40,
        text = "继续战斗 →",
        normalColor = {0.2, 0.4, 0.6, 1},
        hoverColor = {0.3, 0.55, 0.8, 1},
        textColor = {1, 1, 1, 1}
    }, function()
        orbiter.exit()
    end)
    table.insert(widgets, continueBtn)
end

function orbiter.exit()
    -- Apply run mods to player stats
    if state.player and state.player.stats then
        local newStats = mods.applyRunWarframeMods(state, state.player.stats)
        for k, v in pairs(newStats) do
            state.player.stats[k] = v
        end
    end
    
    -- Return to doors phase
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
    return false
end

function orbiter.mousepressed(x, y, button)
    if button ~= 1 then return false end
    
    -- Check all widgets for hit
    for _, widget in ipairs(widgets) do
        if widget.contains and widget:contains(x, y) then
            if widget.onPress then
                widget:onPress(button, x, y)
            end
            if widget.onClick then
                widget:onClick(x, y)
            end
            return true
        end
    end
    return false
end

function orbiter.mousemoved(x, y)
    for _, widget in ipairs(widgets) do
        if widget.contains then
            local isInside = widget:contains(x, y)
            if isInside and not widget.hovered then
                widget.hovered = true
                if widget.onHoverStart then widget:onHoverStart() end
            elseif not isInside and widget.hovered then
                widget.hovered = false
                if widget.onHoverEnd then widget:onHoverEnd() end
            end
        end
    end
end

-- =============================================================================
-- RENDERING
-- =============================================================================

function orbiter.draw()
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    
    -- Dark background
    love.graphics.setColor(0.06, 0.06, 0.1, 1)
    love.graphics.rectangle('fill', 0, 0, screenW, screenH)
    
    -- Title
    love.graphics.setColor(0.9, 0.95, 1.0, 1)
    if state.font then love.graphics.setFont(state.titleFont or state.font) end
    love.graphics.printf("ORBITER - 飞船整备", 0, 20, screenW, 'center')
    
    -- Tab indicator
    love.graphics.setColor(0.3, 0.4, 0.5, 0.3)
    love.graphics.rectangle('fill', PANEL_X - 10, 55, 340, 40, 4, 4)
    
    -- Section labels
    if state.font then love.graphics.setFont(state.font) end
    local tabY = 60
    local slotsY = currentTab == 'weapons' and (tabY + 85) or (tabY + 50)
    
    love.graphics.setColor(0.8, 0.85, 0.9, 1)
    love.graphics.print("已装备 MOD (8槽)", PANEL_X, slotsY + 2)
    
    -- Get slot data for capacity display
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    local slotData = mods.getRunSlotData(state, category, key)
    local slotsData = slotData and slotData.slots or {}
    local capacity = slotData and slotData.capacity or 30
    local catalog = mods.getCatalog(category)
    local usedCapacity = mods.getTotalCost(slotsData, catalog)
    
    -- Capacity bar
    if usedCapacity > capacity then
        love.graphics.setColor(1, 0.4, 0.4, 1)
    else
        love.graphics.setColor(0.6, 0.85, 0.6, 1)
    end
    love.graphics.print(string.format("容量: %d / %d", usedCapacity, capacity), PANEL_X + 150, slotsY + 2)
    
    -- Inventory label
    local slotY = slotsY + 50
    local invY = slotY + 2 * (SLOT_SIZE + SLOT_GAP) + 25
    local inventory = mods.getRunInventoryByCategory(state, category)
    
    love.graphics.setColor(0.8, 0.85, 0.9, 1)
    love.graphics.print("MOD 背包", PANEL_X, invY + 2)
    love.graphics.setColor(0.5, 0.55, 0.6, 1)
    love.graphics.print(string.format("(%d个)", #inventory), PANEL_X + 70, invY + 2)
    
    -- Decorative line
    love.graphics.setColor(0.25, 0.35, 0.5, 0.4)
    love.graphics.setLineWidth(1)
    love.graphics.line(screenW / 2 + 10, 60, screenW / 2 + 10, screenH - 100)
    
    -- Right panel - Stats
    local statsX = screenW / 2 + 40
    local statsY = 80
    
    love.graphics.setColor(0.85, 0.9, 1.0, 1)
    love.graphics.print("当前属性加成", statsX, statsY)
    
    -- Calculate bonuses
    local bonusY = statsY + 30
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
        maxHp = "生命值", armor = "护甲", maxShield = "护盾", maxEnergy = "能量",
        speed = "移速", abilityStrength = "技能强度", abilityEfficiency = "技能效率",
        abilityDuration = "技能持续", abilityRange = "技能范围", energyRegen = "能量回复",
        damage = "伤害", critChance = "暴击率", critMult = "暴击倍率",
        fireRate = "射速", multishot = "多重射击", statusChance = "异常几率",
        magSize = "弹匣", reloadSpeed = "换弹速度", meleeDamage = "近战伤害",
        healthLink = "生命继承", armorLink = "护甲继承", meleeLeeech = "近战吸血"
    }
    
    if next(bonuses) then
        for stat, value in pairs(bonuses) do
            local name = statNames[stat] or stat
            local display = string.format("+%.0f%%", value * 100)
            love.graphics.setColor(0.5, 1.0, 0.5, 1)
            love.graphics.print(name .. ": " .. display, statsX, bonusY)
            bonusY = bonusY + 20
        end
    else
        love.graphics.setColor(0.45, 0.45, 0.5, 1)
        love.graphics.print("(无加成 - 装备MOD获得加成)", statsX, bonusY)
    end
    
    -- Selected mod info
    if selectedInventoryMod then
        local modData = selectedInventoryMod.modData
        local infoY = screenH - 180
        
        love.graphics.setColor(getColor(modData.rarity))
        love.graphics.print(getModName(modData.category, modData.key), statsX, infoY)
        
        love.graphics.setColor(0.65, 0.65, 0.75, 1)
        love.graphics.print(getModDesc(modData.category, modData.key), statsX, infoY + 20)
        
        love.graphics.setColor(0.55, 0.75, 1.0, 1)
        love.graphics.print(string.format("等级: %d | 消耗: %d", modData.rank or 0, getModCost(modData.category, modData.key, modData.rank)), statsX, infoY + 40)
        
        love.graphics.setColor(1, 1, 0.5, 1)
        love.graphics.print("点击槽位装备此MOD", statsX, infoY + 60)
    end
    
    -- Gold and HP display
    love.graphics.setColor(1, 0.9, 0.4, 1)
    love.graphics.print("金币: " .. tostring(state.runCurrency or 0), screenW - 180, screenH - 115)
    
    local hpPct = state.player.hp / state.player.maxHp
    if hpPct > 0.5 then
        love.graphics.setColor(0.4, 1, 0.4, 1)
    elseif hpPct > 0.25 then
        love.graphics.setColor(1, 0.8, 0.3, 1)
    else
        love.graphics.setColor(1, 0.4, 0.4, 1)
    end
    love.graphics.print(string.format("HP: %d / %d", math.floor(state.player.hp), state.player.maxHp), screenW - 180, screenH - 135)
    
    -- Instructions
    love.graphics.setColor(0.45, 0.45, 0.55, 1)
    love.graphics.printf("点击背包MOD选中 → 点击槽位装备 | 点击已装备MOD卸下 | ESC/Tab 退出", 0, screenH - 25, screenW, 'center')
    
    -- Draw all widgets
    for _, widget in ipairs(widgets) do
        if widget.draw then
            widget:draw()
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function orbiter.update(dt)
    -- Animation updates
    for _, widget in ipairs(widgets) do
        if widget.update then
            widget:update(dt)
        end
    end
end

return orbiter
