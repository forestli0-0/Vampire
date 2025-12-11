local logger = require('logger')

local player = {}

function player.updateMovement(state, dt)
    local p = state.player
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') then dy = -1 end
    if love.keyboard.isDown('s') then dy = 1 end
    if love.keyboard.isDown('a') then dx = -1 end
    if love.keyboard.isDown('d') then dx = 1 end
    local moving = dx ~= 0 or dy ~= 0
    if moving then
        local len = math.sqrt(dx * dx + dy * dy)
        p.x = p.x + (dx / len) * p.stats.moveSpeed * dt
        p.y = p.y + (dy / len) * p.stats.moveSpeed * dt
    end

    if dx > 0 then p.facing = 1
    elseif dx < 0 then p.facing = -1 end
    p.isMoving = moving

    state.camera.x = p.x - love.graphics.getWidth() / 2
    state.camera.y = p.y - love.graphics.getHeight() / 2
end

function player.hurt(state, dmg)
    local p = state.player
    if p.invincibleTimer > 0 then return end
    local armor = (p.stats and p.stats.armor) or 0
    local applied = math.max(1, math.floor((dmg or 0) - armor))
    p.hp = math.max(0, p.hp - applied)
    logger.damageTaken(state, applied, p.hp)
    if p.hp <= 0 then
        p.invincibleTimer = 0
        state.shakeAmount = 0
        state.gameState = 'GAME_OVER'
        if state.stopMusic then state.stopMusic() end
        logger.gameOver(state, 'death')
    else
        p.invincibleTimer = 0.5
        state.shakeAmount = 5
    end
    if state.playSfx then state.playSfx('hit') end
    table.insert(state.texts, {x=p.x, y=p.y-30, text="-"..applied, color={1,0,0}, life=1})
end

function player.tickInvincibility(state, dt)
    if state.player.invincibleTimer > 0 then
        state.player.invincibleTimer = state.player.invincibleTimer - dt
        if state.player.invincibleTimer < 0 then state.player.invincibleTimer = 0 end
    end
end

function player.tickRegen(state, dt)
    local regen = state.player.stats.regen or 0
    if regen > 0 and state.player.hp < state.player.maxHp then
        state.player.hp = math.min(state.player.maxHp, state.player.hp + regen * dt)
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
