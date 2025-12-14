local util = require('util')

local crew = {}

local function ensure(state)
    state.crew = state.crew or {}
    local c = state.crew
    c.max = c.max or 2
    c.list = c.list or {}
    c.reviveHoldTime = c.reviveHoldTime or 1.2
    c.bleedoutTime = c.bleedoutTime or 12.0
    return c
end

local function countActive(list)
    local n = 0
    for _, a in ipairs(list or {}) do
        if a and not a.dead then n = n + 1 end
    end
    return n
end

local function nextOwnerKey(state)
    local c = ensure(state)
    local used = {}
    for _, a in ipairs(c.list) do
        if a and not a.dead and a.ownerKey then
            used[a.ownerKey] = true
        end
    end
    for i = 1, (c.max or 2) do
        local k = 'crew' .. tostring(i)
        if not used[k] then return k end
    end
    return nil
end

local function hasWeaponAssigned(state, ownerKey)
    if not state or not ownerKey then return false end
    for _, w in pairs((state.inventory and state.inventory.weapons) or {}) do
        if w and w.owner == ownerKey then
            return true
        end
    end
    return false
end

local function findFirstUnassignedWeapon(state)
    local keys = {}
    for k, w in pairs((state.inventory and state.inventory.weapons) or {}) do
        if w and w.owner == 'stash' then
            table.insert(keys, k)
        end
    end
    table.sort(keys)
    return keys[1]
end

local function assignWeaponToOwner(state, weaponKey, ownerKey)
    if not state or not weaponKey or not ownerKey then return false end
    local w = state.inventory and state.inventory.weapons and state.inventory.weapons[weaponKey]
    if not w then return false end
    w.owner = ownerKey
    return true
end

function crew.count(state)
    local c = ensure(state)
    return countActive(c.list)
end

function crew.get(state, idx)
    local c = ensure(state)
    return c.list and c.list[idx]
end

function crew.init(state)
    local c = ensure(state)
    c.max = 2
    c.list = {}
end

function crew.recruit(state, opts)
    opts = opts or {}
    if not state or not state.player then return nil end
    local c = ensure(state)
    if crew.count(state) >= (c.max or 2) then return nil end

    local ownerKey = nextOwnerKey(state)
    if not ownerKey then return nil end

    local idx = #c.list + 1
    local p = state.player
    local angle = (idx == 1) and (math.pi * 0.75) or (math.pi * 0.25)
    local dist = 34

    local a = {
        id = idx,
        ownerKey = ownerKey,
        name = opts.name or ("Crew " .. tostring(idx)),
        x = p.x + math.cos(angle) * dist,
        y = p.y + math.sin(angle) * dist,
        size = 18,
        speed = 170,
        facing = 1,

        hp = opts.hp or 70,
        maxHp = opts.maxHp or 70,
        armor = opts.armor or 0,
        invincibleTimer = 0,

        downed = false,
        downedTimer = 0,
        reviveProgress = 0,

        mode = 'follow' -- 'follow' | 'hold'
    }
    table.insert(c.list, a)

    -- Auto-equip: if there is an unassigned weapon in inventory, give it to the new crew member.
    if not hasWeaponAssigned(state, ownerKey) then
        local wKey = findFirstUnassignedWeapon(state)
        if wKey then
            assignWeaponToOwner(state, wKey, ownerKey)
        end
    end

    table.insert(state.texts, {x = a.x, y = a.y - 60, text = "CREW JOINED!", color = {0.75, 0.95, 1.0}, life = 1.4})
    if state.spawnEffect then state.spawnEffect('static_hit', a.x, a.y, 0.8) end
    return a
end

function crew.toggleMode(state, idx)
    local a = crew.get(state, idx)
    if not a or a.dead then return false end
    if a.mode == 'follow' then a.mode = 'hold' else a.mode = 'follow' end
    if state and state.texts then
        local label = (a.mode == 'hold') and "HOLD" or "FOLLOW"
        table.insert(state.texts, {x = a.x, y = a.y - 60, text = a.name .. ": " .. label, color = {1, 1, 1}, life = 1.2})
    end
    return true
