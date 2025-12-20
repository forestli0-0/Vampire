local state = {}

local assets = require('assets')
local effects = require('effects')
local progression = require('progression')

local PROFILE_PATH = "profile.lua"

local function serializeLua(value, depth)
    depth = depth or 0
    local t = type(value)
    if t == "table" then
        local parts = {"{"}
        for k, v in pairs(value) do
            local keyStr
            if type(k) == "string" then
                keyStr = string.format("[%q]=", k)
            else
                keyStr = "[" .. tostring(k) .. "]="
            end
            table.insert(parts, string.rep(" ", depth + 2) .. keyStr .. serializeLua(v, depth + 2) .. ",")
        end
        table.insert(parts, string.rep(" ", depth) .. "}")
        return table.concat(parts, "\n")
    elseif t == "string" then
        return string.format("%q", value)
    else
        return tostring(value)
    end
end

local function defaultProfile()
    return {
        modRanks = {},
        -- Weapon-specific mod loadouts (Warframe-like). Each weapon has its own equipped set + ordering.
        weaponMods = {
            wand = {
                equippedMods = {},
                modOrder = {}
            }
        },
        modTargetWeapon = 'wand',

        -- Legacy global mod equip fields (kept for backward compatibility; migrated into weaponMods).
        equippedMods = {},
        modOrder = {},
        ownedMods = {
            mod_serration = true,
            mod_split_chamber = true,
            mod_point_strike = true,
            mod_vital_sense = true,
            mod_status_matrix = true
        },
        currency = 0,

        -- Pets (loadout + light meta progression)
        startPetKey = 'pet_magnet',
        petModules = {},
        petRanks = {},
        
        -- Meta items
        autoTrigger = false -- When true, weapons fire automatically without holding attack key
    }
end

