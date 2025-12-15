local logger = require('logger')

local player = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function getMoveInput()
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') then dy = -1 end
    if love.keyboard.isDown('s') then dy = 1 end
    if love.keyboard.isDown('a') then dx = -1 end
    if love.keyboard.isDown('d') then dx = 1 end
    return dx, dy
end

local function ensureDashState(p)
    if not p then return nil end
    p.dash = p.dash or {}

    local stats = p.stats or {}
    local maxCharges = math.max(0, math.floor(stats.dashCharges or 0))
    local prevMax = p.dash.maxCharges
    p.dash.maxCharges = maxCharges

    if p.dash.charges == nil then
        p.dash.charges = maxCharges
    else
        if prevMax and maxCharges > prevMax then
            p.dash.charges = math.min(maxCharges, (p.dash.charges or 0) + (maxCharges - prevMax))
        else
            p.dash.charges = math.min(maxCharges, (p.dash.charges or 0))
        end
    end

    p.dash.rechargeTimer = p.dash.rechargeTimer or 0
    p.dash.timer = p.dash.timer or 0
    p.dash.dx = p.dash.dx or (p.facing or 1)
    p.dash.dy = p.dash.dy or 0

    return p.dash
end

local function tickDashRecharge(p, dt)
    local dash = ensureDashState(p)
    if not dash then return end
    local maxCharges = dash.maxCharges or 0
    if maxCharges <= 0 then return end
    dash.charges = dash.charges or 0

    if dash.charges >= maxCharges then
        dash.rechargeTimer = 0
        return
    end

    local cd = (p.stats and p.stats.dashCooldown) or 0
    if cd <= 0 then
        dash.charges = maxCharges
        dash.rechargeTimer = 0
        return
    end

    dash.rechargeTimer = (dash.rechargeTimer or 0) + dt
    while dash.rechargeTimer >= cd and dash.charges < maxCharges do
        dash.rechargeTimer = dash.rechargeTimer - cd
        dash.charges = dash.charges + 1
    end
end

function player.tryDash(state, dirX, dirY)
    if not state or not state.player then return false end
    local p = state.player

    local dash = ensureDashState(p)
    if not dash or (dash.maxCharges or 0) <= 0 then return false end
    if (dash.timer or 0) > 0 then return false end
    if (dash.charges or 0) <= 0 then return false end

    local dx, dy = dirX, dirY
    if dx == nil or dy == nil then
        dx, dy = getMoveInput()
    end
    if dx == 0 and dy == 0 then
        dx, dy = (p.facing or 1), 0
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return false end
    dx, dy = dx / len, dy / len

    local stats = p.stats or {}
    local duration = stats.dashDuration or 0
    local distance = stats.dashDistance or 0
    local inv = stats.dashInvincible
    if inv == nil then inv = duration end

    local ctx = {
        player = p,
        dirX = dx,
        dirY = dy,
        duration = duration,
        distance = distance,
        invincibleTimer = inv
    }
    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'preDash', ctx)
        if ctx.cancel then return false end
    end

    dx, dy = ctx.dirX or dx, ctx.dirY or dy
    local len2 = math.sqrt(dx * dx + dy * dy)
    if len2 <= 0 then
        dx, dy = (p.facing or 1), 0
    else
        dx, dy = dx / len2, dy / len2
    end

    duration = ctx.duration or duration
    distance = ctx.distance or distance
    inv = ctx.invincibleTimer
    if inv == nil then inv = duration end

    if duration <= 0 or distance <= 0 then return false end

    dash.charges = math.max(0, (dash.charges or 0) - 1)
    dash.duration = duration
    dash.distance = distance
    dash.speed = distance / duration
    dash.timer = duration
    dash.dx = dx
    dash.dy = dy
    dash.trailX = p.x
    dash.trailY = p.y
    if state.spawnDashAfterimage then
        local face = p.facing or 1
        if dx > 0 then face = 1 elseif dx < 0 then face = -1 end
        state.spawnDashAfterimage(p.x, p.y, face, {alpha = 0.26, duration = 0.20, dirX = dx, dirY = dy})
    end

    if inv and inv > 0 then
        p.invincibleTimer = math.max(p.invincibleTimer or 0, inv)
    end
    if state.spawnEffect then
        state.spawnEffect('shock', p.x, p.y, 0.9)
    end

    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onDash', ctx)
    end

    return true
end

