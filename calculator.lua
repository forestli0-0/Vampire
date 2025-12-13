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

-- Warframe Damage 2.0 style type modifiers (percentages converted to multipliers).
-- Keys use our internal damage names (ELECTRIC not ELECTRICITY) and defense names.
local DEFENSE_MODIFIERS = {
    FLESH = {IMPACT=0.75, SLASH=1.25, TOXIN=1.5, GAS=0.75, VIRAL=1.5},
    CLONED_FLESH = {IMPACT=0.75, SLASH=1.25, HEAT=1.25, GAS=0.5, VIRAL=1.75},
    FOSSILIZED = {SLASH=1.15, COLD=0.75, TOXIN=0.5, BLAST=1.5, CORROSIVE=1.75, RADIATION=0.25},
    INFESTED = {SLASH=1.25, HEAT=1.25, GAS=1.75, RADIATION=0.5, VIRAL=0.5},
    INFESTED_FLESH = {SLASH=1.5, COLD=0.5, HEAT=1.5, GAS=1.5},
    INFESTED_SINEW = {PUNCTURE=1.25, COLD=1.25, BLAST=0.5, RADIATION=1.5},
    MACHINERY = {IMPACT=1.25, ELECTRIC=1.5, BLAST=1.75, TOXIN=0.75, VIRAL=0.75},
    ROBOTIC = {PUNCTURE=1.25, SLASH=0.75, ELECTRIC=1.5, TOXIN=0.75, RADIATION=1.25},
    OBJECT = {},
    SHIELD = {IMPACT=1.5, PUNCTURE=0.8, COLD=1.5, MAGNETIC=1.75, RADIATION=0.75},
    PROTO_SHIELD = {IMPACT=1.15, PUNCTURE=0.5, HEAT=0.5, CORROSIVE=0.5, MAGNETIC=1.75},
    FERRITE_ARMOR = {PUNCTURE=1.5, SLASH=0.85, BLAST=0.75, CORROSIVE=1.75},
    ALLOY_ARMOR = {PUNCTURE=1.15, SLASH=0.5, COLD=1.25, ELECTRIC=0.5, MAGNETIC=0.5, RADIATION=1.75},
    INDIFFERENT_FACADE = {PUNCTURE=1.25, SLASH=0.5, ELECTRIC=1.25, RADIATION=1.75, VIRAL=0.5, VOID=1.25}
}

local function getTypeModifier(dmgType, defenseType)
    local d = string.upper(dmgType or '')
    if d == 'ELECTRICITY' then d = 'ELECTRIC' end
    local t = string.upper(defenseType or '')
    local row = DEFENSE_MODIFIERS[t]
    if row and row[d] then return row[d] end
    return 1
end

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

local function spawnProcVfx(state, enemy, appliedEffects)
    if not state or not state.spawnEffect or not enemy then return end
    if not appliedEffects or #appliedEffects == 0 then return end

    local counts = {}
    for _, eff in ipairs(appliedEffects) do
        local k = string.upper(eff or '')
        local fxKey = 'hit'

        if k == 'STATIC' then
            fxKey = 'static_hit'
        elseif k == 'MAGNETIC' then
            fxKey = 'magnetic_hit'
        elseif k == 'FREEZE' then
            fxKey = 'ice_shatter'
        elseif k == 'FIRE' then
            fxKey = 'ember'
        elseif k == 'TOXIN' then
            fxKey = 'toxin_hit'
        elseif k == 'GAS' then
            fxKey = 'gas_hit'
        elseif k == 'BLEED' then
            fxKey = 'bleed_hit'
        elseif k == 'VIRAL' then
            fxKey = 'viral_hit'
        elseif k == 'CORROSIVE' then
            fxKey = 'corrosive_hit'
        elseif k == 'BLAST' then
            fxKey = 'blast_hit'
        elseif k == 'PUNCTURE' then
            fxKey = 'puncture_hit'
        elseif k == 'RADIATION' then
            fxKey = 'radiation_hit'
        end

        counts[fxKey] = (counts[fxKey] or 0) + 1
    end

    for fxKey, n in pairs(counts) do
        local scale = 0.85 + 0.18 * math.min(3, math.max(0, n - 1))
        state.spawnEffect(fxKey, enemy.x, enemy.y, scale)
    end
end