function state.loadProfile()
    local profile = defaultProfile()
    if love and love.filesystem and love.filesystem.load then
        local ok, chunk = pcall(love.filesystem.load, PROFILE_PATH)
        if ok and chunk then
            local ok2, data = pcall(chunk)
            if ok2 and type(data) == "table" then
                profile = data
            end
        end
    end
    profile.modRanks = profile.modRanks or {}
    profile.weaponMods = profile.weaponMods or {}
    profile.modTargetWeapon = profile.modTargetWeapon or 'wand'
    profile.equippedMods = profile.equippedMods or {} -- legacy
    profile.modOrder = profile.modOrder or {} -- legacy
    profile.ownedMods = profile.ownedMods or {}
    if next(profile.ownedMods) == nil then
        for k, v in pairs(defaultProfile().ownedMods) do
            profile.ownedMods[k] = v
        end
    end
    for k, _ in pairs(profile.modRanks) do profile.ownedMods[k] = true end

    -- Migrate legacy global equippedMods/modOrder into weaponMods.wand if no weapon loadouts exist yet.
    if next(profile.weaponMods) == nil then
        local legacyEq = profile.equippedMods or {}
        local legacyOrder = profile.modOrder or {}
        local hasLegacy = (next(legacyEq) ~= nil) or (type(legacyOrder) == 'table' and #legacyOrder > 0)
        if hasLegacy then
            profile.weaponMods.wand = profile.weaponMods.wand or {equippedMods = {}, modOrder = {}}
            local lo = profile.weaponMods.wand
            lo.equippedMods = lo.equippedMods or {}
            lo.modOrder = lo.modOrder or {}

            for k, v in pairs(legacyEq) do
                if v then lo.equippedMods[k] = true end
            end
            for _, k in ipairs(legacyOrder) do
                if legacyEq[k] then
                    table.insert(lo.modOrder, k)
                end
            end
            -- include equipped-but-not-in-order mods deterministically
            local extra = {}
            for k, v in pairs(legacyEq) do
                if v then
                    local found = false
                    for _, ok in ipairs(lo.modOrder) do
                        if ok == k then found = true break end
                    end
                    if not found then table.insert(extra, k) end
                end
            end
            table.sort(extra)
            for _, k in ipairs(extra) do
                table.insert(lo.modOrder, k)
            end
        end
    end

    for _, lo in pairs(profile.weaponMods or {}) do
        for k, _ in pairs((lo and lo.equippedMods) or {}) do
            profile.ownedMods[k] = true
        end
    end
    profile.startPetKey = profile.startPetKey or 'pet_magnet'
    profile.petModules = profile.petModules or {}
    profile.petRanks = profile.petRanks or {}
    profile.currency = profile.currency or 0
    return profile
end

function state.saveProfile(profile)
    if not (love and love.filesystem and love.filesystem.write) then return end
    local data = "return " .. serializeLua(profile or defaultProfile())
    pcall(function() love.filesystem.write(PROFILE_PATH, data) end)
end

function state.applyPersistentMods()
    state.inventory.mods = {} -- legacy (do not apply globally)
    state.inventory.modOrder = {} -- legacy (do not apply globally)
    state.inventory.weaponMods = {}
    if not state.profile then return end
    local ranks = state.profile.modRanks or {}

    for weaponKey, lo in pairs(state.profile.weaponMods or {}) do
        local equipped = (lo and lo.equippedMods) or {}
        local order = (lo and lo.modOrder) or {}

        local entry = {mods = {}, modOrder = {}}

        for _, modKey in ipairs(order) do
            if equipped[modKey] then
                local lvl = ranks[modKey] or 1
                if lvl > 0 then
                    entry.mods[modKey] = lvl
                    table.insert(entry.modOrder, modKey)
                end
            end
        end

        local extra = {}
        for modKey, on in pairs(equipped) do
            if on and not entry.mods[modKey] then
                table.insert(extra, modKey)
            end
        end
        table.sort(extra)
        for _, modKey in ipairs(extra) do
            local lvl = ranks[modKey] or 1
            if lvl > 0 then
                entry.mods[modKey] = lvl
                table.insert(entry.modOrder, modKey)
            end
        end

        state.inventory.weaponMods[weaponKey] = entry
    end
end

function state.gainGold(amount, ctx)
    if state.benchmarkMode then return 0 end
    local base = tonumber(amount) or 0
    base = math.floor(base)
    if base <= 0 then return 0 end

    ctx = ctx or {}
    ctx.kind = ctx.kind or 'gold'
    ctx.amount = base
    ctx.player = ctx.player or state.player
    ctx.t = ctx.t or state.gameTimer or 0

    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onPickup', ctx)
        if ctx.cancel then
            state.augments.dispatch(state, 'pickupCancelled', ctx)
            return 0
        end
    end

    local amt = math.max(0, math.floor(ctx.amount or base))
    if amt <= 0 then return 0 end

    state.runCurrency = (state.runCurrency or 0) + amt

    if ctx.showText ~= false and state.texts then
        local p = ctx.player or state.player or {}
        local x = ctx.x or p.x or 0
        local y = ctx.y or (p.y and (p.y - 60)) or 0
        table.insert(state.texts, {x = x, y = y, text = "+" .. tostring(amt) .. " GOLD", color = {0.95, 0.9, 0.45}, life = ctx.life or 0.9})
    end

    if state and state.augments and state.augments.dispatch then
        ctx.amount = amt
        state.augments.dispatch(state, 'postPickup', ctx)
    end

    return amt
end

function state.init()
    math.randomseed(os.time())

    if love and love.filesystem and love.filesystem.setIdentity then
        pcall(function() love.filesystem.setIdentity("vampire") end)
    end

    state.gameState = 'ARSENAL'
    state.benchmarkMode = false -- true when running benchmark to suppress level-ups
    state.noLevelUps = false
    state.testArena = false
    state.pendingLevelUps = 0
    state.gameTimer = 0
    -- Use Chinese-supporting font for the entire game
    local fontPath = "fonts/ZZGFBHV1.otf"
    local ok, font = pcall(love.graphics.newFont, fontPath, 14)
    if ok then
        state.font = font
    else
        state.font = love.graphics.newFont(14)
    end
    local ok2, titleFont = pcall(love.graphics.newFont, fontPath, 24)
    if ok2 then
        state.titleFont = titleFont
    else
        state.titleFont = love.graphics.newFont(24)
    end

    local xpBase = (progression.defs and progression.defs.xpBase) or 10

    state.player = {
        x = 400, y = 300,
        size = 28,
        facing = 1,
        isMoving = false,
        hp = 100, maxHp = 100,
        shield = 100, maxShield = 100,
        energy = 100, maxEnergy = 100,
        level = 1, xp = 0, xpToNextLevel = xpBase,
        invincibleTimer = 0,
        shieldDelayTimer = 0,
        dash = {charges = 2, maxCharges = 2, rechargeTimer = 0, timer = 0, dx = 1, dy = 0},
        class = 'volt', -- Current class: warrior / mage / beastmaster / volt
        ability = {cooldown = 0, timer = 0}, -- Q skill state
        -- Weapon slots (2-slot system: ranged + melee, with reserved slot for future class passive)
        weaponSlots = {
            ranged = nil,    -- Ranged weapon key (wands, bows, guns, thrown)
            melee = nil,     -- Melee weapon key (hammers, swords, daggers)
            reserved = nil   -- Reserved for future class-specific passive (summoner summons, alchemist potions, etc.)
        },
        activeSlot = 'ranged', -- Currently active weapon slot
        -- Bow charge state (hold to charge arrows)
        bowCharge = {
            isCharging = false,
            startTime = 0,
            chargeTime = 0,
            weaponKey = nil
        },
        -- Sniper extended aim (Shift to aim beyond screen)
        sniperAim = {
            active = false,
            worldX = 0,
            worldY = 0
        },
        stats = {
            moveSpeed = 110,
            might = 1.0,
            cooldown = 1.0,
            area = 1.0,
            speed = 1.0,
            pickupRange = 120,
            armor = 0,
            regen = 0,
            energyRegen = 2.0,
            maxShield = 100,
            maxEnergy = 100,
            
            -- WF Unified Stats
            abilityStrength = 1.0,
            abilityEfficiency = 1.0,
            abilityDuration = 1.0,
            abilityRange = 1.0,

            dashCharges = 1,
            dashCooldown = 3,
            dashDuration = 0.14,     -- seconds of dash movement
            dashDistance = 56,       -- pixels traveled (2x player width)
            dashInvincible = 0.14    -- i-frames (can be >= dashDuration)
        }
    }

    -- Class definitions: base stats, starting weapon, Q ability
    state.classes = {
        warrior = {
            name = "Warrior",
            desc = "Melee focused, high armor. Q: War Cry (AoE knockback + stun)",
            baseStats = {
                maxHp = 120,
                armor = 120,
                moveSpeed = 125,
                might = 1.1,
                maxShield = 80,   -- Warriors rely more on Armor/HP
                maxEnergy = 100,
                dashCharges = 1  -- Standardized to 1 for balance
            },
            startMelee = 'heavy_hammer',  -- Fragor melee
            startRanged = 'lato',       -- Sidearm
            preferredUpgrades = {'hek', 'boltor', 'dual_zoren'},
            ability = {
                name = "War Cry",
                cooldown = 8.0,
                execute = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                    
                    local radius = 180 * rng
                    local r2 = radius * radius
                    local knockForce = 200
                    local stunDuration = 0.8 * dur
                    
                    -- Visual/audio feedback
                    if state.playSfx then state.playSfx('hit') end
                    state.shakeAmount = math.max(state.shakeAmount or 0, 4)
                    
                    -- Hit all enemies in range
                    local ok, calc = pcall(require, 'calculator')
                    if ok and calc then
                        local instance = calc.createInstance({
                            damage = math.floor(25 * str * (p.stats.might or 1)),
                            critChance = 0.1,
                            critMultiplier = 1.5,
                            statusChance = 0.8,
                            effectType = 'HEAVY',
                            effectData = {duration = stunDuration},
                            elements = {'IMPACT'},
                            damageBreakdown = {IMPACT = 1},
                            weaponTags = {'ability', 'area', 'physical'},
                            knock = true,
                            knockForce = knockForce
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            if e and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                    end
                    
                    -- Spawn visual effect
                    if state.spawnEffect then state.spawnEffect('hit', p.x, p.y) end
                    return true
                end
            }
        },
        mage = {
            name = "Mage",
            desc = "Magic focused, low HP. Q: Blink (teleport + i-frames)",
            baseStats = {
                maxHp = 80,
                armor = 25,
                moveSpeed = 145,
                might = 1.0,
                maxShield = 150, -- Mages rely on Shields
                maxEnergy = 200, -- Mages have more Energy
                cooldown = 0.9, -- 10% faster cooldowns
                critChance = 0.1 -- +10% crit chance
            },
            startRanged = 'wand',          -- Magic Wand
            startMelee = 'karyst',     -- Dagger
            preferredUpgrades = {'fire_wand', 'static_orb', 'lanka', 'thunder_loop'},
            ability = {
                name = "Blink",
                cooldown = 5.0,
                execute = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    
                    local distance = 120 * rng
                    
                    -- Get aim direction (movement or facing)
                    local dx, dy = 0, 0
                    if love.keyboard.isDown('w') then dy = dy - 1 end
                    if love.keyboard.isDown('s') then dy = dy + 1 end
                    if love.keyboard.isDown('a') then dx = dx - 1 end
                    if love.keyboard.isDown('d') then dx = dx + 1 end
                    
                    if dx == 0 and dy == 0 then
                        dx = p.facing or 1
                    end
                    
                    -- Normalize
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len > 0 then
                        dx, dy = dx / len, dy / len
                    end
                    
                    -- Teleport
                    local world = state.world
                    local newX = p.x + dx * distance
                    local newY = p.y + dy * distance
                    if world and world.enabled and world.moveCircle then
                        p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, dx * distance, dy * distance)
                    else
                        p.x, p.y = newX, newY
                    end
                    
                    -- Brief invincibility (scales with strength)
                    p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.3 * str)
                    
                    -- Visual effect
                    if state.playSfx then state.playSfx('shoot') end
                    if state.spawnEffect then state.spawnEffect('static', p.x, p.y) end
                    return true
                end
            }
        },
        beastmaster = {
            name = "Beastmaster",
            desc = "Pet focused, balanced. Q: Summon Aid (heal/buff pet)",
            baseStats = {
                maxHp = 100,
                armor = 60,
                moveSpeed = 135,
                might = 1.0,
                statusChance = 0.15, -- +15% status proc chance
                petHpBonus = 0.25  -- +25% pet HP
            },
            startWeapon = 'paris',         -- Bow (silent)
            startSecondary = 'lex',        -- High-damage pistol
            preferredUpgrades = {'dread', 'vectis', 'braton'},
            ability = {
                name = "Summon Aid",
                cooldown = 12.0,
                execute = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                    
                    local pets = state.pets
                    local pet = pets and pets.list and pets.list[1]
                    
                    if pet and not pet.dead and not pet.downed then
                        -- Heal pet
                        pet.hp = pet.maxHp or 100
                        
                        -- Temporary buff (stored on pet, scales with strength/duration)
                        pet.buffTimer = (pet.buffTimer or 0) + 6.0 * dur
                        pet.buffDamage = 1.0 + 1.0 * str  -- 2x damage at 100% str
                        pet.buffCooldown = 0.5  -- 50% faster ability
                        
                        if state.playSfx then state.playSfx('shoot') end
                        if state.spawnEffect then state.spawnEffect('heal', pet.x, pet.y) end
                    elseif pet and pet.downed then
                        -- Instant revive
                        pet.downed = false
                        pet.hp = (pet.maxHp or 100) * 0.5
                        pet.reviveProgress = 0
                        
                        if state.playSfx then state.playSfx('shoot') end
                        if state.spawnEffect then state.spawnEffect('heal', pet.x, pet.y) end
                    else
                        -- No pet, spawn temporary effect around player
                        if state.playSfx then state.playSfx('shoot') end
                        return false -- Don't consume cooldown
                    end
                    return true
                end
            }
        },
        volt = {
            name = "Volt",
            desc = "电系战甲。高护盾/能量，技能强化电击。Q: Shock (链电)",
            baseStats = {
                maxHp = 85,
                armor = 25,
                moveSpeed = 155,           -- Volt is still fastest
                might = 1.0,
                maxShield = 180,           -- High shields
                maxEnergy = 200,           -- High energy for ability spam
                dashCharges = 1,
                abilityStrength = 1.15,    -- +15% ability damage
                statusChance = 0.10        -- +10% electric procs
            },
            startWeapon = 'static_orb',    -- Amprex (chain lightning)
            startSecondary = 'atomos',     -- Energy pistol
            preferredUpgrades = {'lanka', 'thunder_loop', 'atomos', 'braton'},
            ability = {
                name = "Shock",
                cooldown = 4.0,
                execute = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    
                    -- Find nearest enemy
                    local nearestEnemy, nearestDist = nil, math.huge
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy and e.health and e.health > 0 then
                            local dx, dy = e.x - p.x, e.y - p.y
                            local dist = dx * dx + dy * dy
                            if dist < nearestDist then
                                nearestDist = dist
                                nearestEnemy = e
                            end
                        end
                    end
                    
                    if not nearestEnemy then return false end
                    
                    local ok, calc = pcall(require, 'calculator')
                    if ok and calc then
                        local damage = math.floor(35 * str)
                        local chainRange = 150 * rng
                        local chainR2 = chainRange * chainRange
                        local maxChains = 4
                        
                        local instance = calc.createInstance({
                            damage = damage,
                            critChance = 0.15,
                            critMultiplier = 2.0,
                            statusChance = 0.80,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'ability', 'electric'}
                        })
                        
                        -- Chain lightning
                        local hit = {[nearestEnemy] = true}
                        local current = nearestEnemy
                        calc.applyHit(state, current, instance)
                        if state.spawnEffect then state.spawnEffect('static', current.x, current.y, 0.8) end
                        
                        for i = 1, maxChains do
                            local nextEnemy, nextDist = nil, math.huge
                            for _, e in ipairs(state.enemies or {}) do
                                if e and not e.isDummy and not hit[e] and e.health and e.health > 0 then
                                    local dx, dy = e.x - current.x, e.y - current.y
                                    local dist = dx * dx + dy * dy
                                    if dist < chainR2 and dist < nextDist then
                                        nextDist = dist
                                        nextEnemy = e
                                    end
                                end
                            end
                            if nextEnemy then
                                hit[nextEnemy] = true
                                current = nextEnemy
                                calc.applyHit(state, current, instance)
                                if state.spawnEffect then state.spawnEffect('static', current.x, current.y, 0.6) end
                            else
                                break
                            end
                        end
                    end
                    
                    if state.playSfx then state.playSfx('shoot') end
                    return true
                end
            }
        }
    }

    state.catalog = require('data.defs.catalog')
    progression.recompute(state)

    -- WF-style: 2-slot system (ranged + melee) with extra slot reserved for character passive
    state.inventory = {
        weapons = {},  -- Legacy (for backward compat during transition)
        passives = {},
        mods = {},
        modOrder = {},
        weaponMods = {},
        augments = {},
        augmentOrder = {},
        -- New WF weapon slot system
        weaponSlots = {
            ranged = nil,  -- Primary ranged weapon slot
            melee = nil,   -- Melee weapon slot
            extra = nil    -- Reserved for character passive (e.g. dual-wield gunner)
        },
        activeSlot = 'ranged',     -- Currently active weapon slot
        canUseExtraSlot = false    -- Unlocked by specific character passives
    }
    state.augmentState = {}
    state.maxAugmentsPerRun = 4
    state.maxWeaponsPerRun = 2  -- Changed: 2 slots default (ranged + melee)
    -- Mods are loadout-only by default (Warframe-like); in-run power comes from weapons/passives/augments.
    state.allowInRunMods = false

    -- Run economy (resets each run)
    state.runCurrency = 0
    state.shop = nil

    state.profile = state.loadProfile()
    state.applyPersistentMods()
    state.enemies = {}
    state.bullets = {}
    state.enemyBullets = {}
    state.gems = {}
    state.floorPickups = {}
    state.magnetTimer = 60
    state.texts = {}
    state.chests = {}
    state.doors = {}
    state.upgradeOptions = {}
    state.pendingWeaponSwap = nil
    state.pendingUpgradeRequests = {}
    state.activeUpgradeRequest = nil
    state.chainLinks = {}
    state.lightningLinks = {}
    state.quakeEffects = {}

    state.spawnTimer = 0
    state.camera = { x = 0, y = 0 }
    state.directorState = { event60 = false, event120 = false }
    state.shakeAmount = 0

    -- Run structure: 'rooms' (Hades-like room flow) or 'survival' (timed director) or 'explore' (Mission).
    -- Default to Rooms (Dev Mode). Explore is for production content.
    state.runMode = 'rooms'
    state.rooms = {
        enabled = true,
        phase = 'init',
        roomIndex = 0,
        bossRoom = 8,
        -- reward pacing defaults (rooms mode): upgrades mainly come from room rewards + elites, not XP spam.
        useXp = false,          -- legacy VS-style XP orb loop (off by default for Hades-like rooms pacing)
        xpGivesUpgrades = false,
        eliteDropsChests = false,
        eliteRoomBonusUpgrades = 1
    }

    assets.init(state)
    effects.init(state)
end

return state
