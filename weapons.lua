local enemies = require('enemies')

local weapons = {}

local function cloneStats(base)
    base = base or {}
    return {
        damage = base.damage,
        cd = base.cd,
        speed = base.speed,
        radius = base.radius,
        knockback = base.knockback,
        area = base.area or 1
    }
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
        if stats[statKey] then
            local factor = 1 + (mod * level)
            if factor < 0.1 then factor = 0.1 end
            stats[statKey] = stats[statKey] * factor
        end
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

    local finalDmg = math.floor((wStats.damage or 0) * (state.player.stats.might or 1))
    local area = wStats.area or 1

    if type == 'wand' or type == 'holy_wand' then
        local angle = math.atan2(target.y - y, target.x - x)
        local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
        table.insert(state.bullets, {type='wand', x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd, life=2, size=6 * area, damage=finalDmg})
    elseif type == 'axe' then
        local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
        local vx = (math.random() - 0.5) * 200
        local vy = -spd
        table.insert(state.bullets, {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=12 * area, damage=finalDmg, rotation=0, hitTargets={}})
    elseif type == 'death_spiral' then
        local count = 8
        local spd = (wStats.speed or 300) * (state.player.stats.speed or 1)
        for i = 1, count do
            local angle = (i - 1) / count * math.pi * 2
            table.insert(state.bullets, {
                type='death_spiral', x=x, y=y,
                vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
                life=3, size=14 * area, damage=finalDmg,
                rotation=0, angularVel=1.5, hitTargets={}
            })
        end
    end
end

function weapons.update(state, dt)
    for key, w in pairs(state.inventory.weapons) do
        w.timer = w.timer - dt
        local computedStats = weapons.calculateStats(state, key) or w.stats
        local actualCD = (computedStats.cd or w.stats.cd) * (state.player.stats.cooldown or 1)

        if w.timer <= 0 then
            if key == 'wand' then
                local t = enemies.findNearestEnemy(state, 600)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    weapons.spawnProjectile(state, 'wand', state.player.x, state.player.y, t, computedStats)
                    w.timer = actualCD
                end
            elseif key == 'holy_wand' then
                local t = enemies.findNearestEnemy(state, 700)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    weapons.spawnProjectile(state, 'holy_wand', state.player.x, state.player.y, t, computedStats)
                    w.timer = actualCD
                end
            elseif key == 'axe' then
                if state.playSfx then state.playSfx('shoot') end
                weapons.spawnProjectile(state, 'axe', state.player.x, state.player.y, nil, computedStats)
                w.timer = actualCD
            elseif key == 'death_spiral' then
                if state.playSfx then state.playSfx('shoot') end
                weapons.spawnProjectile(state, 'death_spiral', state.player.x, state.player.y, nil, computedStats)
                w.timer = actualCD
            elseif key == 'garlic' then
                local hit = false
                local actualDmg = math.floor((computedStats.damage or 0) * (state.player.stats.might or 1))
                local actualRadius = (computedStats.radius or 0) * (computedStats.area or 1) * (state.player.stats.area or 1)
                for _, e in ipairs(state.enemies) do
                    local d = math.sqrt((state.player.x - e.x)^2 + (state.player.y - e.y)^2)
                    if d < actualRadius then
                        enemies.damageEnemy(state, e, actualDmg, true, computedStats.knockback or 0)
                        hit = true
                    end
                end
                if hit then w.timer = actualCD end
            end
        end
    end
end

return weapons
