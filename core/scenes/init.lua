-- ============================================================================
-- 场景管理器 (Scene Manager)
-- ============================================================================
-- 文件：core/scenes/init.lua
-- 作用：作为游戏的核心调度中心，管理不同游戏状态（场景）之间的切换
--      以及协调各模块的更新和渲染
-- 
-- 游戏状态流转：
--   ARSENAL（军械库） → PLAYING（战斗进行） → LEVEL_UP（升级） 
--   → SHOP（商店） → GAME_OVER / GAME_CLEAR（结束）
--
-- 此模块被 main.lua 中的 love.update() 和 love.draw() 调用，
-- 负责将游戏循环分发给当前状态的处理器
-- ============================================================================

-- 导入所有游戏模块，用于协调各系统的更新和渲染
local abilities = require('gameplay.abilities')        -- 技能系统
local arsenal = require('core.arsenal')               -- 军械库/装备系统
local benchmark = require('debug.benchmark')          -- 性能基准测试
local bloom = require('render.bloom')                 -- Bloom后期处理
local chapter = require('world.chapter')              -- 章节模式（地图探索）
local debugmenu = require('debug.debugmenu')          -- 调试菜单
local director = require('world.director')            -- 战斗导演（敌人生成控制）
local draw = require('render.draw')                   -- 基础渲染
local enemies = require('gameplay.enemies')           -- 敌人系统
local gameoverScreen = require('ui.screens.gameover') -- 游戏结束界面
local hud = require('ui.screens.hud')                 -- HUD抬头显示
local ingameMenu = require('ui.screens.ingame_menu')  -- 游戏内菜单
local levelupScreen = require('ui.screens.levelup')   -- 升级界面
local minimap = require('ui.minimap')                 -- 小地图
local mission = require('world.mission')              -- 任务系统
local pets = require('gameplay.pets')                 -- 宠物系统
local pickups = require('systems.pickups')            -- 物品拾取系统
local player = require('gameplay.player')             -- 玩家系统
local projectiles = require('gameplay.projectiles')   -- 投射物系统
local rooms = require('world.rooms')                  -- 房间系统（关卡流程）
local shopScreen = require('ui.screens.shop')         -- 商店界面
local spawner = require('world.spawner')              -- 敌人生成器
local testmode = require('debug.testmode')            -- 测试模式
local ui = require('ui')                              -- UI框架
local uiDemo = require('ui.demo')                     -- UI演示模式
local pipeline = require('render.pipeline')           -- 渲染管线
local vfx = require('render.vfx')                     -- 视觉特效
local weapons = require('gameplay.weapons')           -- 武器系统
local world = require('world.world')                  -- 世界/地图系统

-- ============================================================================
-- 局部变量：模块状态
-- ============================================================================

-- scenes 模块的公开接口，所有场景操作都通过此表暴露
local scenes = {}

-- 当前激活的场景ID，对应 state.gameState 的值（如 'PLAYING', 'ARSENAL'）
local currentId = nil

-- 当前场景的处理器表，包含 {update, draw, enter, exit} 等方法
local currentScene = nil

-- 场景处理器注册表：将游戏状态映射到对应的更新和渲染函数
-- 结构：handlers[状态名] = {update = 更新函数, draw = 渲染函数}
local handlers = {}

-- ============================================================================
-- 场景更新函数
-- ============================================================================

