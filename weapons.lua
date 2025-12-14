local enemies = require('enemies')
local calculator = require('calculator')
local statsRules = require('stats_rules')

local weapons = {}

local function cloneStats(base)
    local stats = {}
    for k, v in pairs(base or {}) do
        if type(v) == 'table' then
            local t = {}
            for kk, vv in pairs(v) do t[kk] = vv end
            stats[k] = t
        else
            stats[k] = v
        end
    end
    if stats.area == nil then stats.area = 1 end
    if stats.pierce == nil then stats.pierce = 1 end
    if stats.amount == nil then stats.amount = 0 end
    return stats
end

local function tagsMatch(weaponTags, targetTags)
    if not weaponTags or not targetTags then return false end
    for _, tag in ipairs(targetTags) do
        for _, wTag in ipairs(weaponTags) do
            if tag == wTag then return true end
        end
    end
    return false
end

local function applyPassiveEffects(stats, effect, level)
    statsRules.applyEffect(stats, effect, level)
end

local function applyElementAdds(stats, addElements, level)
    if not addElements or level <= 0 then return end
    stats.elements = stats.elements or {}
    stats.damageBreakdown = stats.damageBreakdown or {}
    local existing = {}
    for _, e in ipairs(stats.elements) do
        existing[string.upper(e)] = true
    end
    for elem, weight in pairs(addElements) do
        local key = string.upper(elem)
        local add = (weight or 0) * level
        if add > 0 then
            stats.damageBreakdown[key] = (stats.damageBreakdown[key] or 0) + add
            if not existing[key] then
                table.insert(stats.elements, key)
                existing[key] = true
            end
        end
    end
end

local function getOrderedMods(state, weaponKey)
    local wm = state.inventory and state.inventory.weaponMods and state.inventory.weaponMods[weaponKey]
    local order = wm and wm.modOrder
    if order and #order > 0 then return order end
    local keys = {}
    for k, _ in pairs((wm and wm.mods) or {}) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

local function getProjectileCount(stats)
    local amt = 0
    if stats and stats.amount then amt = stats.amount end
    return math.max(1, math.floor(1 + amt))
end

local function updateQuakes(state, dt)
    if not state.quakeEffects or #state.quakeEffects == 0 then return end
    for i = #state.quakeEffects, 1, -1 do
        local q = state.quakeEffects[i]
        q.t = (q.t or 0) + dt
        local dur = q.duration or 1
        if q.t < 0 then
            q.lastRadius = 0
            goto continue
        end
        local progress = math.max(0, math.min(1, q.t / dur))
        local currR = (q.radius or 220) * progress
        local lastR = q.lastRadius or 0
        q.lastRadius = currR
        local currR2 = currR * currR
        local lastR2 = lastR * lastR
        q.hit = q.hit or {}
        local instance = calculator.createInstance({
            damage = q.damage or 0,
            critChance = q.critChance,
            critMultiplier = q.critMultiplier,
            statusChance = q.statusChance,
            effectType = q.effectType or 'HEAVY',
            effectData = {duration = q.stun or 0.6},
            weaponTags = q.tags,
            knock = false,
            knockForce = q.knock
        })
        local cx, cy = q.x or state.player.x, q.y or state.player.y
        for _, e in ipairs(state.enemies) do
            if not q.hit[e] then
                local dx = e.x - cx
                local dy = e.y - cy
                local d2 = dx*dx + dy*dy
                if d2 <= currR2 and d2 >= lastR2 then
                    calculator.applyHit(state, e, instance)
                    q.hit[e] = true
                end
            end
        end
        if q.t >= dur then
            table.remove(state.quakeEffects, i)
        end
        ::continue::
    end
end

function weapons.calculateStats(state, weaponKey)
    local invWeapon = state.inventory.weapons[weaponKey]
    if not invWeapon then return nil end

    local stats = cloneStats(invWeapon.stats)
    local weaponDef = state.catalog[weaponKey]
    local weaponTags = weaponDef and weaponDef.tags or {}

    for passiveKey, level in pairs(state.inventory.passives) do
        local passiveDef = state.catalog[passiveKey]
        if level and level > 0 and passiveDef and passiveDef.targetTags and passiveDef.effect then
            if tagsMatch(weaponTags, passiveDef.targetTags) then
                applyPassiveEffects(stats, passiveDef.effect, level)
            end
        end
    end

    local wm = state.inventory and state.inventory.weaponMods and state.inventory.weaponMods[weaponKey]
    for _, modKey in ipairs(getOrderedMods(state, weaponKey)) do
        local level = wm and wm.mods and wm.mods[modKey]
        local modDef = state.catalog[modKey]
        if level and level > 0 and modDef and modDef.targetTags then
            if tagsMatch(weaponTags, modDef.targetTags) then
                if modDef.effect then applyPassiveEffects(stats, modDef.effect, level) end
                if modDef.addElements then applyElementAdds(stats, modDef.addElements, level) end
            end
        end
    end

    return stats
