local enemies = require('enemies')

local calculator = {}

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
        knockForce = params.knockForce or params.knockback or 0
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

function calculator.applyDamage(state, enemy, instance)
    local dmg, isCrit = calculator.computeDamage(instance)
    if dmg > 0 then
        enemies.damageEnemy(state, enemy, dmg, instance.knock, instance.knockForce, isCrit)
    end
    return dmg, isCrit
end

function calculator.applyHit(state, enemy, params)
    local instance = calculator.createInstance(params or {})
    local statusApplied = calculator.applyStatus(state, enemy, instance, params and params.forceStatusChance)
    local dmg, isCrit = calculator.applyDamage(state, enemy, instance)
    return {damage = dmg, isCrit = isCrit, statusApplied = statusApplied}
end

return calculator
