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

local PERCENT_STATS = {
    critChance = true,
    statusChance = true,
    multishot = true,
    abilityStrength = true,
    abilityEfficiency = true,
    abilityDuration = true,
    abilityRange = true,
    energyRegen = true,
    healthLink = true,
    armorLink = true,
    moveSpeed = true,
    fireRate = true,
    reloadSpeed = true,
    magSize = true,
    damage = true,
    meleeDamage = true,
    range = true,
    speed = true,
    dashCooldown = true,
    dashDistance = true,
    bloom = true,
    recoil = true,
    meleeLeeech = true
}

local function getRankValue(value, rank)
    if type(value) == 'table' then
        return value[rank + 1] or 0
    end
    return value or 0
end

local function trimNumber(s)
    if not s then return s end
    s = s:gsub("(%..-)0+$", "%1")
    s = s:gsub("%.$", "")
    return s
end

local function formatSignedNumber(value)
    local sign = value >= 0 and "+" or "-"
    local absVal = math.abs(value)
    if math.abs(absVal - math.floor(absVal)) < 0.001 then
        return sign .. tostring(math.floor(absVal))
    end
    return sign .. trimNumber(string.format("%.2f", absVal))
end

local function formatPercent(value)
    local sign = value >= 0 and "+" or "-"
    local pct = math.floor(math.abs(value) * 100 + 0.5)
    return sign .. tostring(pct) .. "%"
end

local function formatStatValue(stat, kind, value, element)
    if stat == 'element' or element then
        return formatPercent(value)
    end
    if stat == 'critMult' then
        return formatSignedNumber(value) .. "x"
    end
    if kind == 'mult' or PERCENT_STATS[stat] then
        return formatPercent(value)
    end
    return formatSignedNumber(value)
end

local function buildStatLines(def, rank)
    if not def then return {} end
    local lines = {}

    local function pushLine(entry, fallback)
        if not entry then return end
        local stat = entry.stat or (fallback and fallback.stat)
        local kind = entry.type or (fallback and fallback.type) or 'add'
        local element = entry.element or (fallback and fallback.element)
        local value = getRankValue(entry.value or (fallback and fallback.value), rank)
        if math.abs(value or 0) < 0.0001 then return end

        local label = stat
        if stat == 'element' or element then
            label = element or stat
        else
            label = STAT_ABBREVS[stat] or stat or "?"
        end
        table.insert(lines, label .. " " .. formatStatValue(stat, kind, value, element))
    end

    if def.stats then
        for _, entry in ipairs(def.stats) do
            pushLine(entry, def)
        end
    else
        pushLine(def, def)
    end

    return lines
end

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

function model.getModStatLines(category, modKey, rank)
    local catalog = category and mods.getCatalog(category)
    if not catalog or not catalog[modKey] then return {} end
    local def = catalog[modKey]
    local r = tonumber(rank) or 0
    return buildStatLines(def, math.max(0, math.floor(r)))
end

function model.buildModTooltip(category, modKey, rank)
    local catalog = category and mods.getCatalog(category)
    if not catalog or not catalog[modKey] then return nil end
    local def = catalog[modKey]
    local lines = {}

    local name = def.name or modKey
    if name and name ~= "" then table.insert(lines, name) end
    if def.desc and def.desc ~= "" then
        table.insert(lines, def.desc)
    end

    local statLines = model.getModStatLines(category, modKey, rank)
    for _, line in ipairs(statLines) do
        table.insert(lines, line)
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

return model