end

function weapons.addWeapon(state, key)
    local proto = state.catalog[key]
    if not proto then
        print("Error: Attempted to add invalid weapon key: " .. tostring(key))
        return
    end
    local stats = cloneStats(proto.base)
    state.inventory.weapons[key] = { level = 1, timer = 0, stats = stats }
end

function weapons.spawnProjectile(state, type, x, y, target, statsOverride)
    local wStats = statsOverride or weapons.calculateStats(state, type)
    if not wStats then return end

    if state and state.augments and state.augments.dispatch then
        local ctx = {weaponKey = type, weaponStats = wStats, target = target, x = x, y = y}
        state.augments.dispatch(state, 'onShoot', ctx)
        if ctx.cancel then return end
        wStats = ctx.weaponStats or wStats
        target = ctx.target or target
        x = ctx.x or x
        y = ctx.y or y
    end

    local weaponDef = state.catalog[type] or {}
    local weaponTags = weaponDef.tags
    local effectType = weaponDef.effectType or wStats.effectType
    local finalDmg = math.floor((wStats.damage or 0) * (state.player.stats.might or 1))
    local area = (wStats.area or 1) * (state.player.stats.area or 1)

    local function getProjectileTuning(t)
        local pt = state and state.projectileTuning
        return (pt and pt[t]) or (pt and pt.default) or nil
    end

    local function getHitSizeScaleForType(t)
        if not (state and state.weaponSprites and state.weaponSprites[t]) then return 1 end
        return (state.weaponSpriteScale and state.weaponSpriteScale[t]) or 1
    end

    if type == 'wand' or type == 'holy_wand' or type == 'fire_wand' or type == 'hellfire' or type == 'oil_bottle' or type == 'heavy_hammer' or type == 'dagger' or type == 'thousand_edge' or type == 'static_orb' or type == 'thunder_loop' then
        local angle = math.atan2(target.y - y, target.x - x)
        local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
        local tune = getProjectileTuning(type)
        local baseSize = wStats.size
        if baseSize == nil then baseSize = (tune and tune.size) or 6 end
        local size = baseSize * area
        local bullet = {
            type=type, x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
            life=wStats.life or 2, size=size, damage=finalDmg, effectType=effectType, weaponTags=weaponTags,
            pierce=wStats.pierce or 1, rotation=(type == 'oil_bottle') and 0 or angle,
            effectDuration=wStats.duration, splashRadius=wStats.splashRadius, effectRange=wStats.staticRange, chain=wStats.chain, allowRepeat=wStats.allowRepeat,
            elements=wStats.elements, damageBreakdown=wStats.damageBreakdown,
            critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance
        }
        bullet.hitSizeScale = getHitSizeScaleForType(type)
        table.insert(state.bullets, bullet)
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = type, bullet = bullet})
        end
    elseif type == 'axe' then
        local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
        local vx = (math.random() - 0.5) * 200
        local vy = -spd
        local angle = math.atan2(vy, vx)
        local tune = getProjectileTuning('axe')
        local baseSize = wStats.size
        if baseSize == nil then baseSize = (tune and tune.size) or 12 end
        local bullet = {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=baseSize * area, damage=finalDmg, rotation=angle, hitTargets={}, effectType=effectType, weaponTags=weaponTags, elements=wStats.elements, damageBreakdown=wStats.damageBreakdown, critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance}
        bullet.hitSizeScale = getHitSizeScaleForType('axe')
        table.insert(state.bullets, bullet)
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = type, bullet = bullet})
        end
    elseif type == 'death_spiral' then
        local count = 8 + (wStats.amount or 0)
        local spd = (wStats.speed or 300) * (state.player.stats.speed or 1)
        local tune = getProjectileTuning('death_spiral')
        local baseSize = wStats.size
        if baseSize == nil then baseSize = (tune and tune.size) or 14 end
        for i = 1, count do
            local angle = (i - 1) / count * math.pi * 2
            local bullet = {
                type='death_spiral', x=x, y=y,
                vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
                life=3, size=baseSize * area, damage=finalDmg,
                rotation=angle, angularVel=1.5, hitTargets={}, effectType=effectType, weaponTags=weaponTags, elements=wStats.elements, damageBreakdown=wStats.damageBreakdown,
                critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance
            }
            bullet.hitSizeScale = getHitSizeScaleForType('death_spiral')
            table.insert(state.bullets, bullet)
            if state and state.augments and state.augments.dispatch then
                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = type, bullet = bullet})
            end
        end
    elseif type == 'absolute_zero' then
        local radius = (wStats.radius or 0) * area
        local bullet = {
            type='absolute_zero', x=x, y=y, vx=0, vy=0,
            life=wStats.duration or 2.5, size=radius, radius=radius,
            damage=finalDmg, effectType=effectType, weaponTags=weaponTags,
            effectDuration=wStats.duration,
            tick=0,
            elements=wStats.elements, damageBreakdown=wStats.damageBreakdown,
            critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance
        }
        table.insert(state.bullets, bullet)
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = type, bullet = bullet})
        end
    end
