local enemies = require('enemies')

local director = {}

local BOSS_TIME = 360 -- seconds, ~6 min run target
local BOSS_WARNING_TIME = 330
local BOSS_KEY = 'boss_treant'

function director.update(state, dt)
    state.directorState = state.directorState or {}

    -- timed elite events
    if not state.directorState.event60 and state.gameTimer >= 60 then
        enemies.spawnEnemy(state, 'skeleton', true)
        state.directorState.event60 = true
        table.insert(state.texts, {x=state.player.x, y=state.player.y-100, text="ELITE SKELETON!", color={1,0,0}, life=3})
    end
    if not state.directorState.event120 and state.gameTimer >= 120 then
        enemies.spawnEnemy(state, 'bat', true)
        state.directorState.event120 = true
        table.insert(state.texts, {x=state.player.x, y=state.player.y-100, text="ELITE BAT!", color={1,0,0}, life=3})
    end

    if state.testArena then
        if #state.enemies == 0 then
            local dummyKey = (state.debug and state.debug.selectedDummy) or 'dummy_pole'
            enemies.spawnEnemy(state, dummyKey, false, state.player.x + 140, state.player.y)
        end
        return
    end

    -- boss warning / spawn
    if not state.directorState.bossSpawned and not state.directorState.bossWarning and state.gameTimer >= BOSS_WARNING_TIME then
        state.directorState.bossWarning = true
        table.insert(state.texts, {x=state.player.x, y=state.player.y-100, text="BOSS INCOMING!", color={1,0.6,0.2}, life=4})
    end
    if not state.directorState.bossSpawned and state.gameTimer >= BOSS_TIME then
        enemies.spawnEnemy(state, BOSS_KEY, false)
        state.directorState.bossSpawned = true
        table.insert(state.texts, {x=state.player.x, y=state.player.y-100, text="BOSS!", color={1,0.2,0.2}, life=5})
        return
    end
    if state.directorState.bossSpawned then
        -- stop normal spawns during boss fight
        return
    end

    state.spawnTimer = state.spawnTimer - dt
    if state.spawnTimer <= 0 then
        local pool = {}
        local function add(key, weight)
            for _ = 1, weight do table.insert(pool, key) end
        end
        add('skeleton', 6)

        -- soft caps to prevent fast/ranged enemies snowballing
        local batAlive, plantAlive = 0, 0
        for _, e in ipairs(state.enemies) do
            if e.kind == 'bat' then batAlive = batAlive + 1 end
            if e.kind == 'plant' then plantAlive = plantAlive + 1 end
        end
        local batCap = 8 + math.floor((state.gameTimer or 0) / 60) * 2
        if state.gameTimer > 20 and batAlive < batCap then add('bat', 3) end
        local plantCap = 4 + math.floor((state.gameTimer or 0) / 90)
        if state.gameTimer >= 40 and plantAlive < plantCap then add('plant', 2) end
        if state.gameTimer >= 90 then add('shield_lancer', 3) end
        if state.gameTimer >= 150 then add('armored_brute', 2) end
        local type = pool[math.random(#pool)]
        local eliteCap = 1.0 + (state.player.level or 1) * 0.5 -- at most ~3 elites on screen early game
        local elitesAlive = 0
        for _, e in ipairs(state.enemies) do if e.isElite then elitesAlive = elitesAlive + 1 end end
        local isElite = false
        if elitesAlive < eliteCap then
            local baseProb = 0.01
            if state.gameTimer >= 80 then baseProb = 0.02 end
            if state.gameTimer >= 160 then baseProb = 0.03 end
            if state.gameTimer >= 240 then baseProb = 0.04 end
            isElite = math.random() < baseProb
        end
        local batch = 1
        if state.gameTimer >= 210 then
            batch = 4
        elseif state.gameTimer >= 150 then
            batch = 3
        elseif state.gameTimer >= 90 then
            batch = 2
        end
        for _ = 1, batch do
            enemies.spawnEnemy(state, type, isElite)
        end
        local timeFactor = (state.gameTimer or 0) / 240 -- ramp over ~6 min
        state.spawnTimer = math.max(0.16, 0.6 - (state.player.level or 1) * 0.005 - timeFactor * 0.08)
    end
end

return director
