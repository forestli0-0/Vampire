local abilities = require('gameplay.abilities')
local arsenal = require('core.arsenal')
local benchmark = require('debug.benchmark')
local bloom = require('render.bloom')
local chapter = require('world.chapter')
local debugmenu = require('debug.debugmenu')
local director = require('world.director')
local draw = require('render.draw')
local enemies = require('gameplay.enemies')
local gameoverScreen = require('ui.screens.gameover')
local hud = require('ui.screens.hud')
local ingameMenu = require('ui.screens.ingame_menu')
local levelupScreen = require('ui.screens.levelup')
local minimap = require('ui.minimap')
local mission = require('world.mission')
local pets = require('gameplay.pets')
local pickups = require('systems.pickups')
local player = require('gameplay.player')
local projectiles = require('gameplay.projectiles')
local rooms = require('world.rooms')
local shopScreen = require('ui.screens.shop')
local spawner = require('world.spawner')
local testmode = require('debug.testmode')
local ui = require('ui')
local uiDemo = require('ui.demo')
local pipeline = require('render.pipeline')
local vfx = require('render.vfx')
local weapons = require('gameplay.weapons')
local world = require('world.world')

local scenes = {}

local currentId = nil
local currentScene = nil

local handlers = {}

local function updatePlaying(state, dt)
    if ingameMenu.isActive() then
        ingameMenu.update(dt)
        return
    end

    hud.update(state, dt)
    ui.update(dt)

    if bloom and bloom.update then bloom.update(dt) end
    if bloom and bloom.setParams then
        local desired = (state.runMode == 'explore') and 0.10 or 0.0
        if state._vignetteStrength ~= desired then
            state._vignetteStrength = desired
            bloom.setParams({vignette_strength = desired})
        end
    end

    if state.roomTransitionFade and state.roomTransitionFade > 0 then
        state.roomTransitionFade = state.roomTransitionFade - dt * 3
        if state.roomTransitionFade < 0 then state.roomTransitionFade = 0 end
    end

    if state.shakeAmount > 0 then
        state.shakeAmount = math.max(0, state.shakeAmount - dt * 10)
    end

    state.gameTimer = state.gameTimer + dt
    if state.updateEffects then state.updateEffects(dt) end

    player.updateFiring(state)
    player.updateMelee(state, dt)
    abilities.update(state, dt)
    player.updateMovement(state, dt)
    world.update(state, dt)
    pets.update(state, dt)
    if state.augments and state.augments.update then
        state.augments.update(state, dt)
    end
    weapons.update(state, dt)
    weapons.updateReload(state, dt)
    projectiles.updatePlayerBullets(state, dt)
    projectiles.updateEnemyBullets(state, dt)
    if state.runMode == 'chapter' and state.chapterMap then
        -- Chapter mode: use chapter spawner
        spawner.update(state, state.chapterMap, dt)
        spawner.checkRoomClear(state, state.chapterMap)
        spawner.spawnBoss(state, state.chapterMap)
        minimap.update(state, state.chapterMap, dt)
    elseif state.runMode == 'rooms' and not state.testArena and not state.scenarioNoDirector and not state.benchmarkMode then
        rooms.update(state, dt)
    elseif state.runMode == 'explore' and not state.testArena and not state.scenarioNoDirector and not state.benchmarkMode then
        mission.update(state, dt)
    else
        director.update(state, dt)
    end
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
    player.tickRegen(state, dt)
    player.tickShields(state, dt)
    pickups.updateGems(state, dt)
    pickups.updateChests(state, dt)
    pickups.updateFloorPickups(state, dt)
    player.tickTexts(state, dt)
    benchmark.update(state, dt)
end

local function updateArsenal(state, dt)
    ui.update(dt)
    arsenal.update(state, dt)
end

local function updateLevelUp(state, dt)
    ui.update(dt)
    if not levelupScreen.isActive() then
        levelupScreen.init(state)
    end
end

local function updateShop(state, dt)
    ui.update(dt)
    if not shopScreen.isActive() then
        shopScreen.init(state)
    end
end

local function updateGameOver(state, dt)
    ui.update(dt)
    if not gameoverScreen.isActive() then
        gameoverScreen.init(state)
    end
end