--- updatePlaying: 战斗进行状态的更新函数
-- 每帧调用一次，负责更新所有游戏逻辑
-- 更新顺序很重要：输入 → 玩家 → 武器 → 敌人 → 物品 → UI
-- @param state 全局状态表，包含所有游戏数据
-- @param dt delta time，自上一帧以来的时间（秒）
local function updatePlaying(state, dt)
    -- 首先检查游戏内菜单是否激活，如果激活则暂停游戏逻辑更新
    if ingameMenu.isActive() then
        ingameMenu.update(dt)
        return  -- 跳过其他更新
    end

    -- UI 层更新（必须优先于游戏逻辑，确保UI响应及时）
    hud.update(state, dt)
    ui.update(dt)

    -- Bloom后期处理更新：根据运行模式调整暗角强度
    -- explore模式（探索模式）有轻微暗角，战斗模式无暗角
    if bloom and bloom.update then bloom.update(dt) end
    if bloom and bloom.setParams then
        local desired = (state.runMode == 'explore') and 0.10 or 0.0
        if state._vignetteStrength ~= desired then
            state._vignetteStrength = desired
            bloom.setParams({vignette_strength = desired})
        end
    end

    -- 房间切换淡入淡出效果
    if state.roomTransitionFade and state.roomTransitionFade > 0 then
        state.roomTransitionFade = state.roomTransitionFade - dt * 3
        if state.roomTransitionFade < 0 then state.roomTransitionFade = 0 end
    end

    -- 屏幕震动效果，随时间衰减
    if state.shakeAmount > 0 then
        state.shakeAmount = math.max(0, state.shakeAmount - dt * 10)
    end

    -- 游戏总时长计数器
    state.gameTimer = state.gameTimer + dt
    -- 自定义特效更新回调（如果有）
    if state.updateEffects then state.updateEffects(dt) end

    -- ==================== 玩家系统更新 ====================
    player.updateFiring(state)      -- 射击逻辑（开火、冷却、弹药）
    player.updateMelee(state, dt)   -- 近战攻击逻辑
    abilities.update(state, dt)     -- 主动技能冷却和触发
    player.updateMovement(state, dt) -- 移动和闪避

    -- ==================== 世界系统更新 ====================
    world.update(state, dt)         -- 地图、相机跟随
    pets.update(state, dt)          -- 宠物AI和行为
    if state.augments and state.augments.update then
        state.augments.update(state, dt)  -- 战甲强化效果
    end

    -- ==================== 武器系统更新 ====================
    weapons.update(state, dt)       -- 武器状态（切换、特殊效果）
    weapons.updateReload(state, dt) -- 换弹逻辑

    -- ==================== 投射物更新 ====================
    projectiles.updatePlayerBullets(state, dt)  -- 玩家子弹（移动、碰撞）
    projectiles.updateEnemyBullets(state, dt)   -- 敌人子弹

    -- ==================== 世界模式选择 ====================
    -- 根据 runMode 选择不同的敌人生成和房间管理方式：
    -- 1. chapter模式：使用章节生成器，适合连续探索
    -- 2. rooms模式：使用房间系统，适合Hades风格的关卡流
    -- 3. 其他：使用导演系统，适合测试或基准模式
    if state.runMode == 'chapter' and state.chapterMap and not state.testArena and not state.scenarioNoDirector and not state.benchmarkMode then
        -- Chapter模式：使用章节专用的生成器
        spawner.update(state, state.chapterMap, dt)
        spawner.checkRoomClear(state, state.chapterMap)
        spawner.spawnBoss(state, state.chapterMap)
        minimap.update(state, state.chapterMap, dt)
    elseif state.runMode == 'rooms' and not state.testArena and not state.scenarioNoDirector and not state.benchmarkMode then
        -- Rooms模式：使用房间系统管理关卡流程
        -- 房间系统负责：房间生成 → 敌人生成 → 波次管理 → 清理检查 → 奖励/传送门
        rooms.update(state, dt)
    else
        -- 默认/测试模式：使用导演系统
        director.update(state, dt)
    end

    -- ==================== 敌人更新 ====================
    enemies.update(state, dt)       -- 敌人AI、攻击、死亡

    -- ==================== 玩家动画更新 ====================
    if state.playerAnim then
        if state.player.isMoving then
            -- 移动中：播放奔跑动画
            if not state.playerAnim.playing then state.playerAnim:play(false) end
            state.playerAnim:update(dt)
        else
            -- 静止：停止动画
            if state.playerAnim.playing then state.playerAnim:stop() end
        end
    end

    -- ==================== 玩家状态计时器 ====================
    player.tickInvincibility(state, dt)  -- 无敌时间倒计时
    player.tickRegen(state, dt)          -- 自动回血
    player.tickShields(state, dt)        -- 护盾恢复

    -- ==================== 物品更新 ====================
    pickups.updateGems(state, dt)        -- 宝石（经验/货币）
    pickups.updateChests(state, dt)      -- 箱子
    pickups.updateFloorPickups(state, dt) -- 地面掉落物

    -- ==================== 浮动文本更新 ====================
    player.tickTexts(state, dt)          -- 伤害数字、提示文本

    -- ==================== 调试工具更新 ====================
    benchmark.update(state, dt)