local function spawnVoltStaticChain(state, enemy, instance, procCount)
    if not state or not enemy or not state.enemies then return end
    if not state.lightningLinks then return end

    procCount = procCount or 1
    if procCount <= 0 then return end

    local effectData = instance and instance.effectData or nil
    local range = (effectData and (effectData.range or effectData.radius)) or 180
    range = math.max(60, range)

    local maxJumps = (effectData and effectData.chain) or 4
    maxJumps = math.max(1, math.min(8, maxJumps))

    local function addLink(x1, y1, x2, y2, width, alpha)
        table.insert(state.lightningLinks, {
            x1 = x1, y1 = y1, x2 = x2, y2 = y2,
            t = 0, duration = 0.12,
            width = width or 14,
            alpha = alpha or 0.95
        })
        local cap = 80
        if #state.lightningLinks > cap then
            table.remove(state.lightningLinks, 1)
        end
    end

    local function findNearest(fromX, fromY, visited)
        local best, bestD2 = nil, (range * range)
        for _, o in ipairs(state.enemies) do
            if o and o ~= enemy and not o.isDummy then
                local hp = (o.health or o.hp or 0)
                if hp > 0 and not visited[o] then
                    local dx = (o.x or 0) - fromX
                    local dy = (o.y or 0) - fromY
                    local d2 = dx * dx + dy * dy
                    if d2 > 0 and d2 <= bestD2 then
                        bestD2 = d2
                        best = o
                    end
                end
            end
        end
        return best
    end

    -- damage settings (WF/Volt-like: arc deals some electric damage + applies electric proc)
    local baseElectric = 0
    if instance and instance.damageByType then
        baseElectric = instance.damageByType.ELECTRIC or instance.damageByType.ELECTRICITY or 0
    end
    if baseElectric <= 0 then baseElectric = (instance and instance.damage) or 0 end
    local chainDmgMult = (effectData and effectData.chainDamageMult) or 0.35
    if chainDmgMult < 0 then chainDmgMult = 0 end
    if chainDmgMult > 1 then chainDmgMult = 1 end
    local chainHitDmg = math.max(1, math.floor(baseElectric * chainDmgMult + 0.5))

    -- for multiple STATIC procs in one hit, emit slightly more arcs; only apply damage once
    local bursts = math.min(2, procCount)
    for b = 1, bursts do
        local visited = {}
        local current = enemy
        visited[current] = true

        -- seed: a tiny burst at source
        if state.spawnEffect then
            state.spawnEffect('static_hit', enemy.x, enemy.y, 0.9)
        end

        for j = 1, maxJumps do
            local nextEnemy = findNearest(current.x, current.y, visited)
            if not nextEnemy then break end
            visited[nextEnemy] = true
            addLink(current.x, current.y, nextEnemy.x, nextEnemy.y, 14, 0.95)

            if b == 1 then
                -- immediate arc hit (no recursion into calculator.applyHit)
                enemies.damageEnemy(state, nextEnemy, chainHitDmg, false, 0, false, {noText=true, noFlash=true, noSfx=true})
                enemies.applyStatus(state, nextEnemy, 'STATIC', chainHitDmg, instance and instance.weaponTags, {
                    duration = 1.6,
                    radius = math.max(90, range * 0.6),
                    stunDuration = 0.22
                })
                if state.spawnEffect then
                    state.spawnEffect('static_hit', nextEnemy.x, nextEnemy.y, 0.75)
                end
            end
            current = nextEnemy
        end
    end
end