end

function crew.hurt(state, a, dmg)
    if not state or not a or a.dead then return end
    if state.benchmarkMode then return end
    if a.downed then return end
    if (a.invincibleTimer or 0) > 0 then return end

    local applied = math.max(1, math.floor((dmg or 0) - (a.armor or 0)))
    a.hp = (a.hp or 0) - applied
    a.invincibleTimer = 0.35
    if state.texts then
        table.insert(state.texts, {x = a.x, y = a.y - 18, text = tostring(applied), color = {1, 0.6, 0.6}, life = 0.5})
    end
    if state.spawnEffect then state.spawnEffect('hit', a.x, a.y, 0.7) end

    if (a.hp or 0) <= 0 then
        a.hp = 0
        a.downed = true
        a.downedTimer = 0
        a.reviveProgress = 0
        if state.texts then
            table.insert(state.texts, {x = a.x, y = a.y - 60, text = a.name .. " DOWN!", color = {1, 0.35, 0.35}, life = 1.6})
        end
        if state.spawnEffect then state.spawnEffect('shock', a.x, a.y, 0.9) end
    end
end

function crew.update(state, dt)
    if not state or not dt or dt <= 0 then return end
    if state.gameState ~= 'PLAYING' then return end
    local c = ensure(state)
    local p = state.player
    if not p then return end

    for _, a in ipairs(c.list or {}) do
        if not a or a.dead then goto continue end

        a.invincibleTimer = math.max(0, (a.invincibleTimer or 0) - dt)

        if a.downed then
            a.downedTimer = (a.downedTimer or 0) + dt

            local dist = math.sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
            local holding = (dist <= 42) and love.keyboard.isDown('e')
            if holding then
                a.reviveProgress = (a.reviveProgress or 0) + dt
            else
                a.reviveProgress = math.max(0, (a.reviveProgress or 0) - dt * 0.8)
            end

            if (a.reviveProgress or 0) >= (c.reviveHoldTime or 1.2) then
                a.downed = false
                a.downedTimer = 0
                a.reviveProgress = 0
                a.hp = math.max(1, math.floor((a.maxHp or 70) * 0.5))
                a.invincibleTimer = 0.8
                if state.texts then
                    table.insert(state.texts, {x = a.x, y = a.y - 60, text = a.name .. " REVIVED", color = {0.55, 1, 0.55}, life = 1.2})
                end
                if state.spawnEffect then state.spawnEffect('static_hit', a.x, a.y, 0.8) end
            elseif (a.downedTimer or 0) >= (c.bleedoutTime or 12.0) then
                a.dead = true
                if state.texts then
                    table.insert(state.texts, {x = a.x, y = a.y - 60, text = a.name .. " LOST", color = {1, 0.2, 0.2}, life = 1.8})
                end
                if state.spawnEffect then state.spawnEffect('ice_shatter', a.x, a.y, 0.9) end
            end
            goto continue
        end

        local mode = a.mode or 'follow'
        if mode == 'follow' then
            local followIdx = a.id or 1
            local desiredDist = 56
            local desiredAngle = (followIdx == 1) and (-2.2) or (-0.9)
            local tx = p.x + math.cos(desiredAngle) * desiredDist
            local ty = p.y + math.sin(desiredAngle) * desiredDist

            local dx = tx - a.x
            local dy = ty - a.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 2 then
                local spd = a.speed or 170
                local step = math.min(d, spd * dt)
                a.x = a.x + dx / d * step
                a.y = a.y + dy / d * step
                if dx > 1 then a.facing = 1 elseif dx < -1 then a.facing = -1 end
            end
        end

        ::continue::
    end
end

return crew
