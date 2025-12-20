local animation = require('render.animation')

local assets = {}

local function genBeep(freq, duration)
    duration = duration or 0.1
    local sampleRate = 44100
    local data = love.sound.newSoundData(math.floor(sampleRate * duration), sampleRate, 16, 1)
    for i = 0, data:getSampleCount() - 1 do
        local t = i / sampleRate
        local sample = math.sin(2 * math.pi * freq * t) * 0.2
        data:setSample(i, sample)
    end
    return love.audio.newSource(data, 'static')
end

local function loadSfx(path, fallbackFreq)
    local ok, src = pcall(love.audio.newSource, path, 'static')
    if ok and src then return src end
    return genBeep(fallbackFreq)
end

local function loadMusic(paths)
    for _, path in ipairs(paths or {}) do
        local ok, src = pcall(love.audio.newSource, path, 'stream')
        if ok and src then return src end
    end
    return nil
end

local function loadImage(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then return img end
    return nil
end

local function buildSheetFromFrames(paths)
    local frames = {}
    for _, p in ipairs(paths) do
        local ok, data = pcall(love.image.newImageData, p)
        if ok and data then table.insert(frames, data) end
    end
    if #frames == 0 then return nil end
    local fw, fh = frames[1]:getWidth(), frames[1]:getHeight()
    local sheetData = love.image.newImageData(fw * #frames, fh)
    for i, data in ipairs(frames) do
        sheetData:paste(data, (i - 1) * fw, 0, 0, 0, fw, fh)
    end
    local sheet = love.graphics.newImage(sheetData)
    sheet:setFilter('nearest', 'nearest')
    return sheet, fw, fh
end

local function loadMoveAnimationFromFolder(name, frameCount, fps)
    frameCount = frameCount or 4
    local paths = {}
    for i = 1, frameCount do
        paths[i] = string.format('assets/characters/%s/move_%d.png', name, i)
    end
    local sheet, fw, fh = buildSheetFromFrames(paths)
    if not sheet then return nil end
    local frames = animation.newFramesFromGrid(sheet, fw, fh)
    return animation.newAnimation(sheet, frames, {fps = fps or 8, loop = true})
end

function assets.init(state)
    state.loadMoveAnimationFromFolder = loadMoveAnimationFromFolder

    state.sfx = {
        shoot     = loadSfx('assets/sfx/shoot.wav', 600),
        hit       = loadSfx('assets/sfx/hit.wav', 200),
        gem       = loadSfx('assets/sfx/gem.wav', 1200),
        glass     = loadSfx('assets/sfx/glass.wav', 1000),
        freeze    = loadSfx('assets/sfx/freeze.wav', 500),
        ignite    = loadSfx('assets/sfx/ignite.wav', 900),
        static    = loadSfx('assets/sfx/static.wav', 700),
        bleed     = loadSfx('assets/sfx/bleed.wav', 400),
        explosion = loadSfx('assets/sfx/explosion.wav', 300)
    }
    state.music = loadMusic({
        'assets/music/bgm.ogg','assets/music/bgm.mp3','assets/music/bgm.wav',
        'assets/sfx/bgm.ogg','assets/sfx/bgm.mp3','assets/sfx/bgm.wav'
    })

    function state.playSfx(key)
        local s = state.sfx[key]
        if s and s.clone then
            local ok, src = pcall(function() return s:clone() end)
            if ok and src and src.play then
                local okPlay = pcall(function() src:play() end)
                if okPlay then return end
            end
        end
        if s and s.play then
            local okPlay = pcall(function() s:play() end)
            if okPlay then return end
        end
        print("Play Sound: " .. tostring(key))
    end

    function state.playMusic()
        if state.music and state.music.setLooping then
            state.music:setLooping(true)
            pcall(function() state.music:play() end)
        end
    end

    function state.stopMusic()
        if state.music and state.music.stop then
            pcall(function() state.music:stop() end)
        end
    end

    -- Background tile: load or fall back to a generated pattern.
    local bgTexture = loadImage('assets/tiles/grass.png')
    if bgTexture then
        bgTexture:setFilter('nearest', 'nearest')
        state.bgTile = { image = bgTexture, w = bgTexture:getWidth(), h = bgTexture:getHeight() }
    else
        local tileW, tileH = 64, 64
        local bgData = love.image.newImageData(tileW, tileH)
        for x = 0, tileW - 1 do
            for y = 0, tileH - 1 do
                local n1 = (math.sin(x * 0.18) + math.cos(y * 0.21)) * 0.02
                local n2 = (math.sin((x + y) * 0.08)) * 0.015
                local g = 0.58 + n1 + n2
                local r = 0.18 + n1 * 0.5
                bgData:setPixel(x, y, r, g, 0.2, 1)
            end
        end
        for i = 0, tileW - 1, 8 do
            for j = 0, tileH - 1, 8 do
                bgData:setPixel(i, j, 0.22, 0.82, 0.24, 1)
            end
        end
        for i = 0, tileW - 1, 16 do
            for j = 0, tileH - 1, 2 do
                local y = (j + math.floor(i * 0.5)) % tileH
                bgData:setPixel(i, y, 0.16, 0.46, 0.16, 1)
            end
        end
        bgTexture = love.graphics.newImage(bgData)
        bgTexture:setFilter('nearest', 'nearest')
        state.bgTile = { image = bgTexture, w = tileW, h = tileH }
    end

    -- Player animation: load from assets or generate a placeholder sheet.
    local playerAnim = loadMoveAnimationFromFolder('player', 4, 8)
    if playerAnim then
        state.playerAnim = playerAnim
    else
        local frameW, frameH = 32, 32
        local animDuration = 0.8
        local cols, rows = 6, 2
        local sheetData = love.image.newImageData(frameW * cols, frameH * rows)
        for row = 0, rows - 1 do
            for col = 0, cols - 1 do
                local baseR = 0.45 + 0.05 * row
                local baseG = 0.75 - 0.04 * col
                local baseB = 0.55
                for x = col * frameW, (col + 1) * frameW - 1 do
                    for y = row * frameH, (row + 1) * frameH - 1 do
                        local xf = (x - col * frameW) / frameW
                        local yf = (y - row * frameH) / frameH
                        local shade = (math.sin((col + 1) * 0.6) * 0.05) + (yf * 0.08)
                        local r = baseR + shade
                        local g = baseG - shade * 0.5
                        local b = baseB + shade * 0.4
                        if yf < 0.35 and xf > 0.3 and xf < 0.7 then
                            r = r + 0.1; g = g + 0.1; b = b + 0.1
                        end
                        if yf > 0.75 then
                            r = r - 0.05 * math.sin(col + row)
                            g = g - 0.05 * math.cos(col + row)
                        end
                        sheetData:setPixel(x, y, r, g, b, 1)
                    end
                end
                for x = col * frameW, (col + 1) * frameW - 1 do
                    sheetData:setPixel(x, row * frameH, 0, 0, 0, 1)
                    sheetData:setPixel(x, (row + 1) * frameH - 1, 0, 0, 0, 1)
                end
                for y = row * frameH, (row + 1) * frameH - 1 do
                    sheetData:setPixel(col * frameW, y, 0, 0, 0, 1)
                    sheetData:setPixel((col + 1) * frameW - 1, y, 0, 0, 0, 1)
                end
            end
        end
        local sheet = love.graphics.newImage(sheetData)
        sheet:setFilter('nearest', 'nearest')
        state.playerAnim = animation.newAnimation(sheet, frameW, frameH, animDuration)
    end

    local weaponKeys = {
        'wand','holy_wand','axe','death_spiral','fire_wand','oil_bottle','heavy_hammer','dagger','static_orb','garlic','ice_ring',
        'soul_eater','thousand_edge','hellfire','absolute_zero','thunder_loop','earthquake'
    }

    state.projectileTuning = {
        default = { size = 6, spriteScale = 5 },
        axe = { size = 6, spriteScale = 3 },
        -- death_spiral = { size = 14, spriteScale = 2 },
        oil_bottle = { size = 6, spriteScale = 3 },
        heavy_hammer = { size = 6, spriteScale = 3 }
    }

    state.weaponSprites = {}
    state.weaponSpriteScale = {}
    for _, key in ipairs(weaponKeys) do
        local img = loadImage(string.format('assets/weapons/%s.png', key))
        if img then
            img:setFilter('nearest', 'nearest')
            state.weaponSprites[key] = img
            local tune = (state.projectileTuning and state.projectileTuning[key]) or (state.projectileTuning and state.projectileTuning.default)
            state.weaponSpriteScale[key] = (tune and tune.spriteScale) or 5
        end
    end

    state.pickupSprites = {}
    state.pickupSpriteScale = {}
    local chestImg = loadImage('assets/pickups/chest.png')
    if chestImg then
        chestImg:setFilter('nearest', 'nearest')
        state.pickupSprites['chest'] = chestImg
    end
    local function loadPickup(key, scale)
        local img = loadImage(string.format('assets/pickups/%s.png', key))
        if img then
            img:setFilter('nearest', 'nearest')
            state.pickupSprites[key] = img
            state.pickupSpriteScale[key] = scale or 1
        end
    end
    loadPickup('gem', 0.01)

    state.enemySprites = {}
    local plantBullet = loadImage('assets/enemies/plant_bullet.png')
    if plantBullet then
        plantBullet:setFilter('nearest', 'nearest')
        state.enemySprites['plant_bullet'] = plantBullet
    end

    state.enemySprites['skeleton_frames'] = {}
    for i = 1, 4 do
        local img = loadImage('assets/characters/skeleton/move_' .. i .. '.PNG')
        if img then
            img:setFilter('nearest', 'nearest')
            table.insert(state.enemySprites['skeleton_frames'], img)
        end
    end
    if #state.enemySprites['skeleton_frames'] == 0 then
        local fallback = loadImage('assets/characters/skeleton/move_1.PNG')
        if fallback then
            fallback:setFilter('nearest', 'nearest')
            table.insert(state.enemySprites['skeleton_frames'], fallback)
        end
    end
end

return assets
