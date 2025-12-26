-- ============================================================================
-- HUB 世界定义
-- ============================================================================
-- 作用：定义非战斗区域（基地/飞船），提供交互点进入军械库或正式关卡。

local world = require('world.world')

local hub = {}

function hub.init(state)
    local map = {
        w = 40,
        h = 30,
        tileSize = 32,
        spawnX = 400,
        spawnY = 300
    }
    state.hubMap = map
    
    -- 初始化物理世界（和平模式）
    state.world = world.new({w = map.w, h = map.h})
    state.world.tileSize = map.tileSize
    state.world.w = map.w
    state.world.h = map.h
    state.world.pixelW = map.w * map.tileSize
    state.world.pixelH = map.h * map.tileSize
    
    -- 填充 1D 表：0 = 地板, 1 = 墙壁 (draw.renderWorld 的标准)
    state.world.tiles = {}
    for i = 1, map.w * map.h do
        state.world.tiles[i] = 0
    end
    
    -- 添加边界墙
    for x = 1, map.w do
        state.world.tiles[x] = 1 -- 顶
        state.world.tiles[(map.h - 1) * map.w + x] = 1 -- 底
    end
    for y = 1, map.h do
        state.world.tiles[(y - 1) * map.w + 1] = 1 -- 左
        state.world.tiles[(y - 1) * map.w + map.w] = 1 -- 右
    end
    
    -- 玩家位置
    state.player.x = map.spawnX
    state.player.y = map.spawnY
    
    -- 定义交互点（军械库、出战入口）
    state.hubInteractions = {
        { x = 500, y = 300, radius = 50, type = 'arsenal', label = "[E] 进入军械库" },
        { x = 300, y = 200, radius = 60, type = 'chapter_entry', label = "[E] 开始任务" }
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
