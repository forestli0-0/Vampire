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

local function combineElements(elements, damageByType)
    if not elements or #elements == 0 then return elements, damageByType end
    local out = {}
    local outDamage = {}
    local i = 1
    while i <= #elements do
        local a = string.upper(elements[i])
        local b = elements[i + 1] and string.upper(elements[i + 1]) or nil
        if b and PRIMARY[a] and PRIMARY[b] then
            local combo = (COMBOS[a] and COMBOS[a][b]) or (COMBOS[b] and COMBOS[b][a])
            if combo then
                local dmgA = (damageByType and damageByType[a]) or 0
                local dmgB = (damageByType and damageByType[b]) or 0
                local dmgC = dmgA + dmgB
                table.insert(out, combo)
                outDamage[combo] = (outDamage[combo] or 0) + dmgC
                i = i + 2
            else
                table.insert(out, a)
                if damageByType and damageByType[a] then
                    outDamage[a] = (outDamage[a] or 0) + damageByType[a]
                end
                i = i + 1
            end
        else
            table.insert(out, a)
            if damageByType and damageByType[a] then
                outDamage[a] = (outDamage[a] or 0) + damageByType[a]
            end
            i = i + 1
        end
    end
    return out, outDamage
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
    local rawElements = normalizeElements(params.effectType, params.elements) or {}
    local breakdown = params.damageBreakdown or {}
    local baseDamage = params.damage or 0

    local damageByType = {}
    if params.damageByType and type(params.damageByType) == 'table' then
        for k, v in pairs(params.damageByType) do
            damageByType[string.upper(k)] = v
        end
    else
        local weights = {}
        local totalW = 0
        for idx, elem in ipairs(rawElements) do
            local key = string.upper(elem)
            local w = breakdown[key]
            if w == nil then w = 1 end
            if w < 0 then w = 0 end
            weights[idx] = {key = key, w = w}
            totalW = totalW + w
        end

        if totalW > 0 and baseDamage > 0 then
            local allocated = 0
            local remainders = {}
            for _, info in ipairs(weights) do
                local exact = baseDamage * info.w / totalW
                local intPart = math.floor(exact)
                damageByType[info.key] = intPart
                allocated = allocated + intPart
                table.insert(remainders, {key = info.key, rem = exact - intPart})
            end
            local leftover = baseDamage - allocated
            table.sort(remainders, function(a, b)
                if a.rem == b.rem then return a.key < b.key end
                return a.rem > b.rem
            end)
            local ri = 1
            while leftover > 0 and #remainders > 0 do
                local r = remainders[ri]
                damageByType[r.key] = (damageByType[r.key] or 0) + 1
                leftover = leftover - 1
                ri = ri + 1
                if ri > #remainders then ri = 1 end
            end
        else
            for _, info in ipairs(weights) do
                damageByType[info.key] = 0
            end
        end
    end

    local elements, combinedDamageByType = combineElements(rawElements, damageByType)
    return {
        damage = baseDamage,
        critChance = params.critChance or 0,
        critMultiplier = params.critMultiplier or 1.5,
        statusChance = params.statusChance or 0,
        effectType = params.effectType,
        effectData = params.effectData,
        weaponTags = params.weaponTags,
        knock = params.knock or false,
        knockForce = params.knockForce or params.knockback or 0,
        elements = elements,
        damageBreakdown = breakdown,
        damageByType = combinedDamageByType
    }
end

local function chooseProcElement(instance)
    local elems = instance.elements or {}
    if #elems == 0 then return nil end
    local dmgByType = instance.damageByType or {}
    local total = 0
    local weights = {}
    for idx, elem in ipairs(elems) do
        local key = string.upper(elem)
        local w = dmgByType[key]
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
            local baseForElem = instance.damageByType and instance.damageByType[string.upper(elem)] or instance.damage
            enemies.applyStatus(state, enemy, effectType, baseForElem, instance.weaponTags, instance.effectData)
            table.insert(applied, effectType)
        end
    end

    return applied
end

function calculator.computeDamage(instance)
    if not instance then return 1, false end
    local isCrit = false
    local mult = 1
    if math.random() < (instance.critChance or 0) then
        isCrit = true
        mult = instance.critMultiplier or 1.5
    end
    if mult < 0 then mult = 0 end
    return mult, isCrit
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

    local magnetActive = status and status.magneticTimer and status.magneticTimer > 0
    if magnetActive or appliedSet['MAGNETIC'] then
        opts.shieldMult = math.max(opts.shieldMult or 1, (status and status.magneticMult) or 1.75)
        opts.lockShield = true
    end
    if status and status.viralStacks and status.viralStacks > 0 then
        local stacks = math.min(10, status.viralStacks)
        local bonus = math.min(2.25, 0.75 + stacks * 0.25)
        opts.viralMultiplier = 1 + bonus
    end
    return opts
end

function calculator.applyDamage(state, enemy, instance, opts)
    opts = opts or {}
    local mult, isCrit = calculator.computeDamage(instance)
    local totalApplied, totalShield, totalHealth = 0, 0, 0

    local dmgByType = instance.damageByType or {}
    local hasTypes = next(dmgByType) ~= nil
    if hasTypes then
        for elem, baseAmt in pairs(dmgByType) do
            local amt = math.floor((baseAmt or 0) * mult + 0.5)
            if amt > 0 then
                local perOpts = {}
                for k, v in pairs(opts) do perOpts[k] = v end
                if string.upper(elem) == 'TOXIN' then
                    perOpts.bypassShield = true
                end
                perOpts.noText = true
                perOpts.noFlash = true
                perOpts.noSfx = true
                local applied, sh, hp = enemies.damageEnemy(state, enemy, amt, false, 0, isCrit, perOpts)
                totalApplied = totalApplied + (applied or 0)
                totalShield = totalShield + (sh or 0)
                totalHealth = totalHealth + (hp or 0)
            end
        end
    else
        local base = instance.damage or 0
        local amt = math.floor(base * mult + 0.5)
        if amt > 0 then
            local perOpts = {}
            for k, v in pairs(opts) do perOpts[k] = v end
            perOpts.noText = true
            perOpts.noFlash = true
            perOpts.noSfx = true
            totalApplied, totalShield, totalHealth = enemies.damageEnemy(state, enemy, amt, false, 0, isCrit, perOpts)
        end
    end

    if totalApplied > 0 then
        if not opts.noFlash then enemy.flashTimer = 0.1 end
        if not opts.noSfx and state.playSfx then state.playSfx('hit') end

        if instance.knock then
            local a = math.atan2(enemy.y - state.player.y, enemy.x - state.player.x)
            enemy.x = enemy.x + math.cos(a) * (instance.knockForce or 10)
            enemy.y = enemy.y + math.sin(a) * (instance.knockForce or 10)
        end

        if not opts.noText then
            local color = {1,1,1}
            local scale = 1
            if isCrit then
                color = {1, 1, 0}
                scale = 1.5
            elseif totalShield > 0 and totalHealth == 0 then
                color = {0.4, 0.7, 1}
            end
            local shown = math.floor(totalApplied + 0.5)
            local textOffsetY = opts.textOffsetY or 0
            table.insert(state.texts, {x=enemy.x, y=enemy.y-20 + textOffsetY, text=shown, color=color, life=0.5, scale=scale})
        end
    end

    return totalApplied or 0, isCrit
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
