local draw = {}

function draw.render(state)
    love.graphics.setFont(state.font)
    love.graphics.push()
    love.graphics.translate(-state.camera.x, -state.camera.y)

    -- 背景网格
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.rectangle('fill', state.camera.x, state.camera.y, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(0.2, 0.2, 0.2)
    local gridSize = 100
    local startX = math.floor(state.camera.x / gridSize) * gridSize
    local startY = math.floor(state.camera.y / gridSize) * gridSize
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    for x = startX, state.camera.x + w, gridSize do
        love.graphics.line(x, state.camera.y, x, state.camera.y + h)
    end
    for y = startY, state.camera.y + h, gridSize do
        love.graphics.line(state.camera.x, y, state.camera.x + w, y)
    end

    -- 大蒜圈
    if state.inventory.weapons.garlic then
        local r = state.inventory.weapons.garlic.stats.radius * state.player.stats.area
        love.graphics.setColor(1, 0.2, 0.2, 0.2)
        love.graphics.circle('fill', state.player.x, state.player.y, r)
    end

    -- 实体
    love.graphics.setColor(1, 0.84, 0)
    for _, c in ipairs(state.chests) do
        love.graphics.rectangle('fill', c.x - c.w/2, c.y - c.h/2, c.w, c.h)
    end

    -- 地面道具
    for _, item in ipairs(state.floorPickups) do
        if item.kind == 'chicken' then
            love.graphics.setColor(1, 0.7, 0)
            love.graphics.rectangle('fill', item.x - 7, item.y - 7, 14, 14)
            love.graphics.setColor(1,1,1)
            love.graphics.print("H", item.x - 4, item.y - 6)
        elseif item.kind == 'magnet' then
            love.graphics.setColor(0, 0.8, 1)
            love.graphics.rectangle('fill', item.x - 7, item.y - 7, 14, 14)
            love.graphics.setColor(1,1,1)
            love.graphics.print("M", item.x - 4, item.y - 6)
        elseif item.kind == 'bomb' then
            love.graphics.setColor(1, 0, 0)
            love.graphics.rectangle('fill', item.x - 7, item.y - 7, 14, 14)
            love.graphics.setColor(1,1,1)
            love.graphics.print("B", item.x - 4, item.y - 6)
        end
    end

    love.graphics.setColor(0,0.5,1)
    for _, g in ipairs(state.gems) do
        love.graphics.rectangle('fill', g.x-3, g.y-3, 6, 6)
    end

    for _, e in ipairs(state.enemies) do
        love.graphics.setColor(e.color)
        love.graphics.rectangle('fill', e.x - e.size/2, e.y - e.size/2, e.size, e.size)
    end

    love.graphics.setColor(1,1,1)
    if state.playerAnim then
        state.playerAnim:draw(state.player.x, state.player.y)
    else
        love.graphics.setColor(0,1,0)
        if state.player.invincibleTimer > 0 and love.timer.getTime() % 0.2 < 0.1 then love.graphics.setColor(1,1,1) end
        love.graphics.rectangle('fill', state.player.x - (state.player.size/2), state.player.y - (state.player.size/2), state.player.size, state.player.size)
    end

    -- 玩家投射物
    for _, b in ipairs(state.bullets) do
        if b.type == 'axe' then love.graphics.setColor(0,1,1) else love.graphics.setColor(1,1,0) end
        love.graphics.push()
        love.graphics.translate(b.x, b.y)
        if b.rotation then love.graphics.rotate(b.rotation) end
        love.graphics.rectangle('fill', -b.size/2, -b.size/2, b.size, b.size)
        love.graphics.pop()
    end

    -- 敌方子弹
    love.graphics.setColor(1,0,0)
    for _, eb in ipairs(state.enemyBullets) do
        love.graphics.rectangle('fill', eb.x - eb.size/2, eb.y - eb.size/2, eb.size, eb.size)
    end

    -- 飘字
    for _, t in ipairs(state.texts) do love.graphics.setColor(t.color); love.graphics.print(t.text, t.x, t.y) end
    love.graphics.pop()

    -- HUD
    love.graphics.setColor(0,0,1)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth() * (state.player.xp / state.player.xpToNextLevel), 10)
    local hpRatio = math.min(1, math.max(0, state.player.hp / state.player.maxHp))
    love.graphics.setColor(1,0,0)
    love.graphics.rectangle('fill', 10, 20, 150 * hpRatio, 15)
    love.graphics.setColor(1,1,1)
    love.graphics.print("LV "..state.player.level, 10, 40)

    local minutes = math.floor(state.gameTimer / 60)
    local seconds = math.floor(state.gameTimer % 60)
    local timeStr = string.format("%02d:%02d", minutes, seconds)
    love.graphics.printf(timeStr, 0, 20, love.graphics.getWidth(), "center")

    if state.gameState == 'LEVEL_UP' then
        love.graphics.setColor(0,0,0,0.9)
        love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setFont(state.titleFont)
        love.graphics.printf("LEVEL UP! Choose One:", 0, 100, love.graphics.getWidth(), "center")

        love.graphics.setFont(state.font)
        for i, opt in ipairs(state.upgradeOptions) do
            local y = 200 + (i-1) * 100
            love.graphics.setColor(0.3, 0.3, 0.3)
            love.graphics.rectangle('fill', 200, y, 400, 80)
            love.graphics.setColor(1,1,1)
            love.graphics.print(i .. ". " .. opt.name, 220, y+10)
            love.graphics.setColor(0.7,0.7,0.7)
            love.graphics.print(opt.desc, 220, y+35)

            local curLv = 0
            if opt.type == 'weapon' and state.inventory.weapons[opt.key] then curLv = state.inventory.weapons[opt.key].level end
            if opt.type == 'passive' and state.inventory.passives[opt.key] then curLv = state.inventory.passives[opt.key] end
            love.graphics.print("Current Lv: " .. curLv, 500, y+10)
        end
        love.graphics.setColor(1,1,1)
        love.graphics.printf("Press 1, 2, or 3 to select", 0, 550, love.graphics.getWidth(), "center")
    end
end

return draw
