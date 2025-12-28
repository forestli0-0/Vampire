--- ============================================================================
--- 武器系统模块 (Weapons Module)
--- ============================================================================
--- 重构后的武器系统，主要功能：
--- - 远程武器射击（支持多重射击MOD）
--- - 近战武器攻击（扇形范围伤害）
--- - 弹药管理（弹夹/备弹/换弹）
--- - 武器槽位切换
--- ============================================================================

local calculator = require('gameplay.calculator')
local Weapon = require('gameplay.weapon_class')

local weapons = {}

-- 导出 Weapon 类供外部使用
weapons.Weapon = Weapon

-- ============================================================================
-- 辅助函数
-- ============================================================================

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

-- ============================================================================
-- 公共 API（保持向后兼容）
-- ============================================================================

--- 计算武器属性（应用 MOD）
function weapons.calculateStats(state, weaponKey)
    local invWeapon = state.inventory.weapons[weaponKey]
    if not invWeapon then return nil end

    local stats = cloneStats(invWeapon.stats)
    local weaponDef = state.catalog[weaponKey]

    -- 应用 MOD 系统
    local modsModule = require('systems.mods')
    stats = modsModule.applyWeaponMods(state, weaponKey, stats)
    stats = modsModule.applyRunWeaponMods(state, weaponKey, stats)

    -- 更新弹夹容量
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

--- 添加武器到玩家
--- @param state table 游戏状态
--- @param key string 武器 key
--- @param owner string|nil 拥有者
--- @param slotType string|nil 槽位类型
function weapons.addWeapon(state, key, owner, slotType)
    -- 使用 Weapon 类创建实例
    local weapon = Weapon.new(state, key, owner)
    if not weapon then
        print("[WEAPONS] 无效武器 key: " .. tostring(key))
        return nil
    end

    -- 设置槽位类型
    local proto = state.catalog[key]
    slotType = slotType or proto.slotType or 'ranged'
    weapon.slotType = slotType

    -- 确保数据结构存在
    state.inventory = state.inventory or {}
    state.inventory.weapons = state.inventory.weapons or {}
    state.inventory.weaponSlots = state.inventory.weaponSlots or {}

    -- 存储武器实例（导出为兼容格式）
    local weaponData = weapon:toData()
    state.inventory.weapons[key] = weaponData

    -- 自动装备到槽位
    state.inventory.weaponSlots[slotType] = weaponData
    state.inventory.activeSlot = state.inventory.activeSlot or slotType

    print(string.format("[WEAPONS] 已添加武器 %s (Weapon 类实例)", key))
    return weapon
end

--- 装备武器到指定槽位
--- @param state table 游戏状态
--- @param slotType string 槽位类型
--- @param weaponKey string 武器 key
--- @return boolean
function weapons.equipToSlot(state, slotType, weaponKey)
    -- 验证槽位类型
    local validSlots = { ranged = true, melee = true, extra = true, primary = true, secondary = true }
    if not validSlots[slotType] then
        print("[WEAPONS] 无效槽位类型: " .. tostring(slotType))
        return false
    end

    -- 映射 primary/secondary 到新槽位名
    if slotType == 'primary' then slotType = 'ranged' end
    if slotType == 'secondary' then slotType = 'extra' end

    -- 使用 Weapon 类创建实例
    local weapon = Weapon.new(state, weaponKey, 'player')
    if not weapon then
        print("[WEAPONS] 无效武器 key: " .. tostring(weaponKey))
        return false
    end
    weapon.slotType = slotType

    -- 确保数据结构存在
    state.inventory = state.inventory or {}
    state.inventory.weapons = state.inventory.weapons or {}
    state.inventory.weaponSlots = state.inventory.weaponSlots or {}

    -- 导出为兼容格式并存储
    local weaponData = weapon:toData()
    state.inventory.weaponSlots[slotType] = weaponData
    state.inventory.weapons[weaponKey] = weaponData
    state.inventory.activeSlot = state.inventory.activeSlot or slotType

    print(string.format("[WEAPONS] 已装备 %s 到 %s 槽位", weaponKey, slotType))
    return true
end

