local state = {}

local animation = require('animation')

function state.init()
    math.randomseed(os.time())

    state.gameState = 'PLAYING'
    state.pendingLevelUps = 0
    state.gameTimer = 0
    state.font = love.graphics.newFont(14)
    state.titleFont = love.graphics.newFont(24)

    state.player = {
        x = 400, y = 300,
        size = 20,
        hp = 100, maxHp = 100,
        level = 1, xp = 0, xpToNextLevel = 10,
        invincibleTimer = 0,
        stats = {
            moveSpeed = 180,
            might = 1.0,
            cooldown = 1.0,
            area = 1.0,
            speed = 1.0,
            pickupRange = 80
        }
    }

    state.catalog = {
        wand = {
            type = 'weapon', name = "Magic Wand",
            desc = "Fires at nearest enemy.",
            maxLevel = 5,
            base = { damage=10, cd=0.8, speed=400 },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='holy_wand', require='tome' }
        },
        holy_wand = {
            type = 'weapon', name = "Holy Wand",
            desc = "Evolved Magic Wand. Fires rapidly.",
            maxLevel = 1,
            base = { damage=15, cd=0.1, speed=600 },
            onUpgrade = function(w) end
        },
        garlic = {
            type = 'weapon', name = "Garlic",
            desc = "Damages enemies nearby.",
            maxLevel = 5,
            base = { damage=3, cd=0.2, radius=70, knockback=30 },
            onUpgrade = function(w) w.damage = w.damage + 2; w.radius = w.radius + 10 end
        },
        axe = {
            type = 'weapon', name = "Axe",
            desc = "High damage, high arc.",
            maxLevel = 5,
            base = { damage=30, cd=1.2, speed=450, area=1.5 },
            onUpgrade = function(w) w.damage = w.damage + 10; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='death_spiral', require='spinach' }
        },
        death_spiral = {
            type = 'weapon', name = "Death Spiral",
            desc = "Evolved Axe. Spirals out.",
            maxLevel = 1,
            base = { damage=40, cd=1.0, speed=500, area=2.0 },
            onUpgrade = function(w) end
        },
        spinach = {
            type = 'passive', name = "Spinach",
            desc = "Increases damage by 10%.",
            maxLevel = 5,
            onUpgrade = function() state.player.stats.might = state.player.stats.might + 0.1 end
        },
        tome = {
            type = 'passive', name = "Empty Tome",
            desc = "Reduces cooldowns by 8%.",
            maxLevel = 5,
            onUpgrade = function() state.player.stats.cooldown = state.player.stats.cooldown * 0.92 end
        },
        boots = {
            type = 'passive', name = "Boots",
            desc = "Increases movement speed.",
            maxLevel = 5,
            onUpgrade = function() state.player.stats.moveSpeed = state.player.stats.moveSpeed * 1.1 end
        }
    }

    state.inventory = { weapons = {}, passives = {} }
    state.enemies = {}
    state.bullets = {}
    state.enemyBullets = {}
    state.gems = {}
    state.floorPickups = {}
    state.texts = {}
    state.chests = {}
    state.upgradeOptions = {}

    state.spawnTimer = 0
    state.camera = { x = 0, y = 0 }
    state.directorState = { event60 = false, event120 = false }
    state.shakeAmount = 0

    -- 简单音效加载（若文件不存在则生成占位音）
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
    local function loadSfx(name, fallbackFreq)
        local ok, src = pcall(love.audio.newSource, name, 'static')
        if ok and src then return src end
        return genBeep(fallbackFreq)
    end
    state.sfx = {
        shoot = loadSfx('shoot.wav', 600),
        hit   = loadSfx('hit.wav', 200),
        gem   = loadSfx('gem.wav', 1200)
    }
    function state.playSfx(key)
        local s = state.sfx[key]
        if s then s:clone():play() end
    end

    -- 背景平铺纹理（简单生成一张无缝草地占位图）
    local tileW, tileH = 64, 64
    local bgData = love.image.newImageData(tileW, tileH)
    for x = 0, tileW - 1 do
        for y = 0, tileH - 1 do
            local noise = (math.sin(x * 0.2) + math.cos(y * 0.2)) * 0.02
            local g = 0.65 + noise
            bgData:setPixel(x, y, 0.2, g, 0.2, 1)
        end
    end
    for i = 0, tileW - 1, 8 do
        for j = 0, tileH - 1, 8 do
            bgData:setPixel(i, j, 0.25, 0.8, 0.25, 1)
        end
    end
    local bgTexture = love.graphics.newImage(bgData)
    bgTexture:setFilter('nearest', 'nearest')
    state.bgTile = { image = bgTexture, w = tileW, h = tileH }

    -- 简单生成一张4帧占位跑动图集
    local frameW, frameH, frames = 32, 32, 4
    local sheetData = love.image.newImageData(frameW * frames, frameH)
    for f = 0, frames - 1 do
        local r = 0.5 + 0.1 * f
        local g = 0.8 - 0.1 * f
        local b = 0.6
        for x = f * frameW, (f + 1) * frameW - 1 do
            for y = 0, frameH - 1 do
                sheetData:setPixel(x, y, r, g, b, 1)
            end
        end
        -- 加一点竖条纹当作动作区别
        for x = f * frameW + 10, f * frameW + 12 do
            for y = 4, frameH - 5 do
                sheetData:setPixel(x, y, 1, 1, 1, 1)
            end
        end
    end
    local sheet = love.graphics.newImage(sheetData)
    sheet:setFilter('nearest', 'nearest')
    state.playerAnim = animation.newAnimation(sheet, frameW, frameH, 0.6)
end

return state
