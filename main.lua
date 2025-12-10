local state = require('state')
local player = require('player')
local weapons = require('weapons')
local projectiles = require('projectiles')
local enemies = require('enemies')
local pickups = require('pickups')
local upgrades = require('upgrades')
local director = require('director')
local draw = require('draw')

function love.load()
    state.init()
    weapons.addWeapon(state, 'wand')
end

function love.update(dt)
    if state.gameState == 'LEVEL_UP' then return end
    if state.gameState == 'GAME_OVER' then
        if love.keyboard.isDown('r') then love.load() end
        return
    end

    state.gameTimer = state.gameTimer + dt

    player.updateMovement(state, dt)
    weapons.update(state, dt)
    projectiles.updatePlayerBullets(state, dt)
    projectiles.updateEnemyBullets(state, dt)
    director.update(state, dt)
    enemies.update(state, dt)
    player.tickInvincibility(state, dt)
    pickups.updateGems(state, dt)
    pickups.updateChests(state, dt)
    pickups.updateFloorPickups(state, dt)
    player.tickTexts(state, dt)
end

function love.draw()
    draw.render(state)
end

function love.keypressed(key)
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
