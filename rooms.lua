local enemies = require('enemies')

local rooms = {}

local function clearList(list)
    if type(list) ~= 'table' then return end
    for i = #list, 1, -1 do
        table.remove(list, i)
    end
end

local function containsRef(list, ref)
    if type(list) ~= 'table' or not ref then return false end
    for _, v in ipairs(list) do
        if v == ref then return true end
    end
    return false
end

local function countAliveEnemies(state)
    local n = 0
    for _, e in ipairs(state.enemies or {}) do
        if e and not e.isDummy then
            local hp = e.health or e.hp or 0
            if hp > 0 then n = n + 1 end
        end
    end
    return n
end

local function ensureState(state)
    state.rooms = state.rooms or {}
    local r = state.rooms
    if r.enabled == nil then r.enabled = true end

    r.phase = r.phase or 'init'
    r.roomIndex = r.roomIndex or 0
    r.waveIndex = r.waveIndex or 0
    r.wavesTotal = r.wavesTotal or 0
    r.timer = r.timer or 0
    r.roomCenterX = r.roomCenterX or 0
    r.roomCenterY = r.roomCenterY or 0
    r.rewardChest = r.rewardChest or nil
    r.bossRoom = r.bossRoom or 8
    r.rewardCycle = r.rewardCycle or {'weapon', 'passive', 'mod', 'augment'}
    r._hadCombat = r._hadCombat or false
    return r
end