end

--- updateArsenal: 军械库状态的更新函数
-- 军械库是玩家在战斗前选择装备、MOD、战甲的地方
local function updateArsenal(state, dt)
    ui.update(dt)
    arsenal.update(state, dt)
end

--- updateLevelUp: 升级界面的更新函数
-- 玩家升级时暂停游戏，显示3个升级选项供选择
local function updateLevelUp(state, dt)
    ui.update(dt)
    -- 如果升级界面未初始化，则初始化
    if not levelupScreen.isActive() then
        levelupScreen.init(state)
    end
end

--- updateShop: 商店界面的更新函数
-- 玩家可以在商店购买武器、MOD等
local function updateShop(state, dt)
    ui.update(dt)
    if not shopScreen.isActive() then
        shopScreen.init(state)
    end
end

--- updateGameOver: 游戏结束状态的更新函数
-- 显示结算界面，允许玩家返回军械库重新开始
local function updateGameOver(state, dt)
    ui.update(dt)
    if not gameoverScreen.isActive() then
        gameoverScreen.init(state)
    end
end

-- ============================================================================
-- 场景渲染函数
-- ============================================================================

--- drawWorld: 战斗/游戏内场景的渲染函数
-- 使用渲染管线分层渲染：基础层 → 发光层 → 灯光层 → UI层
-- @param state 全局状态表
local function drawWorld(state)
    -- 处理屏幕震动偏移
    if state.shakeAmount and state.shakeAmount > 0 then
        state._shakeOffsetX = love.math.random() * state.shakeAmount
        state._shakeOffsetY = love.math.random() * state.shakeAmount
    else
        state._shakeOffsetX = nil
        state._shakeOffsetY = nil
    end

    -- 开始渲染管线帧
    pipeline.beginFrame()
    
    -- 第一层：基础渲染（地形、角色、敌人、物品）
    pipeline.drawBase(function()
        draw.renderBase(state)
    end)
    
    -- 第二层：发光物体渲染（武器特效、光环、火焰等）
    pipeline.drawEmissive(function()
        draw.renderEmissive(state)
        if ui.drawEmissive then
            ui.drawEmissive()
        end
        return true
    end)
    
    -- 第三层：动态光源渲染（光源在 renderEmissive 阶段收集）
    local camX = state.camera and state.camera.x or 0
    local camY = state.camera and state.camera.y or 0
    pipeline.drawLights(camX, camY)
    
    -- 提交管线帧到屏幕
    pipeline.present(state)
    
    -- 渲染发光物体统计信息（调试用）
    pipeline.drawEmissiveStatsOverlay(state.font)

    -- 调试层（在UI之上）
    benchmark.draw(state)
    debugmenu.draw(state)
    testmode.draw(state)

    -- 第四层：UI渲染
    pipeline.drawUI(function()
        ui.draw()
        -- 如果是章节模式，在UI层之上绘制小地图
        if state.runMode == 'chapter' and state.chapterMap then
            hud.drawMinimap(state)
        end
    end)
end

--- drawArsenal: 军械库界面的渲染函数
local function drawArsenal(state)
    arsenal.draw(state)
    testmode.draw(state)
end

