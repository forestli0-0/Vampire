-- =============================================================================
-- 敌人动画系统 (Enemy Animation System)
-- =============================================================================
-- 配置驱动的通用动画加载器，类似 Unity 的 Animator Override Controller
-- =============================================================================

local animation = require('render.animation')

local enemyAnims = {}

-- =============================================================================
-- 动画配置表
-- =============================================================================
-- 每种敌人素材的路径、帧尺寸、可用动画定义

enemyAnims.configs = {
    skeleton = {
        folder = 'assets/sprites/Skeleton',
        frameSize = 150,
        anims = {
            idle   = { file = 'Idle.png',     fps = 6,  loop = true },
            move   = { file = 'Walk.png',     fps = 8,  loop = true },
            attack = { file = 'Attack.png',   fps = 12, loop = false },
            hit    = { file = 'Take Hit.png', fps = 10, loop = false },
            death  = { file = 'Death.png',    fps = 8,  loop = false },
            shield = { file = 'Shield.png',   fps = 8,  loop = true },
        }
    },
    flying_eye = {
        folder = 'assets/sprites/Flying eye',
        frameSize = 150,
        anims = {
            idle   = { file = 'Flight.png',   fps = 8,  loop = true },  -- 飞行怪用 Flight 作为 idle
            move   = { file = 'Flight.png',   fps = 8,  loop = true },  -- 飞行怪用 Flight 作为 move
            attack = { file = 'Attack.png',   fps = 12, loop = false },
            hit    = { file = 'Take Hit.png', fps = 10, loop = false },
            death  = { file = 'Death.png',    fps = 8,  loop = false },
        }
    },
    goblin = {
        folder = 'assets/sprites/Goblin',
        frameSize = 150,
        anims = {
            idle   = { file = 'Idle.png',     fps = 6,  loop = true },
            move   = { file = 'Run.png',      fps = 8,  loop = true },
            attack = { file = 'Attack.png',   fps = 12, loop = false },
            hit    = { file = 'Take Hit.png', fps = 10, loop = false },
            death  = { file = 'Death.png',    fps = 8,  loop = false },
        }
    },
    mushroom = {
        folder = 'assets/sprites/Mushroom',
        frameSize = 150,
        anims = {
            idle   = { file = 'Idle.png',     fps = 6,  loop = true },
            move   = { file = 'Run.png',      fps = 8,  loop = true },
            attack = { file = 'Attack.png',   fps = 12, loop = false },
            hit    = { file = 'Take Hit.png', fps = 10, loop = false },
            death  = { file = 'Death.png',    fps = 8,  loop = false },
        }
    },
}

-- =============================================================================
-- 敌人类型映射表
-- =============================================================================
-- 游戏中的敌人类型 → 使用的动画配置键

enemyAnims.typeMapping = {
    -- 骷髅系列（基础兵种）
    skeleton      = 'skeleton',
    lancer        = 'skeleton',
    shield_lancer = 'skeleton',
    ballista      = 'skeleton',
    nullifier     = 'skeleton',
    
    -- 飞眼系列（飞行/快速）
    bat             = 'flying_eye',
    volatile_runner = 'flying_eye',
    
    -- 哥布林系列（近战/重型）
    charger       = 'goblin',
    armored_brute = 'goblin',
    heavy_gunner  = 'goblin',
    bombard       = 'goblin',
    scorpion      = 'goblin',
    
    -- 蘑菇人系列（感染/植物类）
    plant          = 'mushroom',
    spore_mortar   = 'mushroom',
    ancient_healer = 'mushroom',
    
    -- Boss 暂时使用骷髅
    boss_treant = 'skeleton',
    
    -- 测试假人
    dummy_pole   = 'skeleton',
    dummy_shield = 'skeleton',
    dummy_armor  = 'skeleton',
    dummy_full   = 'skeleton',
}

-- =============================================================================
-- 加载函数
-- =============================================================================

