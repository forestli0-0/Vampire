local enemies = require('enemies')

local weapons = {}

local function cloneStats(base)
    local stats = {}
    for k, v in pairs(base or {}) do stats[k] = v end
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
    for statKey, mod in pairs(effect) do
        if stats[statKey] ~= nil then
            if statKey == 'amount' then
                stats[statKey] = stats[statKey] + mod * level
            else
                local factor = 1 + (mod * level)
                if factor < 0.1 then factor = 0.1 end
                stats[statKey] = stats[statKey] * factor
            end
        end
    end
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
        local cx, cy = q.x or state.player.x, q.y or state.player.y
        for _, e in ipairs(state.enemies) do
            if not q.hit[e] then
                local dx = e.x - cx
                local dy = e.y - cy
                local d2 = dx*dx + dy*dy
                if d2 <= currR2 and d2 >= lastR2 then
                    enemies.applyStatus(state, e, 'FREEZE', q.damage or 0, q.tags, {duration = q.stun or 0.6})
                    if (q.damage or 0) > 0 then
                        enemies.damageEnemy(state, e, q.damage, false, q.knock or 0)
                    end
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

    return stats
end

function weapons.addWeapon(state, key)
    local proto = state.catalog[key]
    local stats = cloneStats(proto.base)
    state.inventory.weapons[key] = { level = 1, timer = 0, stats = stats }
end

function weapons.spawnProjectile(state, type, x, y, target, statsOverride)
    local wStats = statsOverride or weapons.calculateStats(state, type)
    if not wStats then return end

    local weaponDef = state.catalog[type] or {}
    local weaponTags = weaponDef.tags
    local effectType = weaponDef.effectType or wStats.effectType
    local finalDmg = math.floor((wStats.damage or 0) * (state.player.stats.might or 1))
    local area = (wStats.area or 1) * (state.player.stats.area or 1)

    if type == 'wand' or type == 'holy_wand' or type == 'fire_wand' or type == 'hellfire' or type == 'oil_bottle' or type == 'heavy_hammer' or type == 'dagger' or type == 'thousand_edge' or type == 'static_orb' or type == 'thunder_loop' then
        local angle = math.atan2(target.y - y, target.x - x)
        local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
        local size = (wStats.size or 6) * area
        table.insert(state.bullets, {
            type=type, x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
            life=wStats.life or 2, size=size, damage=finalDmg, effectType=effectType, weaponTags=weaponTags,
            pierce=wStats.pierce or 1, rotation=angle,
            effectDuration=wStats.duration, splashRadius=wStats.splashRadius, effectRange=wStats.staticRange, chain=wStats.chain, allowRepeat=wStats.allowRepeat
        })
    elseif type == 'axe' then
        local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
        local vx = (math.random() - 0.5) * 200
        local vy = -spd
        local angle = math.atan2(vy, vx)
        table.insert(state.bullets, {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=12 * area, damage=finalDmg, rotation=angle, hitTargets={}, effectType=effectType, weaponTags=weaponTags})
    elseif type == 'death_spiral' then
        local count = 8
        local spd = (wStats.speed or 300) * (state.player.stats.speed or 1)
        for i = 1, count do
            local angle = (i - 1) / count * math.pi * 2
            table.insert(state.bullets, {
                type='death_spiral', x=x, y=y,
                vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
                life=3, size=14 * area, damage=finalDmg,
                rotation=angle, angularVel=1.5, hitTargets={}, effectType=effectType, weaponTags=weaponTags
            })
        end
    elseif type == 'absolute_zero' then
        local radius = (wStats.radius or 0) * area
        table.insert(state.bullets, {
            type='absolute_zero', x=x, y=y, vx=0, vy=0,
            life=wStats.duration or 2.5, size=radius, radius=radius,
            damage=finalDmg, effectType=effectType, weaponTags=weaponTags,
            effectDuration=wStats.duration,
            tick=0
        })
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
                for _, e in ipairs(state.enemies) do
                    local d = math.sqrt((state.player.x - e.x)^2 + (state.player.y - e.y)^2)
                    if d < actualRadius then
                        enemies.applyStatus(state, e, effectType, actualDmg, weaponDef.tags, nil)
                        enemies.damageEnemy(state, e, actualDmg, true, computedStats.knockback or 0)
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
                for _, e in ipairs(state.enemies) do
                    local d = math.sqrt((state.player.x - e.x)^2 + (state.player.y - e.y)^2)
                    if d < actualRadius then
                        enemies.applyStatus(state, e, effectType, actualDmg, weaponDef.tags, effectData)
                        if actualDmg > 0 then enemies.damageEnemy(state, e, actualDmg, true, computedStats.knockback or 0) end
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
                        tags = weaponDef.tags
                    })
                    delay = delay + 0.5
                end
                w.timer = actualCD
            end
        end
    end
end

return weapons
