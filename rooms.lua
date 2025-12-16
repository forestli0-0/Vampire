local enemies = require('enemies')
local util = require('util')
local pets = require('pets')

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
    r.rewardCycle = r.rewardCycle or {'weapon', 'passive', 'augment'}
    r.roomRewardType = r.roomRewardType or nil
    r.nextRewardType = r.nextRewardType or nil
    r.roomKind = r.roomKind or 'normal'
    r.nextRoomKind = r.nextRoomKind or nil
    
    -- Mission type: 'exterminate', 'defense', 'survival'
    r.missionType = r.missionType or 'exterminate'
    
    -- Defense mission state
    r.defenseObjective = r.defenseObjective or nil
    
    -- Survival mission state
    r.lifeSupport = r.lifeSupport or nil
    r.lifeSupportCapsuleTimer = r.lifeSupportCapsuleTimer or 0
    r.survivalTimer = r.survivalTimer or 0
    r.survivalTarget = r.survivalTarget or 60  -- seconds to survive

    -- Reward pacing knobs (Hades-like defaults for rooms mode)
    if r.xpGivesUpgrades == nil then r.xpGivesUpgrades = false end
    if r.eliteDropsChests == nil then r.eliteDropsChests = false end
    if r.eliteRoomBonusUpgrades == nil then r.eliteRoomBonusUpgrades = 1 end
    r._hadCombat = r._hadCombat or false
    r.specialPickup = r.specialPickup or nil
    return r
end

