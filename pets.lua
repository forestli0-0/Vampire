local util = require('util')

local pets = {}

local _calculator = nil
local function getCalculator()
    if not _calculator then
        local ok, calc = pcall(require, 'calculator')
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

local function doPetAbility(state, pet)
    if not state or not pet then return end
    local key = pet.key
    local module = pet.module or 'default'
    local lvl = pet.level or 1

    if key == 'pet_magnet' then
        if module == 'pulse' then
            local r = 150 + (lvl - 1) * 8
            local r2 = r * r
            local any = false
            for _, e in ipairs(state.enemies or {}) do
                if e and not e.isDummy and (e.health or e.hp or 0) > 0 then
                    local dx = (e.x or 0) - pet.x
                    local dy = (e.y or 0) - pet.y
                    if dx * dx + dy * dy <= r2 then
                        applyPetProc(state, e, 'MAGNETIC', 1, key, module)
                        any = true
                    end
                end
            end
            if any and state.spawnEffect then state.spawnEffect('static_hit', pet.x, pet.y, 0.8) end
        else
            local t = findNearestEnemyAt(state, pet.x, pet.y, 700)
            if t then
                local stacks = 1
                if lvl >= 4 then stacks = 2 end
                applyPetProc(state, t, 'MAGNETIC', stacks, key, module)
                if state.spawnEffect then state.spawnEffect('static_hit', t.x, t.y, 0.7) end
            end
        end
    elseif key == 'pet_corrosive' then
        if module == 'field' then
            local r = 140 + (lvl - 1) * 6
            local r2 = r * r
            local any = false
            for _, e in ipairs(state.enemies or {}) do
                if e and not e.isDummy and (e.health or e.hp or 0) > 0 then
                    local dx = (e.x or 0) - pet.x
                    local dy = (e.y or 0) - pet.y
                    if dx * dx + dy * dy <= r2 then
                        applyPetProc(state, e, 'CORROSIVE', 1, key, module)
                        any = true
                    end
                end
            end
            if any and state.spawnEffect then state.spawnEffect('toxin_hit', pet.x, pet.y, 0.85) end
        else
            local t = findNearestEnemyAt(state, pet.x, pet.y, 700)
            if t then
                local stacks = 1
                if (t.armor or 0) >= 120 and lvl >= 3 then stacks = 2 end
                applyPetProc(state, t, 'CORROSIVE', stacks, key, module)
                if state.spawnEffect then state.spawnEffect('corrosive_hit', t.x, t.y, 0.75) end
            end
        end
    elseif key == 'pet_guardian' then
        local p = state.player
        if not p then return end
        if module == 'barrier' then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.22 + math.min(0.18, (lvl - 1) * 0.02))
            if state.spawnEffect then state.spawnEffect('static_hit', p.x, p.y, 0.75) end
            table.insert(state.texts, {x = p.x, y = p.y - 46, text = "BARRIER", color = {0.7, 0.95, 1.0}, life = 0.8})
        else
            local heal = 7 + math.min(10, (lvl - 1) * 2)
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
        pet.level = p.runLevel
        local def = state.catalog and state.catalog[pet.key]
        local baseCd = (def and def.base and def.base.cooldown) or (pet.abilityCooldown or 3.0)

        local profile = state.profile or {}
        local meta = profile.petRanks or {}
        local rank = math.max(0, math.floor(meta[pet.key] or 0))

        local lvl = p.runLevel or 1
        local cdMul = 1.0 - math.min(0.18, (lvl - 1) * 0.02)
        cdMul = cdMul * (1.0 - math.min(0.15, rank * 0.03))
        pet.abilityCooldown = math.max(0.25, baseCd * cdMul)
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
    local module = profile.petModules[petKey] or 'default'

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

    if state.texts then
        local label = opts.revive and "PET REVIVED" or (opts.swap and "PET SWAPPED" or "PET READY")
        table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = label .. ": " .. tostring(pet.name), color = {0.85, 0.95, 1.0}, life = 1.3})
    end
    if state.spawnEffect then state.spawnEffect('static_hit', pet.x, pet.y, 0.75) end
    return pet
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
            pet.x = pet.x + dx / d * step
            pet.y = pet.y + dy / d * step
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