--- 获取当前激活的武器
function weapons.getActiveWeapon(state)
    local activeSlot = state.inventory and state.inventory.activeSlot or 'ranged'
    return state.inventory and state.inventory.weaponSlots and state.inventory.weaponSlots[activeSlot]
end

--- 切换到指定槽位
function weapons.switchSlot(state, slotType)
    if not state.inventory then return false end
    if state.inventory.weaponSlots and state.inventory.weaponSlots[slotType] then
        state.inventory.activeSlot = slotType
        return true
    end
    return false
end

--- 循环切换武器槽位
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

    for i = 1, #slots do
        local nextIndex = (currentIndex + i - 1) % #slots + 1
        local nextSlot = slots[nextIndex]
        if inv.weaponSlots and inv.weaponSlots[nextSlot] then
            inv.activeSlot = nextSlot
            return true
        end
    end
    return false
end

--- 生成投射物（保留核心功能）
function weapons.spawnProjectile(state, type, x, y, target, statsOverride)
    local wStats = statsOverride or weapons.calculateStats(state, type)
    if not wStats then return end

    -- 记录射击
    local analytics = require('systems.analytics')
    analytics.recordShot(type)

    -- 计算伤害
    local finalDmg = math.floor((wStats.damage or 0) * (state.player.stats.might or 1))
    local area = (wStats.area or 1) * (state.player.stats.area or 1)

    -- 计算角度
    local angle = 0
    if target then
        angle = math.atan2(target.y - y, target.x - x)
    elseif wStats.rotation then
        angle = wStats.rotation
    end

    local spd = (wStats.speed or 0) * (state.player.stats.speed or 1)
    local size = (wStats.size or 6) * area

    -- 创建投射物
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
        rotation = angle,
        pierce = wStats.pierce or 1,
        effectDuration = wStats.duration,
        splashRadius = wStats.splashRadius,
        critChance = wStats.critChance,
        critMultiplier = wStats.critMultiplier,
        statusChance = wStats.statusChance,
        elements = wStats.elements,
        weaponKey = type
    }

    table.insert(state.bullets, bullet)
end

--- 武器系统更新（简化版）
function weapons.update(state, dt)
    if not state or not state.inventory or not state.inventory.weapons then return end
    if state.player.dead or state.player.downed then return end

    local input = require('core.input')
    local isFiring = input.isDown('fire')
    local wantsReload = input.isPressed('reload') -- R 键手动换弹

    -- 处理手动换弹（R 键）
    if wantsReload then
        local activeSlot = state.inventory.activeSlot or 'ranged'
        local activeWeapon = state.inventory.weaponSlots[activeSlot]
        if activeWeapon then
            weapons.startReload(state, activeWeapon.key)
        end
    end

    -- 处理近战挥砍伤害
    local activeSlot = state.inventory.activeSlot or 'ranged'
    if activeSlot == 'melee' then
        local meleeWeapon = state.inventory.weaponSlots and state.inventory.weaponSlots['melee']
        if meleeWeapon and meleeWeapon.key then
            weapons.processMeleeSwing(state, meleeWeapon.key)
        end
    end

    for key, w in pairs(state.inventory.weapons) do
        -- 更新冷却计时器
        if w.timer then
            w.timer = math.max(0, w.timer - dt)
        end

        -- 处理换弹
        if w.isReloading then
            w.reloadTimer = (w.reloadTimer or 0) + dt
            if w.reloadTimer >= (w.reloadTime or w.stats.reloadTime or 2.0) then
                local needed = (w.maxMagazine or 30) - (w.magazine or 0)
                local transfer = math.min(needed, w.reserve or 0)
                w.magazine = (w.magazine or 0) + transfer
                w.reserve = (w.reserve or 0) - transfer
                w.isReloading = false
                w.reloadTimer = 0
            end
        end

        -- 射击逻辑（仅远程武器）
        if isFiring and w.owner == 'player' and (w.timer or 0) <= 0 then
            -- 检查是否是激活槽位
            local activeSlot = state.inventory.activeSlot or 'ranged'
            -- 跳过近战槽位（近战伤害由 processMeleeSwing 处理）
            if activeSlot ~= 'melee' then
                local activeWeapon = state.inventory.weaponSlots[activeSlot]
                if activeWeapon and activeWeapon.key == key then
                    -- 检查弹药
                    if w.magazine and w.magazine <= 0 then
                        weapons.startReload(state, key)
                    else
                        -- 射击
                        local stats = weapons.calculateStats(state, key)
                        if stats then
                            -- 计算子弹数量（多重射击MOD）
                            local shotCount = 1
                            if stats.amount then
                                local amt = (stats.amount or 0) + 1
                                shotCount = math.floor(amt)
                                -- 小数部分作为概率
                                if math.random() < (amt - shotCount) then
                                    shotCount = shotCount + 1
                                end
                                shotCount = math.max(1, shotCount)
                            end

                            local baseAngle = state.player.aimAngle or 0
                            local spread = 0.12 -- 多发子弹的扩散角度

                            for i = 1, shotCount do
                                -- 多发子弹时添加扩散
                                local ang = baseAngle
                                if shotCount > 1 then
                                    ang = baseAngle + (i - (shotCount + 1) / 2) * spread
                                end

                                local target = {
                                    x = state.player.x + math.cos(ang) * (stats.range or 600),
                                    y = state.player.y + math.sin(ang) * (stats.range or 600)
                                }
                                weapons.spawnProjectile(state, key, state.player.x, state.player.y, target, stats)
                            end

                            -- 消耗弹药（无论发射多少发只消耗1发）
                            if w.magazine then
                                w.magazine = w.magazine - 1
                            end

                            -- 重置冷却
                            w.timer = stats.cd or 0.1
                        end
                    end
                end
            end
        end
    end