function player.keypressed(state, key)
    if not state or state.gameState ~= 'PLAYING' then return false end
    if key == 'space' then
        return player.tryDash(state)
    end
    return false
end

function player.updateMovement(state, dt)
    local p = state.player
    local ox, oy = p.x, p.y

    local dash = ensureDashState(p)
    tickDashRecharge(p, dt)

    local dx, dy = getMoveInput()
    local moving = dx ~= 0 or dy ~= 0
    local world = state.world

    if dash and (dash.timer or 0) > 0 then
        local speed = dash.speed
        if speed == nil then
            local stats = p.stats or {}
            local duration = stats.dashDuration or 0
            local distance = stats.dashDistance or 0
            speed = (duration > 0) and (distance / duration) or 0
        end

        local mx = (dash.dx or 0) * speed * dt
        local my = (dash.dy or 0) * speed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x = p.x + mx
            p.y = p.y + my
        end
        dash.timer = dash.timer - dt
        if dash.timer < 0 then dash.timer = 0 end
        moving = true
        dx, dy = dash.dx or 0, dash.dy or 0

        if state.spawnDashAfterimage then
            local spacing = 24
            dash.trailX = dash.trailX or ox
            dash.trailY = dash.trailY or oy
            local tx, ty = dash.trailX, dash.trailY
            local dirX, dirY = dash.dx or 0, dash.dy or 0
            local face = p.facing or 1
            if dirX > 0 then face = 1 elseif dirX < 0 then face = -1 end
            local ddx = p.x - tx
            local ddy = p.y - ty
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            local guard = 0
            while dist >= spacing and guard < 32 do
                tx = tx + dirX * spacing
                ty = ty + dirY * spacing
                state.spawnDashAfterimage(tx, ty, face, {alpha = 0.20, duration = 0.20, dirX = dirX, dirY = dirY})
                ddx = p.x - tx
                ddy = p.y - ty
                dist = math.sqrt(ddx * ddx + ddy * ddy)
                guard = guard + 1
            end
            dash.trailX, dash.trailY = tx, ty
        end

        if dash.timer <= 0 and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'postDash', {player = p})
        end
    elseif moving then
        local len = math.sqrt(dx * dx + dy * dy)
        local mx = (dx / len) * p.stats.moveSpeed * dt
        local my = (dy / len) * p.stats.moveSpeed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x = p.x + mx
            p.y = p.y + my
        end
    end

    if dash and (dash.timer or 0) <= 0 then
        dash.trailX = nil
        dash.trailY = nil
    end

    if dx > 0 then p.facing = 1
    elseif dx < 0 then p.facing = -1 end
    p.isMoving = moving
    local mdx, mdy = p.x - ox, p.y - oy
    p.movedDist = math.sqrt(mdx * mdx + mdy * mdy)

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local camX = p.x - sw / 2
    local camY = p.y - sh / 2
    if world and world.enabled and world.pixelW and world.pixelH then
        local maxCamX = math.max(0, world.pixelW - sw)
        local maxCamY = math.max(0, world.pixelH - sh)
        camX = clamp(camX, 0, maxCamX)
        camY = clamp(camY, 0, maxCamY)
    end
    state.camera.x = camX
    state.camera.y = camY
end

function player.hurt(state, dmg)
    local p = state.player
    if state.benchmarkMode then return end -- invincible during benchmark/debug runs
    if p.invincibleTimer > 0 then return end
    local armor = (p.stats and p.stats.armor) or 0
    local hpBefore = p.hp
    local applied = math.max(1, math.floor((dmg or 0) - armor))
    local ctx = {
        amount = applied,
        dmg = dmg or 0,
        armor = armor,
        hpBefore = hpBefore,
        hpAfter = hpBefore,
        player = p,
        isMoving = p.isMoving or false,
        movedDist = p.movedDist or 0
    }
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'preHurt', ctx)
    end
    applied = math.max(0, math.floor(ctx.amount or applied))
    if ctx.cancel or applied <= 0 then
        local inv = ctx.invincibleTimer or 0
        if inv > 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, inv)
        end
        ctx.amount = 0
        ctx.hpAfter = p.hp
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'hurtCancelled', ctx)
        end
        return
    end
    if applied > 0 then
        p.hp = math.max(0, p.hp - applied)
        ctx.amount = applied
        ctx.hpAfter = p.hp
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onHurt', ctx)
            state.augments.dispatch(state, 'postHurt', ctx)
        end
    end
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
