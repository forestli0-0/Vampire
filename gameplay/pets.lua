local util = require('core.util')

local pets = {}

local _calculator = nil
local function getCalculator()
    if not _calculator then
        local ok, calc = pcall(require, 'gameplay.calculator')
        if ok then _calculator = calc end
    end
    return _calculator
end

local function ensure(state)
    state.pets = state.pets or {}
    local p = state.pets
    p.max = p.max or 1
    p.list = p.list or {}
    p.reviveHoldTime = p.reviveHoldTime or 1.1
    p.bleedoutTime = p.bleedoutTime or 10.0
    p.runLevel = p.runLevel or 1
    p.lostKey = p.lostKey or nil
    p.upgrades = p.upgrades or {}
    return p
end

local function getActive(state)
    local p = ensure(state)
    return (p.list and p.list[1]) or nil
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function findNearestEnemyAt(state, x, y, maxDist)
    if not state or not x or not y then return nil end
    local best, bestD2 = nil, (maxDist or 999999) ^ 2
    for _, e in ipairs(state.enemies or {}) do
        if e and not e.isDummy and (e.health or e.hp or 0) > 0 then
            local dx = (e.x or 0) - x
            local dy = (e.y or 0) - y
            local d2 = dx * dx + dy * dy
            if d2 < bestD2 then
                bestD2 = d2
                best = e
            end
        end
    end
    return best
end

local function applyPetProc(state, enemy, effectType, procs, petKey, petModule)
    local calc = getCalculator()
    if not calc or not enemy or not effectType then return end
    local tags = {'pet', tostring(petKey or 'pet')}
    if petModule then table.insert(tags, tostring(petModule)) end
    calc.applyHit(state, enemy, {
        damage = 0,
        critChance = 0,
        critMultiplier = 1.0,
        statusChance = procs or 1,
        effectType = effectType,
        weaponTags = tags
    })
end

-- Legacy upgrade level check removed (unified to MOD system)

local function applyPetHit(state, enemy, params)
    local calc = getCalculator()
    if not calc or not enemy then return end
    calc.applyHit(state, enemy, params or {})
end

local function recomputePetStats(state, pet)
    if not state or not pet then return end
    local ps = ensure(state)

    local def = state.catalog and state.catalog[pet.key]
    local base = def and def.base or {}

    local profile = state.profile or {}
    local meta = profile.petRanks or {}
    local rank = math.max(0, math.floor(meta[pet.key] or 0))

    local baseHp = tonumber(base.hp) or 60
    local hpBonus = rank * 6
    local maxHpBase = (baseHp + hpBonus)
    
    -- Apply MOD system
    local modsModule = require('systems.mods')
    
    local baseForMods = {
        maxHp = maxHpBase,
        armor = 0,
        critChance = 0,
        damage = 1.0 -- Base multiplier
    }
    
    local modded = modsModule.applyCompanionMods(state, baseForMods)
    modded = modsModule.applyRunCompanionMods(state, modded)
    
    -- Detect active module from Augment MODs
    local companionSlots = modsModule.getRunSlots(state, 'companion', nil)
    local activeModule = 'default'
    for _, slot in pairs(companionSlots or {}) do
        if slot and slot.key then
            local modDef = modsModule.companion[slot.key]
            if modDef and modDef.group == 'augment' and modDef.requiresPetKey == pet.key then
                activeModule = modDef.moduleId or activeModule
            end
        end
    end
    pet.module = activeModule

    -- Inherit from player (Link mods)
    local p = state.player
    if p then
        if modded.healthLink then
            modded.maxHp = (modded.maxHp or maxHpBase) + (p.maxHp or 100) * modded.healthLink
        end
        if modded.armorLink then
            modded.armor = (modded.armor or 0) + (p.stats and p.stats.armor or 0) * modded.armorLink
        end
    end

    local oldMax = pet.maxHp or 0
    local oldHp = pet.hp or oldMax
    local hpPct = 1
    if oldMax and oldMax > 0 then
        hpPct = math.max(0, math.min(1, oldHp / oldMax))
    end

    local finalMaxHp = math.floor(modded.maxHp or maxHpBase + 0.5)
    finalMaxHp = math.max(1, finalMaxHp)
    pet.maxHp = finalMaxHp
    pet.hp = math.min(finalMaxHp, math.max(0, math.floor(finalMaxHp * hpPct + 0.5)))
    pet.armor = modded.armor or 0
    pet.damageMult = modded.damage or 1.0
    pet.critBonus = modded.critChance or 0
    pet.extraStatusProcs = modded.extraStatusProcs or 0

    local baseCd = tonumber(base.cooldown) or (pet.abilityCooldown or 3.0)
    local petRankBonus = 1.0 - math.min(0.15, rank * 0.03) -- Persistent rank bonus
    local modCdReduction = modded.cooldownReduction or 0
    
    pet.abilityCooldown = math.max(0.25, baseCd * petRankBonus * (1.0 - modCdReduction))
    pet.level = ps.runLevel or 1
