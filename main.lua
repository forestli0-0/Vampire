-- Love2D 主入口，协调状态、渲染与更新循环
local state = require('state')
local player = require('player')
local weapons = require('weapons')
local projectiles = require('projectiles')
local enemies = require('enemies')
local pickups = require('pickups')
local upgrades = require('upgrades')
local director = require('director')
local draw = require('draw')
local debugmenu = require('debugmenu')
local augments = require('augments')
local logger = require('logger')
local benchmark = require('benchmark')
local arsenal = require('arsenal')
local bloom = require('bloom')
local vfx = require('vfx')
local rooms = require('rooms')
local testmode = require('testmode')
local testScenarios = require('test_scenarios')
local abilities = require('abilities')
local pets = require('pets')
local world = require('world')
local mission = require('mission')
local ui = require('ui')
local hud = require('ui.screens.hud')
local levelupScreen = require('ui.screens.levelup')
local shopScreen = require('ui.screens.shop')
local gameoverScreen = require('ui.screens.gameover')
local orbiterScreen = require('ui.screens.orbiter')

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
end

function love.update(dt)
    -- HUD update
    if state.gameState == 'PLAYING' then
        hud.update(state, dt)
    end
    
    -- Update UI system
    ui.update(dt)
    
    if state.gameState == 'ARSENAL' then
        arsenal.update(state, dt)
        return
    end

    if bloom and bloom.update then bloom.update(dt) end
    if bloom and bloom.setParams then
        local desired = (state.runMode == 'explore') and 0.10 or 0.0
        if state._vignetteStrength ~= desired then
            state._vignetteStrength = desired
            bloom.setParams({vignette_strength = desired})
        end
    end
    
    -- Room transition fade (must update even in SHOP/LEVEL_UP to avoid permanent black screen)
    if state.roomTransitionFade and state.roomTransitionFade > 0 then
        state.roomTransitionFade = state.roomTransitionFade - dt * 3  -- Fade out over ~0.33 seconds
        if state.roomTransitionFade < 0 then state.roomTransitionFade = 0 end
    end
    
    -- 升级/死亡界面下暂停主循环
    if state.gameState == 'LEVEL_UP' then
        if not levelupScreen.isActive() then
            levelupScreen.init(state)
        end
        return
    end
    if state.gameState == 'SHOP' then
        if not shopScreen.isActive() then
            shopScreen.init(state)
        end
        return
    end
    if state.gameState == 'ORBITER' then
        orbiterScreen.update(dt)
        -- Also update rooms to detect when orbiter exits
        if state.runMode == 'rooms' then
            rooms.update(state, dt)
        end
        return
    end
    if state.gameState == 'GAME_OVER' or state.gameState == 'GAME_CLEAR' then
        if not gameoverScreen.isActive() then
             gameoverScreen.init(state)
        end
        return
    end

    -- 逐帧衰减屏幕震动
    if state.shakeAmount > 0 then
        state.shakeAmount = math.max(0, state.shakeAmount - dt * 10)
    end

    -- 全局计时与场景效果
    state.gameTimer = state.gameTimer + dt
    -- pickups.updateMagnetSpawns removed
    if state.updateEffects then state.updateEffects(dt) end

    -- 核心更新顺序：玩家 → 武器 → 子弹 → 刷怪
    player.updateFiring(state) -- Update attack/aim state
    player.updateMelee(state, dt) -- Update melee state machine
    abilities.update(state, dt) -- Update ability cooldowns and energy regen
    player.updateMovement(state, dt)
    world.update(state, dt)
    pets.update(state, dt)
    if state.augments and state.augments.update then
        state.augments.update(state, dt)
    end
    weapons.update(state, dt)
    weapons.updateReload(state, dt) -- Tick reload timers
    projectiles.updatePlayerBullets(state, dt)
    projectiles.updateEnemyBullets(state, dt)
    if state.runMode == 'rooms' and not state.testArena and not state.scenarioNoDirector and not state.benchmarkMode then
        rooms.update(state, dt)
    elseif state.runMode == 'explore' and not state.testArena and not state.scenarioNoDirector and not state.benchmarkMode then
        mission.update(state, dt)
    else
        director.update(state, dt)
    end
    enemies.update(state, dt)
    -- 根据移动状态控制玩家动画
    if state.playerAnim then
        if state.player.isMoving then
            if not state.playerAnim.playing then state.playerAnim:play(false) end
            state.playerAnim:update(dt)
        else
            if state.playerAnim.playing then state.playerAnim:stop() end
        end
    end
    player.tickInvincibility(state, dt)
    player.tickRegen(state, dt)
    player.tickShields(state, dt)
    pickups.updateGems(state, dt)
    pickups.updateChests(state, dt)
    pickups.updateFloorPickups(state, dt)
    player.tickTexts(state, dt)
    benchmark.update(state, dt)
