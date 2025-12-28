local enemies = require('gameplay.enemies')
local calculator = require('gameplay.calculator')
local player = require('gameplay.player')

local weapons = {}

--- 根据 owner 标识符在当前游戏状态中查找对应的 Actor (玩家或宠物)
--- @param state table 游戏状态
--- @param owner string|nil 所有者标识符 ('player', 'pet', 'pet_active' 或特定 key)
--- @return table|nil 返回找到的 Actor 对象，未找到则返回 nil
local function findOwnerActor(state, owner)
    if not state then return nil end
    -- 默认返回玩家
    if owner == nil or owner == 'player' then
        return state.player
    end
    -- 处理通用宠物标识
    if owner == 'pet' or owner == 'pet_active' then
        local pet = state.pets and state.pets.list and state.pets.list[1]
        if pet and not pet.dead and not pet.downed then
            return pet
        end
    end
    -- 遍历宠物列表寻找匹配特定 key 的存活宠物
    local list = state.pets and state.pets.list
    if type(list) == 'table' then
        for _, a in ipairs(list) do
            if a and not a.dead and not a.downed and (a.ownerKey == owner or a.key == owner) then
                return a
            end
        end
    end
    return nil
end

local function cloneStats(base)
    local stats = {}
    for k, v in pairs(base or {}) do
        if type(v) == 'table' then
            local t = {}
            for kk, vv in pairs(v) do t[kk] = vv end
            stats[k] = t
        else
            stats[k] = v
        end
    end
    if stats.area == nil then stats.area = 1 end
    if stats.pierce == nil then stats.pierce = 1 end
    if stats.amount == nil then stats.amount = 0 end
    return stats
end

local function getProjectileCount(stats)
    local amt = (stats and stats.amount or 0) + 1
    local count = math.floor(amt)
    if math.random() < (amt - count) then
        count = count + 1
    end
    return math.max(1, count)
end

local function updateQuakes(state, dt)
    if not state.quakeEffects or #state.quakeEffects == 0 then return end
    for i = #state.quakeEffects, 1, -1 do
        local q = state.quakeEffects[i]
        q.t = (q.t or 0) + dt
        local dur = q.duration or 1

        if q.t < 0 then
            q.lastRadius = 0
        else
            local progress = math.max(0, math.min(1, q.t / dur))
            local currR = (q.radius or 220) * progress
            local lastR = q.lastRadius or 0
            q.lastRadius = currR
            local currR2 = currR * currR
            local lastR2 = lastR * lastR
            q.hit = q.hit or {}

            local instance = calculator.createInstance({
                damage = q.damage or 0,
                critChance = q.critChance,
                critMultiplier = q.critMultiplier,
                statusChance = q.statusChance,
                effectType = q.effectType or 'HEAVY',
                effectData = { duration = q.stun or 0.6 },
                weaponTags = q.tags,
                knock = false,
                knockForce = q.knock
            })

            local cx, cy = q.x or state.player.x, q.y or state.player.y
            for _, e in ipairs(state.enemies) do
                if not q.hit[e] then
                    local dx = e.x - cx
                    local dy = e.y - cy
                    local d2 = dx * dx + dy * dy
                    if d2 <= currR2 and d2 >= lastR2 then
                        calculator.applyHit(state, e, instance)
                        q.hit[e] = true
                    end
                end
            end

            if q.t >= dur then
                table.remove(state.quakeEffects, i)
            end
        end
    end
end

function weapons.calculateStats(state, weaponKey)
    local invWeapon = state.inventory.weapons[weaponKey]
    if not invWeapon then return nil end

    local stats = cloneStats(invWeapon.stats)
    local weaponDef = state.catalog[weaponKey]
    local weaponTags = weaponDef and weaponDef.tags or {}

    -- 旧版被动系统已移除，所有强化通过 state.inventory.weaponMods 或 base stats 处理

    -- 应用统一 MOD 系统 (mods.lua)
    local modsModule = require('systems.mods')
    stats = modsModule.applyWeaponMods(state, weaponKey, stats)

    -- 应用运行时 MOD（游戏过程中收集的）
    stats = modsModule.applyRunWeaponMods(state, weaponKey, stats)

    local newMax = stats.maxMagazine or stats.magazine
    if newMax and invWeapon.magazine ~= nil then
        invWeapon.maxMagazine = math.floor(newMax)
        if invWeapon.magazine ~= nil then
            invWeapon.magazine = math.min(invWeapon.magazine, invWeapon.maxMagazine)
        end
    end
    if stats.reloadTime then
        invWeapon.reloadTime = stats.reloadTime
    end

    return stats
end

function weapons.addWeapon(state, key, owner, slotType)
    local proto = state.catalog[key]
    if not proto then
        print("Error: Attempted to add invalid weapon key: " .. tostring(key))
        return
    end
    local stats = cloneStats(proto.base)
    -- 从参数、catalog 或默认值确定槽位类型
    local slot = slotType or proto.slotType or 'primary'

    -- 初始化弹药系统（如果武器使用弹药）
    local magazine = proto.base.magazine
    local reserve = proto.base.reserve

    state.inventory.weapons[key] = {
        level = 1,
        timer = 0,
        stats = stats,
        owner = owner,
        slotType = slot,
        -- 弹药状态（nil 表示无限弹药）
        magazine = magazine,
        reserve = reserve,
        isReloading = false,
        reloadTimer = 0,
        -- 扩散与后坐力状态
        currentBloom = 0,
        lastFireTime = 0
    }
