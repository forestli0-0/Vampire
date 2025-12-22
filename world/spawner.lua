-- Stealth Enemy Spawner
-- Spawns enemies only outside player's view (no visible pop-in)

local spawner = {}

local enemies = require('gameplay.enemies')

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    -- View culling
    screenRadius = 450,     -- Approximate screen half-diagonal in pixels
    spawnBuffer = 100,      -- Extra buffer beyond screen edge
    
    -- Spawn timing
    spawnInterval = 2.0,    -- Seconds between spawn checks
    maxEnemiesPerRoom = 20, -- Cap per room
    globalEnemyCap = 50,    -- Total enemies on map
    
    -- Difficulty scaling
    baseEnemiesPerRoom = {
        easy = 5,
        normal = 8,
        hard = 15,
        boss = 1,
        safe = 0,
        optional = 6,
    },
    eliteChance = {
        easy = 0,
        normal = 0.1,
        hard = 0.25,
        boss = 0,
        optional = 0.15,
    },
}

--------------------------------------------------------------------------------
-- SPAWNER STATE
--------------------------------------------------------------------------------

local state = {
    timer = 0,
    activeRooms = {},  -- Rooms currently being processed
}

--------------------------------------------------------------------------------
-- VISIBILITY CHECK
--------------------------------------------------------------------------------

local function isOutOfView(px, py, sx, sy)
    local dx = sx - px
    local dy = sy - py
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist > (CONFIG.screenRadius + CONFIG.spawnBuffer)
end

--------------------------------------------------------------------------------
-- ROOM ENEMY MANAGEMENT
--------------------------------------------------------------------------------

