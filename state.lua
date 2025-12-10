local state = {}

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
end

return state