end

-- =============================================================================
-- WARFRAME 风格武器槽位系统
-- =============================================================================

-- 装备武器到指定槽位（ranged/melee/extra）
function weapons.equipToSlot(state, slotType, weaponKey)
    local proto = state.catalog[weaponKey]
    if not proto then
        print("[WEAPONS] 无效武器key: " .. tostring(weaponKey))
        return false
    end

    -- 验证槽位类型
    if slotType ~= 'ranged' and slotType ~= 'melee' and slotType ~= 'extra' then
        print("[WEAPONS] 无效槽位类型: " .. tostring(slotType))
        return false
    end

    -- 检查额外槽位权限
    if slotType == 'extra' and not state.inventory.canUseExtraSlot then
        print("[WEAPONS] 额外槽位未解锁")
        return false
    end

    -- 克隆基础属性
    local stats = cloneStats(proto.base)

    -- 创建武器实例
    local weaponInstance = {
        key = weaponKey,
        level = 1,
        timer = 0,
        stats = stats,
        slotType = slotType,
        -- 弹药系统
        magazine = proto.base.magazine,
        maxMagazine = proto.base.maxMagazine or proto.base.magazine,
        reserve = proto.base.reserve,
        maxReserve = proto.base.maxReserve or proto.base.reserve,
        reloadTime = proto.base.reloadTime,
        isReloading = false,
        reloadTimer = 0
    }

    -- 装备到槽位
    state.inventory.weaponSlots[slotType] = weaponInstance

    -- 同时添加到旧版武器表以保持兼容性
    state.inventory.weapons[weaponKey] = weaponInstance

    print(string.format("[WEAPONS] 已装备 %s 到 %s 槽位", weaponKey, slotType))
    return true
end

-- 获取当前激活的武器
function weapons.getActiveWeapon(state)
    local activeSlot = state.inventory.activeSlot or 'ranged'
    return state.inventory.weaponSlots[activeSlot]
end

-- 获取指定槽位的武器
function weapons.getSlotWeapon(state, slotType)
    return state.inventory.weaponSlots[slotType]
end

-- 切换到另一个武器槽位
function weapons.switchSlot(state, slotType)
    if slotType == 'extra' and not state.inventory.canUseExtraSlot then
        return false
    end
    if state.inventory.weaponSlots[slotType] then
        state.inventory.activeSlot = slotType
        return true
    end
    return false
end

-- 循环切换武器槽位（WF 风格 'F' 键切换）
function weapons.cycleSlots(state)
    local inv = state.inventory
    if not inv then return false end
    local slots = { 'ranged', 'melee', 'extra' }
    local current = inv.activeSlot or 'ranged'
    local currentIndex = 1
    for i, s in ipairs(slots) do
        if s == current then
            currentIndex = i
            break
        end
    end

    -- 循环尝试下一个槽位
    for i = 1, #slots do
        local nextIndex = (currentIndex + i - 1) % #slots + 1
        local nextSlot = slots[nextIndex]
        if nextSlot == 'extra' and not inv.canUseExtraSlot then
            -- 跳过未启用的额外槽位
        elseif inv.weaponSlots[nextSlot] then
            inv.activeSlot = nextSlot
            return true
        end
    end
    return false
end

-- 统计已装备的武器槽位数量
function weapons.countSlots(state)
    local count = 0
    for _, slot in pairs({ 'ranged', 'melee', 'extra' }) do
        if state.inventory.weaponSlots[slot] then
            count = count + 1
        end
    end
    return count
end

