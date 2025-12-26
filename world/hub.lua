-- ============================================================================
-- HUB 世界定义
-- ============================================================================
-- 作用：定义非战斗区域（基地/飞船），提供交互点进入军械库或正式关卡。

local world = require('world.world')

local hub = {}

function hub.init(state)
    local map = {
        w = 32,
        h = 24,
        tileSize = 32,
        spawnX = 16 * 32, -- 中央
        spawnY = 12 * 32
    }
    state.hubMap = map
    
    -- 初始化物理世界（和平模式）
    state.world = world.new({w = map.w, h = map.h})
    state.world.tileSize = map.tileSize
    state.world.w = map.w
    state.world.h = map.h
    state.world.pixelW = map.w * map.tileSize
    state.world.pixelH = map.h * map.tileSize
    
    -- 填充 1D 表
    -- 0: 基础地板 (暗灰色)
    -- 1: 墙壁 (厚重金属)
    -- 2: 装饰性格栅 (科技感)
    -- 3: 能源走廊 (带蓝色自发光)
    state.world.tiles = {}
    for i = 1, map.w * map.h do
        state.world.tiles[i] = 1 -- 默认全是墙
    end
    
    -- 助手函数：填充矩形区域
    local function fillRect(tx, ty, tw, th, id)
        for y = ty, ty + th - 1 do
            for x = tx, tx + tw - 1 do
                if x >= 1 and x <= map.w and y >= 1 and y <= map.h then
                    state.world.tiles[(y - 1) * map.w + x] = id
                end
            end
        end
    end

    -- 绘制基地布局
    -- 1. 中央大厅 (Cross shape)
    fillRect(8, 8, 16, 8, 0)  -- 水平主厅
    fillRect(12, 4, 8, 16, 0) -- 垂直主厅
    fillRect(14, 10, 4, 4, 2) -- 中央装饰格栅
    
    -- 2. 走廊连接到功能区
    fillRect(4, 11, 4, 2, 3)  -- 左侧走廊
    fillRect(24, 11, 4, 2, 3) -- 右侧走廊
    
    -- 3. 功能房间
    fillRect(2, 9, 3, 6, 0)   -- 左侧：军械库区
    fillRect(2, 11, 3, 2, 2)  
    
    fillRect(27, 9, 3, 6, 0)  -- 右侧：出战调度
    fillRect(27, 11, 3, 2, 2) 

    -- 玩家位置：中央大厅
    state.player.x = map.spawnX
    state.player.y = map.spawnY
    
    -- 定义交互点（调整到新位置）
    state.hubInteractions = {
        { x = 3.5 * 32, y = 12 * 32, radius = 40, type = 'arsenal', label = "[E] 访问军械库" },
        { x = 28.5 * 32, y = 12 * 32, radius = 40, type = 'chapter_entry', label = "[E] 开启任务" }
    }
end

function hub.enterHub(state)
    print("DEBUG: Entering Hub")
    state.gameState = 'HUB'
    state.runMode = 'hub'
    hub.init(state)
    if state.world and state.world.tiles then
        print("DEBUG: Hub initialized. #tiles=" .. tostring(#state.world.tiles) .. " w=" .. tostring(state.world.w))
    end
    
    -- 清理战斗状态
    state.enemies = {}
    state.bullets = {}
    state.enemyBullets = {}
    state.gems = {}
    state.texts = {}
end

return hub