local function loadImage(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then return img end
    return nil
end

--- 加载单个敌人的动画集
---@param configKey string 配置键（如 'skeleton', 'goblin'）
---@return table|nil 动画集合 { idle, move, attack, hit, death, ... }
function enemyAnims.loadAnimSet(configKey)
    local config = enemyAnims.configs[configKey]
    if not config then
        print("[EnemyAnims] 未找到配置: " .. tostring(configKey))
        return nil
    end
    
    local anims = {}
    local configFrameSize = config.frameSize or 150
    local detectedFrameSize = nil
    
    for animName, animDef in pairs(config.anims) do
        local path = config.folder .. '/' .. animDef.file
        local sheet = loadImage(path)
        
        if sheet then
            sheet:setFilter('nearest', 'nearest')
            
            -- 自动检测帧尺寸：假设帧是正方形，帧尺寸 = 图片高度
            local imgH = sheet:getHeight()
            local imgW = sheet:getWidth()
            local frameSize = imgH  -- 假设帧是正方形，使用图片高度作为帧尺寸
            
            -- 记录检测到的帧尺寸（用于绘制时缩放）
            if not detectedFrameSize then
                detectedFrameSize = frameSize
                print("[EnemyAnims] " .. configKey .. " 检测到帧尺寸: " .. frameSize .. " (图片: " .. imgW .. "x" .. imgH .. ")")
            end
            
            local frames = animation.newFramesFromGrid(sheet, frameSize, frameSize)
            anims[animName] = animation.newAnimation(sheet, frames, {
                fps = animDef.fps or 8,
                loop = animDef.loop ~= false,
            })
        else
            print("[EnemyAnims] 无法加载动画: " .. path)
        end
    end
    
    -- 保存实际检测到的帧尺寸
    if detectedFrameSize then
        config.detectedFrameSize = detectedFrameSize
    end
    
    -- 确保至少有 move 动画作为回退
    if not anims.move and anims.idle then
        anims.move = anims.idle
    end
    if not anims.idle and anims.move then
        anims.idle = anims.move
    end
    
    return anims
end

--- 加载所有敌人动画集
---@return table { configKey = animSet, ... }
function enemyAnims.loadAllAnimSets()
    local allSets = {}
    
    for configKey, config in pairs(enemyAnims.configs) do
        print("[EnemyAnims] 正在加载: " .. configKey .. " 从 " .. config.folder)
        local animSet = enemyAnims.loadAnimSet(configKey)
        if animSet then
            -- 计算成功加载的动画数量
            local count = 0
            for _ in pairs(animSet) do count = count + 1 end
            if count > 0 then
                allSets[configKey] = animSet
                print("[EnemyAnims] ✓ 已加载动画集: " .. configKey .. " (" .. count .. " 个动画)")
            else
                print("[EnemyAnims] ✗ 动画集为空: " .. configKey)
            end
        else
            print("[EnemyAnims] ✗ 加载失败: " .. configKey)
        end
    end
    
    return allSets
end

--- 获取敌人类型对应的动画配置键
---@param enemyType string 敌人类型（如 'bat', 'skeleton'）
---@return string 动画配置键
function enemyAnims.getAnimKeyForType(enemyType)
    return enemyAnims.typeMapping[enemyType] or 'skeleton'
end

--- 获取敌人对应的动画集
---@param enemyAnimSets table 已加载的所有动画集
---@param enemyType string 敌人类型
---@return table|nil 动画集合
function enemyAnims.getAnimsForEnemy(enemyAnimSets, enemyType)
    local animKey = enemyAnims.getAnimKeyForType(enemyType)
    return enemyAnimSets[animKey]
end

--- 获取默认帧尺寸（用于缩放计算）
---@param configKey string 配置键
---@return number 帧尺寸
function enemyAnims.getFrameSize(configKey)
    local config = enemyAnims.configs[configKey]
    if not config then return 150 end
    -- 优先使用检测到的帧尺寸，否则使用配置的帧尺寸
    return config.detectedFrameSize or config.frameSize or 150
end

return enemyAnims
