local enemies = require('enemies')
local calculator = require('calculator')
local statsRules = require('stats_rules')
local player = require('player')

local weapons = {}

local function findOwnerActor(state, owner)
    if not state then return nil end
    if owner == nil or owner == 'player' then
        return state.player
    end
    if owner == 'pet' or owner == 'pet_active' then
        local pet = state.pets and state.pets.list and state.pets.list[1]
        if pet and not pet.dead and not pet.downed then
            return pet
        end
    end
    local list = state.pets and state.pets.list
    if type(list) == 'table' then
        for _, a in ipairs(list) do
            if a and not a.dead and not a.downed and (a.ownerKey == owner or a.key == owner) then
                return a
            end
        end
    end
    return nil
end

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
        else
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
    
    -- Apply new unified MOD system (mods.lua)
    local modsModule = require('mods')
    stats = modsModule.applyWeaponMods(state, weaponKey, stats)

    return stats
end

function weapons.addWeapon(state, key, owner, slotType)
    local proto = state.catalog[key]
    if not proto then
        print("Error: Attempted to add invalid weapon key: " .. tostring(key))
        return
    end
    local stats = cloneStats(proto.base)
    -- Determine slot type from parameter, catalog, or default to 'primary'
    local slot = slotType or proto.slotType or 'primary'
    
    -- Initialize ammo system if weapon uses ammo
    local magazine = proto.base.magazine
    local reserve = proto.base.reserve
    
    state.inventory.weapons[key] = { 
        level = 1, timer = 0, stats = stats, owner = owner, slotType = slot,
        -- Ammo state (nil means unlimited)
        magazine = magazine,
        reserve = reserve,
        isReloading = false,
        reloadTimer = 0
    }
end

-- =============================================================================
-- WF-STYLE WEAPON SLOT SYSTEM
-- =============================================================================

-- Equip weapon to a specific slot (ranged/melee/extra)
function weapons.equipToSlot(state, slotType, weaponKey)
    local proto = state.catalog[weaponKey]
    if not proto then
        print("[WEAPONS] Invalid weapon key: " .. tostring(weaponKey))
        return false
    end
    
    -- Validate slot type
    if slotType ~= 'ranged' and slotType ~= 'melee' and slotType ~= 'extra' then
        print("[WEAPONS] Invalid slot type: " .. tostring(slotType))
        return false
    end
    
    -- Check extra slot permission
    if slotType == 'extra' and not state.inventory.canUseExtraSlot then
        print("[WEAPONS] Extra slot not unlocked")
        return false
    end
    
    -- Clone base stats
    local stats = cloneStats(proto.base)
    
    -- Create weapon instance
    local weaponInstance = {
        key = weaponKey,
        level = 1,
        timer = 0,
        stats = stats,
        slotType = slotType,
        -- Ammo system
        magazine = proto.base.magazine,
        maxMagazine = proto.base.maxMagazine or proto.base.magazine,
        reserve = proto.base.reserve,
        maxReserve = proto.base.maxReserve or proto.base.reserve,
        reloadTime = proto.base.reloadTime,
        isReloading = false,
        reloadTimer = 0
    }
    
    -- Equip to slot
    state.inventory.weaponSlots[slotType] = weaponInstance
    
    -- Also add to legacy weapons table for compatibility
    state.inventory.weapons[weaponKey] = weaponInstance
    
    print(string.format("[WEAPONS] Equipped %s to %s slot", weaponKey, slotType))
    return true
end

-- Get currently active weapon
function weapons.getActiveWeapon(state)
    local activeSlot = state.inventory.activeSlot or 'ranged'
    return state.inventory.weaponSlots[activeSlot]
end

-- Get weapon in specific slot
function weapons.getSlotWeapon(state, slotType)
    return state.inventory.weaponSlots[slotType]
end

-- Switch to a different weapon slot
function weapons.switchSlot(state, slotType)
    if slotType == 'extra' and not state.inventory.canUseExtraSlot then
        return false
    end
    if state.inventory.weaponSlots[slotType] then
        state.inventory.activeSlot = slotType
        return true
    end
    return false
end

