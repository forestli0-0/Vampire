local enemies = require('enemies')

local calculator = {}

local PRIMARY = {HEAT=true, COLD=true, ELECTRIC=true, TOXIN=true}
local COMBOS = {
    HEAT = {COLD='BLAST', ELECTRIC='RADIATION', TOXIN='GAS'},
    COLD = {ELECTRIC='MAGNETIC', TOXIN='VIRAL'},
    ELECTRIC = {TOXIN='CORROSIVE'}
}

local ELEMENT_TO_EFFECT = {
    HEAT='FIRE',
    COLD='FREEZE',
    ELECTRIC='STATIC',
    TOXIN='TOXIN',
    MAGNETIC='MAGNETIC',
    CORROSIVE='CORROSIVE',
    VIRAL='VIRAL',
    BLAST='BLAST',
    GAS='GAS',
    RADIATION='RADIATION',
    SLASH='BLEED',
    IMPACT='HEAVY',
    PUNCTURE='PUNCTURE',
    OIL='OIL'
}

local function combineElements(elements)
    if not elements or #elements == 0 then return elements end
    local out = {}
    local i = 1
    while i <= #elements do
        local a = string.upper(elements[i])
        local b = elements[i + 1] and string.upper(elements[i + 1]) or nil
        if b and PRIMARY[a] and PRIMARY[b] then
            local combo = (COMBOS[a] and COMBOS[a][b]) or (COMBOS[b] and COMBOS[b][a])
            if combo then
                table.insert(out, combo)
                i = i + 2
            else
                table.insert(out, a)
                i = i + 1
            end
        else
            table.insert(out, a)
            i = i + 1
        end
    end
    return out
end

local function normalizeElements(effectType, provided)
    if provided and #provided > 0 then return provided end
    if not effectType then return nil end
    local e = string.upper(effectType)
    if e == 'FIRE' then return {'HEAT'} end
    if e == 'FREEZE' then return {'COLD'} end
    if e == 'STATIC' then return {'ELECTRIC'} end
    if e == 'BLEED' then return {'SLASH'} end
    if e == 'OIL' then return {'OIL'} end
    if e == 'HEAVY' then return {'IMPACT'} end
    if e == 'TOXIN' then return {'TOXIN'} end
    if e == 'MAGNETIC' then return {'MAGNETIC'} end
    if e == 'CORROSIVE' then return {'CORROSIVE'} end
    if e == 'VIRAL' then return {'VIRAL'} end
    if e == 'PUNCTURE' then return {'PUNCTURE'} end
    return nil
end

function calculator.createInstance(params)
    params = params or {}
    local elements = combineElements(normalizeElements(params.effectType, params.elements) or {})
    return {
        damage = params.damage or 0,
        critChance = params.critChance or 0,
        critMultiplier = params.critMultiplier or 1.5,
        statusChance = params.statusChance or 0,
        effectType = params.effectType,
        effectData = params.effectData,
        weaponTags = params.weaponTags,
        knock = params.knock or false,
        knockForce = params.knockForce or params.knockback or 0,
        elements = elements,
        damageBreakdown = params.damageBreakdown
    }
end

local function chooseProcElement(instance)
    local elems = instance.elements or {}
    if #elems == 0 then return nil end
    local breakdown = instance.damageBreakdown or {}
    local total = 0
    local weights = {}
    for idx, elem in ipairs(elems) do
        local key = string.upper(elem)
        local w = breakdown[key]
        if w == nil then w = 1 end
        if w < 0 then w = 0 end
        weights[idx] = w
        total = total + w
    end
    if total <= 0 then
        return elems[math.random(#elems)]
    end
    local r = math.random() * total
    for idx, elem in ipairs(elems) do
        r = r - (weights[idx] or 0)
        if r <= 0 then return elem end
    end
    return elems[#elems]
end

function calculator.applyStatus(state, enemy, instance, overrideChance)
    if not enemy or not instance then return {} end
    local chance = overrideChance
    if chance == nil then chance = instance.statusChance or 0 end
    if chance <= 0 then return {} end

    local elems = instance.elements or {}
    local applied = {}

    if #elems == 0 and instance.effectType then
        if math.random() < chance then
            enemies.applyStatus(state, enemy, instance.effectType, instance.damage, instance.weaponTags, instance.effectData)
            table.insert(applied, string.upper(instance.effectType))
        end
        return applied
    end

    local procs = math.floor(chance)
    local frac = chance - procs
    if math.random() < frac then procs = procs + 1 end
    if procs <= 0 then return applied end

    for _ = 1, procs do
        local elem = chooseProcElement(instance)
        if elem then
            local effectType = ELEMENT_TO_EFFECT[string.upper(elem)] or string.upper(elem)
            enemies.applyStatus(state, enemy, effectType, instance.damage, instance.weaponTags, instance.effectData)
            table.insert(applied, effectType)
        end
    end

    return applied
end

function calculator.computeDamage(instance)
    if not instance then return 0, false end
    local base = instance.damage or 0
    if base <= 0 then return 0, false end
    local isCrit = false
    local mult = 1
    if math.random() < (instance.critChance or 0) then
        isCrit = true
        mult = instance.critMultiplier or 1.5
    end
    local final = math.floor(base * mult)
    if final < 0 then final = 0 end
    return final, isCrit
end

local function buildDamageMods(enemy, instance, appliedEffects)
    local opts = {}
    local status = enemy and enemy.status
    local elems = instance and instance.elements or {}
    local appliedSet = {}
    for _, eff in ipairs(appliedEffects or {}) do
        appliedSet[string.upper(eff)] = true
    end

    local function has(elem)
        local t = string.upper(elem)
        for _, e in ipairs(elems) do
            if string.upper(e) == t then return true end
        end
        return false
    end

    if has('TOXIN') then opts.bypassShield = true end

    local magnetActive = status and status.magneticTimer and status.magneticTimer > 0
    if magnetActive or appliedSet['MAGNETIC'] then
        opts.shieldMult = math.max(opts.shieldMult or 1, (status and status.magneticMult) or 1.75)
        opts.lockShield = true
    end
    if status and status.viralStacks and status.viralStacks > 0 then
        local stacks = math.min(10, status.viralStacks)
        opts.viralMultiplier = 1 + math.min(2.25, stacks * 0.25)
    end
    return opts
end

function calculator.applyDamage(state, enemy, instance, opts)
    local dmg, isCrit = calculator.computeDamage(instance)
    if dmg > 0 then
        enemies.damageEnemy(state, enemy, dmg, instance.knock, instance.knockForce, isCrit, opts)
    end
    return dmg, isCrit
end

function calculator.applyHit(state, enemy, params)
    local instance = calculator.createInstance(params or {})
    local forcedChance = params and params.forceStatusChance
    if instance.effectType and enemy and enemy.status and enemy.status.frozen then
        if string.upper(instance.effectType) == 'HEAVY' then
            forcedChance = 1
        end
    end
    local appliedEffects = calculator.applyStatus(state, enemy, instance, forcedChance)
    local opts = buildDamageMods(enemy, instance, appliedEffects)
    local dmg, isCrit = calculator.applyDamage(state, enemy, instance, opts)
    return {damage = dmg, isCrit = isCrit, statusApplied = (#appliedEffects > 0), appliedEffects = appliedEffects}
end

return calculator
