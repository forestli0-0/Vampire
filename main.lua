--v0.5
function love.load()
    math.randomseed(os.time())
    
    -- === 1. 基础配置 ===
    gameState = 'PLAYING'
    pendingLevelUps = 0
    gameTimer = 0
    font = love.graphics.newFont(14)
    titleFont = love.graphics.newFont(24)
    
    -- === 2. 玩家与全局属性 (Stats) ===
    player = { 
        x = 400, y = 300,
        size = 20,
        hp = 100, maxHp = 100,
        level = 1, xp = 0, xpToNextLevel = 10,
        invincibleTimer = 0,
        -- 核心属性 (被动道具会修改这些值)
        stats = {
            moveSpeed = 180,
            might = 1.0,     -- 伤害倍率
            cooldown = 1.0,  -- 冷却缩减 (越小越快)
            area = 1.0,      -- 范围倍率
            speed = 1.0,     -- 投射物速度倍率
            pickupRange = 80
        }
    }
    
    -- === 3. 物品目录 (Catalog) ===
    -- 这里定义了游戏里所有的 武器(Active) 和 被动(Passive)
    -- 这是一个数据表，方便扩展
    catalog = {
        -- 武器类
        wand = {
            type = 'weapon', name = "Magic Wand", 
            desc = "Fires at nearest enemy.",
            maxLevel = 5,
            base = { damage=10, cd=0.8, speed=400 },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='holy_wand', require='tome' }
        },
        holy_wand = {
            type = 'weapon', name = "Holy Wand",
            desc = "Evolved Magic Wand. Fires rapidly.",
            maxLevel = 1,
            base = { damage=15, cd=0.1, speed=600 },
            onUpgrade = function(w) end
        },
        garlic = {
            type = 'weapon', name = "Garlic", 
            desc = "Damages enemies nearby.",
            maxLevel = 5,
            base = { damage=3, cd=0.2, radius=70, knockback=30 },
            onUpgrade = function(w) w.damage = w.damage + 2; w.radius = w.radius + 10 end
        },
        axe = { -- 新武器：斧头
            type = 'weapon', name = "Axe",
            desc = "High damage, high arc.",
            maxLevel = 5,
            base = { damage=30, cd=1.2, speed=450, area=1.5 }, -- area决定斧头大小
            onUpgrade = function(w) w.damage = w.damage + 10; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='death_spiral', require='spinach' }
        },
        death_spiral = {
            type = 'weapon', name = "Death Spiral",
            desc = "Evolved Axe. Spirals out.",
            maxLevel = 1,
            base = { damage=40, cd=1.0, speed=500, area=2.0 },
            onUpgrade = function(w) end
        },
        -- 被动类
        spinach = {
            type = 'passive', name = "Spinach", 
            desc = "Increases damage by 10%.",
            maxLevel = 5,
            onUpgrade = function() player.stats.might = player.stats.might + 0.1 end
        },
        tome = {
            type = 'passive', name = "Empty Tome", 
            desc = "Reduces cooldowns by 8%.",
            maxLevel = 5,
            onUpgrade = function() player.stats.cooldown = player.stats.cooldown * 0.92 end
        },
        boots = {
            type = 'passive', name = "Boots", 
            desc = "Increases movement speed.",
            maxLevel = 5,
            onUpgrade = function() player.stats.moveSpeed = player.stats.moveSpeed * 1.1 end
        }
    }

    -- 玩家当前的库存
    inventory = {
        weapons = {}, -- 存具体实例
        passives = {} -- 存等级
    }
    
    -- 初始化：给玩家一把魔杖
    addWeapon('wand')

    -- === 4. 实体容器 ===
    enemies = {}; bullets = {}; gems = {}; texts = {}; chests = {}
    
    -- 升级选项缓存
    upgradeOptions = {} 
    
    spawnTimer = 0
    camera = { x = 0, y = 0 }
    
    -- 导演系统状态
    directorState = { event60 = false, event120 = false }
    player.size = 20 -- 确保玩家有尺寸定义
end