end

function love.draw()
    if state.gameState == 'ARSENAL' then
        arsenal.draw(state)
        testmode.draw(state)
        return
    end
    if state.gameState == 'ORBITER' then
        orbiterScreen.draw()
        return
    end
    
    bloom.preDraw()
    -- 渲染世界并叠加调试菜单
    draw.render(state)
    bloom.postDraw(state)

    benchmark.draw(state)
    debugmenu.draw(state)
    testmode.draw(state)
    
    -- Draw UI overlay (on top of everything)
    ui.draw()
end

function love.resize(w, h)
    bloom.resize(w, h)
    ui.resize(w, h)
end

function love.mousemoved(x, y, dx, dy)
    if state.gameState == 'ORBITER' then
        orbiterScreen.mousemoved(x, y, dx, dy)
        return  -- Don't also call ui.mousemoved since orbiter uses same core
    end
    ui.mousemoved(x, y, dx, dy)
end

function love.mousepressed(x, y, button)
    if state.gameState == 'ORBITER' then
        orbiterScreen.mousepressed(x, y, button)
        return  -- Don't also call ui.mousepressed since orbiter uses same core
    end
    if ui.mousepressed(x, y, button) then return end
    -- Other mouse press handling can go here
end

function love.mousereleased(x, y, button)
    if state.gameState == 'ORBITER' then
        orbiterScreen.mousereleased(x, y, button)
        return  -- Don't also call ui.mousereleased since orbiter uses same core
    end
    ui.mousereleased(x, y, button)
end

function love.textinput(text)
    ui.textinput(text)
end

function love.quit()
    -- 退出时尝试刷新日志落盘
    if logger.flushIfActive then logger.flushIfActive(state, 'quit') end
end

local uiDemo = require('ui.demo')

function love.keypressed(key)
    -- UI Demo toggle (F8)
    if uiDemo.keypressed(key) then return end
    -- UI system key handling
    -- Only process UI input during gameplay to avoid blocking Arsenal/Menu inputs
    if state.gameState == 'PLAYING' then
        if ui.keypressed(key) then return end
        
        -- Press ESC to pause/return to Arsenal
        if key == 'escape' then
            -- Reset game state so Arsenal changes can be applied properly
            state.init()
            arsenal.init(state)
            state.gameState = 'ARSENAL'
            arsenal.show(state)
            return
        end
    end
    
    if testmode.keypressed(state, key) then return end
    if state.gameState == 'ARSENAL' then
        if arsenal.keypressed(state, key) then return end
        return
    end

    if state.gameState == 'SHOP' then
        if shopScreen.keypressed(key) then return end
        return
    end
    if state.gameState == 'ORBITER' then
        if orbiterScreen.keypressed(key) then return end
        return
    end
    if state.gameState == 'GAME_OVER' or state.gameState == 'GAME_CLEAR' then
        if gameoverScreen.keypressed(key) then return end
        return
    end
    if key == 'f5' then benchmark.toggle(state) end
    if key == 'v' then vfx.toggle() end

    if player.keypressed and player.keypressed(state, key) then return end

    -- 等级界面：按数字选择升级
    if debugmenu.keypressed(state, key) then return end
    if state.gameState == 'LEVEL_UP' then
        if levelupScreen.keypressed(key) then return end
        return
    end
end