end

local function doPetAbility(state, pet)
    if not state or not pet then return end
    local key = pet.key
    local module = pet.module or 'default'
    local lvl = pet.level or 1
    local p = state.player or {}
    local might = (p.stats and p.stats.might) or 1

    local dmgMul = pet.damageMult or 1.0
    local extraProcs = pet.extraStatusProcs or 0

    local function tags()
        local t = {'pet', tostring(key or 'pet')}
        if module then table.insert(t, tostring(module)) end
        return t
    end

    if key == 'pet_magnet' then
        if module == 'pulse' then
            local r = 150 + (lvl - 1) * 8
            local r2 = r * r
            local any = false
            local hit = 0
            local maxHits = 8
            for _, e in ipairs(state.enemies or {}) do
                if e and not e.isDummy and (e.health or e.hp or 0) > 0 then
                    local dx = (e.x or 0) - pet.x
                    local dy = (e.y or 0) - pet.y
                    if dx * dx + dy * dy <= r2 then
                        local procs = 1 + extraProcs
                        applyPetHit(state, e, {
                            damage = math.max(0, math.floor((6 + (lvl - 1) * 2) * might * dmgMul * (pet.damageMult or 1.0) + 0.5)),
                            critChance = pet.critBonus or 0,
                            critMultiplier = 1.5,
                            statusChance = procs,
                            effectType = 'MAGNETIC',
                            weaponTags = tags()
                        })
                        any = true
                        hit = hit + 1
                        if hit >= maxHits then break end
                    end
                end
            end
            if any and state.spawnEffect then state.spawnEffect('static_hit', pet.x, pet.y, 0.8) end
        else
            local t = findNearestEnemyAt(state, pet.x, pet.y, 700)
            if t then
                local stacks = 1 + extraProcs
                if lvl >= 4 then stacks = stacks + 1 end
                applyPetHit(state, t, {
                    damage = math.max(0, math.floor((8 + (lvl - 1) * 2) * might * dmgMul * (pet.damageMult or 1.0) + 0.5)),
                    critChance = pet.critBonus or 0,
                    critMultiplier = 1.5,
                    statusChance = stacks,
                    effectType = 'MAGNETIC',
                    weaponTags = tags()
                })
                if state.spawnEffect then state.spawnEffect('static_hit', t.x, t.y, 0.7) end
            end
        end
    elseif key == 'pet_corrosive' then
        if module == 'field' then
            local r = 140 + (lvl - 1) * 6
            local r2 = r * r
            local any = false
            local hit = 0
            local maxHits = 8
            for _, e in ipairs(state.enemies or {}) do
                if e and not e.isDummy and (e.health or e.hp or 0) > 0 then
                    local dx = (e.x or 0) - pet.x
                    local dy = (e.y or 0) - pet.y
                    if dx * dx + dy * dy <= r2 then
                        local procs = 1 + extraProcs
                        applyPetHit(state, e, {
                            damage = math.max(0, math.floor((7 + (lvl - 1) * 2) * might * dmgMul * (pet.damageMult or 1.0) + 0.5)),
                            critChance = pet.critBonus or 0,
                            critMultiplier = 1.5,
                            statusChance = procs,
                            effectType = 'CORROSIVE',
                            weaponTags = tags()
                        })
                        any = true
                        hit = hit + 1
                        if hit >= maxHits then break end
                    end
                end
            end
            if any and state.spawnEffect then state.spawnEffect('toxin_hit', pet.x, pet.y, 0.85) end
        else
            local t = findNearestEnemyAt(state, pet.x, pet.y, 700)
            if t then
                local stacks = 1 + extraProcs
                if (t.armor or 0) >= 120 and lvl >= 3 then stacks = stacks + 1 end
                applyPetHit(state, t, {
                    damage = math.max(0, math.floor((9 + (lvl - 1) * 2) * might * dmgMul * (pet.damageMult or 1.0) + 0.5)),
                    critChance = pet.critBonus or 0,
                    critMultiplier = 1.5,
                    statusChance = stacks,
                    effectType = 'CORROSIVE',
                    weaponTags = tags()
                })
                if state.spawnEffect then state.spawnEffect('corrosive_hit', t.x, t.y, 0.75) end
            end
        end
    elseif key == 'pet_guardian' then
        if not p then return end
        if module == 'barrier' then
            local base = 0.22 + math.min(0.18, (lvl - 1) * 0.02)
            local bonus = 1 + 0.10 * powerLv
            p.invincibleTimer = math.max(p.invincibleTimer or 0, base * bonus)
            if state.spawnEffect then state.spawnEffect('static_hit', p.x, p.y, 0.75) end
            table.insert(state.texts, {x = p.x, y = p.y - 46, text = "BARRIER", color = {0.7, 0.95, 1.0}, life = 0.8})
        else
            local heal = 7 + math.min(10, (lvl - 1) * 2)
            heal = math.floor(heal * dmgMul + 0.5)
            p.hp = math.min(p.maxHp or p.hp, (p.hp or 0) + heal)
            if state.spawnEffect then state.spawnEffect('static_hit', p.x, p.y, 0.7) end
            table.insert(state.texts, {x = p.x, y = p.y - 46, text = "+" .. tostring(heal), color = {0.55, 1.0, 0.55}, life = 0.9})
        end
    end