-- Count equipped weapon slots
function weapons.countSlots(state)
    local count = 0
    for _, slot in pairs({'ranged', 'melee', 'extra'}) do
        if state.inventory.weaponSlots[slot] then
            count = count + 1
        end
    end
    return count
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

    -- Default generic projectile spawning logic, behaviors can override or use this
    local angle = 0
    if target then
        angle = math.atan2(target.y - y, target.x - x)
    elseif wStats.rotation then
         angle = wStats.rotation
    end
    
    local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
    
    -- Helper for hit scaling
    local function getHitSizeScaleForType(t)
        if not (state and state.weaponSprites and state.weaponSprites[t]) then return 1 end
        return (state.weaponSpriteScale and state.weaponSpriteScale[t]) or 1
    end
    
    local hitScale = getHitSizeScaleForType(type)
    
    -- Special spawning logic for specific types that need complex init is gradually being moved to behaviors,
    -- but for now, we keep a generic projectile spawner for simple projectiles.
    
    -- NOTE: Most complex logic is now handled by behaviors invoking specific projectile configs
    
    if type == 'axe' then
         local vx = (math.random() - 0.5) * 200
         local vy = -spd
         local spin = math.atan2(vy, vx)
         local size = (wStats.size or 12) * area
          local bullet = {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=size, damage=finalDmg, rotation=spin, hitTargets={}, effectType=effectType, weaponTags=weaponTags, elements=wStats.elements, damageBreakdown=wStats.damageBreakdown, critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance, hitSizeScale=hitScale}
         table.insert(state.bullets, bullet)
         return
    elseif type == 'death_spiral' then
         -- Handled by behavior, but if called here directly:
          local count = 8 + (wStats.amount or 0)
          local baseSize = (wStats.size or 14) * area
          for i = 1, count do
            local spin = (i - 1) / count * math.pi * 2
            local bullet = {
                type='death_spiral', x=x, y=y,
                vx=math.cos(spin)*spd, vy=math.sin(spin)*spd,
                life=3, size=baseSize, damage=finalDmg,
                rotation=spin, angularVel=1.5, hitTargets={}, effectType=effectType, weaponTags=weaponTags, elements=wStats.elements, damageBreakdown=wStats.damageBreakdown,
                critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance, hitSizeScale=hitScale
            }
            table.insert(state.bullets, bullet)
        end
        return
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
        return
    end

    -- Generic Projectile Fallback
    local baseSize = wStats.size or 6
    local size = baseSize * area
    local bullet = {
        type=type, x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
        life=wStats.life or 2, size=size, damage=finalDmg, effectType=effectType, weaponTags=weaponTags,
        pierce=wStats.pierce or 1, rotation=angle,
        effectDuration=wStats.duration, splashRadius=wStats.splashRadius, effectRange=wStats.staticRange, chain=wStats.chain, allowRepeat=wStats.allowRepeat,
        elements=wStats.elements, damageBreakdown=wStats.damageBreakdown,
        critChance=wStats.critChance, critMultiplier=wStats.critMultiplier, statusChance=wStats.statusChance,
        hitSizeScale=hitScale
    }
    table.insert(state.bullets, bullet)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = type, bullet = bullet})
    end
end


-- =========================================================================================
-- STRATEGY PATTERN BEHAVIORS
-- =========================================================================================

local Behaviors = {}

function Behaviors.SHOOT_NEAREST(state, weaponKey, w, stats, params, sx, sy)
    local range = math.max(1, math.floor(stats.range or 600))
    local losOpts = state.world and state.world.enabled and {requireLOS = true} or nil
    
    -- Check for precision aim mode (Shift held)
    local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local aimDx, aimDy = nil, nil
    if isPlayerWeapon and player.getAimDirection then
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
    end
    
    local baseAngle = nil
    local dist = range
    
    if aimDx and aimDy then
        -- Precision aim: use player's aim direction
        baseAngle = math.atan2(aimDy, aimDx)
    else
        -- Auto-aim: find nearest enemy
        local t = enemies.findNearestEnemy(state, range, sx, sy, losOpts)
        if t then
            baseAngle = math.atan2(t.y - sy, t.x - sx)
        end
    end
    
    if baseAngle then
        if state.playSfx then state.playSfx('shoot') end
        local shots = getProjectileCount(stats)
        local spread = 0.12
        
        for i = 1, shots do
            local ang = baseAngle + (i - (shots + 1) / 2) * spread
            local target = {x = sx + math.cos(ang) * dist, y = sy + math.sin(ang) * dist}
            weapons.spawnProjectile(state, weaponKey, sx, sy, target, stats)
        end
        return true
    end
    return false