function love.update(dt)
    if gameState == 'LEVEL_UP' then return end -- 暂停
    if gameState == 'GAME_OVER' then
        if love.keyboard.isDown('r') then love.load() end
        return 
    end

    gameTimer = gameTimer + dt

    -- === 1. 玩家移动 (应用 moveSpeed 属性) ===
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') then dy = -1 end
    if love.keyboard.isDown('s') then dy = 1 end
    if love.keyboard.isDown('a') then dx = -1 end
    if love.keyboard.isDown('d') then dx = 1 end
    if dx~=0 or dy~=0 then
        local len = math.sqrt(dx*dx+dy*dy)
        player.x = player.x + (dx/len) * player.stats.moveSpeed * dt
        player.y = player.y + (dy/len) * player.stats.moveSpeed * dt
    end
    
    -- 摄像机跟随
    camera.x = player.x - love.graphics.getWidth()/2
    camera.y = player.y - love.graphics.getHeight()/2

    -- === 2. 武器逻辑 (应用 might, cooldown 属性) ===
    for key, w in pairs(inventory.weapons) do
        w.timer = w.timer - dt
        
        -- 计算实际冷却时间 (基础CD * 全局冷却缩减)
        local actualCD = w.stats.cd * player.stats.cooldown
        
        if w.timer <= 0 then
            -- 触发武器攻击
            if key == 'wand' then
                local t = findNearestEnemy()
                if t then 
                    spawnProjectile('wand', player.x, player.y, t)
                    w.timer = actualCD
                end
            elseif key == 'axe' then
                -- 斧头不需要目标，向上随机发射
                spawnProjectile('axe', player.x, player.y, nil)
                w.timer = actualCD
            elseif key == 'garlic' then
                -- 大蒜是光环，特殊处理
                local hit = false
                local actualDmg = math.floor(w.stats.damage * player.stats.might)
                local actualRadius = w.stats.radius * player.stats.area
                for _, e in ipairs(enemies) do
                    local d = math.sqrt((player.x-e.x)^2 + (player.y-e.y)^2)
                    if d < actualRadius then
                        damageEnemy(e, actualDmg, true, w.stats.knockback)
                        hit = true
                    end
                end
                if hit then w.timer = actualCD end
            end
        end
    end

    -- === 3. 投射物更新 (斧头重力 & 魔杖直线) ===
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        
        if b.type == 'wand' then
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
        elseif b.type == 'axe' then
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.vy = b.vy + 1000 * dt -- 重力加速度!
            b.rotation = b.rotation + 10 * dt -- 旋转效果
        end
        
        b.life = b.life - dt
        
        local hit = false
        if b.life <= 0 then 
            table.remove(bullets, i) 
        else
            -- 碰撞
            for j = #enemies, 1, -1 do
                local e = enemies[j]
                if checkCollision(b, e) then
                    if b.type == 'wand' then 
                        damageEnemy(e, b.damage, false, 0)
                        table.remove(bullets, i) -- 魔杖单体
                        hit = true
                        break 
                    elseif b.type == 'axe' then
                        -- 斧头穿透，一发只打一次同一目标
                        b.hitTargets = b.hitTargets or {}
                        if not b.hitTargets[e] then
                            b.hitTargets[e] = true
                            damageEnemy(e, b.damage, false, 0)
                        end
                    end 
                end
            end
            -- 斧头如果没碰到怪，飞出屏幕要销毁
            if not hit and b.y > player.y + 600 then table.remove(bullets, i) end
        end
    end

    -- === 4. 敌人生成与移动 ===
    -- 导演事件：固定时间生成精英怪
    if not directorState.event60 and gameTimer >= 60 then
        spawnEnemy('skeleton', true)
        directorState.event60 = true
        table.insert(texts, {x=player.x, y=player.y-100, text="ELITE SKELETON!", color={1,0,0}, life=3})
    end
    if not directorState.event120 and gameTimer >= 120 then
        spawnEnemy('bat', true)
        directorState.event120 = true
        table.insert(texts, {x=player.x, y=player.y-100, text="ELITE BAT!", color={1,0,0}, life=3})
    end

    spawnTimer = spawnTimer - dt
    if spawnTimer <= 0 then
        local type = (gameTimer > 30 and math.random() > 0.5) and 'bat' or 'skeleton'
        local isElite = math.random() < 0.05 -- 5% chance for elite
        spawnEnemy(type, isElite)
        spawnTimer = math.max(0.1, 0.5 - player.level * 0.01)
    end
    
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        local angle = math.atan2(player.y - e.y, player.x - e.x)
        e.x = e.x + math.cos(angle) * e.speed * dt
        e.y = e.y + math.sin(angle) * e.speed * dt
        
        -- 玩家受伤检测
        local pDist = math.sqrt((player.x-e.x)^2+(player.y-e.y)^2)
        local playerRadius = (player.size or 20) / 2
        local enemyRadius = (e.size or 16) / 2
        if pDist < (playerRadius + enemyRadius) and player.invincibleTimer <= 0 then
            player.hp = math.max(0, player.hp - 10)
            player.invincibleTimer = 0.5
            table.insert(texts, {x=player.x, y=player.y-30, text="-10", color={1,0,0}, life=1})
            if player.hp <= 0 then gameState = 'GAME_OVER' end
        end
        
        if e.hp <= 0 then
            if e.isElite then
                table.insert(chests, {x=e.x, y=e.y, w=20, h=20})
            else
                table.insert(gems, {x=e.x, y=e.y, value=1})
            end
            table.remove(enemies, i)
        end
    end

    -- 玩家无敌闪烁
    if player.invincibleTimer > 0 then
        player.invincibleTimer = player.invincibleTimer - dt
        if player.invincibleTimer < 0 then player.invincibleTimer = 0 end
    end

    -- === 5. 宝石与飘字 ===
    for i = #gems, 1, -1 do
        local g = gems[i]
        local dx = player.x - g.x
        local dy = player.y - g.y
        local distSq = dx * dx + dy * dy

        -- 吸附：先判断是否在拾取范围，再更新距离用于后续拾取判定
        if distSq < player.stats.pickupRange^2 then
            local a = math.atan2(dy, dx)
            g.x = g.x + math.cos(a) * 600 * dt
            g.y = g.y + math.sin(a) * 600 * dt
            dx = player.x - g.x
            dy = player.y - g.y
            distSq = dx * dx + dy * dy
        end

        -- 实际拾取判定：用更新后的距离且统一使用平方距离
        local pickupRadius = (player.size or 20) / 2
        if distSq < pickupRadius * pickupRadius then
            player.xp = player.xp + g.value
            table.remove(gems, i)
            while player.xp >= player.xpToNextLevel do
                player.level = player.level + 1
                player.xp = player.xp - player.xpToNextLevel
                player.xpToNextLevel = math.floor(player.xpToNextLevel * 1.5)
                pendingLevelUps = pendingLevelUps + 1
            end
            if gameState ~= 'LEVEL_UP' and pendingLevelUps > 0 then
                pendingLevelUps = pendingLevelUps - 1
                generateUpgradeOptions() -- 生成随机卡牌
                gameState = 'LEVEL_UP'
            end
        end
    end
    
    -- === 6. 宝箱碰撞 ===
    for i = #chests, 1, -1 do
        local c = chests[i]
        local dist = math.sqrt((player.x - c.x)^2 + (player.y - c.y)^2)
        if dist < 30 then
            print("Chest Collected")
            local evolvedWeapon = tryEvolveWeapon()
            if evolvedWeapon then
                table.insert(texts, {x=player.x, y=player.y-50, text="EVOLVED! " .. evolvedWeapon, color={1, 0.84, 0}, life=2})
            else
                player.xp = player.xp + 500
                table.insert(texts, {x=player.x, y=player.y-50, text="+500 XP", color={0, 1, 0}, life=1})
                if player.xp >= player.xpToNextLevel then
                    player.level = player.level + 1
                    player.xp = 0
                    player.xpToNextLevel = math.floor(player.xpToNextLevel * 1.5)
                    generateUpgradeOptions()
                    gameState = 'LEVEL_UP'
                end
            end
            table.remove(chests, i)
        end
    end

    for i=#texts,1,-1 do texts[i].life=texts[i].life-dt; texts[i].y=texts[i].y-30*dt; if texts[i].life<=0 then table.remove(texts, i) end end
