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
        if state.gameTimer >= 120 and math.random() < 0.25 then
            type = 'plant'
        else
            type = (state.gameTimer > 30 and math.random() > 0.5) and 'bat' or 'skeleton'
        end
        local isElite = math.random() < 0.05
        enemies.spawnEnemy(state, type, isElite)
        state.spawnTimer = math.max(0.1, 0.5 - state.player.level * 0.01)
    end
end

return director