local function chooseWeighted(pool)
    local total = 0
    for _, it in ipairs(pool) do
        total = total + (it.w or 0)
    end
    if total <= 0 then return pool[1] and pool[1].key end
    local r = math.random() * total
    for _, it in ipairs(pool) do
        r = r - (it.w or 0)
        if r <= 0 then return it.key end
    end
    return pool[#pool] and pool[#pool].key
end

local function buildEnemyPool(roomIndex)
    local pool = {
        {key = 'skeleton', w = 10}
    }
    if roomIndex >= 2 then
        table.insert(pool, {key = 'bat', w = 6})
    end
    if roomIndex >= 3 then
        table.insert(pool, {key = 'plant', w = 4})
    end
    if roomIndex >= 5 then
        table.insert(pool, {key = 'shield_lancer', w = 4})
    end
    if roomIndex >= 6 then
        table.insert(pool, {key = 'armored_brute', w = 3})
    end
    return pool
end

local function spawnWave(state, r)
    local roomIndex = r.roomIndex or 1
    local waveIndex = r.waveIndex or 1

    local baseCount = 7 + roomIndex * 2
    local waveFactor = 0.85 + (waveIndex - 1) * 0.25
    local count = math.floor(baseCount * waveFactor + 0.5)
    count = math.max(4, math.min(42, count))

    local pool = buildEnemyPool(roomIndex)
    local px, py = state.player.x, state.player.y
    local spawnR = 380 + math.random() * 220

    for _ = 1, count do
        local kind = chooseWeighted(pool) or 'skeleton'
        local ang = math.random() * 6.283185307179586
        local dist = spawnR + math.random() * 120
        local x = px + math.cos(ang) * dist
        local y = py + math.sin(ang) * dist
        enemies.spawnEnemy(state, kind, false, x, y)
    end

    r._hadCombat = true
end

local function startRoom(state, r)
    r.roomCenterX, r.roomCenterY = state.player.x, state.player.y
    r.waveIndex = 1
    r.wavesTotal = 2
    if r.roomIndex >= 3 then r.wavesTotal = 3 end
    if r.roomIndex >= 6 then r.wavesTotal = 4 end
    r.timer = 0
    r.rewardChest = nil
    r._hadCombat = false
    r.phase = 'spawning'

    table.insert(state.texts, {
        x = state.player.x,
        y = state.player.y - 100,
        text = string.format("ROOM %d", r.roomIndex),
        color = {1, 1, 1},
        life = 1.2
    })
end

local function spawnRewardChest(state, r)
    -- stop any remaining threat during the reward phase
    clearList(state.enemyBullets)
    for _, g in ipairs(state.gems or {}) do
        g.magnetized = true
    end

    local cx = r.roomCenterX or state.player.x
    local cy = r.roomCenterY or state.player.y
    local rewardType = nil
    local cycle = r.rewardCycle
    if type(cycle) == 'table' and #cycle > 0 then
        rewardType = cycle[((r.roomIndex or 1) - 1) % #cycle + 1]
    end
    local chest = {
        x = cx,
        y = cy,
        w = 20,
        h = 20,
        kind = 'room_reward',
        room = r.roomIndex,
        rewardType = rewardType
    }
    table.insert(state.chests, chest)
    r.rewardChest = chest

    local rewardLabel = ''
    if rewardType then rewardLabel = ' (' .. string.upper(tostring(rewardType)) .. ')' end
    table.insert(state.texts, {
        x = cx,
        y = cy - 100,
        text = "ROOM CLEAR!" .. rewardLabel,
        color = {0.8, 1, 0.8},
        life = 1.8
    })
end

local function startBossRoom(state, r)
    r.phase = 'boss'
    r.waveIndex = 1
    r.wavesTotal = 1
    r.timer = 0
    r.rewardChest = nil
    r._hadCombat = false

    clearList(state.enemyBullets)

    local px, py = state.player.x, state.player.y
    enemies.spawnEnemy(state, 'boss_treant', false, px + 420, py)
    table.insert(state.texts, {x = px, y = py - 110, text = "BOSS!", color = {1, 0.2, 0.2}, life = 2.0})
end

function rooms.update(state, dt)
    if not state or not dt then return end
    if state.gameState ~= 'PLAYING' then return end
    if state.benchmarkMode then return end
    if state.testArena or state.scenarioNoDirector then return end

    local r = ensureState(state)
    if not r.enabled then return end

    if r.phase == 'init' then
        r.roomIndex = 0
        r.timer = 0.2
        r.phase = 'between_rooms'
        return
    end

    if state.gameState == 'GAME_OVER' or state.gameState == 'GAME_CLEAR' then return end

    if r.phase == 'between_rooms' then
        r.timer = (r.timer or 0) - dt
        if r.timer > 0 then return end
        r.roomIndex = (r.roomIndex or 0) + 1
        if r.roomIndex >= (r.bossRoom or 8) then
            startBossRoom(state, r)
        else
            startRoom(state, r)
        end
        return
    end

    if r.phase == 'spawning' then
        spawnWave(state, r)
        r.phase = 'fighting'
        return
    end

    if r.phase == 'fighting' then
        local alive = countAliveEnemies(state)
        if alive > 0 then return end
        if r._hadCombat then
            if (r.waveIndex or 1) < (r.wavesTotal or 1) then
                clearList(state.enemyBullets)
                r.waveIndex = (r.waveIndex or 1) + 1
                r.timer = 0.65
                r.phase = 'between_waves'
            else
                r.phase = 'reward'
                spawnRewardChest(state, r)
            end
        end
        return
    end

    if r.phase == 'between_waves' then
        r.timer = (r.timer or 0) - dt
        if r.timer > 0 then return end
        r.phase = 'spawning'
        return
    end

    if r.phase == 'reward' then
        -- advance only after the room reward chest has been opened/consumed.
        if r.rewardChest and containsRef(state.chests, r.rewardChest) then
            return
        end
        r.rewardChest = nil
        r.timer = 0.25
        r.phase = 'between_rooms'
        return
    end

    if r.phase == 'boss' then
        -- boss flow is handled by enemies.lua (GAME_CLEAR + rewards). Just keep threats tidy.
        local alive = countAliveEnemies(state)
        if alive <= 0 then
            clearList(state.enemyBullets)
        end
        return
    end
end

return rooms
