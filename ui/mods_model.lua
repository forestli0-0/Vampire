local mods = require('systems.mods')

local model = {}

local STAT_ABBREVS = {
    maxHp = "HP", armor = "AR", maxShield = "SH", maxEnergy = "EN",
    moveSpeed = "MOV", speed = "SP", abilityStrength = "STR", abilityEfficiency = "EFF",
    abilityDuration = "DUR", abilityRange = "RNG", energyRegen = "REG",
    damage = "DMG", critChance = "CC", critMult = "CD", fireRate = "FR",
    multishot = "MS", statusChance = "SC", magSize = "MAG", reloadSpeed = "RLD",
    meleeDamage = "MEL", healthLink = "HLK", armorLink = "ALK",
    dashCooldown = "DCD", dashDistance = "DST", dashInvincible = "IFR",
    range = "RNG", pierce = "PRC", element = "ELM"
}

local ELEMENT_ABBREVS = {
    HEAT = "HT",
    COLD = "CL",
    ELECTRIC = "EL",
    TOXIN = "TX",
    MAGNETIC = "MG",
    CORROSIVE = "CR",
    VIRAL = "VI",
    BLAST = "BL",
    GAS = "GS",
    RADIATION = "RD"
}

function model.getColor(rarity)
    local def = mods.RARITY[rarity]
    return def and def.color or {0.7, 0.7, 0.7}
end

function model.getModName(category, modKey)
    local catalog = category and mods.getCatalog(category)
    if catalog and catalog[modKey] then
        return catalog[modKey].name or modKey
    end
    return modKey
end

function model.getModShortName(category, modKey)
    local name = model.getModName(category, modKey)
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

function model.getModDesc(category, modKey)
    local catalog = category and mods.getCatalog(category)
    if catalog and catalog[modKey] then
        return catalog[modKey].desc or ""
    end
    return ""
end

function model.getStatAbbrev(category, modKey)
    local catalog = category and mods.getCatalog(category)
    if catalog and catalog[modKey] then
        local def = catalog[modKey]
        local stat = def.stat
        if stat == 'element' and def.element then
            return ELEMENT_ABBREVS[def.element] or STAT_ABBREVS[stat] or "+"
        end
        return STAT_ABBREVS[stat] or "+"
    end
    return "+"
end

return model
