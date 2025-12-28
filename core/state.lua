-- 全局状态管理模块
-- 负责维护游戏运行时的所有核心数据，包括玩家属性、存盘数据（Profile）、
-- 物品目录（Catalog）以及各种游戏系统的实时状态。
local state = {}

local assets = require('render.assets')
local effects = require('render.effects')
local progression = require('systems.progression')
local mods = require('systems.mods')

local PROFILE_PATH = "profile.lua"

--- serializeLua: 将 Lua 表递归序列化为字符串，用于存盘。
-- @param value (any) 要序列化的值。
-- @param depth (number) 当前缩进深度。
-- @return (string) 序列化后的字符串。
local function serializeLua(value, depth)
    depth = depth or 0
    local t = type(value)
    if t == "table" then
        local parts = { "{" }
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

--- defaultProfile: 生成一个默认的全新存档数据表。
local function defaultProfile()
    return {
        modRanks = {},
        -- 武器特定的赛前 MOD 配置 (8槽系统)
        weaponMods = {
            braton = {
                slots = {}
            }
        },
        warframeMods = { slots = {} },
        companionMods = { slots = {} },
        modTargetWeapon = 'braton',
        modTargetCategory = 'weapons',
        modSystemVersion = 2,

        -- 遗留存档字段 (为了向后兼容)
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

        -- 宠物系统 (当前携带与成长)
        startPetKey = 'pet_magnet',
        petModules = {},
        petRanks = {}
    }
end