end

function pets.init(state)
    local p = ensure(state)
    p.max = 1
    p.list = {}
    p.runLevel = 1
    p.lostKey = nil
    p.upgrades = {}
end

function pets.getActive(state)
    return getActive(state)
end

function pets.hasLost(state)
    local p = ensure(state)
    return p.lostKey ~= nil
end

function pets.bumpRunLevel(state, delta)
    local p = ensure(state)
    local d = tonumber(delta) or 1
    p.runLevel = math.max(1, math.floor((p.runLevel or 1) + d))

    local pet = getActive(state)
    if pet then
        recomputePetStats(state, pet)
    end
    return p.runLevel
end

function pets.setActive(state, petKey, opts)
    opts = opts or {}
    if not state or not state.player then return nil end
    local p = ensure(state)

    local def = state.catalog and state.catalog[petKey]
    if not def or def.type ~= 'pet' then return nil end

    p.lostKey = nil
    p.list = {}

    local profile = state.profile or {}
    profile.startPetKey = profile.startPetKey or 'pet_magnet'
    profile.petModules = profile.petModules or {}
    -- module is now determined by MOD slots in recomputePetStats
    local module = 'default'

    local baseHp = (def.base and def.base.hp) or 60
    local baseCd = (def.base and def.base.cooldown) or 3.0
    local baseSpeed = (def.base and def.base.speed) or 190

    local meta = profile.petRanks or {}
    local rank = math.max(0, math.floor(meta[petKey] or 0))
    local hpBonus = rank * 6

    local lvl = p.runLevel or 1
    local cdMul = 1.0 - math.min(0.18, (lvl - 1) * 0.02)
    cdMul = cdMul * (1.0 - math.min(0.15, rank * 0.03))

    local offsetX, offsetY = 28, 22
    local pet = {
        key = petKey,
        name = def.name or petKey,
        module = module,
        level = lvl,
        x = state.player.x + offsetX,
        y = state.player.y + offsetY,
        size = (def.base and def.base.size) or 16,
        speed = baseSpeed,
        facing = 1,

        hp = baseHp + hpBonus,
        maxHp = baseHp + hpBonus,
        armor = 0,
        invincibleTimer = 0,

        downed = false,
        downedTimer = 0,
        reviveProgress = 0,

        mode = 'follow', -- 'follow' | 'hold'
        abilityTimer = 0.9,
        abilityCooldown = math.max(0.25, baseCd * cdMul)
    }
    table.insert(p.list, pet)

    recomputePetStats(state, pet)

    if state.texts then
        local label = opts.revive and "PET REVIVED" or (opts.swap and "PET SWAPPED" or "PET READY")
        table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = label .. ": " .. tostring(pet.name), color = {0.85, 0.95, 1.0}, life = 1.3})
    end
    if state.spawnEffect then state.spawnEffect('static_hit', pet.x, pet.y, 0.75) end
    return pet
end

function pets.recompute(state)
    local pet = getActive(state)
    if pet then
        recomputePetStats(state, pet)
    end
end

function pets.spawnStartingPet(state)
    if not state then return nil end
    local profile = state.profile or {}
    local key = profile.startPetKey or 'pet_magnet'
    local p = ensure(state)
    p.runLevel = 1
    local pet = pets.setActive(state, key, {swap = false})
    if not pet and key ~= 'pet_magnet' then
        pet = pets.setActive(state, 'pet_magnet', {swap = false})
    end
    return pet
end

function pets.toggleMode(state)
    local pet = getActive(state)
    if not pet then return false end
    if pet.downed then return false end
    if pet.mode == 'follow' then pet.mode = 'hold' else pet.mode = 'follow' end
    if state and state.texts then
        local label = (pet.mode == 'hold') and "HOLD" or "FOLLOW"
        table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = tostring(pet.name) .. ": " .. label, color = {1, 1, 1}, life = 1.2})
    end
    return true