function weapons.spawnProjectile(state, type, x, y, target, statsOverride)
    local wStats = statsOverride or weapons.calculateStats(state, type)
    if not wStats then return end

    -- 数据分析：记录射击
    local analytics = require('systems.analytics')
    analytics.recordShot(type)

    if state and state.augments and state.augments.dispatch then
        local ctx = { weaponKey = type, weaponStats = wStats, target = target, x = x, y = y }
        state.augments.dispatch(state, 'onShoot', ctx)
        if ctx.cancel then return end
        wStats = ctx.weaponStats or wStats
        target = ctx.target or target
        x = ctx.x or x
        y = ctx.y or y
    end

    local weaponDef = state.catalog[type] or {}
    local weaponTags = weaponDef.tags
    local effectType = weaponDef.effectType or wStats.effectType
    local finalDmg = math.floor((wStats.damage or 0) * (state.player.stats.might or 1))
    local area = (wStats.area or 1) * (state.player.stats.area or 1)

    -- 默认通用投射物生成逻辑，behaviors 可覆盖或使用此逻辑
    local angle = 0
    if target then
        angle = math.atan2(target.y - y, target.x - x)
    elseif wStats.rotation then
        angle = wStats.rotation
    end

    local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)

    -- 命中大小缩放辅助函数
    local function getHitSizeScaleForType(t)
        if not (state and state.weaponSprites and state.weaponSprites[t]) then return 1 end
        return (state.weaponSpriteScale and state.weaponSpriteScale[t]) or 1
    end

    local hitScale = getHitSizeScaleForType(type)

    -- 特殊投射物类型的生成逻辑正在逐步迁移到 behaviors 中
    -- 目前为简单投射物保留通用生成器

    -- 注：大部分复杂逻辑现在由 behaviors 调用特定投射物配置处理

    if type == 'axe' then
        local vx = (math.random() - 0.5) * 200
        local vy = -spd
        local spin = math.atan2(vy, vx)
        local size = (wStats.size or 12) * area
        local bullet = {
            type = 'axe',
            x = x,
            y = y,
            vx = vx,
            vy = vy,
            life = 3,
            size = size,
            damage = finalDmg,
            rotation =
                spin,
            hitTargets = {},
            effectType = effectType,
            weaponTags = weaponTags,
            elements = wStats.elements,
            damageBreakdown =
                wStats.damageBreakdown,
            critChance = wStats.critChance,
            critMultiplier = wStats.critMultiplier,
            statusChance =
                wStats.statusChance,
            hitSizeScale = hitScale
        }
        table.insert(state.bullets, bullet)
        return
    elseif type == 'death_spiral' then
        -- 由 behavior 处理，但如果直接调用此处：
        local count = 8 + (wStats.amount or 0)
        local baseSize = (wStats.size or 14) * area
        for i = 1, count do
            local spin = (i - 1) / count * math.pi * 2
            local bullet = {
                type = 'death_spiral',
                x = x,
                y = y,
                vx = math.cos(spin) * spd,
                vy = math.sin(spin) * spd,
                life = 3,
                size = baseSize,
                damage = finalDmg,
                rotation = spin,
                angularVel = 1.5,
                hitTargets = {},
                effectType = effectType,
                weaponTags = weaponTags,
                elements = wStats.elements,
                damageBreakdown = wStats.damageBreakdown,
                critChance = wStats.critChance,
                critMultiplier = wStats.critMultiplier,
                statusChance = wStats.statusChance,
                hitSizeScale = hitScale
            }
            table.insert(state.bullets, bullet)
        end
        return
    elseif type == 'absolute_zero' then
        local radius = (wStats.radius or 0) * area
        local bullet = {
            type = 'absolute_zero',
            x = x,
            y = y,
            vx = 0,
            vy = 0,
            life = wStats.duration or 2.5,
            size = radius,
            radius = radius,
            damage = finalDmg,
            effectType = effectType,
            weaponTags = weaponTags,
            effectDuration = wStats.duration,
            tick = 0,
            elements = wStats.elements,
            damageBreakdown = wStats.damageBreakdown,
            critChance = wStats.critChance,
            critMultiplier = wStats.critMultiplier,
            statusChance = wStats.statusChance
        }
        table.insert(state.bullets, bullet)
        return
    end

    -- 通用投射物回退逻辑
    local baseSize = wStats.size or 6
    local size = baseSize * area
    local bullet = {
        type = type,
        x = x,
        y = y,
        spawnX = x,
        spawnY = y,
        vx = math.cos(angle) * spd,
        vy = math.sin(angle) * spd,
        life = wStats.life or 2,
        size = size,
        damage = finalDmg,
        effectType = effectType,
        weaponTags = weaponTags,
        pierce = wStats.pierce or 1,
        rotation = angle,
        effectDuration = wStats.duration,
        splashRadius = wStats.splashRadius,
        effectRange = wStats.staticRange,
        chain = wStats.chain,
        allowRepeat = wStats.allowRepeat,
        elements = wStats.elements,
        damageBreakdown = wStats.damageBreakdown,
        critChance = wStats.critChance,
        critMultiplier = wStats.critMultiplier,
        statusChance = wStats.statusChance,
        hitSizeScale = hitScale,
        weaponKey = type, -- 传递武器key用于命中追踪
        -- 距离衰减参数
        falloffStart = wStats.falloffStart,
        falloffEnd = wStats.falloffEnd,
        falloffMin = wStats.falloffMin
    }
    table.insert(state.bullets, bullet)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onProjectileSpawned', { weaponKey = type, bullet = bullet })
    end
end

-- =========================================================================================
-- 策略模式行为表 (STRATEGY PATTERN BEHAVIORS)
-- =========================================================================================

local Behaviors = {}

-- 射击最近敌人行为
function Behaviors.SHOOT_NEAREST(state, weaponKey, w, stats, params, sx, sy)
    local range = math.max(1, math.floor(stats.range or 600))
    local losOpts = state.world and state.world.enabled and { requireLOS = true } or nil

    -- 优先使用玩家瞄准方向
    local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local aimDx, aimDy = nil, nil

    local baseAngle = nil
    local dist = range

    if isPlayerWeapon and player.getAimDirection then
        -- 使用玩家瞄准方向
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
        if aimDx and aimDy then
            baseAngle = math.atan2(aimDy, aimDx)
        end
    end

    if not baseAngle then
        -- 自动瞄准：寻找最近敌人
        local t = enemies.findNearestEnemy(state, range, sx, sy, losOpts)
        if t then
            baseAngle = math.atan2(t.y - sy, t.x - sx)
        end
    end

    if baseAngle then
        if state.playSfx then state.playSfx('shoot') end
        local shots = getProjectileCount(stats)
        local spread = 0.12

        for i = 1, shots do
            local ang = baseAngle + (i - (shots + 1) / 2) * spread
            local target = { x = sx + math.cos(ang) * dist, y = sy + math.sin(ang) * dist }
            weapons.spawnProjectile(state, weaponKey, sx, sy, target, stats)
        end
        return true
    end
    return false