end

-- Melee swing behavior - arc-based attack
function Behaviors.MELEE_SWING(state, weaponKey, w, stats, params, sx, sy)
    local p = state.player
    if not p or not p.meleeState then return false end
    
    local melee = p.meleeState
    
    -- Only deal damage during swing phase and if not already dealt
    if melee.phase ~= 'swing' or melee.damageDealt then
        return false
    end
    
    -- Parameters
    params = params or {}
    local arcWidth = params.arcWidth or 1.2  -- ~70 degrees in radians
    local range = stats.range or 80
    
    -- Get aim direction
    local aimAngle
    local mdx, mdy = 0, 0
    if love.keyboard.isDown('w') then mdy = -1 end
    if love.keyboard.isDown('s') then mdy = 1 end
    if love.keyboard.isDown('a') then mdx = -1 end
    if love.keyboard.isDown('d') then mdx = 1 end
    
    if mdx ~= 0 or mdy ~= 0 then
        aimAngle = math.atan2(mdy, mdx)
    else
        aimAngle = (p.facing or 1) > 0 and 0 or math.pi
    end
    
    -- Damage multiplier based on attack type
    local mult = 1
    if melee.attackType == 'light' then
        mult = 1
    elseif melee.attackType == 'heavy' then
        mult = 3
    elseif melee.attackType == 'finisher' then
        mult = 5
    end
    
    local baseDamage = (stats.damage or 40) * mult
    local might = p.stats and p.stats.might or 1
    local finalDamage = baseDamage * might
    
    -- Knockback
    local knockback = (stats.knockback or 80) * mult
    
    -- Check all enemies in arc
    local hitCount = 0
    for _, e in ipairs(state.enemies) do
        if e.health and e.health > 0 then
            local dx = e.x - sx
            local dy = e.y - sy
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist <= range then
                -- Check if in arc
                local angleToEnemy = math.atan2(dy, dx)
                local angleDiff = math.abs(angleToEnemy - aimAngle)
                -- Normalize angle difference
                if angleDiff > math.pi then angleDiff = 2 * math.pi - angleDiff end
                
                if angleDiff <= arcWidth / 2 then
                    -- Hit enemy - apply damage directly
                    e.health = e.health - finalDamage
                    e.hp = e.health
                    
                    -- Damage text
                    if state.texts then
                        local color = {1, 0.9, 0.4}
                        if melee.attackType == 'finisher' then color = {1, 0.5, 0.2} end
                        table.insert(state.texts, {x=e.x, y=e.y-20, text=math.floor(finalDamage), color=color, life=0.5, scale=melee.attackType == 'finisher' and 1.5 or 1})
                    end
                    
                    -- Apply knockback
                    if knockback > 0 and dist > 0 then
                        local kbX = (dx / dist) * knockback
                        local kbY = (dy / dist) * knockback
                        e.x = e.x + kbX * 0.1
                        e.y = e.y + kbY * 0.1
                    end
                    
                    hitCount = hitCount + 1
                    
                    -- Hit sound
                    if state.playSfx then state.playSfx('hit') end
                end
            end
        end
    end
    
    -- Destroy enemy bullets in swing arc
    if state.enemyBullets then
        for i = #state.enemyBullets, 1, -1 do
            local b = state.enemyBullets[i]
            local dx = b.x - sx
            local dy = b.y - sy
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist <= range then
                local angleToB = math.atan2(dy, dx)
                local angleDiff = math.abs(angleToB - aimAngle)
                if angleDiff > math.pi then angleDiff = 2 * math.pi - angleDiff end
                
                if angleDiff <= arcWidth / 2 then
                    -- Destroy bullet
                    table.remove(state.enemyBullets, i)
                    
                    -- VFX
                    if state.texts then
                        table.insert(state.texts, {x=b.x, y=b.y, text="×", color={0.8, 0.9, 1}, life=0.3, scale=0.8})
                    end
                    if state.playSfx then state.playSfx('gem') end
                end
            end
        end
    end
    
    melee.damageDealt = true
    
    -- Screen shake for heavy/finisher
    if melee.attackType == 'heavy' or melee.attackType == 'finisher' then
        state.shakeAmount = (state.shakeAmount or 0) + (melee.attackType == 'finisher' and 8 or 4)
    end
    
    return hitCount > 0
