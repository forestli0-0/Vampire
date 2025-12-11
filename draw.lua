local weapons = require('weapons')

local draw = {}

function draw.render(state)
    love.graphics.setFont(state.font)
    love.graphics.push()
    if state.shakeAmount and state.shakeAmount > 0 then
        love.graphics.translate(love.math.random() * state.shakeAmount, love.math.random() * state.shakeAmount)
    end
    love.graphics.translate(-state.camera.x, -state.camera.y)

    -- 背景平铺
    local bg = state.bgTile
    if bg then
        local tileW, tileH = bg.w, bg.h
        local offsetX = state.camera.x % tileW
        local offsetY = state.camera.y % tileH
        local startX = state.camera.x - offsetX - tileW
        local startY = state.camera.y - offsetY - tileH
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        for x = startX, state.camera.x + w + tileW, tileW do
            for y = startY, state.camera.y + h + tileH, tileH do
                love.graphics.draw(bg.image, x, y)
            end
        end
    end

    -- 大蒜圈
    if state.inventory.weapons.garlic then
        local gStats = weapons.calculateStats(state, 'garlic') or state.inventory.weapons.garlic.stats
        local r = (gStats.radius or 0) * (gStats.area or 1) * (state.player.stats.area or 1)
        local sprite = state.weaponSprites and state.weaponSprites['garlic']
        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local scale = (r * 2) / sw
            love.graphics.setColor(1, 1, 1, 0.25)
            love.graphics.draw(sprite, state.player.x, state.player.y, 0, scale, scale, sw / 2, sh / 2)
            love.graphics.setColor(0, 0, 0, 0.2) -- fade the center/icon
            love.graphics.circle('fill', state.player.x, state.player.y, r * 0.4)
        else
            love.graphics.setColor(1, 0.2, 0.2, 0.2)
            love.graphics.circle('fill', state.player.x, state.player.y, r)
        end
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
        if e.flashTimer and e.flashTimer > 0 then
            love.graphics.setColor(1,1,1)
        else
            local col = e.color
            if e.status then
                if e.status.frozen then
                    col = {0.6, 0.8, 1}
                elseif e.status.burnTimer and e.status.burnTimer > 0 then
                    local pulse = love.timer.getTime() % 0.2 < 0.1
                    if pulse then col = {1, 0.2, 0.2} else col = {1, 0.4, 0.4} end
                elseif e.status.oiled then
                    col = {0.3, 0.2, 0.1}
                end
            end
            love.graphics.setColor(col)
        end
        if e.anim then
            local sx = e.facing or 1
            e.anim:draw(e.x, e.y, 0, sx, 1)
        else
            love.graphics.rectangle('fill', e.x - e.size/2, e.y - e.size/2, e.size, e.size)
        end
        if e.status and e.status.static then
            love.graphics.setColor(1,1,0)
            love.graphics.setLineWidth(2)
            if e.anim then
                love.graphics.rectangle('line', e.x - e.size/2 - 2, e.y - e.size/2 - 2, e.size + 4, e.size + 4)
            else
                love.graphics.rectangle('line', e.x - e.size/2 - 2, e.y - e.size/2 - 2, e.size + 4, e.size + 4)
            end
            love.graphics.setLineWidth(1)
        end
    end

    if state.chainLinks then
        love.graphics.setColor(0.9, 0.95, 1, 0.9)
        love.graphics.setLineWidth(3)
        for _, link in ipairs(state.chainLinks) do
            love.graphics.line(link.x1, link.y1, link.x2, link.y2)
        end
        love.graphics.setLineWidth(1)
    end

    -- 冰环提示
    if state.inventory.weapons.ice_ring then
        local iStats = weapons.calculateStats(state, 'ice_ring') or state.inventory.weapons.ice_ring.stats
        local r = (iStats.radius or 0) * (iStats.area or 1) * (state.player.stats.area or 1)
        local sprite = state.weaponSprites and state.weaponSprites['ice_ring']
        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local scale = (r * 2) / sw
            love.graphics.setColor(0.7, 0.9, 1, 0.35)
            love.graphics.draw(sprite, state.player.x, state.player.y, 0, scale, scale, sw / 2, sh / 2)
        else
            love.graphics.setColor(0.7, 0.9, 1, 0.2)
            love.graphics.circle('line', state.player.x, state.player.y, r)
        end
    end

    local inv = state.player.invincibleTimer > 0
    local blink = inv and love.timer.getTime() % 0.2 < 0.1
    if state.playerAnim then
        if blink then love.graphics.setColor(1,1,1,0.35) else love.graphics.setColor(1,1,1) end
        state.playerAnim:draw(state.player.x, state.player.y, 0, state.player.facing, 1)
    else
        if blink then love.graphics.setColor(1,1,1) else love.graphics.setColor(0,1,0) end
        love.graphics.rectangle('fill', state.player.x - (state.player.size/2), state.player.y - (state.player.size/2), state.player.size, state.player.size)
    end
    love.graphics.setColor(1,1,1)

    -- 玩家投射物
    for _, b in ipairs(state.bullets) do
        local sprite = state.weaponSprites and state.weaponSprites[b.type]
        if sprite then
            love.graphics.setColor(1,1,1)
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local scale = ((b.size or sw) / sw) * ((state.weaponSpriteScale and state.weaponSpriteScale[b.type]) or 1)
            love.graphics.push()
            love.graphics.translate(b.x, b.y)
            if b.rotation then love.graphics.rotate(b.rotation) end
            love.graphics.draw(sprite, 0, 0, 0, scale, scale, sw/2, sh/2)
            love.graphics.pop()
        else
            if b.type == 'axe' then love.graphics.setColor(0,1,1) else love.graphics.setColor(1,1,0) end
            love.graphics.push()
            love.graphics.translate(b.x, b.y)
            if b.rotation then love.graphics.rotate(b.rotation) end
            love.graphics.rectangle('fill', -b.size/2, -b.size/2, b.size, b.size)
            love.graphics.pop()
        end
    end

    -- 敌方子弹
    for _, eb in ipairs(state.enemyBullets) do
        local sprite = state.enemySprites and state.enemySprites[eb.spriteKey or '']
        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local baseScale = (eb.size or sw) / sw
            if eb.spriteKey == 'plant_bullet' then baseScale = baseScale * 2 end
            local scale = baseScale
            love.graphics.setColor(1,1,1)
            love.graphics.draw(sprite, eb.x, eb.y, eb.rotation or 0, scale, scale, sw/2, sh/2)
        else
            love.graphics.setColor(1,0,0)
            love.graphics.push()
            love.graphics.translate(eb.x, eb.y)
            if eb.rotation then love.graphics.rotate(eb.rotation) end
            local size = eb.size or 10
            love.graphics.rectangle('fill', -size/2, -size/2, size, size)
            love.graphics.pop()
        end
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

    if state.gameState == 'GAME_OVER' then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setColor(0,0,0,0.75)
        love.graphics.rectangle('fill', 0, 0, w, h)
        love.graphics.setFont(state.titleFont)
        love.graphics.setColor(1,0.2,0.2)
        love.graphics.printf("GAME OVER", 0, h/2 - 60, w, "center")
        love.graphics.setFont(state.font)
        love.graphics.setColor(1,1,1)
        love.graphics.printf("Press R to restart", 0, h/2, w, "center")
    end

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