end

-- 近战挥砍行为 - 扇形攻击判定
function Behaviors.MELEE_SWING(state, weaponKey, w, stats, params, sx, sy)
    local p = state.player
    if not p or not p.meleeState then return false end

    local melee = p.meleeState

    -- 只在 swing 阶段造成伤害，且未造成过伤害
    if melee.phase ~= 'swing' or melee.damageDealt then
        return false
    end

    -- 数据分析：记录挥砍
    local analytics = require('systems.analytics')
    analytics.recordShot(weaponKey)

    -- 参数设置
    params = params or {}
    local arcWidth = params.arcWidth or 1.2 -- 约70度（弧度）
    local range = stats.range or 80

    local aimAngle = p.aimAngle or 0

    -- 基于攻击类型的伤害倍率
    local mult = 1
    if melee.attackType == 'light' then
        mult = 1
    elseif melee.attackType == 'heavy' then
        mult = 3
    elseif melee.attackType == 'finisher' then
        mult = 5
    end

    local baseDamage = (stats.damage or 40) * mult
    local might = p.stats and p.stats.might or 1
    local meleeMult = ((p.stats and p.stats.meleeDamageMult) or 1) * (p.exaltedBladeDamageMult or 1)
    local finalDamage = math.floor(baseDamage * might * meleeMult)

    -- 近战连击倍率
    local combo = p.meleeCombo or 0
    local comboTier = math.floor(combo / 20)
    local comboMult = 1 + comboTier * 0.5

    -- 击退力度
    local knockback = (stats.knockback or 80) * mult

    -- 获取武器定义以读取 tags
    local weaponDef = state.catalog and state.catalog[weaponKey]

    -- 检测扇形范围内所有敌人
    local hitCount = 0
    local hitOccurred = false
    for _, e in ipairs(state.enemies) do
        if e.health and e.health > 0 then
            local dx = e.x - sx
            local dy = e.y - sy
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist <= range then
                -- 检查是否在扇形范围内
                local angleToEnemy = math.atan2(dy, dx)
                local angleDiff = math.abs(angleToEnemy - aimAngle)
                -- 归一化角度差
                if angleDiff > math.pi then angleDiff = 2 * math.pi - angleDiff end

                if angleDiff <= arcWidth / 2 then
                    -- 使用 calculator.applyHit 进行正确的伤害计算（暴击、状态、护甲）
                    local result = calculator.applyHit(state, e, {
                        damage = finalDamage * comboMult,
                        critChance = stats.critChance or 0,
                        critMultiplier = stats.critMultiplier or 1.5,
                        statusChance = stats.statusChance or 0,
                        effectType = stats.effectType or (weaponDef and weaponDef.effectType),
                        elements = stats.elements,
                        damageBreakdown = stats.damageBreakdown,
                        weaponKey = weaponKey, -- 传递武器key用于命中追踪
                        weaponTags = weaponDef and weaponDef.tags,
                        knock = knockback > 0,
                        knockForce = knockback * 0.1
                    })

                    if result and result.damage and result.damage > 0 then
                        hitOccurred = true
                    end
                    hitCount = hitCount + 1
                end
            end
        end
    end

    -- 在挥砍扇形范围内销毁敌方子弹
    if state.enemyBullets then
        for i = #state.enemyBullets, 1, -1 do
            local b = state.enemyBullets[i]
            local dx = b.x - sx
            local dy = b.y - sy
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist <= range then
                local angleToB = math.atan2(dy, dx)
                local angleDiff = math.abs(angleToB - aimAngle)
                if angleDiff > math.pi then angleDiff = 2 * math.pi - angleDiff end

                if angleDiff <= arcWidth / 2 then
                    -- 销毁子弹
                    table.remove(state.enemyBullets, i)

                    -- 视觉特效
                    if state.texts then
                        table.insert(state.texts,
                            { x = b.x, y = b.y, text = "×", color = { 0.8, 0.9, 1 }, life = 0.3, scale = 0.8 })
                    end
                    if state.playSfx then state.playSfx('gem') end
                end
            end
        end
    end

    melee.damageDealt = true

    if p.exaltedBladeActive then
        local waveMult = 0.6
        if melee.attackType == 'heavy' then
            waveMult = 0.9
        elseif melee.attackType == 'finisher' then
            waveMult = 1.2
        end
        local waveDamage = math.max(1, math.floor(finalDamage * waveMult))
        local areaScale = (p.stats and p.stats.area) or 1
        local waveSize = 16 * math.max(0.6, math.sqrt(areaScale))
        local waveSpeed = 900 * ((p.stats and p.stats.speed) or 1)
        local waveLife = 0.6 + 0.1 * math.sqrt(areaScale)
        local ang = aimAngle or 0
        local wave = {
            type = 'thousand_edge',
            x = sx + math.cos(ang) * 10,
            y = sy + math.sin(ang) * 10,
            spawnX = sx,
            spawnY = sy,
            vx = math.cos(ang) * waveSpeed,
            vy = math.sin(ang) * waveSpeed,
            life = waveLife,
            size = waveSize,
            damage = waveDamage,
            effectType = 'SLASH',
            weaponTags = { 'ability', 'melee', 'exalted' },
            elements = { 'SLASH' },
            damageBreakdown = { SLASH = 1 },
            critChance = stats.critChance or 0,
            critMultiplier = stats.critMultiplier or 1.5,
            statusChance = stats.statusChance or 0,
            pierce = 4,
            rotation = ang
        }
        table.insert(state.bullets, wave)
    end

    -- 重击/终结技的屏幕震动
    if melee.attackType == 'heavy' or melee.attackType == 'finisher' then
        state.shakeAmount = (state.shakeAmount or 0) + (melee.attackType == 'finisher' and 8 or 4)
    end

    -- 增加全局近战连击数
    if hitOccurred then
        p.meleeCombo = (p.meleeCombo or 0) + hitCount
        p.meleeComboTimer = 5.0 -- 重置衰减计时器

        -- VOLT 被动：静电释放 - 近战命中时释放累积的电荷
        if p.class == 'volt' and (p.staticCharge or 0) > 10 then
            local staticDamage = math.floor(p.staticCharge * 2) -- 每点电荷2点伤害
            p.staticCharge = 0                                  -- 消耗所有电荷

            -- 对扇形范围内所有敌人造成电属性伤害
            local ok, calc = pcall(require, 'gameplay.calculator')
            for _, e in ipairs(state.enemies) do
                if e.health and e.health > 0 then
                    local dx = e.x - sx
                    local dy = e.y - sy
                    local dist = math.sqrt(dx * dx + dy * dy)

                    if dist <= range then
                        local angleToEnemy = math.atan2(dy, dx)
                        local angleDiff = math.abs(angleToEnemy - aimAngle)
                        if angleDiff > math.pi then angleDiff = 2 * math.pi - angleDiff end

                        if angleDiff <= arcWidth / 2 then
                            -- 应用静电释放伤害
                            if ok and calc then
                                local staticInstance = calc.createInstance({
                                    damage = staticDamage,
                                    critChance = 0.25,
                                    critMultiplier = 2.0,
                                    statusChance = 0.8,
                                    elements = { 'ELECTRIC' },
                                    damageBreakdown = { ELECTRIC = 1 },
                                    weaponTags = { 'ability', 'electric', 'melee' }
                                })
                                calc.applyHit(state, e, staticInstance)
                            else
                                e.health = (e.health or 0) - staticDamage
                            end

                            -- 视觉特效：从玩家到敌人的闪电弧
                            state.voltLightningChains = state.voltLightningChains or {}
                            table.insert(state.voltLightningChains, {
                                segments = { {
                                    x1 = sx,
                                    y1 = sy,
                                    x2 = e.x,
                                    y2 = e.y,
                                    width = 10
                                } },
                                timer = 0.25,
                                alpha = 1.0
                            })
                        end
                    end
                end
            end

            -- 视觉反馈
            if state.spawnEffect then
                state.spawnEffect('shock', sx, sy, 1.5)
            end
            if state.texts then
                table.insert(state.texts, {
                    x = sx,
                    y = sy - 40,
                    text = string.format("静电释放! +%d", staticDamage),
                    color = { 0.4, 0.8, 1 },
                    life = 1.0
                })
            end
            if state.playSfx then state.playSfx('hit') end
        end
    end

    return hitCount > 0