end

function Behaviors.SHOOT_DIRECTIONAL(state, weaponKey, w, stats, params, sx, sy)
    local range = math.max(1, math.floor(stats.range or 550))
    local losOpts = state.world and state.world.enabled and {requireLOS = true} or nil
    
    -- Check for precision aim mode
    local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local aimDx, aimDy = nil, nil
    if isPlayerWeapon and player.getAimDirection then
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
    end
    
    local baseAngle = nil
    local dist = range
    
    if aimDx and aimDy then
        baseAngle = math.atan2(aimDy, aimDx)
    else
        local t = enemies.findNearestEnemy(state, range, sx, sy, losOpts)
        if t then
            baseAngle = math.atan2(t.y - sy, t.x - sx)
        end
    end
    
    if baseAngle then
        local shots = getProjectileCount(stats)
        local spread = 0.08
        for i = 1, shots do
            local ang = baseAngle + (i - (shots + 1) / 2) * spread
            local target = {x = sx + math.cos(ang) * dist, y = sy + math.sin(ang) * dist}
            weapons.spawnProjectile(state, weaponKey, sx, sy, target, stats)
        end
        return true
    end
    return false
end

-- Shotgun spread pattern - fires multiple pellets in a cone
function Behaviors.SHOOT_SPREAD(state, weaponKey, w, stats, params, sx, sy)
    local range = math.max(1, math.floor(stats.range or 300))
    local losOpts = state.world and state.world.enabled and {requireLOS = true} or nil
    
    -- Get target direction
    local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local aimDx, aimDy = nil, nil
    if isPlayerWeapon and player.getAimDirection then
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
    end
    
    local baseAngle = nil
    if aimDx and aimDy then
        baseAngle = math.atan2(aimDy, aimDx)
    else
        local t = enemies.findNearestEnemy(state, range * 1.5, sx, sy, losOpts)
        if t then
            baseAngle = math.atan2(t.y - sy, t.x - sx)
        end
    end
    
    if baseAngle then
        if state.playSfx then state.playSfx('shoot') end
        
        -- Shotgun parameters
        params = params or {}
        local pellets = params.pellets or 8
        local spreadAngle = params.spread or 0.4  -- radians total spread
        
        -- Fire all pellets
        for i = 1, pellets do
            -- Random spread within cone
            local angleOffset = (math.random() - 0.5) * spreadAngle
            local ang = baseAngle + angleOffset
            
            -- Slight damage variance per pellet
            local pelletStats = {}
            for k,v in pairs(stats) do pelletStats[k] = v end
            pelletStats.damage = math.floor((stats.damage or 10) * (0.9 + math.random() * 0.2))
            
            -- Shorter range with falloff
            local pelletRange = range * (0.8 + math.random() * 0.4)
            local target = {x = sx + math.cos(ang) * pelletRange, y = sy + math.sin(ang) * pelletRange}
            
            weapons.spawnProjectile(state, weaponKey, sx, sy, target, pelletStats)
        end
        return true
    end
    return false
end

function Behaviors.SHOOT_RANDOM(state, weaponKey, w, stats, params, sx, sy)
    if state.playSfx then state.playSfx('shoot') end
    local shots = getProjectileCount(stats)
    for i = 1, shots do
        weapons.spawnProjectile(state, weaponKey, sx, sy, nil, stats)
    end
    return true
end

function Behaviors.SHOOT_RADIAL(state, weaponKey, w, stats, params, sx, sy)
    if state.playSfx then state.playSfx('shoot') end
    -- Note: spawnProjectile has legacy handling for death_spiral, but we can move it here fully if desired.
    -- For now, delegating to spawnProjectile which handles the radial loop for 'death_spiral' type internally
    weapons.spawnProjectile(state, weaponKey, sx, sy, nil, stats) 
    return true