end

--- 开始换弹
function weapons.startReload(state, weaponKey)
    local w = state.inventory.weapons[weaponKey]
    if not w then return false end

    if w.isReloading then return false end
    if w.reserve and w.reserve <= 0 then return false end
    if w.magazine and w.maxMagazine and w.magazine >= w.maxMagazine then return false end

    w.isReloading = true
    w.reloadTimer = 0

    if state.playSfx then
        state.playSfx('reload')
    end

    return true
end

--- 更新换弹
function weapons.updateReload(state, dt)
    -- 已集成到 weapons.update 中
end

-- ============================================================================
-- 近战攻击处理（从旧系统移植）
-- ============================================================================

--- 处理近战挥砍伤害
function weapons.processMeleeSwing(state, weaponKey)
    local p = state.player
    if not p or not p.meleeState then return false end

    local melee = p.meleeState

    -- 只在 swing 阶段造成伤害，且未造成过伤害
    if melee.phase ~= 'swing' or melee.damageDealt then
        return false
    end

    -- 获取武器数据
    local w = state.inventory.weapons[weaponKey]
    if not w then return false end

    local stats = w.stats or {}
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local params = weaponDef and weaponDef.behaviorParams or {}

    -- 参数设置
    local arcWidth = params.arcWidth or 1.2 -- 弧度
    local range = stats.range or 80

    local sx, sy = p.x, p.y
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

    -- 检测扇形范围内所有敌人
    local hitCount = 0
    local hitOccurred = false

    if state.enemies then
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
                        -- 应用伤害
                        local result = calculator.applyHit(state, e, {
                            damage = finalDamage * comboMult,
                            critChance = stats.critChance or 0,
                            critMultiplier = stats.critMultiplier or 1.5,
                            statusChance = stats.statusChance or 0,
                            effectType = stats.effectType or (weaponDef and weaponDef.effectType),
                            elements = stats.elements,
                            damageBreakdown = stats.damageBreakdown,
                            weaponKey = weaponKey,
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
    end

    -- 标记已造成伤害
    melee.damageDealt = true

    -- 重击/终结技的屏幕震动
    if melee.attackType == 'heavy' or melee.attackType == 'finisher' then
        state.shakeAmount = (state.shakeAmount or 0) + (melee.attackType == 'finisher' and 8 or 4)
    end

    -- 增加近战连击数
    if hitOccurred then
        p.meleeCombo = (p.meleeCombo or 0) + hitCount
        p.meleeComboTimer = 5.0
    end

    return hitCount > 0
end

return weapons