end

-- 弓箭蓄力射击行为 - 长按蓄力提高伤害
function Behaviors.CHARGE_SHOT(state, weaponKey, w, stats, params, sx, sy)
    local p = state.player
    if not p or not p.bowCharge then return false end

    -- 等待蓄力释放（pendingRelease 标志由 player.lua 设置）
    if not p.bowCharge.pendingRelease then
        return false
    end

    -- 获取蓄力时间
    local chargeTime = p.bowCharge.chargeTime or 0
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local maxChargeTime = weaponDef and weaponDef.maxChargeTime or 2.0
    local minChargeMult = weaponDef and weaponDef.minChargeMult or 0.5
    local maxChargeMult = weaponDef and weaponDef.maxChargeMult or 2.0

    -- 计算蓄力倍率（线性插值）
    local t = math.min(1, chargeTime / maxChargeTime)
    local chargeMult = minChargeMult + t * (maxChargeMult - minChargeMult)

    -- 修改属性副本
    local modStats = {}
    for k, v in pairs(stats) do modStats[k] = v end
    modStats.damage = stats.damage * chargeMult

    -- 蓄力速度加成
    if weaponDef and weaponDef.chargeSpeedBonus then
        modStats.speed = (stats.speed or 600) * (0.5 + 0.5 * chargeMult)
    end

    -- 满蓄力暴击加成 (+25%)
    if t >= 1.0 then
        modStats.critChance = (stats.critChance or 0) + 0.25
    end

    -- 发射箭矢
    local range = math.max(1, math.floor(modStats.range or 600))
    local losOpts = state.world and state.world.enabled and { requireLOS = true } or nil
    local aimDx, aimDy = nil, nil
    if player.getAimDirection then
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
    end

    local baseAngle = nil
    if aimDx and aimDy then
        baseAngle = math.atan2(aimDy, aimDx)
    else
        local t_enemy = enemies.findNearestEnemy(state, range, sx, sy, losOpts)
        if t_enemy then
            baseAngle = math.atan2(t_enemy.y - sy, t_enemy.x - sx)
        else
            -- 未找到目标：手动瞄准回退（空放）
            if love and love.mouse then
                local mx, my = love.mouse.getPosition()
                local camX = state.camera and state.camera.x or 0
                local camY = state.camera and state.camera.y or 0
                baseAngle = math.atan2((my + camY) - sy, (mx + camX) - sx)
            else
                baseAngle = (p.facing or 1) > 0 and 0 or math.pi
            end
        end
    end

    if baseAngle then
        if state.playSfx then state.playSfx('shoot') end
        local target = { x = sx + math.cos(baseAngle) * range, y = sy + math.sin(baseAngle) * range }
        weapons.spawnProjectile(state, weaponKey, sx, sy, target, modStats)

        -- 重置蓄力状态
        p.bowCharge.isCharging = false
        p.bowCharge.pendingRelease = false
        p.bowCharge.chargeTime = 0
        return true
    end

    -- 无目标，重置蓄力
    p.bowCharge.isCharging = false
    p.bowCharge.pendingRelease = false
    p.bowCharge.chargeTime = 0
    return false