end

function love.draw()
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)
    
    -- 背景网格
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.rectangle('fill', camera.x, camera.y, love.graphics.getWidth(), love.graphics.getHeight())
    
    love.graphics.setColor(0.2, 0.2, 0.2)
    local gridSize = 100
    local startX = math.floor(camera.x / gridSize) * gridSize
    local startY = math.floor(camera.y / gridSize) * gridSize
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    for x = startX, camera.x + w, gridSize do
        love.graphics.line(x, camera.y, x, camera.y + h)
    end
    for y = startY, camera.y + h, gridSize do
        love.graphics.line(camera.x, y, camera.x + w, y)
    end
    
    -- 大蒜圈
    if inventory.weapons.garlic then
        local r = inventory.weapons.garlic.stats.radius * player.stats.area
        love.graphics.setColor(1, 0.2, 0.2, 0.2)
        love.graphics.circle('fill', player.x, player.y, r)
    end
    
    -- 实体
    love.graphics.setColor(1, 0.84, 0) -- Gold for chests
    for _, c in ipairs(chests) do
        love.graphics.rectangle('fill', c.x - c.w/2, c.y - c.h/2, c.w, c.h)
    end
    
    love.graphics.setColor(0,0.5,1); for _,g in ipairs(gems) do love.graphics.rectangle('fill', g.x-3, g.y-3, 6, 6) end
    for _,e in ipairs(enemies) do love.graphics.setColor(e.color); love.graphics.rectangle('fill', e.x-e.size/2, e.y-e.size/2, e.size, e.size) end
    love.graphics.setColor(0,1,0); if player.invincibleTimer>0 and love.timer.getTime()%0.2<0.1 then love.graphics.setColor(1,1,1) end
    love.graphics.rectangle('fill', player.x-(player.size/2), player.y-(player.size/2), player.size, player.size)
    
    -- 投射物
    for _,b in ipairs(bullets) do
        if b.type == 'axe' then love.graphics.setColor(0,1,1) else love.graphics.setColor(1,1,0) end
        love.graphics.push()
        love.graphics.translate(b.x, b.y)
        if b.rotation then love.graphics.rotate(b.rotation) end
        love.graphics.rectangle('fill', -b.size/2, -b.size/2, b.size, b.size)
        love.graphics.pop()
    end
    
    -- 飘字
    for _,t in ipairs(texts) do love.graphics.setColor(t.color); love.graphics.print(t.text, t.x, t.y) end
    love.graphics.pop()

    -- HUD
    love.graphics.setColor(0,0,1); love.graphics.rectangle('fill',0,0,love.graphics.getWidth()*(player.xp/player.xpToNextLevel),10)
    local hpRatio = math.min(1, math.max(0, player.hp / player.maxHp))
    love.graphics.setColor(1,0,0); love.graphics.rectangle('fill',10,20,150*hpRatio,15)
    love.graphics.setColor(1,1,1); love.graphics.print("LV "..player.level, 10, 40)

    -- 游戏时间
    local minutes = math.floor(gameTimer / 60)
    local seconds = math.floor(gameTimer % 60)
    local timeStr = string.format("%02d:%02d", minutes, seconds)
    love.graphics.printf(timeStr, 0, 20, love.graphics.getWidth(), "center")
    
    -- 升级菜单 (RNG核心)
    if gameState == 'LEVEL_UP' then
        love.graphics.setColor(0,0,0,0.9)
        love.graphics.rectangle('fill',0,0,love.graphics.getWidth(),love.graphics.getHeight())
        love.graphics.setFont(titleFont)
        love.graphics.printf("LEVEL UP! Choose One:", 0, 100, love.graphics.getWidth(), "center")
        
        love.graphics.setFont(font)
        for i, opt in ipairs(upgradeOptions) do
            local y = 200 + (i-1)*100
            -- 简单的选中高亮框
            love.graphics.setColor(0.3, 0.3, 0.3)
            love.graphics.rectangle('fill', 200, y, 400, 80)
            love.graphics.setColor(1,1,1)
            love.graphics.print(i..". "..opt.name, 220, y+10)
            love.graphics.setColor(0.7,0.7,0.7)
            love.graphics.print(opt.desc, 220, y+35)
            
            -- 显示当前等级
            local curLv = 0
            if opt.type == 'weapon' and inventory.weapons[opt.key] then curLv = inventory.weapons[opt.key].level end
            if opt.type == 'passive' and inventory.passives[opt.key] then curLv = inventory.passives[opt.key] end
            love.graphics.print("Current Lv: " .. curLv, 500, y+10)
        end
        love.graphics.setColor(1,1,1)
        love.graphics.printf("Press 1, 2, or 3 to select", 0, 550, love.graphics.getWidth(), "center")
    end