function calculator.applyDamage(state, enemy, instance, opts)
    opts = opts or {}
    local shieldBefore = enemy and (enemy.shield or 0) or 0
    local mult, isCrit = calculator.computeDamage(instance)
    local totalApplied, totalShield, totalHealth = 0, 0, 0

    local dmgByType = instance.damageByType or {}
    local hasTypes = next(dmgByType) ~= nil
    if hasTypes then
        local function applySegment(elemKey, baseAmt)
            local perOpts = {}
            for k, v in pairs(opts) do perOpts[k] = v end

            local key = string.upper(elemKey or '')
            if key == 'ELECTRICITY' then key = 'ELECTRIC' end
            if key == 'TOXIN' then
                perOpts.bypassShield = true
            end

            local amt = (baseAmt or 0) * mult
            if amt <= 0 then return end

            local remain = amt
            local shieldHit = 0
            if not perOpts.bypassShield and enemy.shield and enemy.shield > 0 then
                local mShield = getTypeModifier(key, enemy.shieldType or 'SHIELD') * (perOpts.shieldMult or 1)
                if mShield < 0 then mShield = 0 end
                local effShield = remain * mShield
                shieldHit = math.min(enemy.shield, effShield)
                enemy.shield = enemy.shield - shieldHit
                local consumed = mShield > 0 and (shieldHit / mShield) or 0
                remain = math.max(0, remain - consumed)
                enemy.shieldDelayTimer = 0
                if perOpts.lockShield and enemy.status then
                    enemy.status.shieldLocked = true
                end
            end

            if shieldHit > 0 then
                totalShield = totalShield + shieldHit
                totalApplied = totalApplied + shieldHit
            end

            if remain > 0 then
                local mHealth = getTypeModifier(key, enemy.healthType or 'FLESH')
                local mArmor = 1
                if not perOpts.ignoreArmor and (enemy.armor or 0) > 0 then
                    mArmor = getTypeModifier(key, enemy.armorType or 'FERRITE_ARMOR')
                end
                local effRemain = remain * mHealth * mArmor
                local finalAmt = math.floor(effRemain + 0.5)
                if finalAmt > 0 then
                    perOpts.bypassShield = true
                    perOpts.noText = true
                    perOpts.noFlash = true
                    perOpts.noSfx = true
                    local applied, _, hp = enemies.damageEnemy(state, enemy, finalAmt, false, 0, isCrit, perOpts)
                    totalApplied = totalApplied + (applied or 0)
                    totalHealth = totalHealth + (hp or 0)
                end
            end
        end

        for elem, baseAmt in pairs(dmgByType) do
            applySegment(elem, baseAmt)
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

        if enemy then
            enemy.lastDamage = {
                t = state and state.gameTimer or 0,
                damage = totalApplied,
                shield = totalShield,
                health = totalHealth,
                isCrit = isCrit,
                instance = instance
            }
        end
        if state and state.augments and state.augments.dispatch then
            local ctx = {
                enemy = enemy,
                player = state.player,
                instance = instance,
                damage = totalApplied,
                shieldDamage = totalShield,
                healthDamage = totalHealth,
                isCrit = isCrit
            }
            state.augments.dispatch(state, 'onDamageDealt', ctx)
            if totalShield > 0 then
                state.augments.dispatch(state, 'onShieldDamaged', ctx)
                local shieldAfter = enemy and (enemy.shield or 0) or 0
                if shieldBefore > 0 and shieldAfter <= 0 then
                    ctx.shieldBefore = shieldBefore
                    ctx.shieldAfter = shieldAfter
                    state.augments.dispatch(state, 'onShieldBroken', ctx)
                end
            end
            if totalHealth > 0 then
                state.augments.dispatch(state, 'onHealthDamaged', ctx)
            end
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

    if state and state.augments and state.augments.dispatch then
        local preCtx = {
            enemy = enemy,
            player = state.player,
            instance = instance,
            params = params,
            forceStatusChance = forcedChance
        }
        state.augments.dispatch(state, 'preHit', preCtx)
        if preCtx.cancel then
            return {damage = 0, isCrit = false, statusApplied = false, appliedEffects = {}}
        end
        instance = preCtx.instance or instance
        forcedChance = preCtx.forceStatusChance
    end

    if instance.effectType and enemy and enemy.status and enemy.status.frozen then
        if string.upper(instance.effectType) == 'HEAVY' then
            forcedChance = 1
        end
    end
    local appliedEffects = calculator.applyStatus(state, enemy, instance, forcedChance)

    -- Status feedback should be visible even if the hit kills the enemy.
    spawnProcVfx(state, enemy, appliedEffects)

    -- Volt-like chain lightning: trigger immediately on STATIC proc (doesn't wait for DoT ticks).
    local staticCount = 0
    for _, eff in ipairs(appliedEffects or {}) do
        if string.upper(eff or '') == 'STATIC' then
            staticCount = staticCount + 1
        end
    end
    if staticCount > 0 then
        spawnVoltStaticChain(state, enemy, instance, staticCount)
    end

    local opts = buildDamageMods(enemy, instance, appliedEffects)
    local dmg, isCrit = calculator.applyDamage(state, enemy, instance, opts)
    local result = {damage = dmg, isCrit = isCrit, statusApplied = (#appliedEffects > 0), appliedEffects = appliedEffects}

    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onHit', {
            enemy = enemy,
            player = state.player,
            instance = instance,
            result = result,
            damage = dmg,
            isCrit = isCrit
        })
        for _, eff in ipairs(appliedEffects or {}) do
            state.augments.dispatch(state, 'onProc', {
                enemy = enemy,
                player = state.player,
                instance = instance,
                result = result,
                effectType = eff,
                damage = dmg,
                isCrit = isCrit
            })
        end
        state.augments.dispatch(state, 'postHit', {
            enemy = enemy,
            player = state.player,
            instance = instance,
            result = result,
            damage = dmg,
            isCrit = isCrit
        })
    end

    return result
end

return calculator