--- state.loadProfile: 从磁盘加载玩家存档。
-- 包含复杂的版本迁移逻辑，特别是从旧版全局 MOD 系统迁移到新版武器特定 slot 系统。
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
    -- 确保基础字段存在
    profile.modRanks = profile.modRanks or {}
    profile.weaponMods = profile.weaponMods or {}
    profile.modTargetWeapon = profile.modTargetWeapon or 'braton'
    profile.modTargetCategory = profile.modTargetCategory or 'weapons'
    profile.equippedMods = profile.equippedMods or {} -- legacy
    profile.modOrder = profile.modOrder or {}         -- legacy
    profile.ownedMods = profile.ownedMods or {}
    profile.modSystemVersion = profile.modSystemVersion or 1

    -- 构建验证 MOD key 的集合 (用于清理旧档)
    local function buildModKeySet()
        local set = {}
        for _, category in ipairs({ 'warframe', 'weapons', 'companion' }) do
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

    -- 重新映射键值对以清理旧名前缀
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

    -- 版本迁移逻辑：从 Version 1 -> Version 2
    if profile.modSystemVersion ~= 2 then
        profile.ownedMods = remapKeys(profile.ownedMods)
        profile.modRanks = remapKeys(profile.modRanks)

        for k, v in pairs(profile.modRanks) do
            if type(v) == 'number' then
                profile.modRanks[k] = math.max(0, math.floor(v) - 1)
            end
        end

        -- 将全局装备的 MOD 迁移到默认武器 wand 的配置中
        if next(profile.weaponMods) == nil then
            local legacyEq = profile.equippedMods or {}
            local legacyOrder = profile.modOrder or {}
            local hasLegacy = (next(legacyEq) ~= nil) or (type(legacyOrder) == 'table' and #legacyOrder > 0)
            if hasLegacy then
                profile.weaponMods.braton = profile.weaponMods.braton or { slots = {} }
                local lo = profile.weaponMods.braton
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
                            if ok == nk then
                                found = true
                                break
                            end
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

        -- 处理旧版武器特定 loadout (旧版使用 equippedMods 和 modOrder 分开存储)
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
                            if ok == nk then
                                found = true
                                break
                            end
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
                profile.weaponMods[weaponKey] = { slots = slots }
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

    -- 补全所有已拥有的 MOD 集合
    for k, _ in pairs(profile.modRanks) do profile.ownedMods[k] = true end
    for _, lo in pairs(profile.weaponMods or {}) do
        for _, modKey in pairs((lo and lo.slots) or {}) do
            if modKey then profile.ownedMods[modKey] = true end
        end
    end
    profile.warframeMods = profile.warframeMods or { slots = {} }
    profile.companionMods = profile.companionMods or { slots = {} }
    profile.startPetKey = profile.startPetKey or 'pet_magnet'
    profile.petModules = profile.petModules or {}
    profile.petRanks = profile.petRanks or {}
    profile.currency = profile.currency or 0
    if next(profile.weaponMods) == nil then
        profile.weaponMods.braton = { slots = {} }
    end
    profile.weaponMods[profile.modTargetWeapon] = profile.weaponMods[profile.modTargetWeapon] or { slots = {} }
    return profile
end

function state.saveProfile(profile)
    if not (love and love.filesystem and love.filesystem.write) then return end
    local data = "return " .. serializeLua(profile or defaultProfile())
    pcall(function() love.filesystem.write(PROFILE_PATH, data) end)
end

--- state.applyPersistentMods: 将存档中的 MOD 配置应用到当前的运行清单（inventory）中。
function state.applyPersistentMods()
    state.inventory.mods = {}     -- legacy
    state.inventory.modOrder = {} -- legacy
    state.inventory.weaponMods = {}
    state.inventory.warframeMods = nil
    state.inventory.companionMods = nil
    if not state.profile then return end
    local ranks = state.profile.modRanks or {}

    -- 应用每把武器的专属 MOD
    for weaponKey, lo in pairs(state.profile.weaponMods or {}) do
        local entry = { mods = {}, modOrder = {} }
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
        local entry = { mods = {}, modOrder = {} }
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

    -- 应用战甲与宠物的 MOD
    state.inventory.warframeMods = buildEntry(state.profile.warframeMods)
    state.inventory.companionMods = buildEntry(state.profile.companionMods)
end

--- state.gainGold: 增加玩家在当前 run 中的金币。
-- @param amount (number) 获得金币的基础数值。
-- @param ctx (table) 上下文，包含拾取类型、来源位置、是否显示文字等。
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

    -- 触发拾取插件逻辑 (Augments)
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

    -- 显示浮动金币文字
    if ctx.showText ~= false and state.texts then
        local p = ctx.player or state.player or {}
        local x = ctx.x or p.x or 0
        local y = ctx.y or (p.y and (p.y - 60)) or 0
        table.insert(state.texts,
            { x = x, y = y, text = "+" .. tostring(amt) .. " GOLD", color = { 0.95, 0.9, 0.45 }, life = ctx.life or 0.9 })
    end

    if state and state.augments and state.augments.dispatch then
        ctx.amount = amt
        state.augments.dispatch(state, 'postPickup', ctx)
    end

    return amt
end

--- state.init: 游戏核心状态系统的初始化。
-- 定义了玩家基础属性、战甲类定义、以及每场 run 需要重置的容器（敌人、子弹、掉落物等）。
function state.init()
    math.randomseed(os.time())

    if love and love.filesystem and love.filesystem.setIdentity then
        pcall(function() love.filesystem.setIdentity("vampire") end)
    end

    state.gameState = 'MAIN_MENU'
    state.benchmarkMode = false
    state.noLevelUps = false
    state.testArena = false
    state.pendingLevelUps = 0
    state.gameTimer = 0

    -- === 字体系统 (支持中文) ===
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

    -- === 玩家状态 (Player Entity) ===
    state.player = {
        x = 400,
        y = 300,
        size = 28,
        facing = 1,
        isMoving = false,
        hp = 100,
        maxHp = 100,
        shield = 50,
        maxShield = 50,
        energy = 100,
        maxEnergy = 100,
        level = 0,
        xp = 0,
        xpToNextLevel = xpBase,
        invincibleTimer = 0,
        shieldDelayTimer = 0,
        dash = { charges = 2, maxCharges = 2, rechargeTimer = 0, timer = 0, dx = 1, dy = 0 },
        class = 'volt',                      -- 当前战甲类别
        ability = { cooldown = 0, timer = 0 }, -- 技能状态
        quickAbilityIndex = 1,

        -- 武器插槽 (Warframe 风格: 主手 + 近战)
        weaponSlots = {
            ranged = nil,
            melee = nil,
            reserved = nil     -- 预留位，用于未来的职业被动
        },
        activeSlot = 'ranged', -- 当前激活的武器槽位

        -- 弓箭蓄力状态
        bowCharge = {
            isCharging = false,
            startTime = 0,
            chargeTime = 0,
            weaponKey = nil
        },

        -- === 基础战斗属性 (Unified Stats) ===
        stats = {
            moveSpeed = 110,
            might = 1.0,    -- 威力倍率
            cooldown = 1.0, -- 冷却倍率
            area = 1.0,     -- 攻击范围
            speed = 1.0,    -- 攻击速度
            pickupRange = 120,
            armor = 0,
            regen = 0,
            energyRegen = 2.0,
            maxShield = 100,
            maxEnergy = 100,

            -- WF 四维属性
            abilityStrength = 1.0,   -- 技能强度
            abilityEfficiency = 1.0, -- 技能效率
            abilityDuration = 1.0,   -- 技能持续时间
            abilityRange = 1.0,      -- 技能范围

            dashCharges = 1,
            dashCooldown = 3,
            dashDuration = 0.14,
            dashDistance = 56,
            dashInvincible = 0.14
        }
    }

    -- === 战甲类别定义 (Classes) ===
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
            startRanged = 'braton',
            preferredUpgrades = { 'skana', 'dual_zoren', 'braton', 'lato' },
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
            startMelee = 'skana',
            startRanged = 'braton',
            preferredUpgrades = { 'braton', 'lanka', 'atomos', 'static_orb' },
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
                armor = 15,
                moveSpeed = 155,
                might = 1.0,
                maxShield = 80,
                maxEnergy = 200,
                dashCharges = 1,
                abilityStrength = 1.15,
                statusChance = 0.10
            },
            startWeapon = 'braton',
            startSecondary = 'lato',
            preferredUpgrades = { 'lanka', 'thunder_loop', 'atomos', 'braton' },
            ability = {
                name = "Shock",
                cooldown = 4.0
            }
        }
    }

    state.catalog = require('data.defs.catalog')
    progression.recompute(state)

    -- === 仓库与背包系统 (Inventory) ===
    state.inventory = {
        weapons = {},
        passives = {},
        mods = {},
        modOrder = {},
        weaponMods = {}, -- 存储各武器的 MOD 配置
        augments = {},
        augmentOrder = {},
        weaponSlots = {
            ranged = nil,
            melee = nil,
            extra = nil
        },
        activeSlot = 'ranged',
        canUseExtraSlot = false
    }
    state.augmentState = {}
    state.maxAugmentsPerRun = 4
    state.maxWeaponsPerRun = 2
    state.allowInRunMods = false

    -- === 运行中的核心容器 ===
    state.runCurrency = 0
    state.shop = nil

    state.profile = state.loadProfile()
    state.applyPersistentMods()
    state.enemies = {}      -- 敌人列表
    state.bullets = {}      -- 玩家子弹
    state.enemyBullets = {} -- 敌人子弹
    state.gems = {}         -- 掉落经验
    state.floorPickups = {} -- 地面拾取物
    state.magnetTimer = 60
    state.texts = {}        -- 浮动文字
    state.chests = {}       -- 宝箱
    state.doors = {}        -- 传送门/房门
    state.upgradeOptions = {}
    state.pendingWeaponSwap = nil
    state.pendingUpgradeRequests = {}
    state.activeUpgradeRequest = nil
    state.chainLinks = {}   -- 链式闪电连接线
    state.lightningLinks = {}
    state.quakeEffects = {} -- 震地效果区

    state.spawnTimer = 0
    state.camera = { x = 0, y = 0 }
    state.directorState = { event60 = false, event120 = false }
    state.shakeAmount = 0

    -- === 运行模式 (Run Mode) ===
    -- 'rooms': Hades 风格的房间流转
    -- 'survival': 传统吸血鬼幸存者风格的计时刷怪
    -- 'explore': 关卡/任务模式
    state.runMode = 'rooms'
    state.rooms = {
        enabled = true,
        phase = 'init',
        roomIndex = 0,
        bossRoom = 8,
        useXp = false,
        xpGivesUpgrades = false,
        eliteDropsChests = false,
        eliteRoomBonusUpgrades = 1
    }

    assets.init(state)
    effects.init(state)
end

return state
