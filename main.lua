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

-- 游戏启动时的初始化（状态、日志、默认武器等）
function love.load()
    if state.stopMusic then state.stopMusic() end
    state.init()
    state.augments = augments
    logger.init(state)
    arsenal.init(state)
    bloom.init(love.graphics.getWidth(), love.graphics.getHeight())
    vfx.init()
    vfx.setBloomEmitter(bloom.isEnabled, bloom.getEmissionCanvas)
    if state.gameState ~= 'ARSENAL' then
        weapons.addWeapon(state, 'wand')
    end
    if state.playMusic then state.playMusic() end
    debugmenu.init(state)
    -- 调试用武器组合：测试状态联动时取消注释
    -- weapons.addWeapon(state, 'oil_bottle')
    -- weapons.addWeapon(state, 'fire_wand')
    -- weapons.addWeapon(state, 'ice_ring')
    -- weapons.addWeapon(state, 'heavy_hammer')
end

function love.update(dt)
    if state.gameState == 'ARSENAL' then
        arsenal.update(state, dt)
        return
    end
    -- 升级/死亡界面下暂停主循环
    if state.gameState == 'LEVEL_UP' then return end
    if state.gameState == 'GAME_OVER' then
        if love.keyboard.isDown('r') then love.load() end
        return
    end
    if state.gameState == 'GAME_CLEAR' then
        if love.keyboard.isDown('r') then love.load() end
        return
    end

    -- 逐帧衰减屏幕震动
    if state.shakeAmount > 0 then
        state.shakeAmount = math.max(0, state.shakeAmount - dt * 10)
    end

    -- 全局计时与场景效果
    state.gameTimer = state.gameTimer + dt
    pickups.updateMagnetSpawns(state, dt)
    if state.updateEffects then state.updateEffects(dt) end

    -- 核心更新顺序：玩家 → 武器 → 子弹 → 刷怪
    player.updateMovement(state, dt)
    if state.augments and state.augments.update then
        state.augments.update(state, dt)
    end
    weapons.update(state, dt)
    projectiles.updatePlayerBullets(state, dt)
    projectiles.updateEnemyBullets(state, dt)
    director.update(state, dt)
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
    pickups.updateGems(state, dt)
    pickups.updateChests(state, dt)
    pickups.updateFloorPickups(state, dt)
    player.tickTexts(state, dt)
    benchmark.update(state, dt)
end

function love.draw()
    if state.gameState == 'ARSENAL' then
        arsenal.draw(state)
        return
    end
    
    bloom.preDraw()
    -- 渲染世界并叠加调试菜单
    draw.render(state)
    bloom.postDraw()

    benchmark.draw(state)
    debugmenu.draw(state)
end

function love.resize(w, h)
    bloom.resize(w, h)
end

function love.quit()
    -- 退出时尝试刷新日志落盘
    if logger.flushIfActive then logger.flushIfActive(state, 'quit') end
end

function love.keypressed(key)
    if state.gameState == 'ARSENAL' then
        if arsenal.keypressed(state, key) then return end
        return
    end
    if key == 'f5' then benchmark.toggle(state) end
    if key == 'b' then bloom.toggle() end
    if key == 'v' then vfx.toggle() end
    -- 等级界面：按数字选择升级
    if debugmenu.keypressed(state, key) then return end
    if state.gameState == 'LEVEL_UP' then
        local idx = tonumber(key)
        if idx and idx >= 1 and idx <= #state.upgradeOptions then
            upgrades.applyUpgrade(state, state.upgradeOptions[idx])
            if state.pendingLevelUps > 0 then
                state.pendingLevelUps = state.pendingLevelUps - 1
                upgrades.generateUpgradeOptions(state)
                state.gameState = 'LEVEL_UP'
            else
                state.gameState = 'PLAYING'
            end
        end
    end
end