end

-- 方向射击行为
function Behaviors.SHOOT_DIRECTIONAL(state, weaponKey, w, stats, params, sx, sy)
    local range = math.max(1, math.floor(stats.range or 550))
    local losOpts = state.world and state.world.enabled and { requireLOS = true } or nil

    -- 如果可用，使用玩家瞄准方向
    local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local aimDx, aimDy = nil, nil
    if isPlayerWeapon and player.getAimDirection then
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
    end

    local baseAngle = nil
    local dist = range

    if aimDx and aimDy then
        baseAngle = math.atan2(aimDy, aimDx)
    else
        local t = enemies.findNearestEnemy(state, range, sx, sy, losOpts)
        if t then
            baseAngle = math.atan2(t.y - sy, t.x - sx)
        end
    end

    if baseAngle then
        local shots = getProjectileCount(stats)
        local spread = 0.08

        -- 应用扩散
        local bloomVal = w.currentBloom or 0

        -- 反馈效果
        state.shakeAmount = (state.shakeAmount or 0) + 1.5
        if state.spawnEffect then
            state.spawnEffect('hit', sx + math.cos(baseAngle) * 20, sy + math.sin(baseAngle) * 20, 0.6)
        end

        for i = 1, shots do
            local bloomOffset = (math.random() - 0.5) * bloomVal * 0.4
            local ang = baseAngle + (i - (shots + 1) / 2) * spread + bloomOffset
            local target = { x = sx + math.cos(ang) * dist, y = sy + math.sin(ang) * dist }
            weapons.spawnProjectile(state, weaponKey, sx, sy, target, stats)
        end

        -- 增加扩散值
        local bloomInc = stats and stats.bloomInc or 0.1
        w.currentBloom = math.min(1.5, (w.currentBloom or 0) + bloomInc)

        return true
    end
    return false
end

-- 霍弹枪扩散模式 - 在锥形范围内发射多个弹丸
function Behaviors.SHOOT_SPREAD(state, weaponKey, w, stats, params, sx, sy)
    local range = math.max(1, math.floor(stats.range or 300))
    local losOpts = state.world and state.world.enabled and { requireLOS = true } or nil

    -- 获取目标方向
    local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local aimDx, aimDy = nil, nil
    if isPlayerWeapon and player.getAimDirection then
        aimDx, aimDy = player.getAimDirection(state, weaponDef)
    end

    local baseAngle = nil
    if aimDx and aimDy then
        baseAngle = math.atan2(aimDy, aimDx)
    else
        local t = enemies.findNearestEnemy(state, range * 1.5, sx, sy, losOpts)
        if t then
            baseAngle = math.atan2(t.y - sy, t.x - sx)
        end
    end

    if baseAngle then
        if state.playSfx then state.playSfx('shoot') end

        -- 反馈效果
        state.shakeAmount = (state.shakeAmount or 0) + 3.0
        if state.spawnEffect then
            state.spawnEffect('blast_hit', sx + math.cos(baseAngle) * 15, sy + math.sin(baseAngle) * 15, 0.8)
        end

        -- 霍弹枪参数
        params = params or {}
        local pellets = params.pellets or 8
        local spreadAngle = params.spread or 0.4 -- 弧度单位的扩散角

        -- 将扩散应用到基础角度
        local bloomVal = w.currentBloom or 0
        spreadAngle = spreadAngle + bloomVal * 0.5

        -- 发射所有弹丸
        for i = 1, pellets do
            -- 在锥形范围内随机扩散
            local angleOffset = (math.random() - 0.5) * spreadAngle
            local ang = baseAngle + angleOffset

            -- 每个弹丸的伤害略有差异
            local pelletStats = {}
            for k, v in pairs(stats) do pelletStats[k] = v end
            pelletStats.damage = math.floor((stats.damage or 10) * (0.9 + math.random() * 0.2))

            -- 较短射程带衰减
            local pelletRange = range * (0.8 + math.random() * 0.4)
            local target = { x = sx + math.cos(ang) * pelletRange, y = sy + math.sin(ang) * pelletRange }

            weapons.spawnProjectile(state, weaponKey, sx, sy, target, pelletStats)
        end

        -- 增加扩散值
        local bloomInc = stats and stats.bloomInc or 0.2
        w.currentBloom = math.min(1.5, (w.currentBloom or 0) + bloomInc)

        return true
    end
    return false
