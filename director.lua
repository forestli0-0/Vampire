local enemies = require('enemies')

local director = {}

function director.update(state, dt)
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

    state.spawnTimer = state.spawnTimer - dt
    if state.spawnTimer <= 0 then
        local pool = {}
        local function add(key, weight)
            for _ = 1, weight do table.insert(pool, key) end
        end
        add('skeleton', 5)
        if state.gameTimer > 30 then add('bat', 5) end
        if state.gameTimer >= 60 then add('plant', 3) end
        if state.gameTimer >= 150 then add('shield_lancer', 3) end
        if state.gameTimer >= 210 then add('armored_brute', 2) end
        local type = pool[math.random(#pool)]
        local eliteCap = 1.0 + (state.player.level or 1) * 0.5 -- at most ~3 elites on screen early game
        local elitesAlive = 0
        for _, e in ipairs(state.enemies) do if e.isElite then elitesAlive = elitesAlive + 1 end end
        local isElite = false
        if elitesAlive < eliteCap then
            local baseProb = 0.01
            if state.gameTimer >= 120 then baseProb = 0.02 end
            if state.gameTimer >= 240 then baseProb = 0.03 end
            isElite = math.random() < baseProb
        end
        local batch = 1
        if state.gameTimer >= 240 then
            batch = 4
        elseif state.gameTimer >= 180 then
            batch = 3
        elseif state.gameTimer >= 120 then
            batch = 2
        end
        for _ = 1, batch do
            enemies.spawnEnemy(state, type, isElite)
        end
        local timeFactor = (state.gameTimer or 0) / 240 -- slow shrink of interval over time
        state.spawnTimer = math.max(0.12, 0.5 - (state.player.level or 1) * 0.007 - timeFactor * 0.08)
    end
end

return director