end

function love.keypressed(key)
    if gameState == 'LEVEL_UP' then
        local idx = tonumber(key)
        if idx and idx >= 1 and idx <= #upgradeOptions then
            applyUpgrade(upgradeOptions[idx])
            if pendingLevelUps > 0 then
                pendingLevelUps = pendingLevelUps - 1
                generateUpgradeOptions()
                gameState = 'LEVEL_UP'
            else
                gameState = 'PLAYING'
            end
        end
    end
end

-- === 系统核心逻辑 ===

function tryEvolveWeapon()
    for key, w in pairs(inventory.weapons) do
        local def = catalog[key]
        if def.evolveInfo and w.level >= def.maxLevel then
            local req = def.evolveInfo.require
            if inventory.passives[req] then
                -- 满足进化条件
                local targetKey = def.evolveInfo.target
                local targetDef = catalog[targetKey]
                
                -- 移除旧武器
                inventory.weapons[key] = nil
                -- 添加新武器
                addWeapon(targetKey)
                
                return targetDef.name
            end
        end
    end
    return nil
end

function generateUpgradeOptions()
    -- 1. 找出所有合法的升级项（未满级的）
    local pool = {}
    for key, item in pairs(catalog) do
        local currentLevel = 0
        if item.type == 'weapon' and inventory.weapons[key] then currentLevel = inventory.weapons[key].level end
        if item.type == 'passive' and inventory.passives[key] then currentLevel = inventory.passives[key] end
        
        if currentLevel < item.maxLevel then
            table.insert(pool, {key=key, item=item})
        end
    end
    
    -- 2. 随机抽3个
    upgradeOptions = {}
    for i=1, 3 do
        if #pool == 0 then break end
        local rndIdx = math.random(#pool)
        local choice = pool[rndIdx]
        
        -- 构造选项数据
        table.insert(upgradeOptions, {
            key = choice.key,
            type = choice.item.type,
            name = choice.item.name,
            desc = choice.item.desc,
            def = choice.item
        })
        -- 移除已选的，防止重复出现
        table.remove(pool, rndIdx)
    end
end

function applyUpgrade(opt)
    if opt.type == 'weapon' then
        if not inventory.weapons[opt.key] then
            addWeapon(opt.key) -- 新获得武器
        else
            -- 升级武器
            local w = inventory.weapons[opt.key]
            w.level = w.level + 1
            opt.def.onUpgrade(w.stats) -- 调用升级回调
        end
    elseif opt.type == 'passive' then
        if not inventory.passives[opt.key] then inventory.passives[opt.key] = 0 end
        inventory.passives[opt.key] = inventory.passives[opt.key] + 1
        opt.def.onUpgrade() -- 调用被动回调 (修改全局player.stats)
    end
end

function addWeapon(key)
    local proto = catalog[key]
    -- 深拷贝 stats，否则所有同类武器会共享属性
    local stats = {damage=proto.base.damage, cd=proto.base.cd, speed=proto.base.speed, radius=proto.base.radius, knockback=proto.base.knockback}
    inventory.weapons[key] = {
        level = 1,
        timer = 0,
        stats = stats
    }
end

function spawnProjectile(type, x, y, target)
    local wStats = inventory.weapons[type].stats
    -- 应用玩家全局伤害加成
    local finalDmg = math.floor(wStats.damage * player.stats.might)
    
    if type == 'wand' then
        local angle = math.atan2(target.y-y, target.x-x)
        local spd = wStats.speed * player.stats.speed
        table.insert(bullets, {type='wand', x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd, life=2, size=6, damage=finalDmg})
    elseif type == 'axe' then
        -- 斧头向随机上方抛射
        local spd = wStats.speed * player.stats.speed
        local vx = (math.random()-0.5) * 200 -- 水平随机散布
        local vy = -spd -- 初始向上速度
        table.insert(bullets, {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=12, damage=finalDmg, rotation=0, hitTargets={}})
    end
end

function spawnEnemy(type, isElite)
    local types = {
        skeleton = {hp=10, spd=50, col={0.8,0.8,0.8}, sz=16},
        bat = {hp=5, spd=150, col={0.6,0,1}, sz=12}
    }
    local t = types[type]
    local ang = math.random()*6.28; local d = 500
    
    local hp = t.hp
    local size = t.sz
    local color = t.col
    
    if isElite then
        hp = hp * 5
        size = size * 1.5
        color = {1, 0, 0} -- Red for elite
    end
    
    table.insert(enemies, {
        x=player.x+math.cos(ang)*d, 
        y=player.y+math.sin(ang)*d, 
        hp=hp, 
        speed=t.spd, 
        color=color, 
        size=size,
        isElite=isElite
    })
end

function damageEnemy(e, dmg, knock, kForce)
    e.hp = e.hp - dmg
    table.insert(texts, {x=e.x, y=e.y-20, text=dmg, color={1,1,1}, life=0.5})
    if knock then
        local a = math.atan2(e.y-player.y, e.x-player.x)
        e.x = e.x + math.cos(a)*(kForce or 10); e.y = e.y + math.sin(a)*(kForce or 10)
    end
end
function findNearestEnemy() local t,m=nil,999999; for _,e in ipairs(enemies) do local d=(player.x-e.x)^2+(player.y-e.y)^2; if d<m then m=d;t=e end end; return m<600^2 and t or nil end
function checkCollision(a,b) return (a.x-b.x)^2+(a.y-b.y)^2 < (a.size/2+b.size/2)^2 end