end

-- 随机方向射击行为
function Behaviors.SHOOT_RANDOM(state, weaponKey, w, stats, params, sx, sy)
    if state.playSfx then state.playSfx('shoot') end
    local shots = getProjectileCount(stats)
    for i = 1, shots do
        weapons.spawnProjectile(state, weaponKey, sx, sy, nil, stats)
    end
    return true
end

-- 环形射击行为
function Behaviors.SHOOT_RADIAL(state, weaponKey, w, stats, params, sx, sy)
    if state.playSfx then state.playSfx('shoot') end
    -- 注：spawnProjectile 对 death_spiral 有旧版处理，但可以完全移到此处
    -- 目前委托给 spawnProjectile，它内部处理 'death_spiral' 类型的环形循环
    weapons.spawnProjectile(state, weaponKey, sx, sy, nil, stats)
    return true
end

-- 光环持续伤害行为
function Behaviors.AURA(state, weaponKey, w, stats, params, sx, sy)
    local hit = false
    local actualDmg = math.floor((stats.damage or 0) * (state.player.stats.might or 1))
    local actualRadius = (stats.radius or 0) * (stats.area or 1) * (state.player.stats.area or 1)
    local weaponDef = state.catalog[weaponKey]
    local effectType = weaponDef.effectType or stats.effectType
    local lifesteal = stats.lifesteal
    local effectData = nil

    if weaponKey == 'ice_ring' then
        effectData = { duration = stats.duration or weaponDef.base.duration }
    end

    local instance = calculator.createInstance({
        damage = actualDmg,
        critChance = stats.critChance,
        critMultiplier = stats.critMultiplier,
        statusChance = stats.statusChance,
        effectType = effectType,
        effectData = effectData,
        elements = stats.elements,
        damageBreakdown = stats.damageBreakdown,
        weaponTags = weaponDef.tags,
        knock = true,
        knockForce = stats.knockback or 0
    })

    for _, e in ipairs(state.enemies) do
        local d = math.sqrt((sx - e.x) ^ 2 + (sy - e.y) ^ 2)
        if d < actualRadius then
            calculator.applyHit(state, e, instance)
            if lifesteal and actualDmg > 0 then
                local shooter = findOwnerActor(state, w.owner)
                if shooter and shooter.hp and shooter.maxHp then
                    local heal = math.max(1, math.floor(actualDmg * lifesteal))
                    shooter.hp = math.min(shooter.maxHp, shooter.hp + heal)
                end
            end
            hit = true
        end
    end

    return hit
end

-- 生成特殊投射物行为
function Behaviors.SPAWN(state, weaponKey, w, stats, params, sx, sy)
    local spawnType = (params and params.type) or weaponKey
    if spawnType == 'absolute_zero' and state.playSfx then state.playSfx('freeze') end
    weapons.spawnProjectile(state, spawnType, sx, sy, nil, stats)
    return true
end

-- 全局效果行为（如地震）
function Behaviors.GLOBAL(state, weaponKey, w, stats, params, sx, sy)
    if weaponKey == 'earthquake' then
        local dmg = math.floor((stats.damage or 0) * (state.player.stats.might or 1))
        local stunDuration = stats.duration or 0.6
        local knock = stats.knockback or 0
        local areaScale = (stats.area or 1) * (state.player.stats.area or 1)
        local quakeRadius = 220 * math.sqrt(areaScale)
        local weaponDef = state.catalog[weaponKey]

        if state.playSfx then state.playSfx('hit') end
        state.shakeAmount = math.max(state.shakeAmount or 0, 6)

        local waves = { 1.0, 0.7, 0.5 }
        local delay = 0
        for _, factor in ipairs(waves) do
            table.insert(state.quakeEffects, {
                t = -delay,
                duration = 1.2,
                radius = quakeRadius,
                x = sx,
                y = sy,
                damage = math.floor(dmg * factor),
                stun = stunDuration,
                knock = knock,
                effectType = weaponDef.effectType or stats.effectType or 'HEAVY',
                tags = weaponDef.tags,
                critChance = stats.critChance,
                critMultiplier = stats.critMultiplier,
                statusChance = stats.statusChance
            })
            delay = delay + 0.5
        end
    end
    return true
end

