-- =============================================================================
-- 武器拖影系统 (Weapon Trail System)
-- =============================================================================
-- 近战挥砍拖影 + 投射物尾迹
-- =============================================================================

local trail = {}

-- =============================================================================
-- 挥砍拖影 (Slash Trail)
-- =============================================================================

trail.slashTrails = {}
trail.maxSlashAge = 0.25  -- 拖影最大存活时间（增强）

--- 记录挥砍轨迹点
---@param entity table 实体（玩家或敌人）
---@param angle number 当前挥砍角度
---@param range number 挥砍范围
---@param opts table|nil 可选配置 { color, width, intensity }
function trail.addSlashPoint(entity, angle, range, opts)
    opts = opts or {}
    local id = tostring(entity)
    
    trail.slashTrails[id] = trail.slashTrails[id] or {
        points = {},
        color = opts.color or {1, 1, 1},
        width = opts.width or 3,
        intensity = opts.intensity or 1,
    }
    
    local t = trail.slashTrails[id]
    table.insert(t.points, {
        x = entity.x,
        y = entity.y,
        angle = angle,
        range = range,
        time = love.timer.getTime(),
    })
    
    -- 限制点数
    while #t.points > 12 do
        table.remove(t.points, 1)
    end
end

--- 清除实体的挥砍拖影
---@param entity table 实体
function trail.clearSlash(entity)
    local id = tostring(entity)
    trail.slashTrails[id] = nil
end

--- 更新挥砍拖影（移除过期点）
---@param dt number delta time
function trail.updateSlash(dt)
    local now = love.timer.getTime()
    
    for id, t in pairs(trail.slashTrails) do
        -- 移除过期点
        local i = 1
        while i <= #t.points do
            if now - t.points[i].time > trail.maxSlashAge then
                table.remove(t.points, i)
            else
                i = i + 1
            end
        end
        
        -- 如果没有点了，移除整个轨迹
        if #t.points == 0 then
            trail.slashTrails[id] = nil
        end
    end
end

--- 绘制所有挥砍拖影
function trail.drawSlash()
    local now = love.timer.getTime()
    
    love.graphics.setBlendMode('add')
    
    for _, t in pairs(trail.slashTrails) do
        local points = t.points
        if #points >= 2 then
            -- 绘制多层拖影以增强可见度
            for layer = 1, 3 do
                local layerMult = 1 - (layer - 1) * 0.25  -- 1.0, 0.75, 0.5
                local widthMult = layer == 1 and 1.5 or (layer == 2 and 1.0 or 0.5)
                
                for i = 2, #points do
                    local p1 = points[i - 1]
                    local p2 = points[i]
                    
                    local age1 = now - p1.time
                    local age2 = now - p2.time
                    local avgAge = (age1 + age2) / 2
                    local fadeProgress = avgAge / trail.maxSlashAge
                    
                    -- 透明度计算：基础透明度更高
                    local alpha = math.max(0, 1 - fadeProgress) * t.intensity * layerMult
                    if alpha <= 0.01 then goto continue end
                    
                    -- 线宽计算：保持较粗
                    local baseWidth = t.width * widthMult
                    local lineWidth = math.max(2, baseWidth * (1 - fadeProgress * 0.5))
                    
                    -- 颜色计算：内层更亮
                    local colorMult = layer == 1 and 1.2 or 1.0
                    love.graphics.setColor(
                        math.min(1, t.color[1] * colorMult), 
                        math.min(1, t.color[2] * colorMult), 
                        math.min(1, t.color[3] * colorMult), 
                        alpha
                    )
                    love.graphics.setLineWidth(lineWidth)
                    
                    -- 绘制弧段
                    local avgRange = (p1.range + p2.range) / 2
                    local avgX = (p1.x + p2.x) / 2
                    local avgY = (p1.y + p2.y) / 2
                    
                    local startAngle = math.min(p1.angle, p2.angle)
                    local endAngle = math.max(p1.angle, p2.angle)
                    if endAngle - startAngle > math.pi then
                        startAngle, endAngle = endAngle, startAngle + 2 * math.pi
                    end
                    
                    love.graphics.arc('line', 'open', avgX, avgY, avgRange, startAngle, endAngle)
                    
                    ::continue::
                end
            end
        end
    end
    
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- =============================================================================
-- 投射物尾迹 (Bullet Trail)
-- =============================================================================