end

function pets.hurt(state, pet, dmg)
    if not state or not pet then return end
    if state.benchmarkMode then return end
    if pet.downed then return end
    if (pet.invincibleTimer or 0) > 0 then return end

    local applied = math.max(1, math.floor((dmg or 0) - (pet.armor or 0)))
    pet.hp = (pet.hp or 0) - applied
    pet.invincibleTimer = 0.35
    if state.texts then
        table.insert(state.texts, {x = pet.x, y = pet.y - 18, text = tostring(applied), color = {1, 0.6, 0.6}, life = 0.5})
    end
    if state.spawnEffect then state.spawnEffect('hit', pet.x, pet.y, 0.7) end

    if (pet.hp or 0) <= 0 then
        pet.hp = 0
        pet.downed = true
        pet.downedTimer = 0
        pet.reviveProgress = 0
        if state.texts then
            table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = tostring(pet.name) .. " DOWN!", color = {1, 0.35, 0.35}, life = 1.6})
        end
        if state.spawnEffect then state.spawnEffect('shock', pet.x, pet.y, 0.9) end
    end
end

function pets.reviveLost(state)
    if not state or not state.player then return nil end
    local p = ensure(state)
    if not p.lostKey then return nil end
    local key = p.lostKey
    p.lostKey = nil
    return pets.setActive(state, key, {revive = true})
end

function pets.update(state, dt)
    if not state or not dt or dt <= 0 then return end
    if state.gameState ~= 'PLAYING' then return end
    local p = ensure(state)
    local pl = state.player
    if not pl then return end

    local pet = getActive(state)
    if not pet then return end

    pet.invincibleTimer = math.max(0, (pet.invincibleTimer or 0) - dt)

    if pet.downed then
        pet.downedTimer = (pet.downedTimer or 0) + dt

        local dist = math.sqrt((pl.x - pet.x) ^ 2 + (pl.y - pet.y) ^ 2)
        local holding = (dist <= 42) and love.keyboard.isDown('e')
        if holding then
            pet.reviveProgress = (pet.reviveProgress or 0) + dt
        else
            pet.reviveProgress = math.max(0, (pet.reviveProgress or 0) - dt * 0.8)
        end

        if (pet.reviveProgress or 0) >= (p.reviveHoldTime or 1.1) then
            pet.downed = false
            pet.downedTimer = 0
            pet.reviveProgress = 0
            pet.hp = math.max(1, math.floor((pet.maxHp or 60) * 0.5))
            pet.invincibleTimer = 0.8
            if state.texts then
                table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = tostring(pet.name) .. " REVIVED", color = {0.55, 1, 0.55}, life = 1.2})
            end
            if state.spawnEffect then state.spawnEffect('static_hit', pet.x, pet.y, 0.8) end
        elseif (pet.downedTimer or 0) >= (p.bleedoutTime or 10.0) then
            -- retreat: pet leaves the run until revived via an event.
            p.lostKey = pet.key
            p.list = {}
            if state.texts then
                table.insert(state.texts, {x = pl.x, y = pl.y - 60, text = "PET RETREATED", color = {1, 0.25, 0.25}, life = 1.6})
            end
            if state.spawnEffect then state.spawnEffect('ice_shatter', pet.x, pet.y, 0.9) end
        end
        return
    end

    local mode = pet.mode or 'follow'
    if mode == 'follow' then
        local desiredDist = 52
        local desiredAngle = -2.0
        local tx = pl.x + math.cos(desiredAngle) * desiredDist
        local ty = pl.y + math.sin(desiredAngle) * desiredDist

        local dx = tx - pet.x
        local dy = ty - pet.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 2 then
            local spd = pet.speed or 190
            local step = math.min(d, spd * dt)
            local mx = dx / d * step
            local my = dy / d * step
            local world = state.world
            if world and world.enabled and world.moveCircle then
                pet.x, pet.y = world:moveCircle(pet.x, pet.y, (pet.size or 18) / 2, mx, my)
            else
                pet.x = pet.x + mx
                pet.y = pet.y + my
            end
            if dx > 1 then pet.facing = 1 elseif dx < -1 then pet.facing = -1 end
        end
    end

    pet.abilityTimer = (pet.abilityTimer or 0) - dt
    if pet.abilityTimer <= 0 then
        doPetAbility(state, pet)
        local cd = pet.abilityCooldown or 3.0
        pet.abilityTimer = cd * (0.90 + 0.2 * math.random())
    end
end

return pets
