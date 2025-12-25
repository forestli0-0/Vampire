-- =============================================================================
-- 玩家8向动画加载器 (Player 8-Directional Animation Loader)
-- =============================================================================
-- 加载和管理玩家的8向动画（跑步、滑行等）
-- =============================================================================

local animation = require('render.animation')

local playerAnims = {}

-- =============================================================================
-- 方向常量
-- =============================================================================

-- 8个方向（顺时针，从北开始）
playerAnims.DIRECTIONS = {'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'}

-- 方向名到角度的映射（弧度）
playerAnims.DIR_ANGLES = {
    N = -math.pi/2,         -- 向上 (-90°)
    NE = -math.pi/4,        -- 右上 (-45°)
    E = 0,                  -- 向右 (0°)
    SE = math.pi/4,         -- 右下 (45°)
    S = math.pi/2,          -- 向下 (90°)
    SW = 3*math.pi/4,       -- 左下 (135°)
    W = math.pi,            -- 向左 (180°)
    NW = -3*math.pi/4,      -- 左上 (-135°)
}

-- 方向名到文件后缀的映射
playerAnims.DIR_SUFFIXES = {
    N = 'north',
    NE = 'north-east',
    E = 'east',
    SE = 'south-east',
    S = 'south',
    SW = 'south-west',
    W = 'west',
    NW = 'north-west',
}

-- =============================================================================
-- 方向计算
-- =============================================================================

--- 根据移动角度获取最接近的8方向
---@param angle number 移动角度（弧度）
---@return string 方向名（N, NE, E, SE, S, SW, W, NW）
function playerAnims.getDirection(angle)
    -- 标准化角度到 [-π, π]
    while angle > math.pi do angle = angle - 2 * math.pi end
    while angle < -math.pi do angle = angle + 2 * math.pi end
    
    -- 22.5度 = π/8 弧度，用于划分8个方向区间
    local sector = math.pi / 8
    
    if angle >= -sector and angle < sector then
        return 'E'
    elseif angle >= sector and angle < 3*sector then
        return 'SE'
    elseif angle >= 3*sector and angle < 5*sector then
        return 'S'
    elseif angle >= 5*sector and angle < 7*sector then
        return 'SW'
    elseif angle >= 7*sector or angle < -7*sector then
        return 'W'
    elseif angle >= -7*sector and angle < -5*sector then
        return 'NW'
    elseif angle >= -5*sector and angle < -3*sector then
        return 'N'
    else
        return 'NE'
    end
end

--- 根据 dx, dy 获取方向
---@param dx number X方向速度
---@param dy number Y方向速度
---@return string 方向名
function playerAnims.getDirectionFromVelocity(dx, dy)
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
        return 'S'  -- 默认朝南
    end
    return playerAnims.getDirection(math.atan2(dy, dx))
end

-- =============================================================================
-- 动画加载
-- =============================================================================

--- 加载单个方向的动画（从精灵表）
---@param sheet userdata 精灵表图像
---@param frameW number 帧宽度
---@param frameH number 帧高度
---@param frameCount number 帧数
---@param fps number 帧率
---@param loop boolean 是否循环
---@return table 动画实例
local function loadAnimFromSheet(sheet, frameW, frameH, frameCount, fps, loop)
    local frames = {}
    local imgW = sheet:getWidth()
    
    for i = 0, frameCount - 1 do
        local x = i * frameW
        if x + frameW <= imgW then
            table.insert(frames, love.graphics.newQuad(x, 0, frameW, frameH, imgW, frameH))
        end
    end
    
    return animation.newAnimation(sheet, frames, {
        fps = fps or 8,
        loop = loop ~= false,
    })
end