-- 武器系统主更新函数
function weapons.update(state, dt)
    updateQuakes(state, dt)
    -- WF风格：从 inventory.activeSlot 读取（ranged/melee/extra）
    local activeSlot = state.inventory and state.inventory.activeSlot or 'ranged'

    for key, w in pairs((state.inventory and state.inventory.weapons) or {}) do
        -- 扩散衰减：不开火时衰减更快
        local bloomDecayRate = 1.0
        if w.currentBloom and w.currentBloom > 0 then
            w.currentBloom = math.max(0, w.currentBloom - dt * bloomDecayRate)
        end

        w.timer = (w.timer or 0) - dt
        if w.timer <= 0 then
            local shooter = findOwnerActor(state, w.owner)
            if not shooter or shooter.dead or shooter.downed then
                w.timer = 0
            else
                local sx, sy = shooter.x, shooter.y
                local computedStats = weapons.calculateStats(state, key) or w.stats
                local actualCD = (computedStats.cd or w.stats.cd) * (state.player.stats.cooldown or 1)
                local atkMult = (state.player and state.player.attackSpeedBuffMult) or 1
                if state.player and state.player.stats and state.player.stats.attackSpeedMult then
                    atkMult = atkMult * state.player.stats.attackSpeedMult
                end
                if atkMult > 0 then
                    actualCD = actualCD / atkMult
                end

                -- 策略查找
                local def = state.catalog[key]
                local behaviorName = def and def.behavior
                local behaviorFunc = behaviorName and Behaviors[behaviorName]

                -- 检查武器槽位 - 只有在激活槽位时才开火（玩家武器）
                local isPlayerWeapon = (w.owner == nil or w.owner == 'player')
                local weaponSlot = w.slotType or def.slotType or 'ranged'
                local isInActiveSlot = (weaponSlot == activeSlot)

                -- 检查玩家是否在开火（大多数武器需要，光环/近战/蓄力除外）
                -- 光环、近战、蓄力射击和宠物武器有自己的逻辑
                local isAura = (behaviorName == 'AURA')
                local isMelee = (behaviorName == 'MELEE_SWING')
                local isChargeShot = (behaviorName == 'CHARGE_SHOT')
                local needsFiring = isPlayerWeapon and not isAura and not isMelee and not isChargeShot
                local canFire = not needsFiring or (state.player.isFiring == true)

                -- 如果玩家武器不在激活槽位则跳过
                if isPlayerWeapon and not isInActiveSlot then
                    w.timer = 0 -- 保持就绪但不开火
                elseif w.isReloading then
                    -- 武器正在换弹，跳过开火
                    w.timer = 0
                elseif behaviorFunc and canFire then
                    -- 开火前检查弹药
                    local hasAmmo = true
                    if w.magazine ~= nil then
                        if w.magazine <= 0 then
                            hasAmmo = false
                            -- 弹夹清空时自动换弹
                            if (w.reserve or 0) > 0 then
                                local reloadTime = w.reloadTime or (def and def.base.reloadTime) or 1.5
                                w.isReloading = true
                                w.reloadTimer = reloadTime
                            end
                        end
                    end

                    if hasAmmo then
                        local fired = behaviorFunc(state, key, w, computedStats, def.behaviorParams, sx, sy)
                        if fired then
                            -- 成功开火时消耗弹药
                            if w.magazine ~= nil then
                                w.magazine = math.max(0, w.magazine - 1)
                            end
                            w.timer = actualCD
                        end
                    else
                        w.timer = 0
                    end
                elseif behaviorFunc and needsFiring and not canFire then
                    -- 玩家武器等待攻击输入，不重置计时器
                    w.timer = 0
                else
                    -- 回退或未迁移的武器在此处理
                    -- 目前所有已知武器都应有 tags
                end
            end
        end
    end
end

-- 更新所有武器的换弹计时器
function weapons.updateReload(state, dt)
    for key, w in pairs((state.inventory and state.inventory.weapons) or {}) do
        if w.isReloading and w.reloadTimer then
            w.reloadTimer = w.reloadTimer - dt
            if w.reloadTimer <= 0 then
                -- 完成换弹
                local def = state.catalog[key]
                local maxMag = w.maxMagazine or (def and def.base.maxMagazine) or 30
                local needed = maxMag - (w.magazine or 0)
                local transfer = math.min(needed, w.reserve or 0)
                w.magazine = (w.magazine or 0) + transfer
                w.reserve = (w.reserve or 0) - transfer
                w.isReloading = false
                w.reloadTimer = 0
                if state.playSfx then state.playSfx('gem') end
            end
        end
    end
end

-- 尝试开始换弹当前激活武器
function weapons.startReload(state)
    local inv = state.inventory
    if not inv then return false end

    -- WF风格：从 inventory.activeSlot 和 inventory.weaponSlots 读取
    local activeSlot = inv.activeSlot or 'ranged'
    local slotData = inv.weaponSlots and inv.weaponSlots[activeSlot]
    if not slotData then return false end

    local weaponKey = slotData.key
    local w = inv.weapons and inv.weapons[weaponKey]
    if not w then return false end
    if w.isReloading then return false end
    if w.magazine == nil then return false end -- 无弹药武器（近战）

    local def = state.catalog[weaponKey]
    local maxMag = w.maxMagazine or (def and def.base.maxMagazine) or 30
    if w.magazine >= maxMag then return false end  -- 已满
    if (w.reserve or 0) <= 0 then return false end -- 无备用弹药

    local reloadTime = w.reloadTime or (def and def.base.reloadTime) or 1.5
    w.isReloading = true
    w.reloadTimer = reloadTime
    if state.playSfx then state.playSfx('shoot') end
    return true
end

return weapons
