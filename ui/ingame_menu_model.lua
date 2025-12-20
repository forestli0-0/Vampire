local mods = require('mods')
local modsModel = require('ui.mods_model')
local pets = require('pets')
local weapons = require('weapons')

local model = {}

local function getRunModContext(currentTab, selectedWeaponKey)
    local category = currentTab == 'weapons' and 'weapons' or currentTab
    local key = currentTab == 'weapons' and selectedWeaponKey or nil
    return category, key
end

function model.getColor(rarity)
    return modsModel.getColor(rarity)
end

function model.getModName(category, modKey)
    return modsModel.getModName(category, modKey)
end

function model.getModShortName(category, modKey)
    return modsModel.getModShortName(category, modKey)
end

function model.getModDesc(category, modKey)
    return modsModel.getModDesc(category, modKey)
end

function model.getStatAbbrev(category, modKey)
    return modsModel.getStatAbbrev(category, modKey)
end

function model.getWeaponSelectorData(state, selectedWeaponKey)
    local data = {}
    local slots = state.inventory and state.inventory.weaponSlots or {}
    for _, slotData in pairs(slots) do
        local weaponKey = slotData and slotData.key
        if weaponKey then
            local def = state.catalog and state.catalog[weaponKey]
            local name = def and def.name or weaponKey
            if #name > 5 then name = name:sub(1, 4) .. ".." end
            table.insert(data, {
                key = weaponKey,
                label = name,
                isSelected = (selectedWeaponKey == weaponKey)
            })
        end
    end
    return data
end

function model.buildStatsLines(state, currentTab, selectedWeaponKey)
    local lines = {}
    local p = state.player or {}
    local stats = p.stats or {}

    if currentTab == 'warframe' then
        local maxHp = stats.maxHp or p.maxHp or 100
        local maxShield = stats.maxShield or p.maxShield or 100
        local maxEnergy = stats.maxEnergy or p.maxEnergy or 100
        table.insert(lines, {label = "HP", value = string.format("%d/%d", math.floor(p.hp or 0), math.floor(maxHp))})
        table.insert(lines, {label = "护盾", value = string.format("%d/%d", math.floor(p.shield or 0), math.floor(maxShield))})
        table.insert(lines, {label = "能量", value = string.format("%d/%d", math.floor(p.energy or 0), math.floor(maxEnergy))})
        table.insert(lines, {label = "护甲", value = string.format("%d", stats.armor or 0)})
        table.insert(lines, {label = "移速", value = string.format("%d", stats.moveSpeed or 180)})
        table.insert(lines, {label = "强度", value = string.format("%.0f%%", (stats.abilityStrength or 1) * 100)})
        table.insert(lines, {label = "持续", value = string.format("%.0f%%", (stats.abilityDuration or 1) * 100)})
        table.insert(lines, {label = "效率", value = string.format("%.0f%%", (stats.abilityEfficiency or 1) * 100)})
        table.insert(lines, {label = "范围", value = string.format("%.0f%%", (stats.abilityRange or 1) * 100)})
        table.insert(lines, {label = "回能", value = string.format("%.1f/s", stats.energyRegen or 2)})
    elseif currentTab == 'weapons' then
        local weaponKey = selectedWeaponKey
        local weaponDef = state.catalog and state.catalog[weaponKey]
        local weaponData = state.inventory and state.inventory.weapons and state.inventory.weapons[weaponKey]

        if weaponDef then
            local calculated = weapons.calculateStats(state, weaponKey)
            table.insert(lines, {label = "伤害", value = string.format("%.0f", calculated.damage or 10)})
            table.insert(lines, {label = "多重", value = string.format("%.1f", (calculated.amount or 0) + 1)})
            table.insert(lines, {label = "暴击", value = string.format("%.0f%%", (calculated.critChance or 0.1) * 100)})
            table.insert(lines, {label = "倍率", value = string.format("%.1fx", (calculated.critMultiplier or calculated.critMult or 2.0))})
            table.insert(lines, {label = "异常", value = string.format("%.0f%%", (calculated.statusChance or 0) * 100)})
            local fireRate = calculated.fireRate or (1 / (calculated.cd or 1))
            table.insert(lines, {label = "射速", value = string.format("%.1f", fireRate)})
            if weaponData then
                local mag = weaponData.magazine or 0
                local maxMag = (calculated.maxMagazine) or calculated.magazine or mag
                table.insert(lines, {label = "弹匣", value = string.format("%d/%d", mag, maxMag)})
                table.insert(lines, {label = "储备", value = string.format("%d", weaponData.reserve or 0)})
            end
        else
            table.insert(lines, {label = "武器", value = "无"})
        end
    elseif currentTab == 'companion' then
        local pet = pets.getActive(state)
        if pet then
            local petDef = state.catalog and state.catalog[pet.key]
            table.insert(lines, {label = "名称", value = (petDef and petDef.name) or pet.key})
            table.insert(lines, {label = "HP", value = string.format("%d/%d", math.floor(pet.hp or 0), math.floor(pet.maxHp or 50))})
            table.insert(lines, {label = "攻击", value = string.format("%.0f", pet.damage or 10)})
        else
            table.insert(lines, {label = "同伴", value = "无"})
        end
    end

    return lines
end

function model.getEquippedModsData(state, currentTab, selectedWeaponKey)
    local category, key = getRunModContext(currentTab, selectedWeaponKey)
    local slotData = state.runMods and mods.getRunSlotData(state, category, key)
    local slotsData = slotData and slotData.slots or {}
    local capacity = slotData and slotData.capacity or 30
    local catalog = mods.getCatalog(category)
    local usedCapacity = mods.getTotalCost(slotsData, catalog)
    return {
        category = category,
        key = key,
        slotsData = slotsData,
        capacity = capacity,
        usedCapacity = usedCapacity
    }
end

function model.getInventoryData(state, currentTab, selectedWeaponKey)
    local category, key = getRunModContext(currentTab, selectedWeaponKey)
    local inventory = state.runMods and mods.getRunInventoryByCategory(state, category) or {}
    local runInventory = (state.runMods and state.runMods.inventory) or {}
    local list = {}
    for _, modData in ipairs(inventory) do
        local actualIdx = 0
        for i, m in ipairs(runInventory) do
            if m == modData then
                actualIdx = i
                break
            end
        end
        table.insert(list, {mod = modData, index = actualIdx})
    end
    return {
        category = category,
        key = key,
        list = list
    }
end

return model