end

function weapons.update(state, dt)
    updateQuakes(state, dt)
    for key, w in pairs(state.inventory.weapons) do
        w.timer = w.timer - dt
        local computedStats = weapons.calculateStats(state, key) or w.stats
        local weaponDef = state.catalog[key] or {}
        local actualCD = (computedStats.cd or w.stats.cd) * (state.player.stats.cooldown or 1)

        if w.timer <= 0 then
            if key == 'wand' then
                local t = enemies.findNearestEnemy(state, 600)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    local shots = getProjectileCount(computedStats)
                    local baseAngle = math.atan2(t.y - state.player.y, t.x - state.player.x)
                    local spread = 0.12
                    local dist = 600
                    for i = 1, shots do
                        local ang = baseAngle + (i - (shots + 1) / 2) * spread
                        local target = {x = state.player.x + math.cos(ang) * dist, y = state.player.y + math.sin(ang) * dist}
                        weapons.spawnProjectile(state, 'wand', state.player.x, state.player.y, target, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'holy_wand' then
                local t = enemies.findNearestEnemy(state, 700)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    local shots = getProjectileCount(computedStats)
                    local baseAngle = math.atan2(t.y - state.player.y, t.x - state.player.x)
                    local spread = 0.1
                    local dist = 650
                    for i = 1, shots do
                        local ang = baseAngle + (i - (shots + 1) / 2) * spread
                        local target = {x = state.player.x + math.cos(ang) * dist, y = state.player.y + math.sin(ang) * dist}
                        weapons.spawnProjectile(state, 'holy_wand', state.player.x, state.player.y, target, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'fire_wand' or key == 'hellfire' then
                local t = enemies.findNearestEnemy(state, 700)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    local shots = getProjectileCount(computedStats)
                    for i = 1, shots do
                        weapons.spawnProjectile(state, key, state.player.x, state.player.y, t, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'oil_bottle' then
                local t = enemies.findNearestEnemy(state, 700)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    local shots = getProjectileCount(computedStats)
                    for i = 1, shots do
                        weapons.spawnProjectile(state, 'oil_bottle', state.player.x, state.player.y, t, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'dagger' or key == 'thousand_edge' then
                local t = enemies.findNearestEnemy(state, 550)
                if t then
                    local shots = getProjectileCount(computedStats)
                    local baseAngle = math.atan2(t.y - state.player.y, t.x - state.player.x)
                    local spread = 0.08
                    local dist = 450
                    for i = 1, shots do
                        local ang = baseAngle + (i - (shots + 1) / 2) * spread
                        local target = {x = state.player.x + math.cos(ang) * dist, y = state.player.y + math.sin(ang) * dist}
                        weapons.spawnProjectile(state, key, state.player.x, state.player.y, target, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'static_orb' or key == 'thunder_loop' then
                local t = enemies.findNearestEnemy(state, 650)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    local shots = getProjectileCount(computedStats)
                    for i = 1, shots do
                        weapons.spawnProjectile(state, key, state.player.x, state.player.y, t, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'heavy_hammer' then
                local t = enemies.findNearestEnemy(state, 550)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    local shots = getProjectileCount(computedStats)
                    for i = 1, shots do
                        weapons.spawnProjectile(state, 'heavy_hammer', state.player.x, state.player.y, t, computedStats)
                    end
                    w.timer = actualCD
                end
            elseif key == 'axe' then
                if state.playSfx then state.playSfx('shoot') end
                local shots = getProjectileCount(computedStats)
                for i = 1, shots do
                    weapons.spawnProjectile(state, 'axe', state.player.x, state.player.y, nil, computedStats)
                end
                w.timer = actualCD
            elseif key == 'death_spiral' then
                if state.playSfx then state.playSfx('shoot') end
                weapons.spawnProjectile(state, 'death_spiral', state.player.x, state.player.y, nil, computedStats)
                w.timer = actualCD
            elseif key == 'garlic' or key == 'soul_eater' then
                local hit = false
                local actualDmg = math.floor((computedStats.damage or 0) * (state.player.stats.might or 1))
                local actualRadius = (computedStats.radius or 0) * (computedStats.area or 1) * (state.player.stats.area or 1)
                local effectType = weaponDef.effectType or computedStats.effectType
                local lifesteal = computedStats.lifesteal
                local instance = calculator.createInstance({
                    damage = actualDmg,
                    critChance = computedStats.critChance,
                    critMultiplier = computedStats.critMultiplier,
                    statusChance = computedStats.statusChance,
                    effectType = effectType,
                    elements = computedStats.elements,
                    damageBreakdown = computedStats.damageBreakdown,
                    weaponTags = weaponDef.tags,
                    knock = true,
                    knockForce = computedStats.knockback or 0
                })
                for _, e in ipairs(state.enemies) do
                    local d = math.sqrt((state.player.x - e.x)^2 + (state.player.y - e.y)^2)
                    if d < actualRadius then
                        calculator.applyHit(state, e, instance)
                        if lifesteal and actualDmg > 0 then
                            local heal = math.max(1, math.floor(actualDmg * lifesteal))
                            state.player.hp = math.min(state.player.maxHp, state.player.hp + heal)
                        end
                        hit = true
                    end
                end
                if hit then w.timer = actualCD end
            elseif key == 'ice_ring' then
                local hit = false
                local actualDmg = math.floor((computedStats.damage or 0) * (state.player.stats.might or 1))
                local actualRadius = (computedStats.radius or 0) * (computedStats.area or 1) * (state.player.stats.area or 1)
                local effectType = weaponDef.effectType or computedStats.effectType
                local effectData = {duration = computedStats.duration or weaponDef.base.duration}
                local instance = calculator.createInstance({
                    damage = actualDmg,
                    critChance = computedStats.critChance,
                    critMultiplier = computedStats.critMultiplier,
                    statusChance = computedStats.statusChance,
                    effectType = effectType,
                    effectData = effectData,
                    elements = computedStats.elements,
                    damageBreakdown = computedStats.damageBreakdown,
                    weaponTags = weaponDef.tags,
                    knock = true,
                    knockForce = computedStats.knockback or 0
                })
                for _, e in ipairs(state.enemies) do
                    local d = math.sqrt((state.player.x - e.x)^2 + (state.player.y - e.y)^2)
                    if d < actualRadius then
                        calculator.applyHit(state, e, instance)
                        hit = true
                    end
                end
                if hit then w.timer = actualCD end
            elseif key == 'absolute_zero' then
                if state.playSfx then state.playSfx('freeze') end
                weapons.spawnProjectile(state, 'absolute_zero', state.player.x, state.player.y, nil, computedStats)
                w.timer = actualCD
            elseif key == 'earthquake' then
                local dmg = math.floor((computedStats.damage or 0) * (state.player.stats.might or 1))
                local stunDuration = computedStats.duration or 0.6
                local knock = computedStats.knockback or 0
                local areaScale = (computedStats.area or 1) * (state.player.stats.area or 1)
                local quakeRadius = 220 * math.sqrt(areaScale)
                if state.playSfx then state.playSfx('hit') end
                state.shakeAmount = math.max(state.shakeAmount or 0, 6)
                local waves = {1.0, 0.7, 0.5}
                local delay = 0
                for _, factor in ipairs(waves) do
                    table.insert(state.quakeEffects, {
                        t = -delay,
                        duration = 1.2,
                        radius = quakeRadius,
                        x = state.player.x, y = state.player.y,
                        damage = math.floor(dmg * factor),
                        stun = stunDuration,
                        knock = knock,
                        effectType = weaponDef.effectType or computedStats.effectType or 'HEAVY',
                        tags = weaponDef.tags,
                        critChance = computedStats.critChance,
                        critMultiplier = computedStats.critMultiplier,
                        statusChance = computedStats.statusChance
                    })
                    delay = delay + 0.5
                end
                w.timer = actualCD
            end
        end
    end
end

return weapons