-- ============================================================================
-- 场景处理器注册
-- ============================================================================
-- 将每个游戏状态映射到其对应的更新和渲染函数
-- handlers 表是场景管理器的核心配置

handlers.PLAYING = {update = updatePlaying, draw = drawWorld}
handlers.ARSENAL = {update = updateArsenal, draw = drawArsenal}
handlers.LEVEL_UP = {update = updateLevelUp, draw = drawWorld}  -- 升级时仍渲染游戏世界（背景模糊等效果）
handlers.SHOP = {update = updateShop, draw = drawWorld}         -- 商店时也渲染游戏世界
handlers.GAME_OVER = {update = updateGameOver, draw = drawWorld}
handlers.GAME_CLEAR = handlers.GAME_CLEAR or handlers.GAME_OVER  -- 游戏通关与结束使用相同处理器

-- ============================================================================
-- 场景切换逻辑
-- ============================================================================

--- setCurrent: 切换当前场景
-- 当 state.gameState 改变时调用此函数
-- 执行退出旧场景 → 切换ID → 初始化新场景的流程
-- @param state 全局状态表
local function setCurrent(state)
    -- 从状态表获取下一个场景ID，默认使用 'ARSENAL'
    local nextId = (state and state.gameState) or 'ARSENAL'
    
    -- 如果场景未改变，不执行任何操作
    if nextId == currentId then return end

    -- 退出当前场景（如果有退出回调）
    if currentScene and currentScene.exit then
        currentScene.exit(state)
    end

    -- 更新当前场景ID
    currentId = nextId
    -- 从处理器表中获取新场景的处理器
    currentScene = handlers[currentId] or handlers.PLAYING

    -- 进入新场景（如果有待进入回调）
    if currentScene and currentScene.enter then
        currentScene.enter(state)
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- scenes.init: 场景管理器初始化
-- 在 love.load() 中调用，初始化当前场景
function scenes.init(state)
    setCurrent(state)
end

--- scenes.sync: 同步场景状态
-- 当外部修改了 state.gameState 时调用，确保场景管理器响应变化
function scenes.sync(state)
    setCurrent(state)
end

--- scenes.update: 分发更新调用
-- 在 love.update() 中调用，将更新逻辑分发给当前场景的处理器
-- @param state 全局状态表
-- @param dt delta time
function scenes.update(state, dt)
    if not currentScene then setCurrent(state) end
    if currentScene and currentScene.update then
        currentScene.update(state, dt)
    end
end

--- scenes.draw: 分发渲染调用
-- 在 love.draw() 中调用，将渲染逻辑分发给当前场景的处理器
-- @param state 全局状态表
function scenes.draw(state)
    if not currentScene then setCurrent(state) end
    if currentScene and currentScene.draw then
        currentScene.draw(state)
    end
end

--- scenes.resize: 处理窗口大小变化
-- 在 love.resize() 中调用，更新渲染管线和UI系统的尺寸
function scenes.resize(state, w, h)
    pipeline.resize(w, h)
    ui.resize(w, h)
end

-- ============================================================================
-- 输入处理函数
-- ============================================================================
-- 这些函数被 main.lua 中的对应 love 回调调用
-- 每个函数都会根据当前游戏状态分发输入到对应的处理器

--- scenes.mousemoved: 鼠标移动处理
function scenes.mousemoved(state, x, y, dx, dy)
    if state.gameState == 'PLAYING' and ingameMenu.isActive() then
        -- 游戏进行中且菜单打开：菜单处理鼠标移动
        ingameMenu.mousemoved(x, y, dx, dy)
        return
    end
    -- 默认：UI系统处理
    ui.mousemoved(x, y, dx, dy)
end

--- scenes.mousepressed: 鼠标按下处理
function scenes.mousepressed(state, x, y, button)
    if state.gameState == 'PLAYING' and ingameMenu.isActive() then
        ingameMenu.mousepressed(x, y, button)
        return
    end
    -- UI优先处理，如果UI处理了则不再传递
    if ui.mousepressed(x, y, button) then return end