local function countEnemiesInRoom(gameState, node)
    local count = 0
    for _, e in ipairs(gameState.enemies or {}) do
        if e and e._roomId == node.id and (e.health or e.hp or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

local function countTotalEnemies(gameState)
    local count = 0
    for _, e in ipairs(gameState.enemies or {}) do
        if e and (e.health or e.hp or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- SPAWN POINT SELECTION
--------------------------------------------------------------------------------

local function getValidSpawnPoint(gameState, chapterMap, node, px, py)
    -- Get spawn points in this room
    local points = chapterMap:getSpawnPointsForNode(node, 10)
    
    -- Filter to only out-of-view points
    local valid = {}
    for _, pt in ipairs(points) do
        if isOutOfView(px, py, pt.x, pt.y) then
            table.insert(valid, pt)
        end
    end
    
    if #valid == 0 then return nil end
    return valid[math.random(#valid)]
end

--------------------------------------------------------------------------------
-- ENEMY TYPE SELECTION
--------------------------------------------------------------------------------

local function chooseEnemyType(roomProgress)
    -- Simple pool based on progression
    local pool = {'skeleton', 'skeleton', 'skeleton'}
    
    if roomProgress >= 2 then
        table.insert(pool, 'bat')
        table.insert(pool, 'bat')
    end
    if roomProgress >= 3 then
        table.insert(pool, 'plant')
        table.insert(pool, 'charger')
    end
    if roomProgress >= 4 then
        table.insert(pool, 'lancer')
        table.insert(pool, 'shield_lancer')
    end
    if roomProgress >= 5 then
        table.insert(pool, 'heavy_gunner')
        table.insert(pool, 'scorpion')
    end
    if roomProgress >= 6 then
        table.insert(pool, 'armored_brute')
        table.insert(pool, 'nullifier')
    end
    
    return pool[math.random(#pool)]
end

--------------------------------------------------------------------------------
-- MAIN SPAWN LOGIC
--------------------------------------------------------------------------------

function spawner.update(gameState, chapterMap, dt)
    if not gameState or not chapterMap then return end
    if gameState.gameState ~= 'PLAYING' then return end
    
    state.timer = state.timer - dt
    if state.timer > 0 then return end
    state.timer = CONFIG.spawnInterval
    
    local p = gameState.player
    if not p then return end
    local px, py = p.x or 0, p.y or 0
    
    -- Check global cap
    if countTotalEnemies(gameState) >= CONFIG.globalEnemyCap then
        return
    end
    
    -- Find rooms near player that need enemies
    local nearbyNodes = chapterMap:getNodesInRange(px, py, 800)
    
    for _, node in ipairs(nearbyNodes) do
        -- Skip safe rooms
        if node.difficulty == 'safe' then goto continue end
        
        -- Skip cleared rooms (minimal respawn)
        if node.cleared and math.random() > 0.1 then goto continue end
        
        -- Check room cap
        local roomEnemies = countEnemiesInRoom(gameState, node)
        local targetCount = CONFIG.baseEnemiesPerRoom[node.difficulty] or 8
        
        if roomEnemies >= targetCount then goto continue end
        
        -- Try to spawn one enemy
        local spawnPt = getValidSpawnPoint(gameState, chapterMap, node, px, py)
        if not spawnPt then goto continue end
        
        -- Determine enemy type
        local roomProgress = node.id or 1
        local kind = chooseEnemyType(roomProgress)
        
        -- Elite chance
        local isElite = false
        local eliteChance = CONFIG.eliteChance[node.difficulty] or 0
        if node.spawnElite and math.random() < eliteChance then
            isElite = true
        end
        
        -- Spawn!
        local enemy = enemies.spawnEnemy(gameState, kind, isElite, spawnPt.x, spawnPt.y)
        if enemy then
            enemy._roomId = node.id  -- Tag for room tracking
        end
        
        ::continue::
    end
end

--------------------------------------------------------------------------------
-- ROOM CLEAR CHECK
--------------------------------------------------------------------------------

function spawner.checkRoomClear(gameState, chapterMap)
    if not chapterMap then return end
    
    for _, node in ipairs(chapterMap.nodes or {}) do
        if not node.cleared and node.difficulty ~= 'safe' then
            local count = countEnemiesInRoom(gameState, node)
            
            -- Check if player is in room and all enemies dead
            local playerNode = chapterMap:getNodeAtPosition(
                gameState.player.x, 
                gameState.player.y
            )
            
            if playerNode and playerNode.id == node.id and count == 0 then
                -- Room cleared!
                node.cleared = true
                
                -- Trigger reward/event
                if node.type == 'small_combat' or node.type == 'large_combat' then
                    spawner.onRoomCleared(gameState, node)
                end
            end
        end
    end
end

function spawner.onRoomCleared(gameState, node)
    -- Drop rewards
    local wx, wy = node.cx * 32, node.cy * 32  -- Convert to world coords
    
    if node.difficulty == 'hard' then
        -- Large room cleared - better rewards
        gameState.floorPickups = gameState.floorPickups or {}
        table.insert(gameState.floorPickups, {
            x = wx, y = wy, size = 14, kind = 'mod_card', bonusRareChance = 0.3
        })
        
        -- Healing
        table.insert(gameState.floorPickups, {
            x = wx + 20, y = wy, size = 12, kind = 'health_orb', amount = 30
        })
    end
    
    -- Play clear sound
    if gameState.playSfx then
        gameState.playSfx('level_up')  -- Or appropriate sound
    end
    
    -- Show text
    if gameState.texts then
        table.insert(gameState.texts, {
            x = wx, y = wy - 40, 
            text = "AREA CLEAR", 
            color = {0.3, 1, 0.5}, 
            life = 1.5
        })
    end
end

--------------------------------------------------------------------------------
-- BOSS ROOM
--------------------------------------------------------------------------------

function spawner.spawnBoss(gameState, chapterMap)
    local bossNode = nil
    for _, node in ipairs(chapterMap.nodes or {}) do
        if node.type == 'boss' then
            bossNode = node
            break
        end
    end
    
    if not bossNode or bossNode.cleared then return end
    
    -- Only spawn when player enters boss room
    local playerNode = chapterMap:getNodeAtPosition(
        gameState.player.x,
        gameState.player.y
    )
    
    if playerNode and playerNode.id == bossNode.id then
        local existingBoss = false
        for _, e in ipairs(gameState.enemies or {}) do
            if e and e.isBoss then
                existingBoss = true
                break
            end
        end
        
        if not existingBoss then
            local wx, wy = bossNode.cx * 32, bossNode.cy * 32
            -- Spawn boss (use existing boss spawning logic)
            enemies.spawnEnemy(gameState, 'boss_treant', false, wx, wy)
            
            if gameState.texts then
                table.insert(gameState.texts, {
                    x = wx, y = wy - 60,
                    text = "BOSS INCOMING",
                    color = {1, 0.3, 0.3},
                    life = 2.0,
                    scale = 1.5
                })
            end
        end
    end
end

--------------------------------------------------------------------------------
-- RESET
--------------------------------------------------------------------------------

function spawner.reset()
    state.timer = 0
    state.activeRooms = {}
end

return spawner
