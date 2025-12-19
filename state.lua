local state = {}

local animation = require('animation')

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

    state.player = {
        x = 400, y = 300,
        size = 28,
        facing = 1,
        isMoving = false,
        hp = 100, maxHp = 100,
        shield = 100, maxShield = 100,
        energy = 100, maxEnergy = 100,
        level = 1, xp = 0, xpToNextLevel = 10,
        invincibleTimer = 0,
        shieldDelayTimer = 0,
        dash = {charges = 2, maxCharges = 2, rechargeTimer = 0, timer = 0, dx = 1, dy = 0},
        class = 'warrior', -- Current class: warrior / mage / beastmaster
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
            moveSpeed = 140,
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
                armor = 2,
                moveSpeed = 170,
                might = 1.1,
                maxShield = 80,   -- Warriors rely more on Armor/HP
                maxEnergy = 100,
                dashCharges = 1  -- Standardized to 1 for balance
            },
            startWeapon = 'heavy_hammer',  -- Fragor melee
            startSecondary = 'lato',       -- Sidearm
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
                armor = 0,
                moveSpeed = 190,
                might = 1.0,
                maxShield = 150, -- Mages rely on Shields
                maxEnergy = 200, -- Mages have more Energy
                cooldown = 0.9, -- 10% faster cooldowns
                critChance = 0.1 -- +10% crit chance
            },
            startWeapon = 'wand',          -- Magic Wand (legacy energy)
            startSecondary = 'atomos',     -- Energy pistol
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
                armor = 1,
                moveSpeed = 180,
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
                armor = 0,
                moveSpeed = 200,           -- Volt is fast
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

    state.catalog = {
        pet_magnet = {
            type = 'pet', name = "Magnet Pup",
            desc = "Periodic MAGNETIC procs (utility). Module: pulse AoE.",
            maxLevel = 1,
            base = {hp = 60, cooldown = 3.0, speed = 200, size = 16}
        },
        pet_corrosive = {
            type = 'pet', name = "Corrosive Slime",
            desc = "Periodic CORROSIVE procs (armor shred). Module: field AoE.",
            maxLevel = 1,
            base = {hp = 70, cooldown = 3.4, speed = 185, size = 17}
        },
        pet_guardian = {
            type = 'pet', name = "Guardian Wisp",
            desc = "Support: heal or brief barrier. Module: barrier i-frames.",
            maxLevel = 1,
            base = {hp = 55, cooldown = 4.0, speed = 215, size = 15}
        },
        -- Pet Modules (in-run relic-like, non-replaceable once installed)
        pet_module_pulse = {
            type = 'pet_module', name = "Pulse Core",
            desc = "Magnet Pup: ability becomes a short-range pulse that hits multiple enemies.",
            maxLevel = 1,
            requiresPetKey = 'pet_magnet',
            moduleId = 'pulse'
        },
        pet_module_field = {
            type = 'pet_module', name = "Field Core",
            desc = "Corrosive Slime: ability becomes a corrosive field around it.",
            maxLevel = 1,
            requiresPetKey = 'pet_corrosive',
            moduleId = 'field'
        },
        pet_module_barrier = {
            type = 'pet_module', name = "Barrier Core",
            desc = "Guardian Wisp: ability grants a brief barrier instead of healing.",
            maxLevel = 1,
            requiresPetKey = 'pet_guardian',
            moduleId = 'barrier'
        },

        -- Pet Upgrades (in-run growth, stackable)
        pet_upgrade_power = {
            type = 'pet_upgrade', name = "Pet Power",
            desc = "Pet ability deals more damage.",
            maxLevel = 5
        },
        pet_upgrade_overclock = {
            type = 'pet_upgrade', name = "Pet Overclock",
            desc = "Pet ability cooldown reduced.",
            maxLevel = 5
        },
        pet_upgrade_status = {
            type = 'pet_upgrade', name = "Pet Catalyst",
            desc = "Pet applies more status procs per ability.",
            maxLevel = 4
        },
        pet_upgrade_vitality = {
            type = 'pet_upgrade', name = "Pet Vitality",
            desc = "Pet max HP increased.",
            maxLevel = 5
        },
        wand = {
            type = 'weapon', name = "Magic Wand",
            desc = "[Legacy] Energy weapon. Fires at nearest enemy.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',  -- WF category
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.0 },
            legacy = true,  -- Easter egg weapon from VS era
            base = { 
                damage=8, cd=1.2, speed=380, range=600, 
                critChance=0.05, critMultiplier=1.5, statusChance=0,
                magazine=30, maxMagazine=30,
                reserve=120, maxReserve=120,
                reloadTime=1.5
            },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.9 end
        },
        holy_wand = {
            type = 'weapon', name = "Holy Wand",
            desc = "[Legacy] Rapid-fire energy projectiles.",
            maxLevel = 3,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'energy'},
            classWeight = { warrior = 0.3, mage = 2.0, beastmaster = 0.8 },
            rare = true, legacy = true,
            base = { damage=15, cd=0.16, speed=600, range=700, elements={'IMPACT'}, damageBreakdown={IMPACT=1}, critChance=0.05, critMultiplier=1.5, statusChance=0,
                magazine=60, maxMagazine=60, reserve=180, maxReserve=180, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 3 end
        },
        garlic = {
            -- DEPRECATED: VS-style aura weapon
            type = 'deprecated', name = "Garlic",
            desc = "[Removed] VS-style aura weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'AURA',
            tags = {'weapon', 'area', 'aura', 'magic'},
            base = { damage=3, cd=0.35, radius=70, knockback=30 }
        },
        axe = {
            -- DEPRECATED: VS-style random projectile
            type = 'deprecated', name = "Axe",
            desc = "[Removed] VS-style thrown weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_RANDOM',
            tags = {'weapon', 'projectile', 'physical', 'arc'},
            base = { damage=30, cd=1.4, speed=450, area=1.5 }
        },
        death_spiral = {
            -- DEPRECATED: Will be reimplemented as ability
            type = 'deprecated', name = "Death Spiral",
            desc = "[Removed] Will be reimplemented as ability.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_RADIAL',
            tags = {'weapon', 'projectile', 'physical', 'arc'},
            base = { damage=40, cd=1.2, speed=500, area=2.0 }
        },
        oil_bottle = {
            -- RESERVED for specialized Pet content in future.
            type = 'reserved', name = "Oil Bottle",
            desc = "Coats enemies in Oil.",
            maxLevel = 5,
            hidden = true,
            behavior = 'SHOOT_NEAREST',
            behaviorParams = {rotate = false},
            tags = {'weapon', 'projectile', 'chemical'},
            base = { damage=0, cd=2.0, speed=300, range=700, pierce=1, effectType='OIL', size=12, splashRadius=80, duration=6.0, critChance=0.05, critMultiplier=1.5, statusChance=0.8 },
            onUpgrade = function(w) w.cd = w.cd * 0.95 end
        },
        fire_wand = {
            type = 'weapon', name = "Fire Wand",
            desc = "[Legacy] Energy weapon with heat damage.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'fire', 'magic', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.0 },
            legacy = true,
            base = { damage=15, cd=0.9, speed=450, range=700, elements={'HEAT'}, damageBreakdown={HEAT=1}, splashRadius=70, critChance=0.05, critMultiplier=1.5, statusChance=0.3,
                magazine=40, maxMagazine=40, reserve=120, maxReserve=120, reloadTime=1.8 },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.95 end
        },
        ice_ring = {
            -- DEPRECATED: VS-style aura weapon
            type = 'deprecated', name = "Ice Ring",
            desc = "[Removed] VS-style aura weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'AURA',
            tags = {'weapon', 'area', 'magic', 'ice'},
            base = { damage=2, cd=2.5, radius=100 }
        },
        heavy_hammer = {
            type = 'weapon', name = "Fragor",
            desc = "[Legacy] Heavy hammer with massive knockback.",
            maxLevel = 5,
            slotType = 'melee',
            weaponCategory = 'melee',
            behavior = 'MELEE_SWING',
            behaviorParams = { arcWidth = 1.4 },
            tags = {'weapon', 'physical', 'heavy', 'melee'},
            classWeight = { warrior = 2.0, mage = 0.5, beastmaster = 1.0 },
            legacy = true,
            base = { damage=40, cd=0.2, range=90, knockback=100, effectType='HEAVY', size=12, critChance=0.15, critMultiplier=2.0, statusChance=0.5 },
            onUpgrade = function(w) w.damage = w.damage + 10 end
        },
        dagger = {
            -- DEPRECATED: VS-style throwing weapon
            type = 'deprecated', name = "Throwing Knife",
            desc = "[Removed] VS-style throwing weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_DIRECTIONAL',
            tags = {'weapon', 'projectile', 'physical', 'fast'},
            base = { damage=4, cd=0.18, speed=600, range=550 }
        },
        static_orb = {
            type = 'weapon', name = "Amprex",
            desc = "[Legacy] Chain lightning energy weapon.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'electric', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.5 },
            legacy = true,
            base = { damage=6, cd=0.08, speed=380, range=650, elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1}, duration=3.0, staticRange=160, chain=4, critChance=0.20, critMultiplier=2.0, statusChance=0.4,
                magazine=100, maxMagazine=100, reserve=300, maxReserve=300, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 3; w.chain = w.chain + 1 end
        },
        soul_eater = {
            -- DEPRECATED: VS-style aura weapon
            type = 'deprecated', name = "Soul Eater",
            desc = "[Removed] VS-style vampiric aura.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'AURA',
            tags = {'weapon', 'area', 'aura', 'magic'},
            base = { damage=8, cd=0.3, radius=130, knockback=50, lifesteal=0.4 }
        },
        thousand_edge = {
            -- DEPRECATED: VS-style throwing weapon
            type = 'deprecated', name = "Thousand Edge",
            desc = "[Removed] VS-style throwing weapon.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_DIRECTIONAL',
            tags = {'weapon', 'projectile', 'physical', 'fast'},
            base = { damage=7, cd=0.05, speed=650, range=550, pierce=6 }
        },
        hellfire = {
            type = 'weapon', name = "Ignis",
            desc = "[Legacy] Flame thrower energy weapon.",
            maxLevel = 3,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'fire', 'magic', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.5, beastmaster = 1.0 },
            rare = true, legacy = true,
            base = { damage=15, cd=0.05, speed=520, range=400, elements={'HEAT'}, damageBreakdown={HEAT=1}, splashRadius=80, pierce=99, size=10, area=1.3, life=0.5, statusChance=0.5,
                magazine=200, maxMagazine=200, reserve=400, maxReserve=400, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 5 end
        },
        absolute_zero = {
            -- DEPRECATED: Will be reimplemented as ability
            type = 'deprecated', name = "Absolute Zero",
            desc = "[Removed] Will be reimplemented as ability.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'SPAWN',
            tags = {'weapon', 'area', 'magic', 'ice'},
            base = { damage=5, cd=2.2, radius=160, duration=2.5 }
        },
        thunder_loop = {
            type = 'weapon', name = "Synapse",
            desc = "[Legacy] Chain lightning beam weapon.",
            maxLevel = 3,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'electric', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.5, beastmaster = 1.5 },
            rare = true, legacy = true,
            base = { damage=10, cd=0.05, speed=420, range=650, elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1}, duration=3.0, staticRange=220, pierce=1, chain=10, allowRepeat=true, statusChance=0.5,
                magazine=80, maxMagazine=80, reserve=240, maxReserve=240, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 3; w.chain = w.chain + 2 end
        },
        earthquake = {
            -- DEPRECATED: Will be reimplemented as ability
            type = 'deprecated', name = "Earthquake",
            desc = "[Removed] Will be reimplemented as ability.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'GLOBAL',
            tags = {'weapon', 'area', 'physical', 'heavy'},
            base = { damage=60, cd=2.5, area=2.2, knockback=120 }
        },

        -- ===================================================================
        -- WARFRAME-STYLE WEAPONS
        -- Primary: Rifles, Shotguns, Snipers, Bows
        -- Secondary: Pistols
        -- Melee: Swords, Hammers, Dual Wield
        -- ===================================================================

        -- === RIFLES (Primary) ===
        braton = {
            type = 'weapon', name = "Braton",
            desc = "Standard automatic rifle. Balanced and reliable.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'rifle',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'rifle'},
            classWeight = { warrior = 1.2, mage = 0.8, beastmaster = 1.5 },
            base = { 
                damage=25, cd=0.08, speed=1200, range=700, size=8,
                elements={'IMPACT','PUNCTURE'}, damageBreakdown={IMPACT=1, PUNCTURE=1},
                falloffStart=400, falloffEnd=700, falloffMin=0.5,
                critChance=0.22, critMultiplier=1.8, statusChance=0.20,
                magazine=45, maxMagazine=45, reserve=270, maxReserve=270, reloadTime=1.8
            },
            onUpgrade = function(w) w.damage = w.damage + 5 end
        },
        boltor = {
            type = 'weapon', name = "Boltor",
            desc = "Fires heavy bolts. High puncture damage.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'rifle',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'rifle'},
            classWeight = { warrior = 1.5, mage = 0.5, beastmaster = 1.2 },
            base = { 
                damage=35, cd=0.10, speed=1000, range=750, size=10,
                elements={'PUNCTURE'}, damageBreakdown={PUNCTURE=1},
                falloffStart=400, falloffEnd=750, falloffMin=0.5,
                critChance=0.18, critMultiplier=2.0, statusChance=0.30,
                magazine=60, maxMagazine=60, reserve=360, maxReserve=360, reloadTime=2.4
            },
            onUpgrade = function(w) w.damage = w.damage + 7 end
        },

        -- === SHOTGUNS (Primary) ===
        hek = {
            type = 'weapon', name = "Hek",
            desc = "Quad-barrel shotgun. Devastating at close range.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'shotgun',
            behavior = 'SHOOT_SPREAD',
            behaviorParams = { pellets = 7, spread = 0.4 },
            tags = {'weapon', 'projectile', 'physical', 'shotgun'},
            classWeight = { warrior = 2.0, mage = 0.3, beastmaster = 1.5 },
            base = { 
                damage=65, cd=0.9, speed=800, range=300, size=6,
                elements={'IMPACT','PUNCTURE','SLASH'}, damageBreakdown={IMPACT=3, PUNCTURE=2, SLASH=2},
                falloffStart=80, falloffEnd=250, falloffMin=0.15,
                critChance=0.25, critMultiplier=2.2, statusChance=0.40,
                magazine=4, maxMagazine=4, reserve=120, maxReserve=120, reloadTime=2.0
            },
            onUpgrade = function(w) w.damage = w.damage + 12 end
        },
        strun = {
            type = 'weapon', name = "Strun",
            desc = "Pump-action shotgun. Good spread pattern.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'shotgun',
            behavior = 'SHOOT_SPREAD',
            behaviorParams = { pellets = 10, spread = 0.5 },
            tags = {'weapon', 'projectile', 'physical', 'shotgun'},
            classWeight = { warrior = 1.5, mage = 0.5, beastmaster = 1.5 },
            base = { 
                damage=45, cd=0.7, speed=750, range=250, size=5,
                elements={'IMPACT'}, damageBreakdown={IMPACT=1},
                falloffStart=60, falloffEnd=200, falloffMin=0.20,
                critChance=0.15, critMultiplier=1.8, statusChance=0.30,
                magazine=6, maxMagazine=6, reserve=120, maxReserve=120, reloadTime=2.2
            },
            onUpgrade = function(w) w.damage = w.damage + 8 end
        },

        -- === SNIPERS (Primary) ===
        vectis = {
            type = 'weapon', name = "Vectis",
            desc = "Sniper rifle. [Shift: Sniper Mode]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'sniper',
            behavior = 'SHOOT_NEAREST',
            sniperMode = true,
            tags = {'weapon', 'projectile', 'physical', 'sniper'},
            classWeight = { warrior = 1.0, mage = 1.5, beastmaster = 0.8 },
            base = { 
                damage=200, cd=1.3, speed=1800, range=900, size=12,
                sniperRange=1500,
                elements={'PUNCTURE','IMPACT'}, damageBreakdown={PUNCTURE=3, IMPACT=1},
                critChance=0.50, critMultiplier=3.5, statusChance=0.30,
                magazine=1, maxMagazine=1, reserve=72, maxReserve=72, reloadTime=0.8,
                pierce=3
            },
            onUpgrade = function(w) w.damage = w.damage + 30; w.critChance = w.critChance + 0.05 end
        },
        lanka = {
            type = 'weapon', name = "Lanka",
            desc = "Corpus energy sniper. [Shift: Sniper Mode]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'sniper',
            behavior = 'SHOOT_NEAREST',
            sniperMode = true,
            tags = {'weapon', 'projectile', 'energy', 'sniper'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.0 },
            rare = true,
            base = { 
                damage=180, cd=1.0, speed=1500, range=900, size=14,
                sniperRange=1600,
                elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1},
                critChance=0.40, critMultiplier=3.0, statusChance=0.40,
                magazine=10, maxMagazine=10, reserve=72, maxReserve=72, reloadTime=1.8,
                pierce=5
            },
            onUpgrade = function(w) w.damage = w.damage + 25 end
        },

        -- === BOWS (Primary) ===
        dread = {
            type = 'weapon', name = "Dread",
            desc = "Stalker's bow. [Hold: Charge Shot]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'bow',
            behavior = 'CHARGE_SHOT',
            chargeEnabled = true,
            maxChargeTime = 2.0,
            minChargeMult = 0.5,
            maxChargeMult = 2.0,
            chargeSpeedBonus = true,
            tags = {'weapon', 'projectile', 'physical', 'bow', 'silent'},
            classWeight = { warrior = 1.0, mage = 1.0, beastmaster = 2.0 },
            rare = true,
            base = { 
                damage=120, cd=0.7, speed=900, range=800, size=10,
                elements={'SLASH'}, damageBreakdown={SLASH=1},
                critChance=0.60, critMultiplier=2.5, statusChance=0.55,
                pierce=2
            },
            onUpgrade = function(w) w.damage = w.damage + 20; w.critChance = w.critChance + 0.05 end
        },
        paris = {
            type = 'weapon', name = "Paris",
            desc = "Tenno longbow. [Hold: Charge Shot]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'bow',
            behavior = 'CHARGE_SHOT',
            chargeEnabled = true,
            maxChargeTime = 2.0,
            minChargeMult = 0.5,
            maxChargeMult = 2.0,
            chargeSpeedBonus = true,
            tags = {'weapon', 'projectile', 'physical', 'bow', 'silent'},
            classWeight = { warrior = 1.0, mage = 1.0, beastmaster = 2.0 },
            base = { 
                damage=90, cd=0.6, speed=850, range=750, size=10,
                elements={'PUNCTURE','IMPACT'}, damageBreakdown={PUNCTURE=3, IMPACT=1},
                critChance=0.40, critMultiplier=2.2, statusChance=0.35,
                pierce=1
            },
            onUpgrade = function(w) w.damage = w.damage + 15 end
        },

        -- === PISTOLS (Secondary) ===
        lato = {
            type = 'weapon', name = "Lato",
            desc = "Standard sidearm. Reliable and fast.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'pistol',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'pistol'},
            classWeight = { warrior = 1.0, mage = 1.0, beastmaster = 1.0 },
            base = { 
                damage=25, cd=0.12, speed=1100, range=500, size=6,
                elements={'IMPACT','PUNCTURE'}, damageBreakdown={IMPACT=1, PUNCTURE=1},
                falloffStart=250, falloffEnd=500, falloffMin=0.4,
                critChance=0.18, critMultiplier=2.0, statusChance=0.12,
                magazine=15, maxMagazine=15, reserve=210, maxReserve=210, reloadTime=1.0
            },
            onUpgrade = function(w) w.damage = w.damage + 5 end
        },
        lex = {
            type = 'weapon', name = "Lex",
            desc = "High-caliber pistol. Hits like a truck.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'pistol',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'pistol'},
            classWeight = { warrior = 1.5, mage = 1.0, beastmaster = 1.0 },
            base = { 
                damage=75, cd=0.4, speed=1000, range=600, size=8,
                elements={'IMPACT','PUNCTURE'}, damageBreakdown={IMPACT=2, PUNCTURE=1},
                falloffStart=250, falloffEnd=600, falloffMin=0.4,
                critChance=0.30, critMultiplier=2.5, statusChance=0.15,
                magazine=6, maxMagazine=6, reserve=120, maxReserve=120, reloadTime=2.0
            },
            onUpgrade = function(w) w.damage = w.damage + 15 end
        },
        atomos = {
            type = 'weapon', name = "Atomos",
            desc = "Particle cannon. Chains to nearby enemies.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'energy', 'pistol'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.5 },
            rare = true,
            base = { 
                damage=12, cd=0.05, speed=800, range=400, size=4,
                elements={'HEAT'}, damageBreakdown={HEAT=1},
                falloffStart=200, falloffEnd=400, falloffMin=0.5,
                critChance=0.15, critMultiplier=1.8, statusChance=0.40,
                magazine=70, maxMagazine=70, reserve=210, maxReserve=210, reloadTime=1.8,
                life=0.8, duration=2.0, chain=3, staticRange=100
            },
            onUpgrade = function(w) w.damage = w.damage + 3; w.chain = w.chain + 1 end
        },

        -- === MELEE ===
        skana = {
            type = 'weapon', name = "Skana",
            desc = "Standard Tenno sword. Balanced melee.",
            maxLevel = 5,
            slotType = 'melee',
            weaponCategory = 'melee',
            behavior = 'MELEE_SWING',
            behaviorParams = { arcWidth = 1.2 },
            tags = {'weapon', 'physical', 'melee', 'sword'},
            classWeight = { warrior = 1.5, mage = 0.8, beastmaster = 1.0 },
            base = { 
                damage=60, cd=0.12, range=100, 
                elements={'SLASH','IMPACT'}, damageBreakdown={SLASH=2, IMPACT=1},
                critChance=0.15, critMultiplier=1.8, statusChance=0.18,
                knockback=70
            },
            onUpgrade = function(w) w.damage = w.damage + 12 end
        },
        dual_zoren = {
            type = 'weapon', name = "Dual Zoren",
            desc = "Twin hatchets. Very fast attack speed.",
            maxLevel = 5,
            slotType = 'melee',
            weaponCategory = 'melee',
            behavior = 'MELEE_SWING',
            behaviorParams = { arcWidth = 1.0 },
            tags = {'weapon', 'physical', 'melee', 'dual'},
            classWeight = { warrior = 1.5, mage = 0.5, beastmaster = 1.5 },
            base = { 
                damage=50, cd=0.06, range=90, 
                elements={'SLASH'}, damageBreakdown={SLASH=1},
                critChance=0.35, critMultiplier=2.5, statusChance=0.10,
                knockback=50
            },
            onUpgrade = function(w) w.damage = w.damage + 10; w.critChance = w.critChance + 0.03 end
        },
        -- DEPRECATED PASSIVES (VS-style, hidden from upgrade pools)
        -- These effects are now handled by the WF MOD system
        -- Kept for backward save compatibility only
        -- ===================================================================
        -- DEPRECATED PASSIVES REMOVED
        -- These effects are now handled by the WF MOD system
        -- ===================================================================


        -- Warframe-style Mods (loadout-only, per-weapon)
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
        },

        -- Mechanics Augments (per-run, change play patterns)
        aug_gilded_instinct = {
            type = 'augment', name = "Gilded Instinct",
            desc = "Gain more GOLD from kills and room rewards.",
            maxLevel = 3,
            triggers = {
                {
                    event = 'onPickup',
                    requires = {pickupKind = 'gold'},
                    action = function(state, ctx, level)
                        local amt = tonumber(ctx and ctx.amount) or 0
                        if amt <= 0 then return end
                        local mult = 1 + 0.25 * math.max(1, level or 1)
                        ctx.amount = math.max(1, math.floor(amt * mult + 0.5))
                    end
                }
            }
        },
        aug_kinetic_discharge = {
            type = 'augment', name = "Kinetic Discharge",
            desc = "Moving charges up. Every distance traveled releases an electric pulse.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'tick',
                    counter = 'moveDist',
                    threshold = 260,
                    cooldown = 0.2,
                    maxPerSecond = 2,
                    requires = {isMoving = true},
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end
                        local radius = 130
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(10 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.35,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'augment', 'area'}
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            if not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('static', p.x, p.y) end
                    end
                }
            }
        },
        aug_blood_burst = {
            type = 'augment', name = "Blood Burst",
            desc = "Killing an enemy detonates it, damaging nearby foes.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onKill',
                    cooldown = 0.15,
                    maxPerSecond = 6,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local enemy = ctx and ctx.enemy
                        if not enemy then return end
                        local p = state.player or {}
                        local radius = 110
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(12 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.25,
                            elements = {'BLAST'},
                            damageBreakdown = {BLAST = 1},
                            weaponTags = {'augment', 'area'}
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            if e ~= enemy and not e.isDummy then
                                local dx = e.x - enemy.x
                                local dy = e.y - enemy.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('hit', enemy.x, enemy.y) end
                    end
                }
            }
        },
        aug_combo_arc = {
            type = 'augment', name = "Combo Arc",
            desc = "Every 7 hits releases chain lightning to nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onHit',
                    counter = 'hits',
                    threshold = 7,
                    cooldown = 0.1,
                    maxPerSecond = 3,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local enemy = ctx and ctx.enemy
                        if not enemy then return end
                        local p = state.player or {}
                        local radius = 180
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(8 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.4,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'augment', 'chain'}
                        })
                        local hits = 0
                        for _, e in ipairs(state.enemies or {}) do
                            if e ~= enemy and not e.isDummy and e.health and e.health > 0 then
                                local dx = e.x - enemy.x
                                local dy = e.y - enemy.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                    hits = hits + 1
                                    if hits >= 4 then break end
                                end
                            end
                        end
                        if hits > 0 and state.spawnEffect then state.spawnEffect('static', enemy.x, enemy.y) end
                    end
                }
            }
        },
        aug_forked_trajectory = {
            type = 'augment', name = "Forked Trajectory",
            desc = "Projectiles split into 2 angled forks.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 60,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b._forked or b.augmentChild then return end
                        if b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        if not b.vx or not b.vy then return end

                        local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                        if spd <= 0 then return end
                        local baseAng = math.atan2(b.vy, b.vx)
                        local spread = 0.22
                        local forks = 2
                        local dmg = b.damage or 0
                        if dmg <= 0 then return end

                        local function cloneBullet(src)
                            local out = {}
                            for k, v in pairs(src) do
                                if type(v) == 'table' then
                                    local t = {}
                                    for kk, vv in pairs(v) do t[kk] = vv end
                                    out[k] = t
                                else
                                    out[k] = v
                                end
                            end
                            out.hitTargets = nil
                            return out
                        end

                        b._forked = true
                        for i = 1, forks do
                            local sign = (i == 1) and -1 or 1
                            local ang = baseAng + sign * spread
                            local c = cloneBullet(b)
                            c.x = b.x
                            c.y = b.y
                            c.vx = math.cos(ang) * spd
                            c.vy = math.sin(ang) * spd
                            c.rotation = ang
                            c.life = (b.life or 2) * 0.9
                            c.size = math.max(4, (b.size or 8) * 0.9)
                            c.damage = math.max(1, math.floor(dmg * 0.6 + 0.5))
                            c.augmentChild = true
                            c._forked = true
                            table.insert(state.bullets, c)
                            if state and state.augments and state.augments.dispatch then
                                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = c.type, bullet = c, spawnedBy = 'fork'})
                            end
                        end
                    end
                }
            }
        },
        aug_homing_protocol = {
            type = 'augment', name = "Homing Protocol",
            desc = "Projectiles steer toward nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        b.homing = math.max(b.homing or 0, 6.5)
                        b.homingRange = math.max(b.homingRange or 0, 720)
                    end
                }
            }
        },
        aug_ricochet_matrix = {
            type = 'augment', name = "Ricochet Matrix",
            desc = "Projectiles ricochet to nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local add = 2
                        b.ricochetRemaining = (b.ricochetRemaining or 0) + add
                        b.ricochetRange = math.max(b.ricochetRange or 0, 420)
                        b.pierce = (b.pierce or 1) + add
                    end
                }
            }
        },
        aug_boomerang_return = {
            type = 'augment', name = "Boomerang Return",
            desc = "Projectiles turn back and return to you.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local t = math.min(0.9, (b.life or 2) * 0.45)
                        if b.boomerangTimer == nil or b.boomerangTimer > t then
                            b.boomerangTimer = t
                        end
                        b.returnHoming = math.max(b.returnHoming or 0, 22)
                        b.life = (b.life or 2) + 0.9
                        b.pierce = (b.pierce or 1) + 1
                    end
                }
            }
        },
        aug_shatter_shards = {
            type = 'augment', name = "Shatter Shards",
            desc = "On hit, projectiles burst into shards.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileHit',
                    cooldown = 0.05,
                    maxPerSecond = 30,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        local enemy = ctx and ctx.enemy
                        if not b or not enemy then return end
                        if b._shattered or b.augmentChild then return end
                        if b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local dmg = b.damage or 0
                        if dmg <= 0 then return end
                        b._shattered = true

                        local spd = math.sqrt((b.vx or 0)^2 + (b.vy or 0)^2)
                        if spd <= 0 then spd = 520 end
                        local baseAng = math.atan2((b.vy or 0), (b.vx or 1))
                        local count = 3
                        local spread = 0.45

                        local function copyArray(src)
                            if not src then return nil end
                            local t = {}
                            for i, v in ipairs(src) do t[i] = v end
                            return t
                        end

                        local function copyMap(src)
                            if not src then return nil end
                            local t = {}
                            for k, v in pairs(src) do t[k] = v end
                            return t
                        end

                        for i = 1, count do
                            local offset = (i - (count + 1) / 2) * spread
                            local ang = baseAng + offset
                            local shardTags = copyArray(b.weaponTags) or {}
                            table.insert(shardTags, 'augment')
                            local shard = {
                                type = 'augment_shard',
                                x = enemy.x,
                                y = enemy.y,
                                vx = math.cos(ang) * spd,
                                vy = math.sin(ang) * spd,
                                life = 1.2,
                                size = math.max(4, (b.size or 10) * 0.7),
                                damage = math.max(1, math.floor(dmg * 0.35 + 0.5)),
                                effectType = b.effectType,
                                weaponTags = shardTags,
                                pierce = 1,
                                rotation = ang,
                                parentWeaponKey = b.type,
                                elements = copyArray(b.elements),
                                damageBreakdown = copyMap(b.damageBreakdown),
                                critChance = b.critChance,
                                critMultiplier = b.critMultiplier,
                                statusChance = b.statusChance
                            }
                            shard.augmentChild = true
                            table.insert(state.bullets, shard)
                            if state and state.augments and state.augments.dispatch then
                                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = b.type, bullet = shard, spawnedBy = 'shatter'})
                            end
                        end
                    end
                }
            }
        },
        aug_evasive_momentum = {
            type = 'augment', name = "Evasive Momentum",
            desc = "While moving, evade one hit periodically.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'preHurt',
                    cooldown = 2.0,
                    requires = {isMoving = true},
                    action = function(state, ctx)
                        ctx.cancel = true
                        ctx.invincibleTimer = 0.25
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end
                        table.insert(state.texts, {x=p.x, y=p.y-30, text="DODGE!", color={0.6,1,0.6}, life=0.6})
                    end
                }
            }
        },
        aug_greater_reflex = {
            type = 'augment', name = "Greater Reflex",
            desc = "Gain +1 Dash charge.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onUpgradeChosen',
                    action = function(state, ctx)
                        local opt = ctx and ctx.opt
                        if not opt or opt.key ~= 'aug_greater_reflex' then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p or not p.stats then return end
                        p.stats.dashCharges = math.max(0, (p.stats.dashCharges or 0) + 1)
                    end
                }
            }
        },
        aug_dash_strike = {
            type = 'augment', name = "Dash Strike",
            desc = "Dashing releases an impact shockwave that damages nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.05,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end
                        local radius = 95
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(14 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.15,
                            elements = {'IMPACT'},
                            damageBreakdown = {IMPACT = 1},
                            weaponTags = {'augment', 'dash', 'area'},
                            knock = true,
                            knockForce = 18
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            local hp = e and (e.health or e.hp) or 0
                            if e and hp and hp > 0 and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('impact_hit', p.x, p.y, 1.0) end
                    end
                }
            }
        },
        aug_quickstep = {
            type = 'augment', name = "Quickstep",
            desc = "Dash recharges faster.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onUpgradeChosen',
                    action = function(state, ctx)
                        local opt = ctx and ctx.opt
                        if not opt or opt.key ~= 'aug_quickstep' then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p or not p.stats then return end
                        local cd = p.stats.dashCooldown or 0
                        if cd <= 0 then return end
                        cd = cd * 0.75
                        if cd < 0.15 then cd = 0.15 end
                        p.stats.dashCooldown = cd
                    end
                }
            }
        },
        aug_longstride = {
            type = 'augment', name = "Longstride",
            desc = "Dash travels farther and grants longer i-frames.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onUpgradeChosen',
                    action = function(state, ctx)
                        local opt = ctx and ctx.opt
                        if not opt or opt.key ~= 'aug_longstride' then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p or not p.stats then return end
                        local dist = p.stats.dashDistance or 0
                        if dist > 0 then
                            p.stats.dashDistance = dist * 1.25
                        end
                        p.stats.dashInvincible = math.max(0, (p.stats.dashInvincible or 0) + 0.04)
                    end
                }
            }
        },
        aug_reload_step = {
            type = 'augment', name = "Reload Step",
            desc = "Dashing refreshes weapon cooldowns.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.05,
                    action = function(state, ctx)
                        for _, w in pairs((state.inventory and state.inventory.weapons) or {}) do
                            if w and w.timer ~= nil then
                                w.timer = 0
                            end
                        end
                        local p = (ctx and ctx.player) or state.player
                        if p then
                            table.insert(state.texts, {x=p.x, y=p.y-38, text="RESET!", color={0.75,0.9,1}, life=0.55})
                        end
                    end
                }
            }
        },
        aug_shockstep = {
            type = 'augment', name = "Shockstep",
            desc = "Dashing releases an electric pulse that can chain.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.15,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end

                        local radius = 120
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(10 * might + 0.5)
                        if dmg <= 0 then dmg = 1 end

                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.55,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'augment', 'dash', 'area'}
                        })

                        for _, e in ipairs(state.enemies or {}) do
                            local hp = e and (e.health or e.hp) or 0
                            if e and hp and hp > 0 and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end

                        if state.spawnEffect then state.spawnEffect('static', p.x, p.y, 0.95) end
                        if state.spawnAreaField then state.spawnAreaField('static', p.x, p.y, radius, 0.35, 1.1) end
                    end
                }
            }
        },
        aug_froststep = {
            type = 'augment', name = "Froststep",
            desc = "Dashing freezes nearby enemies briefly.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.65,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end

                        local radius = 90
                        local r2 = radius * radius
                        local instance = calc.createInstance({
                            damage = 0,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 1.0,
                            effectType = 'FREEZE',
                            effectData = {fullFreeze = true, freezeDuration = 0.45},
                            elements = {'COLD'},
                            damageBreakdown = {COLD = 1},
                            weaponTags = {'augment', 'dash', 'area'}
                        })

                        for _, e in ipairs(state.enemies or {}) do
                            local hp = e and (e.health or e.hp) or 0
                            if e and hp and hp > 0 and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end

                        if state.spawnEffect then state.spawnEffect('freeze', p.x, p.y, 0.7) end
                        if state.spawnAreaField then state.spawnAreaField('freeze', p.x, p.y, radius, 0.5, 1.0) end
                    end
                }
            }
        }
    }

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

    -- Projectile sizing/scale tuning (single source of truth for "how big it should look/hit").
    -- size: logical diameter before spriteScale; spriteScale: base magnification for rendering (and hitbox, via hitSizeScale).
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
    -- 状态特效贴图（3 帧横条）
    state.effectSprites = {}
    state.hitEffects = {}
    -- 纯视觉屏幕波纹（用于后处理扭曲/冲击波），不参与伤害/判定
    state.screenWaves = {}
    -- 持续性地面/范围场（shader 体积云类）
    state.areaFields = {}
    -- 敌方攻击预警（纯视觉，不参与判定）
    state.telegraphs = {}
    -- 闪避拖影（纯视觉，不参与判定）
    state.dashAfterimages = {}
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

    local proceduralEffectDefs = {
        hit = { duration = 0.16, defaultScale = 1.0 },
        shock = { duration = 0.18, defaultScale = 1.0 },
        static_hit = { duration = 0.18, defaultScale = 1.0 },
        impact_hit = { duration = 0.16, defaultScale = 1.0 },
        ice_shatter = { duration = 0.20, defaultScale = 1.0 },
        ember = { duration = 0.18, defaultScale = 1.0 },

        -- proc feedback (procedural)
        toxin_hit = { duration = 0.18, defaultScale = 1.0 },
        gas_hit = { duration = 0.18, defaultScale = 1.0 },
        bleed_hit = { duration = 0.18, defaultScale = 1.0 },
        viral_hit = { duration = 0.18, defaultScale = 1.0 },
        corrosive_hit = { duration = 0.18, defaultScale = 1.0 },
        magnetic_hit = { duration = 0.18, defaultScale = 1.0 },
        blast_hit = { duration = 0.18, defaultScale = 1.0 },
        puncture_hit = { duration = 0.18, defaultScale = 1.0 },
        radiation_hit = { duration = 0.18, defaultScale = 1.0 }
    }

    local screenWaveDefs = {
        blast_hit = { radius = 200, duration = 0.40, strength = 2.8, priority = 3 },
        impact_hit = { radius = 160, duration = 0.34, strength = 2.5, priority = 2 },
        shock = { radius = 140, duration = 0.30, strength = 2.2, priority = 2 },
        hit = { radius = 100, duration = 0.26, strength = 1.5, priority = 1, cooldown = 0.07 },
    }

    local screenWaveMax = 12

    local function trimScreenWaves()
        local list = state.screenWaves
        if type(list) ~= 'table' then return end
        while #list > screenWaveMax do
            local removeIndex = 1
            local worstPrio = list[1].priority or 0
            local worstT = list[1].t or 0
            for i = 2, #list do
                local p = list[i].priority or 0
                local t = list[i].t or 0
                if p < worstPrio or (p == worstPrio and t > worstT) then
                    removeIndex = i
                    worstPrio = p
                    worstT = t
                end
            end
            table.remove(list, removeIndex)
        end
    end

    function state.spawnScreenWave(x, y, radius, duration, strength, priority)
        if not x or not y then return end
        radius = radius or 120
        duration = duration or 0.28
        strength = strength or 1.8
        if duration <= 0 or radius <= 0 or strength <= 0 then return end
        state.screenWaves = state.screenWaves or {}
        table.insert(state.screenWaves, {
            x = x,
            y = y,
            t = 0,
            duration = duration,
            radius = radius,
            strength = strength,
            priority = priority or 0
        })
        trimScreenWaves()
    end

    function state.spawnEffect(key, x, y, scale)
        -- 纯视觉冲击波（用于后处理扭曲），表驱动 + 节流 + 上限
        -- NOTE: 这里不做任何伤害/判定，只是喂给 bloom 的 warp pass。
        local def = screenWaveDefs[key]
        if def then
            local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
            local cd = def.cooldown or 0
            if cd <= 0 then
                state.spawnScreenWave(x, y, def.radius, def.duration, def.strength, def.priority)
            else
                state._screenWaveCooldown = state._screenWaveCooldown or {}
                local last = state._screenWaveCooldown[key] or 0
                if last + cd <= now then
                    state._screenWaveCooldown[key] = now
                    state.spawnScreenWave(x, y, def.radius, def.duration, def.strength, def.priority)
                end
            end
        end

        local eff = state.effectSprites[key]
        if eff then
            local useScale = scale or eff.defaultScale or 1
            table.insert(state.hitEffects, {key = key, x = x, y = y, t = 0, duration = eff.duration or 0.3, scale = useScale})
            return
        end

        local p = proceduralEffectDefs[key]
        if not p then return end
        local useScale = scale or p.defaultScale or 1
        table.insert(state.hitEffects, {key = key, x = x, y = y, t = 0, duration = p.duration or 0.18, scale = useScale})
    end

    function state.spawnAreaField(kind, x, y, radius, duration, intensity)
        if not kind then return end
        if not radius or radius <= 0 then return end
        table.insert(state.areaFields, {
            kind = kind,
            x = x,
            y = y,
            radius = radius,
            t = 0,
            duration = duration or 2.0,
            intensity = intensity or 1
        })
    end

    function state.spawnTelegraphCircle(x, y, radius, duration, opts)
        if not x or not y then return nil end
        if not radius or radius <= 0 then return nil end
        duration = duration or 0.7
        if duration <= 0 then return nil end
        state.telegraphs = state.telegraphs or {}
        local t = {
            shape = 'circle',
            x = x,
            y = y,
            radius = radius,
            t = 0,
            duration = duration,
            kind = (opts and opts.kind) or 'telegraph',
            intensity = (opts and opts.intensity) or 1
        }
        table.insert(state.telegraphs, t)
        return t
    end

    function state.spawnTelegraphLine(x1, y1, x2, y2, width, duration, opts)
        if not x1 or not y1 or not x2 or not y2 then return nil end
        width = width or 28
        if width <= 0 then return nil end
        duration = duration or 0.6
        if duration <= 0 then return nil end
        state.telegraphs = state.telegraphs or {}
        local t = {
            shape = 'line',
            x1 = x1,
            y1 = y1,
            x2 = x2,
            y2 = y2,
            width = width,
            t = 0,
            duration = duration,
            color = (opts and opts.color) or nil
        }
        table.insert(state.telegraphs, t)
        return t
    end

    local dashAfterimageMax = 28
    function state.spawnDashAfterimage(x, y, facing, opts)
        if not x or not y then return nil end
        state.dashAfterimages = state.dashAfterimages or {}
        local a = {
            x = x,
            y = y,
            facing = facing or 1,
            t = 0,
            duration = (opts and opts.duration) or 0.22,
            alpha = (opts and opts.alpha) or 0.22,
            dirX = (opts and opts.dirX) or nil,
            dirY = (opts and opts.dirY) or nil
        }
        table.insert(state.dashAfterimages, a)
        while #state.dashAfterimages > dashAfterimageMax do
            table.remove(state.dashAfterimages, 1)
        end
        return a
    end

    function state.updateEffects(dt)
        for i = #state.hitEffects, 1, -1 do
            local e = state.hitEffects[i]
            e.t = e.t + dt
            if e.t >= (e.duration or 0.3) then
                table.remove(state.hitEffects, i)
            end
        end

        for i = #(state.screenWaves or {}), 1, -1 do
            local w = state.screenWaves[i]
            w.t = (w.t or 0) + dt
            if w.t >= (w.duration or 0.3) then
                table.remove(state.screenWaves, i)
            end
        end

        for i = #state.areaFields, 1, -1 do
            local a = state.areaFields[i]
            a.t = a.t + dt
            if a.t >= (a.duration or 2.0) then
                table.remove(state.areaFields, i)
            end
        end

        for i = #(state.telegraphs or {}), 1, -1 do
            local t = state.telegraphs[i]
            t.t = (t.t or 0) + dt
            if t.t >= (t.duration or 0.6) then
                table.remove(state.telegraphs, i)
            end
        end

        for i = #(state.dashAfterimages or {}), 1, -1 do
            local a = state.dashAfterimages[i]
            a.t = (a.t or 0) + dt
            if a.t >= (a.duration or 0.22) then
                table.remove(state.dashAfterimages, i)
            end
        end

        for i = #state.lightningLinks, 1, -1 do
            local l = state.lightningLinks[i]
            l.t = (l.t or 0) + dt
            if l.t >= (l.duration or 0.12) then
                table.remove(state.lightningLinks, i)
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
    -- VS pickups removed (chicken, magnet)
    loadPickup('gem', 0.01) -- XP Gem / Affinity Orb


    -- 敌人子弹贴图
    state.enemySprites = {}
    local plantBullet = loadImage('assets/enemies/plant_bullet.png')
    if plantBullet then
        plantBullet:setFilter('nearest', 'nearest')
        state.enemySprites['plant_bullet'] = plantBullet
    end
    
    -- 共享骷髅精灵动画帧 (用于所有敌人)
    state.enemySprites['skeleton_frames'] = {}
    for i = 1, 4 do
        local img = loadImage('assets/characters/skeleton/move_' .. i .. '.PNG')
        if img then
            img:setFilter('nearest', 'nearest')
            table.insert(state.enemySprites['skeleton_frames'], img)
        end
    end
    -- Fallback if no frames loaded
    if #state.enemySprites['skeleton_frames'] == 0 then
        local fallback = loadImage('assets/characters/skeleton/move_1.PNG')
        if fallback then
            fallback:setFilter('nearest', 'nearest')
            table.insert(state.enemySprites['skeleton_frames'], fallback)
        end
    end
end

return state
