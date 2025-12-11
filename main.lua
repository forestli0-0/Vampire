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

function love.load()
    if state.stopMusic then state.stopMusic() end
    state.init()
    weapons.addWeapon(state, 'wand')
    if state.playMusic then state.playMusic() end
    debugmenu.init(state)
    -- Debug combos for testing status synergies (uncomment as needed):
    -- weapons.addWeapon(state, 'oil_bottle')
    -- weapons.addWeapon(state, 'fire_wand')
    -- weapons.addWeapon(state, 'ice_ring')
    -- weapons.addWeapon(state, 'heavy_hammer')
end

function love.update(dt)
    if state.gameState == 'LEVEL_UP' then return end
    if state.gameState == 'GAME_OVER' then
        if love.keyboard.isDown('r') then love.load() end
        return
    end

    if state.shakeAmount > 0 then
        state.shakeAmount = math.max(0, state.shakeAmount - dt * 10)
    end

    state.gameTimer = state.gameTimer + dt
    if state.updateEffects then state.updateEffects(dt) end

    player.updateMovement(state, dt)
    weapons.update(state, dt)
    projectiles.updatePlayerBullets(state, dt)
    projectiles.updateEnemyBullets(state, dt)
    director.update(state, dt)
    enemies.update(state, dt)
    if state.playerAnim then
        if state.player.isMoving then
            if not state.playerAnim.playing then state.playerAnim:play(false) end
            state.playerAnim:update(dt)
        else
            if state.playerAnim.playing then state.playerAnim:stop() end
        end
    end
    player.tickInvincibility(state, dt)
    pickups.updateGems(state, dt)
    pickups.updateChests(state, dt)
    pickups.updateFloorPickups(state, dt)
    player.tickTexts(state, dt)
end

function love.draw()
    draw.render(state)
    debugmenu.draw(state)
end

function love.keypressed(key)
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