end

function Behaviors.AURA(state, weaponKey, w, stats, params, sx, sy)
    local hit = false
    local actualDmg = math.floor((stats.damage or 0) * (state.player.stats.might or 1))
    local actualRadius = (stats.radius or 0) * (stats.area or 1) * (state.player.stats.area or 1)
    local weaponDef = state.catalog[weaponKey]
    local effectType = weaponDef.effectType or stats.effectType
    local lifesteal = stats.lifesteal
    local effectData = nil
    
    if weaponKey == 'ice_ring' then
         effectData = {duration = stats.duration or weaponDef.base.duration}
    end

    local instance = calculator.createInstance({
        damage = actualDmg,
        critChance = stats.critChance,
        critMultiplier = stats.critMultiplier,
        statusChance = stats.statusChance,
        effectType = effectType,
        effectData = effectData,
        elements = stats.elements,
        damageBreakdown = stats.damageBreakdown,
        weaponTags = weaponDef.tags,
        knock = true,
        knockForce = stats.knockback or 0
    })

    for _, e in ipairs(state.enemies) do
        local d = math.sqrt((sx - e.x)^2 + (sy - e.y)^2)
        if d < actualRadius then
            calculator.applyHit(state, e, instance)
            if lifesteal and actualDmg > 0 then
                 local shooter = findOwnerActor(state, w.owner)
                 if shooter and shooter.hp and shooter.maxHp then
                    local heal = math.max(1, math.floor(actualDmg * lifesteal))
                    shooter.hp = math.min(shooter.maxHp, shooter.hp + heal)
                 end
            end
            hit = true
        end
    end
    
    return hit
end

function Behaviors.SPAWN(state, weaponKey, w, stats, params, sx, sy)
    local spawnType = (params and params.type) or weaponKey
    if spawnType == 'absolute_zero' and state.playSfx then state.playSfx('freeze') end
    weapons.spawnProjectile(state, spawnType, sx, sy, nil, stats)
    return true
end

function Behaviors.GLOBAL(state, weaponKey, w, stats, params, sx, sy)
    if weaponKey == 'earthquake' then
         local dmg = math.floor((stats.damage or 0) * (state.player.stats.might or 1))
         local stunDuration = stats.duration or 0.6
         local knock = stats.knockback or 0
         local areaScale = (stats.area or 1) * (state.player.stats.area or 1)
         local quakeRadius = 220 * math.sqrt(areaScale)
         local weaponDef = state.catalog[weaponKey]
         
         if state.playSfx then state.playSfx('hit') end
         state.shakeAmount = math.max(state.shakeAmount or 0, 6)
         
         local waves = {1.0, 0.7, 0.5}
         local delay = 0
         for _, factor in ipairs(waves) do
             table.insert(state.quakeEffects, {
                 t = -delay,
                 duration = 1.2,
                 radius = quakeRadius,
                 x = sx, y = sy,
                 damage = math.floor(dmg * factor),
                 stun = stunDuration,
                 knock = knock,
                 effectType = weaponDef.effectType or stats.effectType or 'HEAVY',
                 tags = weaponDef.tags,
                 critChance = stats.critChance,
                 critMultiplier = stats.critMultiplier,
                 statusChance = stats.statusChance
             })
             delay = delay + 0.5
         end
    end
    return true
end

