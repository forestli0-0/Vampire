local enemies = require('enemies')

local calculator = {}

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
    return nil
end

function calculator.createInstance(params)
    params = params or {}
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
        elements = normalizeElements(params.effectType, params.elements)
    }
end

function calculator.applyStatus(state, enemy, instance, overrideChance)
    if not enemy or not instance then return false end
    local chance = overrideChance
    if chance == nil then chance = instance.statusChance or 0 end
    if not instance.effectType or chance <= 0 then return false end
    if math.random() < chance then
        enemies.applyStatus(state, enemy, instance.effectType, instance.damage, instance.weaponTags, instance.effectData)
        return true
    end
    return false
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

local function buildDamageMods(enemy, instance, statusApplied)
    local opts = {}
    local status = enemy and enemy.status
    local elems = instance and instance.elements or {}

    local function has(elem)
        local t = string.upper(elem)
        for _, e in ipairs(elems) do
            if string.upper(e) == t then return true end
        end
        return false
    end

    if has('TOXIN') then opts.bypassShield = true end

    local magnetActive = status and status.magneticTimer and status.magneticTimer > 0
    if magnetActive or (statusApplied and has('MAGNETIC')) then
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
    local statusApplied = calculator.applyStatus(state, enemy, instance, forcedChance)
    local opts = buildDamageMods(enemy, instance, statusApplied)
    local dmg, isCrit = calculator.applyDamage(state, enemy, instance, opts)
    return {damage = dmg, isCrit = isCrit, statusApplied = statusApplied}
end

return calculator