local function pickTwoDistinct(list)
    if type(list) ~= 'table' or #list <= 0 then return nil, nil end
    if #list == 1 then return list[1], list[1] end

    local a = list[math.random(#list)]
    local b = list[math.random(#list)]
    local guard = 0
    while b == a and guard < 12 do
        b = list[math.random(#list)]
        guard = guard + 1
    end
    if b == a then
        local idx = 1
        for i, v in ipairs(list) do
            if v == a then idx = i break end
        end
        b = list[(idx % #list) + 1]
    end
    return a, b
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
        table.insert(pool, {key = 'charger', w = 4})
    end
    if roomIndex >= 3 then
        table.insert(pool, {key = 'plant', w = 4})
    end
    if roomIndex >= 4 then
        table.insert(pool, {key = 'spore_mortar', w = 3})
    end
    if roomIndex >= 5 then
        table.insert(pool, {key = 'shield_lancer', w = 4})
    end
    if roomIndex >= 6 then
        table.insert(pool, {key = 'armored_brute', w = 3})
    end
    return pool
end

local function chooseEliteKind(roomIndex)
    if (roomIndex or 0) < 4 then return 'skeleton' end
    local candidates = {'skeleton', 'bat', 'plant', 'charger', 'spore_mortar', 'shield_lancer'}
    if (roomIndex or 0) >= 6 then
        table.insert(candidates, 'armored_brute')
    end
    return candidates[math.random(#candidates)] or 'skeleton'
end

local spawnSpecialRoomPickup

local function spawnWave(state, r)
    local roomIndex = r.roomIndex or 1
    local waveIndex = r.waveIndex or 1
    local world = state.world

    local baseCount = 7 + roomIndex * 2
    local waveFactor = 0.85 + (waveIndex - 1) * 0.25
    local count = math.floor(baseCount * waveFactor + 0.5)
    count = math.max(4, math.min(42, count))

    local pool = buildEnemyPool(roomIndex)

    local eliteCount = (r.roomKind == 'elite') and 1 or 0
    eliteCount = math.min(eliteCount, count)
    
    for _ = 1, count do
        local isElite = (eliteCount > 0)
        if isElite then eliteCount = eliteCount - 1 end
        local kind = isElite and chooseEliteKind(roomIndex) or (chooseWeighted(pool) or 'skeleton')
        

        local x, y
        if state.world and state.world.enabled and state.world.sampleSpawn then
            -- Arena Mode: Spawn inside walkable area
            -- Try to spawn away from player if possible
            local px, py = state.player.x, state.player.y
            -- Require min distance of 280 (approx 9 tiles) to avoid spawning on top of player
            x, y = state.world:sampleSpawn(px, py, 280, 800, 12)
        else
             -- Open Field Fallback
             local px, py = state.player.x, state.player.y
             local spawnR = 380 + math.random() * 220
             local ang = math.random() * 6.283185307179586
             local dist = spawnR + math.random() * 120
             x = px + math.cos(ang) * dist
             y = py + math.sin(ang) * dist
        end
        
        enemies.spawnEnemy(state, kind, isElite, x, y)
    end

    r._hadCombat = true
end

local function startRoom(state, r)
    -- Procedural Arena Generation
    if state.world and state.world.generateArena then
        local layout = 'random'
        if r.roomIndex == r.bossRoom then layout = 'boss' end
        state.world:generateArena({w=42, h=32, layout=layout})
        
        -- Teleport player to safe spawn
        if state.world.spawnX and state.world.spawnY then
            -- Ensure spawn is walkable
            local sx, sy = state.world.spawnX, state.world.spawnY
            if state.world.adjustToWalkable then
                sx, sy = state.world:adjustToWalkable(sx, sy, 8)
            end
            state.player.x, state.player.y = sx, sy
            state.camera.x = state.player.x - love.graphics.getWidth()/2
            state.camera.y = state.player.y - love.graphics.getHeight()/2
            
            -- Add brief screen fade for smoother transition
            state.roomTransitionFade = 1.0  -- Will fade out over time
        end
    end
    
    r.roomCenterX, r.roomCenterY = state.player.x, state.player.y
    r.waveIndex = 1
    r.wavesTotal = 2
    if r.roomIndex >= 3 then r.wavesTotal = 3 end
    if r.roomIndex >= 6 then r.wavesTotal = 4 end
    r.timer = 0
    r.rewardChest = nil
    state.doors = state.doors or {}
    clearList(state.doors)
    clearList(state.text) -- clear old texts
    clearList(state.enemyBullets) -- safety clear
    
    -- QoL: entering a new room refreshes dash charges to keep the flow fast (Hades-like rooms pacing).
    do
        local p = state.player
        local dash = p and p.dash
        if dash then
            local maxCharges = (p.stats and p.stats.dashCharges) or dash.maxCharges or 0
            maxCharges = math.max(0, math.floor(maxCharges))
            dash.charges = maxCharges
            dash.rechargeTimer = 0
        end
    end

    local roomKind = r.nextRoomKind
    r.nextRoomKind = nil
    if roomKind == nil then roomKind = 'normal' end
    r.roomKind = roomKind

    local rewardType = r.nextRewardType
    r.nextRewardType = nil
    if rewardType == nil then
        local cycle = r.rewardCycle
        if type(cycle) == 'table' and #cycle > 0 then
            rewardType = cycle[((r.roomIndex or 1) - 1) % #cycle + 1]
        end
    end
    r.roomRewardType = rewardType

    r._hadCombat = false
    if roomKind == 'shop' or roomKind == 'event' then
        r.phase = 'special'
        if spawnSpecialRoomPickup then spawnSpecialRoomPickup(state, r) end
    else
        r.phase = 'spawning'
        
        -- Mission-specific initialization
        if r.missionType == 'defense' then
            -- Spawn defense objective at room center
            local cx, cy = r.roomCenterX, r.roomCenterY
            if state.world and state.world.adjustToWalkable then
                cx, cy = state.world:adjustToWalkable(cx, cy, 6)
            end
            r.defenseObjective = {
                x = cx, y = cy,
                hp = 1000, maxHp = 1000,
                size = 40
            }
            table.insert(state.texts, {x=cx, y=cy-50, text="保护目标!", color={1, 0.8, 0.3}, life=2})
        elseif r.missionType == 'survival' then
            -- Initialize life support
            r.lifeSupport = 100
            r.survivalTimer = 0
            r.survivalTarget = 60  -- 60 seconds to survive
            r.lifeSupportCapsuleTimer = 15  -- first capsule in 15s
            table.insert(state.texts, {x=state.player.x, y=state.player.y-50, text="存活60秒!", color={0.6, 0.9, 1}, life=2})
        end
    end
    
    -- Mission type label
    local missionLabel = ""
    if r.missionType == 'defense' then missionLabel = " [DEFENSE]"
    elseif r.missionType == 'survival' then missionLabel = " [SURVIVAL]"
    end

    table.insert(state.texts, {
        x = state.player.x,
        y = state.player.y - 100,
        text = string.format("ROOM %d%s%s", r.roomIndex,
            (roomKind == 'elite') and " (ELITE)" or ((roomKind == 'shop') and " (SHOP)" or ((roomKind == 'event') and " (EVENT)" or "")),
            missionLabel
        ),
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

    -- Pet per-run growth: clear a combat room -> pet run level up.
    if pets and pets.bumpRunLevel then
        pets.bumpRunLevel(state, 1)
    end

    local cx = r.roomCenterX or state.player.x
    local cy = r.roomCenterY or state.player.y
    -- Ensure chest doesn't spawn in a wall (e.g., center pillar)
    if state.world and state.world.enabled and state.world.adjustToWalkable then
        -- Use a larger search radius (12 tiles approx 384px) to ensure we find a valid spot
        local ax, ay = state.world:adjustToWalkable(cx, cy, 12)
        if ax and ay then
            cx, cy = ax, ay
        elseif state.world.sampleValidFloor then
            -- Absolute fallback: Find ANY valid floor tile
            cx, cy = state.world:sampleValidFloor(50)
        end
    end

    local rewardType = r.roomRewardType
    if rewardType == nil then
        local cycle = r.rewardCycle
        if type(cycle) == 'table' and #cycle > 0 then
            rewardType = cycle[((r.roomIndex or 1) - 1) % #cycle + 1]
        end
    end
    local chest = {
        x = cx,
        y = cy,
        w = 20,
        h = 20,
        kind = 'room_reward',
        room = r.roomIndex,
        rewardType = rewardType,
        roomKind = r.roomKind,
        bonusLevelUps = nil
    }
    if r.roomKind == 'elite' then
        local bonus = tonumber(r.eliteRoomBonusUpgrades) or 0
        bonus = math.max(0, math.floor(bonus))
        if bonus > 0 then
            chest.bonusLevelUps = bonus
        end
    end
    table.insert(state.chests, chest)
    r.rewardChest = chest

    -- Extra pet progression (low frequency): elite rooms may drop a pet chip.
    if r.roomKind == 'elite' and state.floorPickups then
        local pet = pets and pets.getActive and pets.getActive(state) or nil
        if pet and not pet.downed then
            local kind = 'pet_upgrade_chip'
            if (pet.module or 'default') == 'default' and math.random() < 0.65 then
                kind = 'pet_module_chip'
            end
            table.insert(state.floorPickups, {x = cx + 60, y = cy + 10, size = 14, kind = kind})
        end
    end

    local rewardLabel = ''
    if rewardType then rewardLabel = ' (' .. string.upper(tostring(rewardType)) .. ')' end
    local clearLabel = (r.roomKind == 'elite') and 'ELITE CLEAR!' or 'ROOM CLEAR!'
    table.insert(state.texts, {
        x = cx,
        y = cy - 100,
        text = clearLabel .. rewardLabel,
        color = {0.8, 1, 0.8},
        life = 1.8
    })
end

local function spawnDoors(state, r)
    state.doors = state.doors or {}
    clearList(state.doors)

    local cycle = r.rewardCycle
    if type(cycle) ~= 'table' or #cycle <= 0 then
        cycle = {'weapon', 'passive', 'augment'}
    end
    local leftType, rightType = pickTwoDistinct(cycle)

    local leftKind, rightKind = 'normal', 'normal'
    local nextRoomIndex = (r.roomIndex or 0) + 1
    if nextRoomIndex >= 3 and nextRoomIndex < (r.bossRoom or 8) then
        if math.random() < 0.5 then leftKind = 'elite' else rightKind = 'elite' end
    end

    -- Special rooms: event/shop can appear (pet swap / pet revival).
    local specialKind = nil
    local chance = 0
    if pets and pets.hasLost and pets.hasLost(state) then
        specialKind = 'event'
        chance = 1.0
    else
        specialKind = (math.random() < 0.5) and 'shop' or 'event'
        chance = 0.22
    end
    if specialKind and math.random() < chance then
        if math.random() < 0.5 then leftKind = specialKind else rightKind = specialKind end
    end

    -- Calculate door positions near the bottom of the arena, in walkable areas
    local w, h = 54, 86
    local size = 70
    local world = state.world
    
    local leftX, leftY, rightX, rightY
    
    if world and world.enabled and world.pixelW then
        -- Place doors at bottom-left and bottom-right of walkable area
        local ts = world.tileSize or 32
        local arenaW = world.pixelW
        local arenaH = world.pixelH
        
        -- Target positions: near the bottom, 1/3 and 2/3 across horizontally
        leftX = arenaW * 0.3
        rightX = arenaW * 0.7
        leftY = arenaH * 0.75
        rightY = arenaH * 0.75
        
        -- Adjust to walkable positions
        if world.adjustToWalkable then
            leftX, leftY = world:adjustToWalkable(leftX, leftY, 10)
            rightX, rightY = world:adjustToWalkable(rightX, rightY, 10)
        end
    else
        -- Fallback: use player position with offset
        local cx = r.roomCenterX or state.player.x
        local cy = r.roomCenterY or state.player.y
        local offset = 150
        leftX, leftY = cx - offset, cy + 80
        rightX, rightY = cx + offset, cy + 80
    end
    
    table.insert(state.doors, {x = leftX, y = leftY, w = w, h = h, size = size, kind = 'door', rewardType = leftType, roomKind = leftKind})
    table.insert(state.doors, {x = rightX, y = rightY, w = w, h = h, size = size, kind = 'door', rewardType = rightType, roomKind = rightKind})

    table.insert(state.texts, {
        x = state.player.x,
        y = state.player.y - 120,
        text = "CHOOSE NEXT ROOM",
        color = {0.9, 0.9, 1},
        life = 1.4
    })
end

spawnSpecialRoomPickup = function(state, r)
    clearList(state.enemyBullets)

    local cx = r.roomCenterX or state.player.x
    local cy = r.roomCenterY or state.player.y

    state.floorPickups = state.floorPickups or {}
    local kind = 'pet_contract'
    if r.roomKind == 'shop' then
        kind = 'shop_terminal'
    elseif r.roomKind == 'event' and pets and pets.hasLost and pets.hasLost(state) then
        kind = 'pet_revive'
    end
    local pickup = {
        x = cx,
        y = cy,
        size = 18,
        kind = kind,
        roomKind = r.roomKind
    }
    table.insert(state.floorPickups, pickup)
    r.specialPickup = pickup

    local label = (r.roomKind == 'shop') and "SHOP" or "EVENT"
    table.insert(state.texts, {x = cx, y = cy - 110, text = label, color = {0.9, 0.9, 1}, life = 1.8})
end

local function startBossRoom(state, r)
    r.phase = 'boss'
    r.waveIndex = 1
    r.wavesTotal = 1
    r.timer = 0
    r.rewardChest = nil
    r.roomRewardType = nil
    r.nextRewardType = nil
    r.roomKind = 'boss'
    r.nextRoomKind = nil
    state.doors = state.doors or {}
    clearList(state.doors)
    r._hadCombat = false

    clearList(state.enemyBullets)

    -- QoL: refresh dash charges for the boss opener.
    do
        local p = state.player
        local dash = p and p.dash
        if dash then
            local maxCharges = (p.stats and p.stats.dashCharges) or dash.maxCharges or 0
            maxCharges = math.max(0, math.floor(maxCharges))
            dash.charges = maxCharges
            dash.rechargeTimer = 0
        end
    end

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
        -- Mission-specific updates
        if r.missionType == 'defense' and r.defenseObjective then
            local obj = r.defenseObjective
            -- Enemies near objective deal damage to it
            for _, e in ipairs(state.enemies or {}) do
                if e.health and e.health > 0 then
                    local dx = e.x - obj.x
                    local dy = e.y - obj.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist < obj.size + (e.size or 16) then
                        -- Enemy touching objective damages it
                        local dmg = (e.damage or 5) * dt
                        obj.hp = obj.hp - dmg
                    end
                end
            end
            -- Check fail condition
            if obj.hp <= 0 then
                state.gameState = 'GAME_OVER'
                table.insert(state.texts, {x=obj.x, y=obj.y-30, text="目标被摧毁!", color={1, 0.2, 0.2}, life=3})
                return
            end
        elseif r.missionType == 'survival' and r.lifeSupport then
            -- Life support decay
            r.lifeSupport = r.lifeSupport - (2 * dt)  -- 2% per second
            r.survivalTimer = (r.survivalTimer or 0) + dt
            
            -- Spawn life support capsule periodically
            r.lifeSupportCapsuleTimer = (r.lifeSupportCapsuleTimer or 0) - dt
            if r.lifeSupportCapsuleTimer <= 0 then
                r.lifeSupportCapsuleTimer = 20  -- every 20 seconds
                -- Spawn capsule pickup near player
                local px, py = state.player.x, state.player.y
                local ang = math.random() * 6.28
                local dist = 100 + math.random() * 100
                local cx = px + math.cos(ang) * dist
                local cy = py + math.sin(ang) * dist
                if state.world and state.world.adjustToWalkable then
                    cx, cy = state.world:adjustToWalkable(cx, cy, 5)
                end
                state.floorPickups = state.floorPickups or {}
                table.insert(state.floorPickups, {x=cx, y=cy, size=16, kind='life_support'})
                table.insert(state.texts, {x=cx, y=cy-20, text="生命支援!", color={0.4, 0.8, 1}, life=1.5})
            end
            
            -- Check fail condition
            if r.lifeSupport <= 0 then
                state.gameState = 'GAME_OVER'
                table.insert(state.texts, {x=state.player.x, y=state.player.y-50, text="生命支援耗尽!", color={1, 0.2, 0.2}, life=3})
                return
            end
            
            -- Check win condition
            if r.survivalTimer >= r.survivalTarget then
                r.phase = 'reward'
                r.lifeSupport = nil
                spawnRewardChest(state, r)
                return
            end
        end
        
        -- Standard exterminate check
        local alive = countAliveEnemies(state)
        if alive > 0 then return end
        if r._hadCombat then
            if (r.waveIndex or 1) < (r.wavesTotal or 1) then
                clearList(state.enemyBullets)
                r.waveIndex = (r.waveIndex or 1) + 1
                r.timer = 0.65
                r.phase = 'between_waves'
            else
                -- For defense/survival, clearing waves still triggers reward
                r.defenseObjective = nil
                r.lifeSupport = nil
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

        -- if the next room is the boss room, skip branching and move on.
        local nextRoom = (r.roomIndex or 0) + 1
        if nextRoom >= (r.bossRoom or 8) then
            r.timer = 0.25
            r.phase = 'between_rooms'
            return
        end

        r.phase = 'doors'
        spawnDoors(state, r)
        return
    end

    if r.phase == 'special' then
        clearList(state.enemyBullets)
        if r.specialPickup and containsRef(state.floorPickups, r.specialPickup) then
            return
        end
        r.specialPickup = nil

        local nextRoom = (r.roomIndex or 0) + 1
        if nextRoom >= (r.bossRoom or 8) then
            r.timer = 0.25
            r.phase = 'between_rooms'
            return
        end

        r.phase = 'doors'
        spawnDoors(state, r)
        return
    end

    if r.phase == 'doors' then
        clearList(state.enemyBullets)

        local p = state.player or {}
        for _, d in ipairs(state.doors or {}) do
            if d and util.checkCollision(p, d) then
                local rewardType = d.rewardType
                r.nextRewardType = rewardType
                r.nextRoomKind = d.roomKind or 'normal'
                clearList(state.doors)

                local suffix = rewardType and (" (" .. string.upper(tostring(rewardType)) .. ")") or ""
                local kindLabel = (r.nextRoomKind == 'elite') and " ELITE" or ""
                if r.nextRoomKind == 'shop' then kindLabel = " SHOP" end
                if r.nextRoomKind == 'event' then kindLabel = " EVENT" end
                table.insert(state.texts, {
                    x = p.x,
                    y = p.y - 110,
                    text = "NEXT ROOM" .. kindLabel .. suffix,
                    color = {0.85, 0.95, 1},
                    life = 1.2
                })

                r.timer = 0.25
                r.phase = 'between_rooms'
                return
            end
        end
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
