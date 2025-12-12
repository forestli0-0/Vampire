local state = {}

local animation = require('animation')

function state.init()
    math.randomseed(os.time())

    state.gameState = 'PLAYING'
    state.benchmarkMode = false -- true when running benchmark to suppress level-ups
    state.noLevelUps = false
    state.testArena = false
    state.pendingLevelUps = 0
    state.gameTimer = 0
    state.font = love.graphics.newFont(14)
    state.titleFont = love.graphics.newFont(24)

    state.player = {
        x = 400, y = 300,
        size = 20,
        facing = 1,
        isMoving = false,
        hp = 100, maxHp = 100,
        level = 1, xp = 0, xpToNextLevel = 10,
        invincibleTimer = 0,
        stats = {
            moveSpeed = 180,
            might = 1.0,
            cooldown = 1.0,
            area = 1.0,
            speed = 1.0,
            pickupRange = 80,
            armor = 0,
            regen = 0
        }
    }

    state.catalog = {
        wand = {
            type = 'weapon', name = "Magic Wand",
            desc = "Fires at nearest enemy.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'magic'},
            base = { damage=8, cd=1.2, speed=380, elements={'IMPACT'}, damageBreakdown={IMPACT=1}, critChance=0.05, critMultiplier=1.5, statusChance=0 },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='holy_wand', require='tome' }
        },
        holy_wand = {
            type = 'weapon', name = "Holy Wand",
            desc = "Evolved Magic Wand. Fires rapidly.",
            maxLevel = 1,
            tags = {'weapon', 'projectile', 'magic'},
            base = { damage=15, cd=0.16, speed=600, elements={'IMPACT'}, damageBreakdown={IMPACT=1}, critChance=0.05, critMultiplier=1.5, statusChance=0 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        garlic = {
            type = 'weapon', name = "Garlic",
            desc = "Damages enemies nearby.",
            maxLevel = 5,
            tags = {'weapon', 'area', 'aura', 'magic'},
            base = { damage=3, cd=0.35, radius=70, knockback=30, elements={'IMPACT'}, damageBreakdown={IMPACT=1}, critChance=0.05, critMultiplier=1.5, statusChance=0 },
            onUpgrade = function(w) w.damage = w.damage + 2; w.radius = w.radius + 10 end,
            evolveInfo = { target='soul_eater', require='pummarola' }
        },
        axe = {
            type = 'weapon', name = "Axe",
            desc = "High damage, high arc.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'physical', 'arc'},
            base = { damage=30, cd=1.4, speed=450, area=1.5, elements={'SLASH','IMPACT'}, damageBreakdown={SLASH=7, IMPACT=3}, critChance=0.10, critMultiplier=2.5, statusChance=0 },
            onUpgrade = function(w) w.damage = w.damage + 10; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='death_spiral', require='spinach' }
        },
        death_spiral = {
            type = 'weapon', name = "Death Spiral",
            desc = "Evolved Axe. Spirals out.",
            maxLevel = 1,
            tags = {'weapon', 'projectile', 'physical', 'arc'},
            base = { damage=40, cd=1.2, speed=500, area=2.0, elements={'SLASH','IMPACT'}, damageBreakdown={SLASH=7, IMPACT=3}, critChance=0.10, critMultiplier=2.5, statusChance=0 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        oil_bottle = {
            type = 'weapon', name = "Oil Bottle",
            desc = "Coats enemies in Oil.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'chemical'},
            base = { damage=0, cd=2.0, speed=300, pierce=1, effectType='OIL', size=16, splashRadius=80, duration=6.0, critChance=0.05, critMultiplier=1.5, statusChance=0.8 },
            onUpgrade = function(w) w.cd = w.cd * 0.95 end
        },
        fire_wand = {
            type = 'weapon', name = "Fire Wand",
            desc = "Ignites Oiled enemies.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'fire', 'magic'},
            base = { damage=15, cd=0.9, speed=450, elements={'HEAT'}, damageBreakdown={HEAT=1}, splashRadius=70, critChance=0.05, critMultiplier=1.5, statusChance=0.3 },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.95 end,
            evolveInfo = { target='hellfire', require='candelabrador' }
        },
        ice_ring = {
            type = 'weapon', name = "Ice Ring",
            desc = "Chills nearby enemies, stacking to Freeze.",
            maxLevel = 5,
            tags = {'weapon', 'area', 'magic', 'ice'},
            base = { damage=2, cd=2.5, radius=100, duration=6.0, elements={'COLD'}, damageBreakdown={COLD=1}, critChance=0.05, critMultiplier=1.5, statusChance=0.3 },
            onUpgrade = function(w) w.radius = w.radius + 10; w.cd = w.cd * 0.95 end,
            evolveInfo = { target='absolute_zero', require='spellbinder' }
        },
        heavy_hammer = {
            type = 'weapon', name = "Warhammer",
            desc = "Shatters Frozen enemies for 3x Damage.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'physical', 'heavy'},
            base = { damage=40, cd=2.0, speed=220, knockback=100, effectType='HEAVY', elements={'IMPACT'}, damageBreakdown={IMPACT=1}, size=16, critChance=0.05, critMultiplier=1.5, statusChance=0.5 },
            onUpgrade = function(w) w.damage = w.damage + 10; w.cd = w.cd * 0.9 end,
            evolveInfo = { target='earthquake', require='armor' }
        },
        dagger = {
            type = 'weapon', name = "Throwing Knife",
            desc = "Applies Slash Bleed that bypasses armor.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'physical', 'fast'},
            base = { damage=4, cd=0.18, speed=600, elements={'SLASH'}, damageBreakdown={SLASH=1}, critChance=0.20, critMultiplier=2.0, statusChance=0.2 },
            onUpgrade = function(w) w.damage = w.damage + 2 end,
            evolveInfo = { target='thousand_edge', require='bracer' }
        },
        static_orb = {
            type = 'weapon', name = "Static Orb",
            desc = "Electrocutes enemies, dealing AOE DoT and stunning.",
            maxLevel = 5,
            tags = {'weapon', 'projectile', 'magic', 'electric'},
            base = { damage=6, cd=1.25, speed=380, elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1}, duration=3.0, staticRange=160, chain=4, critChance=0.05, critMultiplier=1.5, statusChance=0.4 },
            onUpgrade = function(w) w.damage = w.damage + 3; w.cd = w.cd * 0.95 end,
            evolveInfo = { target='thunder_loop', require='duplicator' }
        },
        soul_eater = {
            type = 'weapon', name = "Soul Eater",
            desc = "Evolved Garlic. Huge aura that heals on hit.",
            maxLevel = 1,
            tags = {'weapon', 'area', 'aura', 'magic'},
            base = { damage=8, cd=0.3, radius=130, knockback=50, lifesteal=0.4, area=1.5, elements={'IMPACT'}, damageBreakdown={IMPACT=1}, critChance=0.05, critMultiplier=1.5, statusChance=0 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        thousand_edge = {
            type = 'weapon', name = "Thousand Edge",
            desc = "Evolved Throwing Knife. Rapid endless barrage.",
            maxLevel = 1,
            tags = {'weapon', 'projectile', 'physical', 'fast'},
            base = { damage=7, cd=0.05, speed=650, elements={'SLASH'}, damageBreakdown={SLASH=1}, pierce=6, amount=1, critChance=0.20, critMultiplier=2.0, statusChance=0.2 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        hellfire = {
            type = 'weapon', name = "Hellfire",
            desc = "Evolved Fire Wand. Giant piercing fireballs.",
            maxLevel = 1,
            tags = {'weapon', 'projectile', 'fire', 'magic'},
            base = { damage=40, cd=0.6, speed=520, elements={'HEAT'}, damageBreakdown={HEAT=1}, splashRadius=140, pierce=12, size=18, area=1.3, life=3.0, statusChance=0.5 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        absolute_zero = {
            type = 'weapon', name = "Absolute Zero",
            desc = "Evolved Ice Ring. Persistent blizzard that chills and freezes foes.",
            maxLevel = 1,
            tags = {'weapon', 'area', 'magic', 'ice'},
            base = { damage=5, cd=2.2, radius=160, duration=2.5, elements={'COLD'}, damageBreakdown={COLD=1}, area=1.2, statusChance=0.6 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        thunder_loop = {
            type = 'weapon', name = "Thunder Loop",
            desc = "Evolved Static Orb. Stronger, larger electric fields.",
            maxLevel = 1,
            tags = {'weapon', 'projectile', 'magic', 'electric'},
            base = { damage=10, cd=1.1, speed=420, elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1}, duration=3.0, staticRange=220, pierce=1, amount=1, chain=10, allowRepeat=true, statusChance=0.5 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        earthquake = {
            type = 'weapon', name = "Earthquake",
            desc = "Evolved Warhammer. Quakes stun everything on screen.",
            maxLevel = 1,
            tags = {'weapon', 'area', 'physical', 'heavy'},
            base = { damage=60, cd=2.5, area=2.2, knockback=120, effectType='HEAVY', elements={'IMPACT'}, damageBreakdown={IMPACT=1}, duration=0.6, statusChance=0.6 },
            evolvedOnly = true,
            onUpgrade = function(w) end
        },
        spinach = {
            type = 'passive', name = "Spinach",
            desc = "Increases damage of tagged weapons by 10%.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { damage = 0.1 }
        },
        tome = {
            type = 'passive', name = "Empty Tome",
            desc = "Reduces cooldowns of projectile and magic weapons by 8%.",
            maxLevel = 5,
            targetTags = {'projectile', 'magic'},
            effect = { cd = -0.08 }
        },
        boots = {
            type = 'passive', name = "Boots",
            desc = "Increases movement speed and boosts projectile speed by 5%.",
            maxLevel = 5,
            targetTags = {'projectile'},
            effect = { speed = 0.05 },
            onUpgrade = function() state.player.stats.moveSpeed = state.player.stats.moveSpeed * 1.1 end
        },
        duplicator = {
            type = 'passive', name = "Duplicator",
            desc = "Adds +1 projectile to weapons per level.",
            maxLevel = 2,
            targetTags = {'weapon'},
            effect = { amount = 1 }
        },
        candelabrador = {
            type = 'passive', name = "Candelabrador",
            desc = "Increases weapon area by 10%.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { area = 0.1 }
        },
        spellbinder = {
            type = 'passive', name = "Spellbinder",
            desc = "Extends weapon duration by 10%.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { duration = 0.1 }
        },
        attractorb = {
            type = 'passive', name = "Attractorb",
            desc = "Greatly increases pickup range.",
            maxLevel = 5,
            targetTags = {'weapon'},
            onUpgrade = function() state.player.stats.pickupRange = state.player.stats.pickupRange + 40 end
        },
        pummarola = {
            type = 'passive', name = "Pummarola",
            desc = "Regenerates health over time.",
            maxLevel = 5,
            targetTags = {'weapon'},
            onUpgrade = function()
                state.player.stats.regen = (state.player.stats.regen or 0) + 0.25
                state.player.hp = math.min(state.player.maxHp, state.player.hp + 2)
            end
        },
        bracer = {
            type = 'passive', name = "Bracer",
            desc = "Increases projectile speed.",
            maxLevel = 5,
            targetTags = {'projectile', 'physical', 'fast'},
            effect = { speed = 0.08 }
        },
        armor = {
            type = 'passive', name = "Armor",
            desc = "Reduces incoming damage.",
            maxLevel = 5,
            targetTags = {'weapon'},
            onUpgrade = function() state.player.stats.armor = (state.player.stats.armor or 0) + 1 end
        },
        clover = {
            type = 'passive', name = "Clover",
            desc = "Increases Critical Hit Chance by 10%.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { critChance = 0.10 }
        },
        skull = {
            type = 'passive', name = "Titanium Skull",
            desc = "Increases Critical Damage by 20%.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { critMultiplier = 0.20 }
        },
        venom_vial = {
            type = 'passive', name = "Venom Vial",
            desc = "Increases Status Effect Chance by 20%.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { statusChance = 0.20 }
        },

        -- Warframe-style Mods (per-run, currently global)
        mod_serration = {
            type = 'mod', name = "Serration",
            desc = "+15% Damage per rank.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { damage = 0.15 }
        },
        mod_split_chamber = {
            type = 'mod', name = "Split Chamber",
            desc = "+1 Multishot per rank.",
            maxLevel = 3,
            targetTags = {'weapon', 'projectile'},
            effect = { amount = 1 }
        },
        mod_point_strike = {
            type = 'mod', name = "Point Strike",
            desc = "+10% Crit Chance per rank.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { critChance = 0.10 }
        },
        mod_vital_sense = {
            type = 'mod', name = "Vital Sense",
            desc = "+20% Crit Damage per rank.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { critMultiplier = 0.20 }
        },
        mod_status_matrix = {
            type = 'mod', name = "Status Matrix",
            desc = "+10% Status Chance per rank.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { statusChance = 0.10 }
        },
        mod_heated_charge = {
            type = 'mod', name = "Heated Charge",
            desc = "Adds Heat damage.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { damage = 0.05 },
            addElements = { HEAT = 1 }
        },
        mod_cryogenic_rounds = {
            type = 'mod', name = "Cryogenic Rounds",
            desc = "Adds Cold damage.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { damage = 0.05 },
            addElements = { COLD = 1 }
        },
        mod_stormbringer = {
            type = 'mod', name = "Stormbringer",
            desc = "Adds Electric damage.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { damage = 0.05 },
            addElements = { ELECTRIC = 1 }
        },
        mod_infected_clip = {
            type = 'mod', name = "Infected Clip",
            desc = "Adds Toxin damage.",
            maxLevel = 5,
            targetTags = {'weapon'},
            effect = { damage = 0.05 },
            addElements = { TOXIN = 1 }
        }
    }

    state.inventory = { weapons = {}, passives = {}, mods = {}, modOrder = {} }
    state.enemies = {}
    state.bullets = {}
    state.enemyBullets = {}
    state.gems = {}
    state.floorPickups = {}
    state.magnetTimer = 60
    state.texts = {}
    state.chests = {}
    state.upgradeOptions = {}
    state.chainLinks = {}
    state.quakeEffects = {}

    state.spawnTimer = 0
    state.camera = { x = 0, y = 0 }
    state.directorState = { event60 = false, event120 = false }
    state.shakeAmount = 0

    -- 资源加载：先尝试真实素材，缺失时生成占位
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

    -- Build a sheet from individual frame files: move_1.png ... move_N.png
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

    -- 背景平铺纹理：优先加载素材，缺失时用占位生成
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

    -- 玩家动画：优先从角色文件夹加载 move_1.png..move_4.png，缺失时用占位图集
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

    -- Weapon sprites (optional). Missing files are simply skipped.
    local weaponKeys = {
        'wand','holy_wand','axe','death_spiral','fire_wand','oil_bottle','heavy_hammer','dagger','static_orb','garlic','ice_ring',
        'soul_eater','thousand_edge','hellfire','absolute_zero','thunder_loop','earthquake'
    }
    state.weaponSprites = {}
    state.weaponSpriteScale = {}
    for _, key in ipairs(weaponKeys) do
        local img = loadImage(string.format('assets/weapons/%s.png', key))
        if img then
            img:setFilter('nearest', 'nearest')
            state.weaponSprites[key] = img
            state.weaponSpriteScale[key] = 5
        end
    end
    state.weaponSpriteScale['axe'] = 2
    state.weaponSpriteScale['death_spiral'] = 2
    -- 状态特效贴图（3 帧横条）
    state.effectSprites = {}
    state.hitEffects = {}
    local effectScaleOverrides = {
        freeze = 0.4,
        oil = 0.2,
        fire = 0.5,
        static = 0.4,
        bleed = 0.2
    }
    local function loadEffectFrames(name, frameCount)
        frameCount = frameCount or 3
        local frames = {}
        for i = 1, frameCount do
            local img = loadImage(string.format('assets/effects/%s/%d.png', name, i))
            if img then
                img:setFilter('nearest', 'nearest')
                table.insert(frames, img)
            end
        end
        if #frames > 0 then
            local frameW = frames[1]:getWidth()
            local frameH = frames[1]:getHeight()
            local autoScale = frameW > 32 and (32 / frameW) or 1 -- fallback auto downscale
            local defaultScale = effectScaleOverrides[name] or autoScale
            state.effectSprites[name] = {
                frames = frames,
                frameW = frameW,
                frameH = frameH,
                frameCount = #frames,
                duration = 0.3,
                defaultScale = defaultScale
            }
        end
    end
    local effectKeys = {'freeze','oil','fire','static','bleed'}
    for _, k in ipairs(effectKeys) do loadEffectFrames(k, 3) end
    function state.spawnEffect(key, x, y, scale)
        local eff = state.effectSprites[key]
        if not eff then return end
        local useScale = scale or eff.defaultScale or 1
        table.insert(state.hitEffects, {key = key, x = x, y = y, t = 0, duration = eff.duration or 0.3, scale = useScale})
    end
    function state.updateEffects(dt)
        for i = #state.hitEffects, 1, -1 do
            local e = state.hitEffects[i]
            e.t = e.t + dt
            if e.t >= (e.duration or 0.3) then
                table.remove(state.hitEffects, i)
            end
        end
        for i = #state.quakeEffects, 1, -1 do
            local q = state.quakeEffects[i]
            q.t = q.t + dt
            if q.t >= (q.duration or 0.5) then
                table.remove(state.quakeEffects, i)
            end
        end
    end

    -- 宝箱/道具贴图
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
    loadPickup('chicken')
    loadPickup('magnet')
    loadPickup('bomb')
    loadPickup('gem', 0.01) -- adjust this scale if the gem sprite looks too big/small

    -- 敌人子弹贴图
    state.enemySprites = {}
    local plantBullet = loadImage('assets/enemies/plant_bullet.png')
    if plantBullet then
        plantBullet:setFilter('nearest', 'nearest')
        state.enemySprites['plant_bullet'] = plantBullet
    end
end

return state