--- 从PNG精灵表文件加载8向动画集
---@param basePath string 基础路径（如 'assets/characters/player/run'）
---@param frameCount number 每个方向的帧数
---@param fps number 帧率
---@param frameSize number 帧大小（正方形边长）
---@param loop boolean 是否循环
---@return table|nil 8向动画集 { N = anim, NE = anim, ... }
function playerAnims.load8DirAnimSet(basePath, frameCount, fps, frameSize, loop)
    frameSize = frameSize or 64
    local animSet = {}
    local loadedCount = 0
    
    for _, dir in ipairs(playerAnims.DIRECTIONS) do
        local suffix = playerAnims.DIR_SUFFIXES[dir]
        local path = string.format('%s_%s.png', basePath, suffix)
        
        local ok, sheet = pcall(love.graphics.newImage, path)
        if ok and sheet then
            sheet:setFilter('nearest', 'nearest')
            local anim = loadAnimFromSheet(sheet, frameSize, frameSize, frameCount, fps, loop)
            if anim then
                animSet[dir] = anim
                loadedCount = loadedCount + 1
            end
        end
    end
    
    if loadedCount == 0 then
        return nil
    end
    
    -- 如果某些方向缺失，用其他方向填充
    local fallbackDir = nil
    for _, dir in ipairs(playerAnims.DIRECTIONS) do
        if animSet[dir] then
            fallbackDir = dir
            break
        end
    end
    
    if fallbackDir then
        for _, dir in ipairs(playerAnims.DIRECTIONS) do
            if not animSet[dir] then
                animSet[dir] = animSet[fallbackDir]
            end
        end
    end
    
    return animSet
end

--- 加载所有玩家动画集
---@return table { run = {8DirSet}, slide = {8DirSet}, idle = {8DirSet} }
function playerAnims.loadAllAnimSets()
    local sets = {}
    
    -- 跑步动画：4帧，10FPS
    sets.run = playerAnims.load8DirAnimSet(
        'assets/characters/player/run',
        4,  -- 帧数
        10, -- FPS
        64  -- 帧大小
    )
    
    -- 滑行动画：6帧，14FPS
    sets.slide = playerAnims.load8DirAnimSet(
        'assets/characters/player/slide',
        6,   -- 帧数
        14,  -- FPS
        64,  -- 帧大小
        false -- loop (滑行动画不循环)
    )
    
    -- 待机动画：8帧，6FPS（慢速呼吸感）
    sets.idle = playerAnims.load8DirAnimSet(
        'assets/characters/player/idle',
        8,   -- 帧数
        6,   -- FPS
        64   -- 帧大小
    )
    
    -- 如果加载失败，尝试加载旧版单向动画作为回退
    if not sets.run then
        print('[PlayerAnims] 警告: 8向跑步动画加载失败，尝试加载旧版动画')
        local ok, img = pcall(love.graphics.newImage, 'assets/characters/player/move_1.PNG')
        if ok and img then
            -- 使用单帧作为回退
            sets.run = {}
            for _, dir in ipairs(playerAnims.DIRECTIONS) do
                sets.run[dir] = animation.newAnimation(img, {{0, 0, img:getWidth(), img:getHeight()}}, {fps = 4, loop = true})
            end
        end
    end
    
    -- 如果没有待机动画，使用跑步动画代替
    if not sets.idle and sets.run then
        sets.idle = sets.run
    end
    
    return sets
end

-- =============================================================================
-- 玩家动画状态定义
-- =============================================================================

--- 创建玩家动画状态机的状态定义
---@return table 状态定义表
function playerAnims.createPlayerStates()
    return {
        idle = {
            animation = 'idle',
            animSet = 'run',  -- idle 使用 run 动画但速度慢
            loop = true,
            canInterrupt = true,
            speedMultiplier = 0.3,  -- 慢速播放
            transitions = {
                { to = 'run', condition = function(ctx) return ctx.isMoving end },
                { to = 'slide', condition = function(ctx) return ctx.isSliding end },
                { to = 'dash', condition = function(ctx) return ctx.isDashing end },
            },
        },
        run = {
            animation = 'run',
            animSet = 'run',
            loop = true,
            canInterrupt = true,
            speedMultiplier = 1.0,
            transitions = {
                { to = 'idle', condition = function(ctx) return not ctx.isMoving end },
                { to = 'slide', condition = function(ctx) return ctx.isSliding end },
                { to = 'dash', condition = function(ctx) return ctx.isDashing end },
            },
        },
        slide = {
            animation = 'slide',
            animSet = 'slide',
            loop = false,
            canInterrupt = false,
            lockDuration = 0.3,
            speedMultiplier = 1.0,
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
        dash = {
            animation = 'dash',
            animSet = 'slide',  -- 冲刺也使用滑行动画
            loop = false,
            canInterrupt = false,
            lockDuration = 0.2,
            speedMultiplier = 2.0,  -- 快速播放
            enterTransform = { stretch = 0.6, instant = true },
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
        hit = {
            animation = 'hit',
            animSet = 'run',
            loop = false,
            canInterrupt = true,
            speedMultiplier = 1.5,
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
    }
end

return playerAnims
