local enemies = require('enemies')
local biomes = require('biomes')

local mission = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function containsCell(r, cx, cy)
    return cx >= (r.x1 or 0) and cx <= (r.x2 or 0) and cy >= (r.y1 or 0) and cy <= (r.y2 or 0)
end

local function pickStartZone(world)
    local scx, scy = world.spawnCx, world.spawnCy
    for i, r in ipairs(world.rooms or {}) do
        if scx and scy and containsCell(r, scx, scy) then
            return i
        end
    end
    return 1
end

local function pickBossZone(world, startId)
    local rooms = world.rooms or {}
    local sr = rooms[startId] or rooms[1]
    if not sr then return 1 end
    local bestId, bestD2 = startId, -1
    for i, r in ipairs(rooms) do
        local dx = (r.cx or 0) - (sr.cx or 0)
        local dy = (r.cy or 0) - (sr.cy or 0)
        local d2 = dx * dx + dy * dy
        if d2 > bestD2 then
            bestD2 = d2
            bestId = i
        end
    end
    return bestId
end

local function buildEnemyPool(state)
    local c = state and state.campaign
    local biomeDef = (c and c.biomeDef) or (c and biomes.get(c.biome)) or biomes.get(1)
    local tier = math.max(1, math.min(2, math.floor((c and c.stageInBiome) or 1)))
    return biomes.buildEnemyPool(biomeDef, tier)
end

local function distanceToRoomRectPx(world, room, x, y)
    local ts = (world and world.tileSize) or 32
    local x1 = (room and room.x1) or 1
    local y1 = (room and room.y1) or 1
    local x2 = (room and room.x2) or x1
    local y2 = (room and room.y2) or y1

    local left = (x1 - 1) * ts
    local right = x2 * ts
    local top = (y1 - 1) * ts
    local bottom = y2 * ts

    local dx = 0
    if x < left then dx = left - x
    elseif x > right then dx = x - right end

    local dy = 0
    if y < top then dy = top - y
    elseif y > bottom then dy = y - bottom end

    return math.sqrt(dx * dx + dy * dy)
end

local function computeZonePreSpawnRangePx(state)
    local world = state.world
    local ts = (world and world.tileSize) or 32

    local sw, sh = 800, 600
    if love and love.graphics and love.graphics.getWidth then
        sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    end
    local screenMin = math.min(sw or 800, sh or 600)

    local base = ts * 6
    local byScreen = screenMin * 0.55
    return clamp(math.max(base, byScreen), ts * 4, ts * 14)
end

local function computeSpawnMinDistPx(state, room)
    local world = state.world
    local ts = (world and world.tileSize) or 32
    local rw = math.max(1, ((room.x2 or 0) - (room.x1 or 0) + 1)) * ts
    local rh = math.max(1, ((room.y2 or 0) - (room.y1 or 0) + 1)) * ts
    local base = math.min(220, math.max(90, math.min(rw, rh) * 0.35))
    local playerR = ((state.player and state.player.size) or 20) * 0.5
    return math.max(base, playerR + 26)
end

