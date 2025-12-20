local defs = require('data.defs.progression')
local mods = require('mods')

local progression = {}

local function computeBonuses(level)
    local per = defs.rankUp or {}
    local base = defs.modCapacityBase or 1
    local lvl = math.max(1, math.floor(level or 1))
    local steps = math.max(0, lvl - 1)
    return {
        maxHp = steps * (per.maxHp or 0),
        maxShield = steps * (per.maxShield or 0),
        maxEnergy = steps * (per.maxEnergy or 0),
        modCapacity = base + steps * (per.modCapacity or 0)
    }
end

local function applyCapacity(state, capacity)
    if not state then return end
    if not state.runMods then return end

    state.runMods.warframe = state.runMods.warframe or {slots = {}, capacity = capacity}
    state.runMods.warframe.capacity = capacity
    state.runMods.companion = state.runMods.companion or {slots = {}, capacity = capacity}
    state.runMods.companion.capacity = capacity

    state.runMods.weapons = state.runMods.weapons or {}
    for _, slotData in pairs(state.runMods.weapons) do
        if slotData then
            slotData.capacity = capacity
        end
    end
end

function progression.recompute(state)
    if not (state and state.player) then return end
    local bonuses = computeBonuses(state.player.level)
    state.progression = state.progression or {}
    state.progression.rankBonuses = {
        maxHp = bonuses.maxHp,
        maxShield = bonuses.maxShield,
        maxEnergy = bonuses.maxEnergy
    }
    state.progression.modCapacity = bonuses.modCapacity
    applyCapacity(state, bonuses.modCapacity)
end

function progression.applyRankUp(state)
    if not state then return end
    progression.recompute(state)
    mods.refreshActiveStats(state)
end

return progression