end

--- scenes.mousereleased: 鼠标释放处理
function scenes.mousereleased(state, x, y, button)
    if state.gameState == 'PLAYING' and ingameMenu.isActive() then
        ingameMenu.mousereleased(x, y, button)
        return
    end
    ui.mousereleased(x, y, button)
end

--- scenes.keypressed: 键盘按键处理
-- 这是最复杂的输入处理函数，需要处理各种游戏状态的按键
function scenes.keypressed(state, key, scancode, isrepeat)
    -- UI演示模式优先
    if uiDemo.keypressed(key) then return true end

    -- ==================== 游戏进行中 ====================
    if state.gameState == 'PLAYING' then
        -- Tab键：打开/关闭游戏内菜单
        if key == 'tab' then
            ingameMenu.toggle(state)
            return true
        end

        -- 如果菜单打开，优先处理菜单输入
        if ingameMenu.isActive() then
            if ingameMenu.keypressed(key) then return true end
            return true  -- 菜单打开时阻止其他输入
        end

        -- UI系统处理
        if ui.keypressed(key) then return true end

        -- Escape键：返回军械库（调试用）
        if key == 'escape' then
            state.init()
            arsenal.init(state)
            state.gameState = 'ARSENAL'
            arsenal.show(state)
            return true
        end
    end

    -- ==================== 通用调试按键 ====================
    -- 这些按键在任何状态下都有效
    if testmode.keypressed(state, key) then return true end
    
    -- F5：切换基准测试模式
    if key == 'f5' then benchmark.toggle(state) end
    -- V：切换VFX特效
    if key == 'v' then vfx.toggle() end
    -- F7：切换调试视图（渲染管线的不同层）
    if key == 'f7' then
        pipeline.nextDebugView()
        return true
    end
    -- F9：切换发光统计显示
    if key == 'f9' then
        pipeline.toggleEmissiveStats()
        return true
    end

    -- ==================== 各状态专用输入 ====================
    
    -- 玩家按键（可能需要玩家系统处理，如切换武器、技能快捷键）
    if player.keypressed and player.keypressed(state, key) then return true end

    -- 调试菜单
    if debugmenu.keypressed(state, key) then return true end

    -- 军械库状态
    if state.gameState == 'ARSENAL' then
        if arsenal.keypressed(state, key) then return true end
        return true  -- 军械库处理后不再传递
    end

    -- 商店状态
    if state.gameState == 'SHOP' then
        if shopScreen.keypressed(key) then return true end
        return true
    end

    -- 游戏结束状态
    if state.gameState == 'GAME_OVER' or state.gameState == 'GAME_CLEAR' then
        if gameoverScreen.keypressed(key) then return true end
        return true
    end

    -- 升级状态
    if state.gameState == 'LEVEL_UP' then
        if levelupScreen.keypressed(key) then return true end
        return true
    end

    -- 默认：未处理
    return false
end

--- scenes.textinput: 文本输入处理
-- 用于输入框等需要输入文本的场景
function scenes.textinput(state, text)
    ui.textinput(text)
end

--- scenes.wheelmoved: 鼠标滚轮处理
-- 用于滚动列表、切换快捷技能等
function scenes.wheelmoved(state, x, y)
    if state.gameState == 'PLAYING' then
        -- 游戏进行中
        if ingameMenu.isActive() then
            -- 菜单打开时：菜单处理滚轮
            if ingameMenu.wheelmoved then
                ingameMenu.wheelmoved(x, y)
            end
            return
        end
        
        -- 滚轮切换快捷技能（向上滚：上一个，向下滚：下一个）
        if y and y ~= 0 then
            player.cycleQuickAbility(state, -y)
        end
    end
    
    -- UI处理滚轮（列表滚动等）
    ui.wheelmoved(x, y)
end

-- 返回场景管理器模块，供其他模块使用
return scenes
