-- Chapter Enemy Spawner
-- Pre-spawns enemies at map generation, uses activation range for AI state

local spawner = {}

local enemies = require('gameplay.enemies')

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    -- Activation range (pixels) - enemies start chasing when player is within this distance
    aggroRange = 500,
    
    -- Room spawn counts
    baseEnemiesPerRoom = {
        easy = 5,
        normal = 8,
        hard = 15,
        boss = 0,  -- Boss spawned separately
        safe = 0,
        optional = 6,
    },
    eliteChance = {
        easy = 0,
        normal = 0.1,
        hard = 0.25,
        boss = 0,
        safe = 0,
        optional = 0.15,
    },
}

--------------------------------------------------------------------------------
-- SPAWNER STATE
--------------------------------------------------------------------------------

local state = {
    populated = false,  -- Has the map been populated with enemies?
}

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

--------------------------------------------------------------------------------
-- ENEMY TYPE SELECTION
--------------------------------------------------------------------------------

local function chooseEnemyType(roomProgress)
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
-- PRE-SPAWN AT MAP GENERATION
--------------------------------------------------------------------------------

function spawner.populateMapOnGenerate(gameState, chapterMap)
    if not gameState or not chapterMap then return end
    if state.populated then return end
    
    gameState.enemies = gameState.enemies or {}
    
    for _, node in ipairs(chapterMap.nodes or {}) do
        -- Skip safe rooms and boss room (boss spawned separately)
        if node.difficulty == 'safe' or node.type == 'boss' or node.type == 'exit' or node.type == 'start' then
            goto continue
        end
        
        local targetCount = CONFIG.baseEnemiesPerRoom[node.difficulty] or 8
        local eliteChance = CONFIG.eliteChance[node.difficulty] or 0
        -- Use mainPathProgress for branches (their IDs start at 1000), otherwise use node.id
        local roomProgress = node.mainPathProgress or node.id or 1
        
        -- Get spawn points for this room
        local spawnPoints = chapterMap:getSpawnPointsForNode(node, targetCount + 5)
        
        local roomSpawned = 0
        for i = 1, targetCount do
            local spawnPt = spawnPoints[i]
            if not spawnPt then break end
            
            local kind = chooseEnemyType(roomProgress)
            local isElite = node.spawnElite and math.random() < eliteChance
            
            -- Spawn with aiState = 'idle' (won't chase until player is close)
            local enemy = enemies.spawnEnemy(gameState, kind, isElite, spawnPt.x, spawnPt.y, {suppressSpawnText = true})
            if enemy then
                enemy._roomId = node.id
                enemy.aiState = 'idle'
                enemy.aggroRange = CONFIG.aggroRange
                enemy.homeX = spawnPt.x
                enemy.homeY = spawnPt.y
                roomSpawned = roomSpawned + 1
            end
        end
        
        -- Mark room as having been populated if any enemies were spawned
        if roomSpawned > 0 then
            node.spawned = true
        end
        
        ::continue::
    end
    
    state.populated = true
end

--------------------------------------------------------------------------------
-- UPDATE (only handles special cases now)
--------------------------------------------------------------------------------

function spawner.update(gameState, chapterMap, dt)
    -- No dynamic spawning in chapter mode
    -- Enemies are pre-spawned at map generation
end

--------------------------------------------------------------------------------
-- ROOM CLEAR CHECK
--------------------------------------------------------------------------------

function spawner.checkRoomClear(gameState, chapterMap)
    if not chapterMap then return end
    
    for _, node in ipairs(chapterMap.nodes or {}) do
        -- Skip already cleared rooms
        if node.cleared then goto continue_clear end
        
        -- Skip non-combat rooms
        if node.difficulty == 'safe' then goto continue_clear end
        if node.type == 'start' or node.type == 'exit' or node.type == 'boss' or node.type == 'merchant' or node.type == 'forge' then
            goto continue_clear
        end
        
        -- Only check rooms that have been populated with enemies
        if not node.spawned then goto continue_clear end
        
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
        
        ::continue_clear::
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
        -- Check if boss was already spawned
        if bossNode.bossSpawned then
            -- Boss was spawned before, check if defeated
            local bossAlive = false
            for _, e in ipairs(gameState.enemies or {}) do
                if e and e.isBoss and (e.health or e.hp or 0) > 0 then
                    bossAlive = true
                    break
                end
            end
            
            if not bossAlive then
                -- Boss defeated! Mark room as cleared
                bossNode.cleared = true
                if gameState.texts then
                    table.insert(gameState.texts, {
                        x = bossNode.cx * 32, y = bossNode.cy * 32 - 60,
                        text = "BOSS DEFEATED!",
                        color = {1, 0.9, 0.3},
                        life = 3.0,
                        scale = 1.8
                    })
                end
            end
            return
        end
        
        -- Spawn boss for the first time
        local wx, wy = bossNode.cx * 32, bossNode.cy * 32
        bossNode.bossSpawned = true
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

--------------------------------------------------------------------------------
-- RESET
--------------------------------------------------------------------------------

function spawner.reset()
    state.populated = false
end

return spawner