trail.bulletTrails = {}
trail.maxBulletTrailPoints = 8
trail.bulletTrailInterval = 0.016  -- 每帧记录一个点

--- 记录投射物轨迹点
---@param bullet table 子弹实例
function trail.addBulletPoint(bullet)
    local id = tostring(bullet)
    
    -- 根据子弹类型自动分配尾迹颜色
    local trailColor = bullet.trailColor
    if not trailColor then
        local bType = bullet.type or ''
        if bType:find('fire') or bType:find('hellfire') or bType:find('flame') then
            trailColor = {1, 0.5, 0.2}  -- 火焰橙红
        elseif bType:find('ice') or bType:find('frost') or bType:find('cold') or bType:find('absolute_zero') then
            trailColor = {0.4, 0.8, 1}  -- 冰霜蓝
        elseif bType:find('electric') or bType:find('shock') or bType:find('thunder') or bType:find('static') then
            trailColor = {0.6, 0.9, 1}  -- 电光淡蓝
        elseif bType:find('poison') or bType:find('toxin') or bType:find('acid') then
            trailColor = {0.4, 1, 0.4}  -- 毒素绿
        elseif bType:find('void') or bType:find('dark') or bType:find('death') or bType:find('soul') then
            trailColor = {0.8, 0.4, 1}  -- 虚空紫
        elseif bType:find('holy') or bType:find('light') or bType:find('radiant') then
            trailColor = {1, 1, 0.7}  -- 圣光金
        else
            trailColor = {0.9, 0.9, 0.95}  -- 默认白色
        end
    end
    
    trail.bulletTrails[id] = trail.bulletTrails[id] or {
        points = {},
        color = trailColor,
        width = bullet.trailWidth or 2,
        lastUpdate = 0,
    }
    
    local t = trail.bulletTrails[id]
    local now = love.timer.getTime()
    
    -- 限制更新频率
    if now - t.lastUpdate < trail.bulletTrailInterval then
        return
    end
    t.lastUpdate = now
    
    table.insert(t.points, {
        x = bullet.x,
        y = bullet.y,
    })
    
    -- 限制点数
    while #t.points > trail.maxBulletTrailPoints do
        table.remove(t.points, 1)
    end
end

--- 清除投射物尾迹
---@param bullet table 子弹实例
function trail.clearBullet(bullet)
    local id = tostring(bullet)
    trail.bulletTrails[id] = nil
end

--- 绘制投射物尾迹
function trail.drawBulletTrails()
    love.graphics.setBlendMode('add')
    
    for _, t in pairs(trail.bulletTrails) do
        local points = t.points
        if #points >= 2 then
            for i = 2, #points do
                local p1 = points[i - 1]
                local p2 = points[i]
                
                local progress = i / #points
                local alpha = progress * 0.6
                local width = progress * t.width
                
                love.graphics.setColor(t.color[1], t.color[2], t.color[3], alpha)
                love.graphics.setLineWidth(width)
                love.graphics.line(p1.x, p1.y, p2.x, p2.y)
            end
        end
    end
    
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

--- 批量更新投射物尾迹（传入当前存活的子弹列表）
---@param bullets table 子弹列表
function trail.updateBulletTrails(bullets)
    -- 记录当前存活的子弹ID
    local alive = {}
    for _, b in ipairs(bullets or {}) do
        local id = tostring(b)
        alive[id] = true
        -- 只为需要尾迹的子弹记录
        if b.hasTrail ~= false then
            trail.addBulletPoint(b)
        end
    end
    
    -- 清除已死亡子弹的尾迹
    for id in pairs(trail.bulletTrails) do
        if not alive[id] then
            trail.bulletTrails[id] = nil
        end
    end
end

-- =============================================================================
-- 统一接口
-- =============================================================================

--- 更新所有拖影系统
---@param dt number delta time
---@param bullets table|nil 当前子弹列表（用于投射物尾迹）
function trail.update(dt, bullets)
    trail.updateSlash(dt)
    if bullets then
        trail.updateBulletTrails(bullets)
    end
end

--- 绘制所有拖影
function trail.draw()
    trail.drawSlash()
    trail.drawBulletTrails()
end

--- 清除所有拖影
function trail.clearAll()
    trail.slashTrails = {}
    trail.bulletTrails = {}
end

return trail