function weapons.update(state, dt)
    updateQuakes(state, dt)
    -- WF-style: Read from inventory.activeSlot (ranged/melee/extra)
    local activeSlot = state.inventory and state.inventory.activeSlot or 'ranged'
    
    for key, w in pairs((state.inventory and state.inventory.weapons) or {}) do
        w.timer = (w.timer or 0) - dt
        if w.timer <= 0 then
            local shooter = findOwnerActor(state, w.owner)
            if not shooter or shooter.dead or shooter.downed then
                w.timer = 0
            else
                local sx, sy = shooter.x, shooter.y
                local computedStats = weapons.calculateStats(state, key) or w.stats
                local actualCD = (computedStats.cd or w.stats.cd) * (state.player.stats.cooldown or 1)
                
                -- Strategy Lookup
                local def = state.catalog[key]
                local behaviorName = def and def.behavior
                local behaviorFunc = behaviorName and Behaviors[behaviorName]
                
                -- Check weapon slot - only fire if in active slot (for player weapons)
                local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
                local weaponSlot = w.slotType or def.slotType or 'ranged'
                local isInActiveSlot = (weaponSlot == activeSlot)
                
                -- Check if player is firing (required for most weapons unless pet/aura/melee)
                -- Auras, melee, and pet weapons always fire when ready (use their own state machines)
                -- autoTrigger meta item bypasses the firing requirement
                local isAura = (behaviorName == 'AURA')
                local isMelee = (behaviorName == 'MELEE_SWING')
                local hasAutoTrigger = state.profile and state.profile.autoTrigger
                local needsFiring = isPlayerWeapon and not isAura and not isMelee and not hasAutoTrigger
                local canFire = not needsFiring or (state.player.isFiring == true)
                
                -- Skip if player weapon not in active slot
                if isPlayerWeapon and not isInActiveSlot then
                    w.timer = 0 -- Keep ready but don't fire
                elseif w.isReloading then
                    -- Weapon is reloading, skip firing
                    w.timer = 0
                elseif behaviorFunc and canFire then
                    -- Check ammo before firing
                    local hasAmmo = true
                    if w.magazine ~= nil then
                        if w.magazine <= 0 then
                            hasAmmo = false
                            -- Auto-reload when empty
                            if (w.reserve or 0) > 0 then
                                local reloadTime = def.base.reloadTime or 1.5
                                w.isReloading = true
                                w.reloadTimer = reloadTime
                            end
                        end
                    end
                    
                    if hasAmmo then
                        local fired = behaviorFunc(state, key, w, computedStats, def.behaviorParams, sx, sy)
                        if fired then
                            -- Consume ammo on successful fire
                            if w.magazine ~= nil then
                                w.magazine = math.max(0, w.magazine - 1)
                            end
                            w.timer = actualCD
                        end
                    else
                        w.timer = 0
                    end
                elseif behaviorFunc and needsFiring and not canFire then
                    -- Player weapon waiting for attack input, don't reset timer
                    w.timer = 0
                else
                    -- Fallback or un-migrated weapons could go here, or simple warning
                    -- For now, all known weapons should have tags.
                end
            end
        end
    end
end

-- Update reload timers for all weapons
function weapons.updateReload(state, dt)
    for key, w in pairs((state.inventory and state.inventory.weapons) or {}) do
        if w.isReloading and w.reloadTimer then
            w.reloadTimer = w.reloadTimer - dt
            if w.reloadTimer <= 0 then
                -- Complete reload
                local def = state.catalog[key]
                local maxMag = (def and def.base.maxMagazine) or 30
                local needed = maxMag - (w.magazine or 0)
                local transfer = math.min(needed, w.reserve or 0)
                w.magazine = (w.magazine or 0) + transfer
                w.reserve = (w.reserve or 0) - transfer
                w.isReloading = false
                w.reloadTimer = 0
                if state.playSfx then state.playSfx('gem') end
            end
        end
    end
end

-- Try to start reloading the active weapon
function weapons.startReload(state)
    local inv = state.inventory
    if not inv then return false end
    
    -- WF-style: Read from inventory.activeSlot and inventory.weaponSlots
    local activeSlot = inv.activeSlot or 'ranged'
    local slotData = inv.weaponSlots and inv.weaponSlots[activeSlot]
    if not slotData then return false end
    
    local weaponKey = slotData.key
    local w = inv.weapons and inv.weapons[weaponKey]
    if not w then return false end
    if w.isReloading then return false end
    if w.magazine == nil then return false end -- No ammo weapon (melee)
    
    local def = state.catalog[weaponKey]
    local maxMag = (def and def.base.maxMagazine) or 30
    if w.magazine >= maxMag then return false end -- Already full
    if (w.reserve or 0) <= 0 then return false end -- No reserve ammo
    
    local reloadTime = (def and def.base.reloadTime) or 1.5
    w.isReloading = true
    w.reloadTimer = reloadTime
    if state.playSfx then state.playSfx('shoot') end
    return true
end

return weapons
