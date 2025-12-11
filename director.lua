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

    state.spawnTimer = state.spawnTimer - dt
    if state.spawnTimer <= 0 then
        local type
        local plantChance = 0.0
        if state.gameTimer >= 180 then
            plantChance = 0.8
        elseif state.gameTimer >= 120 then
            plantChance = 0.65
        elseif state.gameTimer >= 60 then
            plantChance = 0.4
        end
        if math.random() < plantChance then
            type = 'plant'
        else
            type = (state.gameTimer > 30 and math.random() > 0.5) and 'bat' or 'skeleton'
        end
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