local function sampleSpawnFarFromPlayer(state, room, attempts)
    local world = state.world
    if not (world and world.enabled and world.isWalkableCell and world.cellToWorld) then return nil end

    attempts = math.max(12, math.floor(attempts or 64))
    local minDist = computeSpawnMinDistPx(state, room)
    local minDistSq = minDist * minDist
    local px = (state.player and state.player.x) or 0
    local py = (state.player and state.player.y) or 0

    local x1, y1, x2, y2 = room.x1, room.y1, room.x2, room.y2
    local minCx = clamp((x1 or 2) + 1, 2, (world.w or 3) - 1)
    local maxCx = clamp((x2 or minCx) - 1, 2, (world.w or 3) - 1)
    local minCy = clamp((y1 or 2) + 1, 2, (world.h or 3) - 1)
    local maxCy = clamp((y2 or minCy) - 1, 2, (world.h or 3) - 1)
    if maxCx < minCx then minCx, maxCx = maxCx, minCx end
    if maxCy < minCy then minCy, maxCy = maxCy, minCy end

    local function acceptCell(cx, cy)
        if not world:isWalkableCell(cx, cy) then return nil end
        local wx, wy = world:cellToWorld(cx, cy)
        local dx = wx - px
        local dy = wy - py
        if dx * dx + dy * dy < minDistSq then return nil end
        return wx, wy
    end

    -- Prefer perimeter spawns (feels less "pop-in" and reduces on-top spawns).
    for _ = 1, attempts do
        local side = math.random(4)
        local cx, cy
        if side == 1 then
            cx = minCx
            cy = math.random(minCy, maxCy)
        elseif side == 2 then
            cx = maxCx
            cy = math.random(minCy, maxCy)
        elseif side == 3 then
            cx = math.random(minCx, maxCx)
            cy = minCy
        else
            cx = math.random(minCx, maxCx)
            cy = maxCy
        end
        local wx, wy = acceptCell(cx, cy)
        if wx then return wx, wy end
    end

    -- Fallback: any interior cell but still keep a safety distance.
    for _ = 1, attempts do
        local cx = math.random(minCx, maxCx)
        local cy = math.random(minCy, maxCy)
        local wx, wy = acceptCell(cx, cy)
        if wx then return wx, wy end
    end

    -- Last resort: center-ish cell.
    local ccx = math.floor((minCx + maxCx) * 0.5)
    local ccy = math.floor((minCy + maxCy) * 0.5)
    if world.findNearestWalkable then
        local fx, fy = world:findNearestWalkable(ccx, ccy, 24)
        if fx then return world:cellToWorld(fx, fy) end
    end

    -- If the room is too small to satisfy minDist, pick the farthest walkable cell available.
    local bestWx, bestWy, bestD2 = nil, nil, -1
    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            if world:isWalkableCell(cx, cy) then
                local wx, wy = world:cellToWorld(cx, cy)
                local dx = wx - px
                local dy = wy - py
                local d2 = dx * dx + dy * dy
                if d2 > bestD2 then
                    bestD2 = d2
                    bestWx, bestWy = wx, wy
                end
            end
        end
    end
    if bestWx then return bestWx, bestWy end
    return world:cellToWorld(ccx, ccy)
end

