local player = {}

function player.updateMovement(state, dt)
    local p = state.player
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') then dy = -1 end
    if love.keyboard.isDown('s') then dy = 1 end
    if love.keyboard.isDown('a') then dx = -1 end
    if love.keyboard.isDown('d') then dx = 1 end
    if dx ~= 0 or dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        p.x = p.x + (dx / len) * p.stats.moveSpeed * dt
        p.y = p.y + (dy / len) * p.stats.moveSpeed * dt
    end

    state.camera.x = p.x - love.graphics.getWidth() / 2
    state.camera.y = p.y - love.graphics.getHeight() / 2
end

function player.hurt(state, dmg)
    local p = state.player
    if p.invincibleTimer > 0 then return end
    p.hp = math.max(0, p.hp - dmg)
    p.invincibleTimer = 0.5
    table.insert(state.texts, {x=p.x, y=p.y-30, text="-"..dmg, color={1,0,0}, life=1})
    if p.hp <= 0 then state.gameState = 'GAME_OVER' end
end

function player.tickInvincibility(state, dt)
    if state.player.invincibleTimer > 0 then
        state.player.invincibleTimer = state.player.invincibleTimer - dt
        if state.player.invincibleTimer < 0 then state.player.invincibleTimer = 0 end
    end
end

function player.tickTexts(state, dt)
    for i = #state.texts, 1, -1 do
        local t = state.texts[i]
        t.life = t.life - dt
        t.y = t.y - 30 * dt
        if t.life <= 0 then table.remove(state.texts, i) end
    end
end

return player