local function drawWorld(state)
    if state.shakeAmount and state.shakeAmount > 0 then
        state._shakeOffsetX = love.math.random() * state.shakeAmount
        state._shakeOffsetY = love.math.random() * state.shakeAmount
    else
        state._shakeOffsetX = nil
        state._shakeOffsetY = nil
    end

    pipeline.beginFrame()
    pipeline.drawBase(function()
        draw.renderBase(state)
    end)
    pipeline.drawEmissive(function()
        draw.renderEmissive(state)
        if ui.drawEmissive then
            ui.drawEmissive()
        end
        return true
    end)
    
    -- Draw dynamic lights (collected during renderEmissive)
    local camX = state.camera and state.camera.x or 0
    local camY = state.camera and state.camera.y or 0
    pipeline.drawLights(camX, camY)
    
    pipeline.present(state)
    pipeline.drawEmissiveStatsOverlay(state.font)

    benchmark.draw(state)
    debugmenu.draw(state)
    testmode.draw(state)

    pipeline.drawUI(function()
        ui.draw()
        -- Draw minimap for chapter mode (after UI so it's on top)
        if state.runMode == 'chapter' and state.chapterMap then
            hud.drawMinimap(state)
        end
    end)
end

local function drawArsenal(state)
    arsenal.draw(state)
    testmode.draw(state)
end

handlers.PLAYING = {update = updatePlaying, draw = drawWorld}
handlers.ARSENAL = {update = updateArsenal, draw = drawArsenal}
handlers.LEVEL_UP = {update = updateLevelUp, draw = drawWorld}
handlers.SHOP = {update = updateShop, draw = drawWorld}
handlers.GAME_OVER = {update = updateGameOver, draw = drawWorld}
handlers.GAME_CLEAR = handlers.GAME_OVER

local function setCurrent(state)
    local nextId = (state and state.gameState) or 'ARSENAL'
    if nextId == currentId then return end

    if currentScene and currentScene.exit then
        currentScene.exit(state)
    end

    currentId = nextId
    currentScene = handlers[currentId] or handlers.PLAYING

    if currentScene and currentScene.enter then
        currentScene.enter(state)
    end
end

function scenes.init(state)
    setCurrent(state)
end

function scenes.sync(state)
    setCurrent(state)
end

function scenes.update(state, dt)
    if not currentScene then setCurrent(state) end
    if currentScene and currentScene.update then
        currentScene.update(state, dt)
    end
end

function scenes.draw(state)
    if not currentScene then setCurrent(state) end
    if currentScene and currentScene.draw then
        currentScene.draw(state)
    end
end

function scenes.resize(state, w, h)
    pipeline.resize(w, h)
    ui.resize(w, h)
end

function scenes.mousemoved(state, x, y, dx, dy)
    if state.gameState == 'PLAYING' and ingameMenu.isActive() then
        ingameMenu.mousemoved(x, y, dx, dy)
        return
    end
    ui.mousemoved(x, y, dx, dy)
end

function scenes.mousepressed(state, x, y, button)
    if state.gameState == 'PLAYING' and ingameMenu.isActive() then
        ingameMenu.mousepressed(x, y, button)
        return
    end
    if ui.mousepressed(x, y, button) then return end
end

function scenes.mousereleased(state, x, y, button)
    if state.gameState == 'PLAYING' and ingameMenu.isActive() then
        ingameMenu.mousereleased(x, y, button)
        return
    end
    ui.mousereleased(x, y, button)
end

function scenes.keypressed(state, key, scancode, isrepeat)
    if uiDemo.keypressed(key) then return true end

    if state.gameState == 'PLAYING' then
        if key == 'tab' then
            ingameMenu.toggle(state)
            return true
        end

        if ingameMenu.isActive() then
            if ingameMenu.keypressed(key) then return true end
            return true
        end

        if ui.keypressed(key) then return true end

        if key == 'escape' then
            state.init()
            arsenal.init(state)
            state.gameState = 'ARSENAL'
            arsenal.show(state)
            return true
        end
    end

    if testmode.keypressed(state, key) then return true end
    if state.gameState == 'ARSENAL' then
        if arsenal.keypressed(state, key) then return true end
        return true
    end
    if state.gameState == 'SHOP' then
        if shopScreen.keypressed(key) then return true end
        return true
    end
    if state.gameState == 'GAME_OVER' or state.gameState == 'GAME_CLEAR' then
        if gameoverScreen.keypressed(key) then return true end
        return true
    end
    if key == 'f5' then benchmark.toggle(state) end
    if key == 'v' then vfx.toggle() end
    if key == 'f7' then
        pipeline.nextDebugView()
        return true
    end
    if key == 'f9' then
        pipeline.toggleEmissiveStats()
        return true
    end

    if player.keypressed and player.keypressed(state, key) then return true end

    if debugmenu.keypressed(state, key) then return true end
    if state.gameState == 'LEVEL_UP' then
        if levelupScreen.keypressed(key) then return true end
        return true
    end
    return false
end

function scenes.textinput(state, text)
    ui.textinput(text)
end

function scenes.wheelmoved(state, x, y)
    if state.gameState == 'PLAYING' then
        if ingameMenu.isActive() then
            if ingameMenu.wheelmoved then
                ingameMenu.wheelmoved(x, y)
            end
            return
        end
        if y and y ~= 0 then
            -- Scroll up: previous quick ability, scroll down: next
            player.cycleQuickAbility(state, -y)
        end
    end
    ui.wheelmoved(x, y)
end

return scenes