local function buildSpawnQueuePack(state, zoneId, room, opts)
    opts = opts or {}
    local world = state.world
    if not (world and world.enabled) then return nil end

    local count = math.max(1, math.floor(opts.count or 6))
    local eliteChance = math.max(0, math.min(1, tonumber(opts.eliteChance) or 0))
    local telegraph = (opts.telegraph == true)
    local baseDelay = tonumber(opts.baseDelay)
    if baseDelay == nil then baseDelay = 0.0 end
    local delayJitter = tonumber(opts.delayJitter)
    if delayJitter == nil then delayJitter = 0.0 end

    local pool = buildEnemyPool(state)
    local q = {}
    local used = {}

    for i = 1, count do
        local kind = pool[math.random(#pool)]
        local isElite = false
        if i == 1 and eliteChance > 0 and math.random() < eliteChance then
            isElite = true
        end

        local sx, sy
        for _ = 1, 6 do
            local tx, ty = sampleSpawnFarFromPlayer(state, room, 80)
            if not tx then break end
            if world.worldToCell then
                local cx, cy = world:worldToCell(tx, ty)
                local key = tostring(cx) .. "," .. tostring(cy)
                if not used[key] then
                    used[key] = true
                    sx, sy = tx, ty
                    break
                end
            else
                sx, sy = tx, ty
                break
            end
        end

        if sx and sy then
            local delay = baseDelay
            if delayJitter > 0 then delay = delay + math.random() * delayJitter end
            q[#q + 1] = {kind = kind, isElite = isElite, x = sx, y = sy, t = delay}
            if telegraph and state.spawnTelegraphCircle then
                state.spawnTelegraphCircle(sx, sy, 22, delay, {kind = 'danger', intensity = 1.0})
            end
        end
    end

    return q
end

local function buildSpawnQueueBoss(state, zoneId, room)
    local world = state.world
    if not (world and world.enabled) then return nil end
    local sx, sy = sampleSpawnFarFromPlayer(state, room, 120)
    if not (sx and sy) then return nil end
    local delay = 0.95
    if state.spawnTelegraphCircle then
        state.spawnTelegraphCircle(sx, sy, 54, delay, {kind = 'danger', intensity = 1.25})
    end
    local c = state and state.campaign
    local bossKey = (c and c.biomeDef and c.biomeDef.boss) or 'boss_treant'
    return {{kind = bossKey, isElite = false, x = sx, y = sy, t = delay, isBoss = true}}
end

local function processSpawnQueues(state, dt)
    local m = state.mission
    if not (m and m.zones) then return end
    dt = dt or 0

    for _, z in ipairs(m.zones) do
        local q = z and z.spawnQueue
        if q and #q == 0 then
            z.spawnQueue = nil
        elseif q and #q > 0 then
            for i = #q, 1, -1 do
                local s = q[i]
                s.t = (s.t or 0) - dt
                if (s.t or 0) <= 0 then
                    local spawned = enemies.spawnEnemy(state, s.kind, s.isElite, s.x, s.y, {suppressSpawnText = true})
                    if spawned then
                        spawned.zoneId = z.id
                        spawned.noContactDamageTimer = 0.65
                    end
                    table.remove(q, i)
                end
            end
            if #q == 0 then
                z.spawnQueue = nil
            end
        end
    end
end

function mission.start(state)
    local world = state and state.world
    if not (world and world.enabled and world.rooms and #world.rooms > 0) then
        state.mission = nil
        return
    end

    local startId = pickStartZone(world)
    local stageType = (state and state.campaign and state.campaign.stageType) or 'boss'
    local bossId = nil
    local exitId = nil
    if stageType == 'boss' then
        bossId = pickBossZone(world, startId)
    else
        exitId = pickBossZone(world, startId)
        if exitId == startId and (world.rooms and #world.rooms > 1) then
            -- pick the farthest room excluding start, if possible
            local sr = world.rooms[startId]
            local bestId, bestD2 = nil, -1
            for i, r in ipairs(world.rooms) do
                if i ~= startId then
                    local dx = (r.cx or 0) - (sr.cx or 0)
                    local dy = (r.cy or 0) - (sr.cy or 0)
                    local d2 = dx * dx + dy * dy
                    if d2 > bestD2 then
                        bestD2 = d2
                        bestId = i
                    end
                end
            end
            exitId = bestId or exitId
        end
    end

    local zones = {}
    for i, r in ipairs(world.rooms) do
        zones[i] = {
            id = i,
            room = r,
            spawned = false,
            cleared = false,
            isStart = (i == startId),
            isBoss = (bossId ~= nil) and (i == bossId) or false,
            isExit = (exitId ~= nil) and (i == exitId) or false
        }
    end
    if zones[startId] and not zones[startId].isBoss then
        zones[startId].spawned = true
        zones[startId].cleared = true
    end

    state.mission = {
        zones = zones,
        startId = startId,
        bossId = bossId,
        exitId = exitId,
        stageType = stageType,
        currentZoneId = nil,
        clearedCount = 0
    }

    if state.texts then
        if stageType == 'boss' then
            table.insert(state.texts, {x = state.player.x, y = state.player.y - 110, text = "OBJECTIVE: DEFEAT THE BOSS", color = {0.95, 0.95, 1.0}, life = 2.2})
        else
            table.insert(state.texts, {x = state.player.x, y = state.player.y - 110, text = "OBJECTIVE: REACH EXTRACTION", color = {0.95, 0.95, 1.0}, life = 2.2})
        end
    end

    -- Safety: if generation produced only a single room in an explore stage, make extraction available immediately.
    if stageType ~= 'boss' and exitId and exitId == startId and zones[startId] and zones[startId].isExit then
        zones[startId].exitChestSpawned = true
        state.chests = state.chests or {}
        local wx, wy = world:cellToWorld((zones[startId].room and zones[startId].room.cx) or world.spawnCx or 1, (zones[startId].room and zones[startId].room.cy) or world.spawnCy or 1)
        table.insert(state.chests, {x = wx, y = wy, w = 26, h = 26, kind = 'stage_exit'})
    end
end

local function findZoneAt(state, cx, cy)
    local m = state.mission
    if not m then return nil end
    for i, z in ipairs(m.zones or {}) do
        if z and z.room and containsCell(z.room, cx, cy) then
            return i, z
        end
    end
    return nil
end

local function isZoneCleared(state, zoneId)
    for _, e in ipairs(state.enemies or {}) do
        if e and e.zoneId == zoneId and (e.health or e.hp or 0) > 0 then
            return false
        end
    end
    return true
end

function mission.update(state, dt)
    if not state or state.gameState ~= 'PLAYING' then return end
    if state.runMode ~= 'explore' then return end
    local world = state.world
    if not (world and world.enabled and world.worldToCell) then return end

    local m = state.mission
    if not m or not m.zones then
        mission.start(state)
        m = state.mission
        if not m then return end
    end

    local px = state.player.x or 0
    local py = state.player.y or 0
    local pcx, pcy = world:worldToCell(px, py)
    local zid, z = findZoneAt(state, pcx, pcy)
    m.currentZoneId = zid

    local stageType = (m and m.stageType) or (state.campaign and state.campaign.stageType) or 'boss'

    -- "无感刷新"：玩家接近房间时就预先刷怪（通常发生在走廊里，看不到房间内部）。
    local preSpawnRange = computeZonePreSpawnRangePx(state)
    for id, zone in ipairs(m.zones or {}) do
        if zone and not zone.spawned and not zone.cleared and not zone.isStart and not zone.isBoss then
            local d = distanceToRoomRectPx(world, zone.room, px, py)
            if d <= preSpawnRange then
                zone.spawned = true
                local base = 6 + math.min(6, math.floor((state.gameTimer or 0) / 60))
                local count = base + math.random(0, 2)
                local eliteChance = (m.clearedCount >= 3) and 0.18 or 0.0
                zone.spawnQueue = buildSpawnQueuePack(state, id, zone.room, {
                    count = count,
                    eliteChance = eliteChance,
                    telegraph = false,
                    baseDelay = 0,
                    delayJitter = 0
                })
            end
        end
    end

    -- Boss 仍然在进入 boss 房时生成（更可读，也避免 boss 提前游荡）。
    if zid and z and z.isBoss and not z.spawned then
        z.spawned = true
        z.spawnQueue = buildSpawnQueueBoss(state, zid, z.room)
    end

    -- Process queued spawns after scheduling so packs can appear before the player fully steps in.
    processSpawnQueues(state, dt)

    -- Zone clear logic: allow clearing even if the player leaves the room (but only show text when inside).
    for id, zone in ipairs(m.zones or {}) do
        if zone and zone.spawned and not zone.cleared and not zone.isBoss then
            if not zone.spawnQueue and isZoneCleared(state, id) then
                zone.cleared = true
                m.clearedCount = (m.clearedCount or 0) + 1
                if state.texts and m.currentZoneId == id then
                    table.insert(state.texts, {x = state.player.x, y = state.player.y - 110, text = "CLEARED", color = {0.75, 1.0, 0.75}, life = 1.2})
                end

                if stageType ~= 'boss' and zone.isExit and not zone.exitChestSpawned then
                    zone.exitChestSpawned = true
                    state.chests = state.chests or {}
                    local wx, wy = world:cellToWorld((zone.room and zone.room.cx) or 1, (zone.room and zone.room.cy) or 1)
                    table.insert(state.chests, {x = wx, y = wy, w = 26, h = 26, kind = 'stage_exit'})
                    if state.texts and m.currentZoneId == id then
                        table.insert(state.texts, {x = wx, y = wy - 90, text = "EXTRACTION READY", color = {0.85, 0.95, 1.0}, life = 2.0})
                    end
                end
            end
        end
    end
end

return mission
