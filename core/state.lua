local state = {}

local assets = require('render.assets')
local effects = require('render.effects')
local progression = require('systems.progression')
local mods = require('systems.mods')

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
        -- Weapon-specific pre-run mod loadouts (8-slot system).
        weaponMods = {
            wand = {
                slots = {}
            }
        },
        warframeMods = {slots = {}},
        companionMods = {slots = {}},
        modTargetWeapon = 'wand',
        modTargetCategory = 'weapons',
        modSystemVersion = 2,

        -- Legacy global mod equip fields (kept for backward compatibility; migrated into weaponMods).
        equippedMods = {},
        modOrder = {},
        ownedMods = {
            serration = true,
            split_chamber = true,
            point_strike = true,
            vital_sense = true,
            status_matrix = true
        },
        currency = 0,

        -- Pets (loadout + light meta progression)
        startPetKey = 'pet_magnet',
        petModules = {},
        petRanks = {}
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
    profile.modTargetCategory = profile.modTargetCategory or 'weapons'
    profile.equippedMods = profile.equippedMods or {} -- legacy
    profile.modOrder = profile.modOrder or {} -- legacy
    profile.ownedMods = profile.ownedMods or {}
    profile.modSystemVersion = profile.modSystemVersion or 1

    local function buildModKeySet()
        local set = {}
        for _, category in ipairs({'warframe', 'weapons', 'companion'}) do
            for key, _ in pairs(mods.getCatalog(category) or {}) do
                set[key] = true
            end
        end
        return set
    end

    local validModKeys = buildModKeySet()
    local function normalizeModKey(key)
        if validModKeys[key] then return key end
        if type(key) == 'string' and key:sub(1, 4) == 'mod_' then
            local stripped = key:sub(5)
            if validModKeys[stripped] then
                return stripped
            end
        end
        return key
    end

    local function remapKeys(tbl)
        local out = {}
        for k, v in pairs(tbl or {}) do
            local nk = normalizeModKey(k)
            out[nk] = v
        end
        return out
    end

    if next(profile.ownedMods) == nil then
        for k, v in pairs(defaultProfile().ownedMods) do
            profile.ownedMods[k] = v
        end
    end

    if profile.modSystemVersion ~= 2 then
        profile.ownedMods = remapKeys(profile.ownedMods)
        profile.modRanks = remapKeys(profile.modRanks)

        for k, v in pairs(profile.modRanks) do
            if type(v) == 'number' then
                profile.modRanks[k] = math.max(0, math.floor(v) - 1)
            end
        end

        -- Migrate legacy global equippedMods/modOrder into weaponMods.wand if no weapon loadouts exist yet.
        if next(profile.weaponMods) == nil then
            local legacyEq = profile.equippedMods or {}
            local legacyOrder = profile.modOrder or {}
            local hasLegacy = (next(legacyEq) ~= nil) or (type(legacyOrder) == 'table' and #legacyOrder > 0)
            if hasLegacy then
                profile.weaponMods.wand = profile.weaponMods.wand or {slots = {}}
                local lo = profile.weaponMods.wand
                local slots = lo.slots or {}
                local idx = 1

                for _, k in ipairs(legacyOrder) do
                    local nk = normalizeModKey(k)
                    if legacyEq[k] or legacyEq[nk] then
                        slots[idx] = nk
                        idx = idx + 1
                        if idx > 8 then break end
                    end
                end

                local extra = {}
                for k, v in pairs(legacyEq) do
                    if v then
                        local nk = normalizeModKey(k)
                        local found = false
                        for _, ok in pairs(slots) do
                            if ok == nk then found = true break end
                        end
                        if not found then table.insert(extra, nk) end
                    end
                end
                table.sort(extra)
                for _, nk in ipairs(extra) do
                    if idx > 8 then break end
                    slots[idx] = nk
                    idx = idx + 1
                end
                lo.slots = slots
            end
        end

        for weaponKey, lo in pairs(profile.weaponMods or {}) do
            if lo and lo.equippedMods and lo.modOrder then
                local slots = {}
                local idx = 1
                for _, modKey in ipairs(lo.modOrder) do
                    local nk = normalizeModKey(modKey)
                    if lo.equippedMods[modKey] or lo.equippedMods[nk] then
                        slots[idx] = nk
                        idx = idx + 1
                        if idx > 8 then break end
                    end
                end
                local extra = {}
                for modKey, on in pairs(lo.equippedMods) do
                    if on then
                        local nk = normalizeModKey(modKey)
                        local found = false
                        for _, ok in pairs(slots) do
                            if ok == nk then found = true break end
                        end
                        if not found then table.insert(extra, nk) end
                    end
                end
                table.sort(extra)
                for _, nk in ipairs(extra) do
                    if idx > 8 then break end
                    slots[idx] = nk
                    idx = idx + 1
                end
                profile.weaponMods[weaponKey] = {slots = slots}
            elseif lo and lo.slots then
                local slots = {}
                for slotIdx, modKey in pairs(lo.slots) do
                    slots[tonumber(slotIdx) or slotIdx] = normalizeModKey(modKey)
                end
                lo.slots = slots
            elseif lo then
                lo.slots = lo.slots or {}
            end
        end

        profile.modSystemVersion = 2
    end

    for k, _ in pairs(profile.modRanks) do profile.ownedMods[k] = true end
    for _, lo in pairs(profile.weaponMods or {}) do
        for _, modKey in pairs((lo and lo.slots) or {}) do
            if modKey then profile.ownedMods[modKey] = true end
        end
    end
    profile.warframeMods = profile.warframeMods or {slots = {}}
    profile.companionMods = profile.companionMods or {slots = {}}
    profile.startPetKey = profile.startPetKey or 'pet_magnet'
    profile.petModules = profile.petModules or {}
    profile.petRanks = profile.petRanks or {}
    profile.currency = profile.currency or 0
    if next(profile.weaponMods) == nil then
        profile.weaponMods.wand = {slots = {}}
    end
    profile.weaponMods[profile.modTargetWeapon] = profile.weaponMods[profile.modTargetWeapon] or {slots = {}}
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
    state.inventory.warframeMods = nil
    state.inventory.companionMods = nil
    if not state.profile then return end
    local ranks = state.profile.modRanks or {}

    for weaponKey, lo in pairs(state.profile.weaponMods or {}) do
        local entry = {mods = {}, modOrder = {}}
        local slots = (lo and lo.slots) or {}
        for i = 1, 8 do
            local modKey = slots[i]
            if modKey then
                local lvl = ranks[modKey] or 0
                entry.mods[modKey] = lvl
                table.insert(entry.modOrder, modKey)
            end
        end

        state.inventory.weaponMods[weaponKey] = entry
    end

    local function buildEntry(loadout)
        local entry = {mods = {}, modOrder = {}}
        local slots = (loadout and loadout.slots) or {}
        for i = 1, 8 do
            local modKey = slots[i]
            if modKey then
                local lvl = ranks[modKey] or 0
                entry.mods[modKey] = lvl
                table.insert(entry.modOrder, modKey)
            end
        end
        return entry
    end

    state.inventory.warframeMods = buildEntry(state.profile.warframeMods)
    state.inventory.companionMods = buildEntry(state.profile.companionMods)
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
        level = 0, xp = 0, xpToNextLevel = xpBase,
        invincibleTimer = 0,
        shieldDelayTimer = 0,
        dash = {charges = 2, maxCharges = 2, rechargeTimer = 0, timer = 0, dx = 1, dy = 0},
        class = 'volt', -- Current class: excalibur / mag / volt
        ability = {cooldown = 0, timer = 0}, -- Q skill state
        quickAbilityIndex = 1, -- Quick cast selection (1-4)
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
        excalibur = {
            name = "咖喱",
            desc = "均衡近战战甲。Q: Slash Dash (斩击突进)",
            baseStats = {
                maxHp = 110,
                armor = 90,
                moveSpeed = 135,
                might = 1.05,
                maxShield = 100,
                maxEnergy = 120,
                dashCharges = 1,
                abilityStrength = 1.05
            },
            startMelee = 'skana',
            startRanged = 'lato',
            preferredUpgrades = {'skana', 'dual_zoren', 'braton', 'lato'},
            ability = {
                name = "Slash Dash",
                cooldown = 6.0
            }
        },
        mag = {
            name = "磁妹",
            desc = "磁力控制战甲。Q: Pull (牵引)",
            baseStats = {
                maxHp = 80,
                armor = 30,
                moveSpeed = 140,
                might = 1.0,
                maxShield = 200,
                maxEnergy = 200,
                dashCharges = 1,
                abilityStrength = 1.10,
                abilityRange = 1.05
            },
            startMelee = 'karyst',
            startRanged = 'braton',
            preferredUpgrades = {'braton', 'lanka', 'atomos', 'static_orb'},
            ability = {
                name = "Pull",
                cooldown = 5.0
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
                cooldown = 4.0
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
