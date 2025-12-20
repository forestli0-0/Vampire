-- Love2D 主入口，协调状态、渲染与更新循环
local state = require('state')
local weapons = require('weapons')
local draw = require('draw')
local debugmenu = require('debugmenu')
local augments = require('augments')
local logger = require('logger')
local arsenal = require('arsenal')
local bloom = require('bloom')
local vfx = require('vfx')
local testmode = require('testmode')
local testScenarios = require('test_scenarios')
local pets = require('pets')
local ui = require('ui')
local hud = require('ui.screens.hud')
local scenes = require('scenes')

-- Enable new HUD
draw.useNewHUD = true

-- 游戏启动时的初始化（状态、日志、默认武器等）
function love.load()
    if state.stopMusic then state.stopMusic() end
    state.init()
    pets.init(state)

    -- deterministic runs for scenario-driven tests
    if state.pendingScenarioSeed then
        math.randomseed(state.pendingScenarioSeed)
    end
    state.augments = augments
    logger.init(state)
    arsenal.init(state)
    ui.init()
    bloom.init(love.graphics.getWidth(), love.graphics.getHeight())
    vfx.init()
    if state.gameState ~= 'ARSENAL' then
        weapons.addWeapon(state, 'wand', 'player')
    end
    if state.playMusic then state.playMusic() end
    debugmenu.init(state)
    testmode.init(state)
    -- 调试用武器组合：测试状态联动时取消注释
    -- weapons.addWeapon(state, 'oil_bottle')
    -- weapons.addWeapon(state, 'fire_wand')
    -- weapons.addWeapon(state, 'ice_ring')
    -- weapons.addWeapon(state, 'heavy_hammer')

    -- Initialize HUD if starting directly in game
    if state.gameState == 'PLAYING' then
        hud.init(state)
        ui.core.enabled = true
    end

    if state.pendingScenarioId then
        arsenal.startRun(state, {skipStartingWeapon = true})
        testScenarios.apply(state, state.pendingScenarioId)
        state.activeScenarioId = state.pendingScenarioId
        state.activeScenarioSeed = state.pendingScenarioSeed
        state.pendingScenarioId = nil
        state.pendingScenarioSeed = nil
    end

    scenes.init(state)
end

function love.update(dt)
    scenes.sync(state)
    scenes.update(state, dt)
end

function love.draw()
    scenes.draw(state)
end

function love.resize(w, h)
    scenes.resize(state, w, h)
end

function love.mousemoved(x, y, dx, dy)
    scenes.mousemoved(state, x, y, dx, dy)
end

function love.mousepressed(x, y, button)
    scenes.mousepressed(state, x, y, button)
end

function love.mousereleased(x, y, button)
    scenes.mousereleased(state, x, y, button)
end

function love.textinput(text)
    scenes.textinput(state, text)
end

function love.wheelmoved(x, y)
    scenes.wheelmoved(state, x, y)
end


function love.quit()
    -- 退出时尝试刷新日志落盘
    if logger.flushIfActive then logger.flushIfActive(state, 'quit') end
end

function love.keypressed(key, scancode, isrepeat)
    scenes.keypressed(state, key, scancode, isrepeat)
end
