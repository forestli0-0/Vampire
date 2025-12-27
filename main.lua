-- Love2D 主入口文件，负责协调游戏状态、渲染引擎、物理更新与输入处理。
local state = require('core.state')
local weapons = require('gameplay.weapons')
local draw = require('render.draw')
local debugmenu = require('debug.debugmenu')
local augments = require('gameplay.augments')
local logger = require('core.logger')
local arsenal = require('core.arsenal')
local pipeline = require('render.pipeline')
local vfx = require('render.vfx')
local testmode = require('debug.testmode')
local testScenarios = require('debug.test_scenarios')
local pets = require('gameplay.pets')
local ui = require('ui')
local hud = require('ui.screens.hud')
local scenes = require('core.scenes.init')

-- 强制开启新版 HUD 系统
draw.useNewHUD = true

--- love.load: 游戏启动时的初始化钩子
-- 负责：
-- 1. 初始化核心状态机 (state.init)
-- 2. 加载子系统 (pets, arsenal, ui, pipeline, vfx)
-- 3. 设置测试/场景模拟环境 (scenario-driven tests)
-- 4. 触发场景管理器的初始化
function love.load()
    if state.stopMusic then state.stopMusic() end
    state.init()
    local analytics = require('systems.analytics')
    analytics.startRun(state)
    pets.init(state)

    -- 确定性随机：用于场景驱动的自动化测试，确保测试结果可重现。
    if state.pendingScenarioSeed then
        math.randomseed(state.pendingScenarioSeed)
    end
    state.augments = augments
    logger.init(state)
    arsenal.init(state)
    ui.init()
    pipeline.init(love.graphics.getWidth(), love.graphics.getHeight())
    vfx.init()

    -- 如果不是从配置界面进入，默认给玩家一把武器
    if state.gameState ~= 'ARSENAL' then
        weapons.addWeapon(state, 'wand', 'player')
    end
    if state.playMusic then state.playMusic() end
    debugmenu.init(state)
    testmode.init(state)

    -- 如果直接进入战斗状态，初始化 HUD
    if state.gameState == 'PLAYING' then
        hud.init(state)
        ui.core.enabled = true
    end

    -- 应用待处理的测试场景配置
    if state.pendingScenarioId then
        arsenal.startRun(state, {skipStartingWeapon = true})
        testScenarios.apply(state, state.pendingScenarioId)
        state.activeScenarioId = state.pendingScenarioId
        state.activeScenarioSeed = state.pendingScenarioSeed
        state.pendingScenarioId = nil
        state.pendingScenarioSeed = nil
    end

    -- 初始化场景管理器（负责具体画面的渲染与更新逻辑切换）
    scenes.init(state)
end

--- love.update: 每帧逻辑更新钩子
-- @param dt (number) 自上一帧以来的时间间隔（秒）
function love.update(dt)
    scenes.sync(state)   -- 同步外部状态到场景系统
    scenes.update(state, dt) -- 分发更新逻辑
end

--- love.draw: 每帧渲染钩子
function love.draw()
    scenes.draw(state) -- 分发渲染逻辑
end

--- love.resize: 窗口尺寸改变回调
function love.resize(w, h)
    scenes.resize(state, w, h)
end

-- === 鼠标输入处理 ===

function love.mousemoved(x, y, dx, dy)
    scenes.mousemoved(state, x, y, dx, dy)
end

function love.mousepressed(x, y, button)
    scenes.mousepressed(state, x, y, button)
end

function love.mousereleased(x, y, button)
    scenes.mousereleased(state, x, y, button)
end

-- === 键盘与文本输入处理 ===

function love.textinput(text)
    scenes.textinput(state, text)
end

function love.keypressed(key, scancode, isrepeat)
    scenes.keypressed(state, key, scancode, isrepeat)
end

--- love.wheelmoved: 鼠标滚轮滚动回调
function love.wheelmoved(x, y)
    scenes.wheelmoved(state, x, y)
end

--- love.quit: 游戏退出钩子
-- 退出前确保分析数据被保存，日志已写入磁盘。
function love.quit()
    local analytics = require('systems.analytics')
    analytics.endRun()
    
    -- 尝试刷新日志缓冲区
    if logger.flushIfActive then logger.flushIfActive(state, 'quit') end
end
