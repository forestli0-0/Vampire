--[[
================================================================================
    玩家模块 (Player Module)
================================================================================
    本模块是游戏的核心系统之一，负责处理所有与玩家相关的逻辑：

    【核心功能】
    1. 移动系统 - 普通移动、冲刺(Dash)、子弹跳(Bullet Jump)、滑行(Slide)
    2. 战斗系统 - 远程射击、近战连招状态机、蓄力攻击
    3. 防御系统 - 护盾机制、护盾锁(Shield Gate)、无敌帧
    4. 技能系统 - 快捷技能切换、技能释放
    5. 动画系统 - 8方向动画状态机

    【设计参考】
    - 移动系统参考《Warframe》(星际战甲) 的子弹跳和滑行机制
    - 闪避系统参考《Hades》(哈迪斯) 的冲刺取消和无敌帧设计
    - 护盾系统参考《Warframe》的Shield Gating机制
================================================================================
]]

-- =============================================================================
-- 依赖模块导入
-- =============================================================================
local logger = require('core.logger')                       -- 日志记录器，用于追踪游戏数据
local input = require('core.input')                         -- 输入系统，处理键盘/鼠标输入
local weaponTrail = require('render.weapon_trail')          -- 武器拖影系统，生成近战挥砍的视觉效果
local animTransform = require('render.animation_transform') -- 挤压拉伸变换，实现冲刺时的形变效果

-- 玩家模块表
local player = {}

-- =============================================================================
-- 工具函数
-- =============================================================================

--- 将数值限制在指定范围内
--- @param v number 要限制的值
--- @param lo number 最小值
--- @param hi number 最大值
--- @return number 限制后的值
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- =============================================================================
-- 常量定义
-- =============================================================================

-- 【护盾系统常量】(仿Warframe设计)
-- 护盾是玩家的第一道防线，会在生命值之前承受伤害
local SHIELD_REGEN_DELAY = 3.0   -- 受击后多少秒开始回复护盾
local SHIELD_REGEN_RATE = 0.25   -- 每秒回复最大护盾值的百分比 (25%)
local SHIELD_GATE_DURATION = 0.3 -- 护盾破裂时的无敌时间 (防止被秒杀的核心机制)

-- 【移动系统常量】(仿Warframe设计)
local SLIDE_SPEED_MULT = 1.3     -- 滑行时的速度倍率 (按住Shift)
local SLIDE_DRAG = 0.98          -- 滑行时如果不移动的速度衰减 (暂未使用)
local BULLET_JUMP_SPEED = 500    -- 子弹跳的基础速度 (像素/秒)
local BULLET_JUMP_DURATION = 0.4 -- 子弹跳的持续时间 (秒)
local QUICK_ABILITY_COUNT = 4    -- 快捷技能槽位数量 (对应1/2/3/4键)

-- =============================================================================
-- 输入辅助函数
-- =============================================================================

--- 获取移动输入轴向值
--- @return number, number X轴(-1~1)和Y轴(-1~1)的输入值
local function getMoveInput()
    return input.getAxis('move_x'), input.getAxis('move_y')
end

--- 检查玩家是否正在按住攻击键 (鼠标左键 或 J键)
--- @return boolean 是否按下攻击键
local function isAttackKeyDown()
    return input.isDown('fire')
end

-- =============================================================================
-- 瞄准系统
-- =============================================================================

--- 获取玩家当前的瞄准方向 (单位向量)
--- @param state table 游戏状态
--- @param weaponDef table|nil 武器定义 (暂未使用，预留给不同武器的瞄准逻辑)
--- @return number dirX X方向分量
--- @return number dirY Y方向分量
--- @return nil reserved 预留返回值
function player.getAimDirection(state, weaponDef)
    local p = state.player
    -- 使用玩家的瞄准角度(aimAngle)计算方向向量
    -- aimAngle 是鼠标相对于玩家的角度，在updateMovement中更新
    return math.cos(p.aimAngle or 0), math.sin(p.aimAngle or 0), nil
end

-- =============================================================================
-- 快捷技能系统
-- =============================================================================

--- 规范化快捷技能索引 (确保在1-4范围内循环)
--- @param index number|any 原始索引值
--- @return number 规范化后的索引 (1-4)
local function normalizeQuickAbilityIndex(index)
    local idx = math.floor(tonumber(index) or 1)
    -- 使用模运算实现循环: 0->4, 1->1, 2->2, 3->3, 4->4, 5->1
    idx = ((idx - 1) % QUICK_ABILITY_COUNT) + 1
    return idx
end

--- 获取当前选中的快捷技能索引
--- @param state table 游戏状态
--- @return number 当前快捷技能索引 (1-4)
function player.getQuickAbilityIndex(state)
    local p = state.player
    if not p then return 1 end
    p.quickAbilityIndex = normalizeQuickAbilityIndex(p.quickAbilityIndex)
    return p.quickAbilityIndex
end

--- 设置当前快捷技能索引
--- @param state table 游戏状态
--- @param index number 目标索引
--- @return number 设置后的索引 (自动规范化)
function player.setQuickAbilityIndex(state, index)
    local p = state.player
    if not p then return 1 end
    p.quickAbilityIndex = normalizeQuickAbilityIndex(index)
    return p.quickAbilityIndex
end

--- 循环切换快捷技能
--- @param state table 游戏状态
--- @param dir number 切换方向 (>0向后, <0向前, =0不变)
--- @return number 切换后的索引
function player.cycleQuickAbility(state, dir)
    local p = state.player
    if not p then return 1 end
    local step = tonumber(dir) or 0
    if step == 0 then
        return player.getQuickAbilityIndex(state)
    end
    step = (step > 0) and 1 or -1
    return player.setQuickAbilityIndex(state, (p.quickAbilityIndex or 1) + step)
end

-- =============================================================================
-- 射击系统 (远程武器 + 蓄力弓)
-- =============================================================================
--- 更新射击状态
--- 【核心逻辑】
--- 1. 检测玩家是否按下攻击键
--- 2. 滑行时禁止射击 (专注于闪避)
--- 3. 处理蓄力武器(弓)的蓄力逻辑
---
--- @param state table 游戏状态
function player.updateFiring(state)
    local p = state.player

    -- 获取攻击键状态 (对于蓄力武器需要精确追踪按键状态)
    local manualAttack = isAttackKeyDown()
    p.isFiring = manualAttack

    -- 【战术冲刺】滑行时禁止射击，让玩家专注于闪避
    if p.isSliding then
        p.isFiring = false
    end

    -- 获取当前装备的武器信息
    -- activeSlot: 当前激活的武器槽 ('ranged' 或 'melee')
    local activeWeaponInst = state.inventory and state.inventory.weaponSlots and
        state.inventory.weaponSlots[p.activeSlot]
    local activeWeaponKey = activeWeaponInst and activeWeaponInst.key
    local weaponDef = activeWeaponKey and state.catalog and state.catalog[activeWeaponKey]

    -- 如果切换了武器，重置弓的蓄力状态
    if p.bowCharge.isCharging and p.bowCharge.weaponKey ~= activeWeaponKey then
        p.bowCharge.isCharging = false
        p.bowCharge.pendingRelease = false
        p.bowCharge.chargeTime = 0
    end

    -- 【蓄力武器系统】仅对启用蓄力的武器生效 (如弓箭)
    -- chargeEnabled: 武器定义中的蓄力开关
    local isBowWeapon = weaponDef and weaponDef.chargeEnabled
    if isBowWeapon then
        local shouldCharge = manualAttack
        local maxCharge = weaponDef.maxChargeTime or 2.0 -- 最大蓄力时间

        if shouldCharge then
            if not p.bowCharge.isCharging then
                -- 开始蓄力：记录开始时间
                p.bowCharge.isCharging = true
                p.bowCharge.pendingRelease = false
                p.bowCharge.startTime = state.gameTimer or 0
                p.bowCharge.chargeTime = 0
                p.bowCharge.weaponKey = activeWeaponKey
            elseif p.bowCharge.isCharging then
                -- 持续蓄力：更新蓄力时间，但不超过最大值
                p.bowCharge.chargeTime = (state.gameTimer or 0) - p.bowCharge.startTime
                if p.bowCharge.chargeTime > maxCharge then
                    p.bowCharge.chargeTime = maxCharge
                end
            end
        elseif not shouldCharge and p.bowCharge.isCharging then
            -- 松开按键：标记为待释放状态
            -- 保持isCharging=true直到武器模块消费pendingRelease
            -- 这确保UI能继续显示蓄力条直到箭矢发射
            p.bowCharge.pendingRelease = true
        end
    end
end

-- =============================================================================
-- 近战系统 (Melee Combat System)
-- =============================================================================
--[[
    近战系统采用状态机设计，状态流转如下：

    idle (待机) --> swing (挥砍) --> recovery (后摇) --> idle
                      ↑
              按下攻击键触发

    【攻击类型判定】
    - 轻击(light): 短按攻击键 (<0.4秒)
    - 重击(heavy): 长按攻击键 (>=0.4秒)
    - 终结技(finisher): 连击数>=3时的重击

    【连击系统】
    - 每次轻击增加连击计数
    - 连击窗口为1.2秒，超时重置
    - 连击满3次后可释放终结技
]]

--- 确保近战状态对象存在 (懒初始化模式)
--- @param p table 玩家对象
--- @return table 近战状态对象
local function ensureMeleeState(p)
    if not p.meleeState then
        p.meleeState = {
            -- 状态机当前阶段: 'idle'(待机) / 'swing'(挥砍中) / 'recovery'(后摇)
            phase = 'idle',
            comboCount = 0,      -- 连击计数 (0-3)，满3次可放终结技
            comboTimer = 0,      -- 连击窗口倒计时，归零时重置连击
            holdTimer = 0,       -- 按住攻击键的时间，用于判定轻/重击
            isHolding = false,   -- 是否正在按住攻击键
            attackType = nil,    -- 当前攻击类型: 'light'(轻击) / 'heavy'(重击) / 'finisher'(终结)
            swingTimer = 0,      -- 挥砍阶段剩余时间
            recoveryTimer = 0,   -- 后摇阶段剩余时间
            damageDealt = false, -- 本次攻击是否已造成伤害 (防止重复伤害)
        }
    end
    return p.meleeState
end

-- 【近战攻击常量】
local HEAVY_HOLD_THRESHOLD = 0.4 -- 重击判定阈值：按住超过0.4秒视为重击
local COMBO_WINDOW = 1.2         -- 连击窗口：1.2秒内再次攻击可累计连击
local LIGHT_SWING_TIME = 0.15    -- 轻击挥砍动画时长
local HEAVY_SWING_TIME = 0.3     -- 重击挥砍动画时长 (更慢但更强)
local RECOVERY_TIME = 0.1        -- 攻击后摇时长 (可被闪避取消)

-- Update melee attack state machine
function player.updateMelee(state, dt)
    local p = state.player
    if not p then return end

    local melee = ensureMeleeState(p)
    -- WF-style: Read from inventory.activeSlot
    local activeSlot = state.inventory and state.inventory.activeSlot or 'ranged'

    -- Only process melee when melee slot is active
    if activeSlot ~= 'melee' then
        melee.phase = 'idle'
        melee.holdTimer = 0
        melee.isHolding = false
        return
    end

    -- Update combo timer
    if melee.comboTimer > 0 then
        melee.comboTimer = melee.comboTimer - dt
        if melee.comboTimer <= 0 then
            melee.comboCount = 0
            melee.comboTimer = 0
        end
    end

    -- Decay global melee combo (WF-style)
    if p.meleeCombo and p.meleeCombo > 0 then
        p.meleeComboTimer = (p.meleeComboTimer or 0) - dt
        if p.meleeComboTimer <= 0 then
            p.meleeCombo = 0
            p.meleeComboTimer = 0
        end
    end

    local attacking = isAttackKeyDown() and not p.isSliding

    -- State machine
    if melee.phase == 'idle' then
        if attacking then
            if not melee.isHolding then
                -- Just pressed attack
                melee.isHolding = true
                melee.holdTimer = 0
            else
                -- Holding attack
                melee.holdTimer = melee.holdTimer + dt
            end
        else
            if melee.isHolding then
                -- Released attack - determine type
                melee.isHolding = false

                if melee.holdTimer >= HEAVY_HOLD_THRESHOLD then
                    -- Heavy attack
                    if melee.comboCount >= 3 then
                        melee.attackType = 'finisher'
                        melee.comboCount = 0
                    else
                        melee.attackType = 'heavy'
                    end
                    local speedMult = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) *
                        (p.exaltedBladeSpeedMult or 1)
                    melee.swingTimer = HEAVY_SWING_TIME / math.max(0.01, speedMult)
                else
                    -- Light attack
                    melee.attackType = 'light'
                    melee.comboCount = melee.comboCount + 1
                    local speedMult = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) *
                        (p.exaltedBladeSpeedMult or 1)
                    melee.swingTimer = LIGHT_SWING_TIME / math.max(0.01, speedMult)
                end

                melee.phase = 'swing'
                melee.damageDealt = false
                melee.comboTimer = COMBO_WINDOW
                melee.holdTimer = 0

                -- Sound
                if state.playSfx then state.playSfx('shoot') end
            end
        end
    elseif melee.phase == 'swing' then
        melee.swingTimer = melee.swingTimer - dt

        -- ==================== 挥砍拖影记录 ====================
        local meleeRange = 60          -- 近战攻击范围
        local swingArc = math.pi * 0.8 -- 挥砍弧度 (~145度)

        -- 计算当前挥砍角度 (从起始角度到结束角度)
        local totalSwingTime = melee.attackType == 'heavy' and HEAVY_SWING_TIME or LIGHT_SWING_TIME
        local speedMult = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) *
            (p.exaltedBladeSpeedMult or 1)
        totalSwingTime = totalSwingTime / math.max(0.01, speedMult)

        local swingProgress = 1 - (melee.swingTimer / totalSwingTime)
        local baseAngle = p.aimAngle or 0
        local startAngle = baseAngle - swingArc / 2
        local currentAngle = startAngle + swingArc * swingProgress

        -- 根据攻击类型设置拖影颜色
        local trailColor = { 1, 1, 1 }
        if melee.attackType == 'heavy' then
            trailColor = { 1, 0.6, 0.3 } -- 重击橙色
        elseif melee.attackType == 'finisher' then
            trailColor = { 1, 0.3, 0.3 } -- 终结技红色
        else
            trailColor = { 0.8, 0.9, 1 } -- 轻击淡蓝色
        end

        weaponTrail.addSlashPoint(p, currentAngle, meleeRange, {
            color = trailColor,
            width = melee.attackType == 'heavy' and 12 or 8,           -- 增粗线宽
            intensity = melee.attackType == 'finisher' and 2.0 or 1.2, -- 增强强度
        })

        if melee.swingTimer <= 0 then
            melee.phase = 'recovery'
            local speedMul = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) *
                (p.exaltedBladeSpeedMult or 1)
            melee.recoveryTimer = RECOVERY_TIME / math.max(0.01, speedMul)
            -- 挥砍结束时清除拖影
            weaponTrail.clearSlash(p)
        end
    elseif melee.phase == 'recovery' then
        melee.recoveryTimer = melee.recoveryTimer - dt
        if melee.recoveryTimer <= 0 then
            melee.phase = 'idle'
            melee.attackType = nil
        end
    end
end

-- =============================================================================
-- 冲刺/闪避系统 (Dash System)
-- =============================================================================
--[[
    冲刺系统设计参考《Hades》:
    - 冲刺有次数限制 (charges)
    - 冲刺期间有无敌帧
    - 可以取消近战后摇 (动作取消机制)
    - 使用缓动曲线让冲刺感觉更有"弹性"
]]

--- 取消近战攻击 (用于闪避时中断攻击)
--- 这是动作游戏提升手感的关键技术：让玩家可以用闪避取消攻击后摇
--- @param state table 游戏状态
function player.cancelMelee(state)
    local p = state.player
    if not p or not p.meleeState then return end
    local melee = p.meleeState
    if melee.phase ~= 'idle' then
        -- 强制重置所有近战状态
        melee.phase = 'idle'
        melee.attackType = nil
        melee.swingTimer = 0
        melee.recoveryTimer = 0
        melee.isHolding = false
        melee.holdTimer = 0
    end
end

--- 确保冲刺状态对象存在 (懒初始化)
--- @param p table 玩家对象
--- @return table|nil 冲刺状态对象
local function ensureDashState(p)
    if not p then return nil end
    p.dash = p.dash or {}

    -- 从玩家属性中读取冲刺次数上限
    local stats = p.stats or {}
    local maxCharges = math.max(0, math.floor(stats.dashCharges or 0))
    local prevMax = p.dash.maxCharges
    p.dash.maxCharges = maxCharges

    -- 处理冲刺次数的初始化和变化
    if p.dash.charges == nil then
        -- 首次初始化：满次数
        p.dash.charges = maxCharges
    else
        -- 如果最大次数增加了 (比如装备加成)，给予额外次数
        if prevMax and maxCharges > prevMax then
            p.dash.charges = math.min(maxCharges, (p.dash.charges or 0) + (maxCharges - prevMax))
        else
            p.dash.charges = math.min(maxCharges, (p.dash.charges or 0))
        end
    end

    -- 初始化其他冲刺相关字段
    p.dash.rechargeTimer = p.dash.rechargeTimer or 0 -- 次数恢复计时器
    p.dash.timer = p.dash.timer or 0                 -- 当前冲刺剩余时间
    p.dash.dx = p.dash.dx or (p.facing or 1)         -- 冲刺方向X
    p.dash.dy = p.dash.dy or 0                       -- 冲刺方向Y

    return p.dash
end

--- 更新冲刺次数恢复
--- @param p table 玩家对象
--- @param dt number 帧间隔时间
local function tickDashRecharge(p, dt)
    local dash = ensureDashState(p)
    if not dash then return end
    local maxCharges = dash.maxCharges or 0
    if maxCharges <= 0 then return end
    dash.charges = dash.charges or 0

    -- 已满次数，不需要恢复
    if dash.charges >= maxCharges then
        dash.rechargeTimer = 0
        return
    end

    -- 获取冲刺冷却时间 (每次恢复需要的时间)
    local cd = (p.stats and p.stats.dashCooldown) or 0
    if cd <= 0 then
        -- 无冷却 = 无限冲刺
        dash.charges = maxCharges
        dash.rechargeTimer = 0
        return
    end

    local rechargeDt = dt
    -- 【战术冲刺加速】滑行时冲刺恢复速度翻倍
    -- 这鼓励玩家在战斗中使用滑行来更快恢复冲刺次数
    if p.isSliding then
        rechargeDt = rechargeDt * 2
    end

    -- 累加恢复计时器，满一个CD周期就恢复一次
    dash.rechargeTimer = (dash.rechargeTimer or 0) + rechargeDt
    while dash.rechargeTimer >= cd and dash.charges < maxCharges do
        dash.rechargeTimer = dash.rechargeTimer - cd
        dash.charges = dash.charges + 1
    end
end

--- 尝试执行冲刺
--- @param state table 游戏状态
--- @param dirX number|nil 冲刺方向X (可选，默认使用输入方向)
--- @param dirY number|nil 冲刺方向Y
--- @return boolean 是否成功执行冲刺
function player.tryDash(state, dirX, dirY)
    if not state or not state.player then return false end
    local p = state.player

    -- 【动作取消】冲刺时取消近战攻击 (仿Hades的响应式设计)
    player.cancelMelee(state)

    -- 从钩索状态挣脱 (如被蓝子的钩索拖拽)
    if p.grappled then
        p.grappled = false
        p.grappleEnemy = nil
        p.grappleSlowMult = nil
    end

    local dash = ensureDashState(p)
    if not dash or (dash.maxCharges or 0) <= 0 then return false end
    if (dash.timer or 0) > 0 then return false end -- 正在冲刺中
    -- 如果正在 Bullet Jump，不触发普通 dash
    if (p.bulletJumpTimer or 0) > 0 then return false end
    if (dash.charges or 0) <= 0 then return false end -- 没有冲刺次数

    local dx, dy = dirX, dirY
    if dx == nil or dy == nil then
        dx, dy = getMoveInput()
    end
    if dx == 0 and dy == 0 then
        dx, dy = (p.facing or 1), 0
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return false end
    dx, dy = dx / len, dy / len

    local stats = p.stats or {}
    local duration = stats.dashDuration or 0
    local distance = stats.dashDistance or 0
    local inv = stats.dashInvincible
    if inv == nil then inv = duration end

    local ctx = {
        player = p,
        dirX = dx,
        dirY = dy,
        duration = duration,
        distance = distance,
        invincibleTimer = inv
    }
    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'preDash', ctx)
        if ctx.cancel then return false end
    end

    dx, dy = ctx.dirX or dx, ctx.dirY or dy
    local len2 = math.sqrt(dx * dx + dy * dy)
    if len2 <= 0 then
        dx, dy = (p.facing or 1), 0
    else
        dx, dy = dx / len2, dy / len2
    end

    duration = ctx.duration or duration
    distance = ctx.distance or distance
    inv = ctx.invincibleTimer
    if inv == nil then inv = duration end

    if duration <= 0 or distance <= 0 then return false end

    dash.charges = math.max(0, (dash.charges or 0) - 1)
    dash.duration = duration
    dash.distance = distance
    dash.speed = distance / duration
    dash.timer = duration
    dash.dx = dx
    dash.dy = dy
    dash.trailX = p.x
    dash.trailY = p.y

    -- ==================== 冲刺拉伸效果 ====================
    -- 顶视角：沿冲刺方向拉伸（变成冲刺方向的椭圆）
    -- 初始化玩家的transform（如果没有）
    if not p.transform then
        p.transform = animTransform.new()
    end

    -- 记录冲刺方向角度，用于draw时正确应用拉伸方向
    local dashAngle = math.atan2(dy, dx)
    p.transform.dashAngle = dashAngle

    -- 沿冲刺方向拉伸：X放大Y缩小（水平椭圆），然后在绘制时旋转
    animTransform.stretch(p.transform, 0.4, true)

    if state.spawnDashAfterimage then
        local face = p.facing or 1
        if dx > 0 then face = 1 elseif dx < 0 then face = -1 end
        state.spawnDashAfterimage(p.x, p.y, face, { alpha = 0.26, duration = 0.20, dirX = dx, dirY = dy })
    end

    if inv and inv > 0 then
        p.invincibleTimer = math.max(p.invincibleTimer or 0, inv)
    end
    if state.spawnEffect then
        state.spawnEffect('shock', p.x, p.y, 0.9)
    end

    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onDash', ctx)
    end

    -- 【仿Warframe】冲刺时取消所有正在进行的换弹
    local inv = state.inventory
    if inv and inv.weapons then
        for key, w in pairs(inv.weapons) do
            if w.isReloading then
                w.isReloading = false
                w.reloadTimer = 0
            end
        end
    end

    return true
end

-- =============================================================================
-- 武器切换系统
-- =============================================================================

--- 切换武器槽位
--- @param state table 游戏状态
--- @param slot string 目标槽位 ('ranged'=远程, 'melee'=近战)
--- @return boolean 是否切换成功
function player.switchWeaponSlot(state, slot)
    if not state or not state.player then return false end
    local validSlots = { ranged = true, melee = true }
    if not validSlots[slot] then return false end

    local p = state.player
    local oldSlot = p.activeSlot
    if oldSlot == slot then return false end -- 已经在该槽位

    p.activeSlot = slot

    -- 视觉/音效反馈
    if state.playSfx then state.playSfx('shoot') end

    -- 触发武器切换事件 (供增强系统使用)
    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onWeaponSwitch', {
            oldSlot = oldSlot, newSlot = slot
        })
    end

    return true
end

-- =============================================================================
-- 键盘事件处理
-- =============================================================================

--- 处理键盘按下事件
--- @param state table 游戏状态
--- @param key string 按下的键
--- @return boolean 是否处理了该按键
function player.keypressed(state, key)
    if not state or state.gameState ~= 'PLAYING' then return false end
    local p = state.player
    local input = require('core.input')

    -- 切换武器 (F键)
    if input.isActionKey(key, 'cycle_weapon') then
        local weapons = require('gameplay.weapons')
        return weapons.cycleSlots(state)
    end


    -- 换弹 (R键)
    if input.isActionKey(key, 'reload') then
        local weapons = require('gameplay.weapons')
        return weapons.startReload(state)
    end

    -- 快速近战 (E键)
    if input.isActionKey(key, 'melee') then
        return player.quickMelee(state)
    end

    -- 快捷施法 (Q键)
    if input.isActionKey(key, 'quick_cast') then
        local abilities = require('gameplay.abilities')
        return abilities.tryActivate(state, player.getQuickAbilityIndex(state))
    end

    -- 技能键 (1/2/3/4)
    local abilities = require('gameplay.abilities')
    local abilityIndex = abilities.getAbilityForKey(key)
    if not abilityIndex then
        if input.isActionKey(key, 'ability1') then
            abilityIndex = 1
        elseif input.isActionKey(key, 'ability2') then
            abilityIndex = 2
        elseif input.isActionKey(key, 'ability3') then
            abilityIndex = 3
        elseif input.isActionKey(key, 'ability4') then
            abilityIndex = 4
        end
    end
    if abilityIndex then
        return abilities.tryActivate(state, abilityIndex)
    end

    -- M键: 测试MOD系统 (调试用)
    if input.isActionKey(key, 'debug_mods') then
        local mods = require('systems.mods')
        local inv = state.inventory
        local activeSlot = inv and inv.activeSlot or 'ranged'
        local slotData = inv and inv.weaponSlots and inv.weaponSlots[activeSlot]
        local activeKey = slotData and slotData.key
        mods.equipTestMods(state, 'warframe', nil)
        if activeKey then mods.equipTestMods(state, 'weapons', activeKey) end
        mods.equipTestMods(state, 'companion', nil)
        table.insert(state.texts,
            { x = state.player.x, y = state.player.y - 50, text = "MOD已装备!", color = { 0.6, 0.9, 0.4 }, life = 2 })
        return true
    end

    -- Esc键: 返回准备界面
    if input.isActionKey(key, 'cancel') then
        local arsenal = require('core.arsenal')
        if arsenal.reset then arsenal.reset(state) end
        state.gameState = 'ARSENAL'
        table.insert(state.texts or {},
            { x = state.player.x, y = state.player.y - 50, text = "返回准备界面", color = { 0.8, 0.8, 1 }, life = 1.5 })
        return true
    end

    -- 空格键: 子弹跳 / 冲刺
    if input.isActionKey(key, 'dodge') then
        local dash = ensureDashState(p)
        if p.isSliding and dash and (dash.charges or 0) > 0 then
            -- 【子弹跳】滑行中按空格触发，消耗1次冲刺
            local dx, dy = input.getAxis('move_x'), input.getAxis('move_y')
            if dx == 0 and dy == 0 then dx = p.facing or 1 end
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 0.001 then dx, len = (p.facing or 1), 1 end

            dash.charges = dash.charges - 1
            -- 清除普通 dash timer，防止 Bullet Jump 结束后又触发普通 dash
            dash.timer = 0

            p.bulletJumpTimer = BULLET_JUMP_DURATION
            p.bjDx, p.bjDy = (dx / len), (dy / len)

            if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.2) end
            p.isSliding = false
            if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 1.5) end
            return true
        else
            -- 普通冲刺
            return player.tryDash(state)
        end
    end

    -- 宠物切换
    if input.isActionKey(key, 'toggle_pet') then
        local pets = require('gameplay.pets')
        return pets.toggleMode(state)
    end

    return false
end

-- =============================================================================
-- 移动更新系统
-- =============================================================================

--- 更新玩家移动
--- 【核心进程】
--- 1. 检测并处理各种移动状态 (子弹跳 > 冲刺 > 连键冲杀 > 滑行 > 普通移动)
--- 2. 应用缓动曲线计算实际速度
--- 3. 生成残影效果
--- 4. 更新瞄准角度和面向
--- 5. 更新摄像机位置
--- @param state table 游戏状态
--- @param dt number 帧间隔时间
function player.updateMovement(state, dt)
    local p = state.player
    local ox, oy = p.x, p.y -- 记录移动前的位置

    local dash = ensureDashState(p)
    tickDashRecharge(p, dt)       -- 更新冲刺次数恢复

    local dx, dy = getMoveInput() -- 获取移动输入
    local moving = dx ~= 0 or dy ~= 0
    local world = state.world

    -- ==================== 高级移动处理 ====================
    if (p.bulletJumpTimer or 0) > 0 then
        -- ==================== Bullet Jump 加速曲线 ====================
        -- 比普通Dash更爆发：开始3x，快速减速
        local duration = BULLET_JUMP_DURATION
        local progress = 1 - (p.bulletJumpTimer / duration)

        -- Ease-Out Quart: 比普通Dash更猛烈的减速
        local easeOut = 1 - math.pow(1 - progress, 4)
        local speedMultiplier = 3.0 - easeOut * 2.5 -- 3.0 → 0.5
        local speed = BULLET_JUMP_SPEED * speedMultiplier

        p.bulletJumpTimer = p.bulletJumpTimer - dt
        local mx = (p.bjDx or 0) * speed * dt
        local my = (p.bjDy or 0) * speed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x, p.y = p.x + mx, p.y + my
        end

        -- Bullet Jump 残影（比普通Dash更密集、更亮）
        if state.spawnDashAfterimage then
            p.bjTrailX = p.bjTrailX or ox
            p.bjTrailY = p.bjTrailY or oy
            local spacing = 16 -- 比普通Dash(24)更密集
            local ddx = p.x - (p.bjTrailX or ox)
            local ddy = p.y - (p.bjTrailY or oy)
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            local face = p.facing or 1
            if p.bjDx and p.bjDx > 0 then face = 1 elseif p.bjDx and p.bjDx < 0 then face = -1 end
            local guard = 0
            while dist >= spacing and guard < 16 do
                p.bjTrailX = (p.bjTrailX or ox) + (p.bjDx or 0) * spacing
                p.bjTrailY = (p.bjTrailY or oy) + (p.bjDy or 0) * spacing
                -- 更亮的残影（alpha 0.35 vs 普通的0.20）
                state.spawnDashAfterimage(p.bjTrailX, p.bjTrailY, face,
                    { alpha = 0.35, duration = 0.25, dirX = p.bjDx, dirY = p.bjDy })
                ddx = p.x - p.bjTrailX
                ddy = p.y - p.bjTrailY
                dist = math.sqrt(ddx * ddx + ddy * ddy)
                guard = guard + 1
            end
        end

        -- 清理残影追踪
        if p.bulletJumpTimer <= 0 then
            p.bjTrailX = nil
            p.bjTrailY = nil
        end

        moving = true
    elseif dash and (dash.timer or 0) > 0 then
        -- ==================== 闪避加速度曲线 ====================
        -- 使用 Ease-Out Cubic 曲线：开始快，结束慢
        -- 这让闪避有"弹射出去"的爆发感
        local baseSpeed = dash.speed
        if baseSpeed == nil then
            local stats = p.stats or {}
            local duration = stats.dashDuration or 0
            local distance = stats.dashDistance or 0
            baseSpeed = (duration > 0) and (distance / duration) or 0
        end

        -- 计算当前进度 (0 = 开始, 1 = 结束)
        local progress = 1 - (dash.timer / dash.duration)

        -- Ease-Out Cubic: 开始快，结束慢
        -- 速度倍率：开始时2.0x，结束时0.5x
        local easeOut = 1 - math.pow(1 - progress, 3)
        local speedMultiplier = 2.0 - easeOut * 1.5 -- 2.0 → 0.5
        local speed = baseSpeed * speedMultiplier

        local mx = (dash.dx or 0) * speed * dt
        local my = (dash.dy or 0) * speed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x = p.x + mx
            p.y = p.y + my
        end
        dash.timer = dash.timer - dt
        if dash.timer < 0 then dash.timer = 0 end
        moving = true
        dx, dy = dash.dx or 0, dash.dy or 0

        if state.spawnDashAfterimage then
            local spacing = 24
            dash.trailX = dash.trailX or ox
            dash.trailY = dash.trailY or oy
            local tx, ty = dash.trailX, dash.trailY
            local dirX, dirY = dash.dx or 0, dash.dy or 0
            local face = p.facing or 1
            if dirX > 0 then face = 1 elseif dirX < 0 then face = -1 end
            local ddx = p.x - tx
            local ddy = p.y - ty
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            local guard = 0
            while dist >= spacing and guard < 32 do
                tx = tx + dirX * spacing
                ty = ty + dirY * spacing
                state.spawnDashAfterimage(tx, ty, face, { alpha = 0.20, duration = 0.20, dirX = dirX, dirY = dirY })
                ddx = p.x - tx
                ddy = p.y - ty
                dist = math.sqrt(ddx * ddx + ddy * ddy)
                guard = guard + 1
            end
            dash.trailX, dash.trailY = tx, ty
        end

        if dash.timer <= 0 and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'postDash', { player = p })
        end
    elseif p.slashDashChain and p.slashDashChain.active then
        local chain = p.slashDashChain
        moving = true
        p.isSliding = false
        if p.grappled then
            p.grappled = false
            p.grappleEnemy = nil
            p.grappleSlowMult = nil
        end

        if chain.instance and not chain._calc then
            local ok, calc = pcall(require, 'gameplay.calculator')
            if ok and calc then chain._calc = calc end
        end

        if chain.pauseTimer and chain.pauseTimer > 0 then
            chain.pauseTimer = chain.pauseTimer - dt
            dx, dy = chain.lastDx or 0, chain.lastDy or 0
        else
            local target = chain.targets and chain.targets[chain.index]
            if not target then
                p.slashDashChain = nil
            else
                if (target.health or 0) <= 0 then
                    chain.currentTarget = nil
                    chain.stepTargetX = nil
                    chain.stepTargetY = nil
                    chain.index = chain.index + 1
                    chain.pauseTimer = chain.pause or 0
                    chain.stepTimer = 0
                else
                    if chain.currentTarget ~= target then
                        chain.currentTarget = target
                        chain.stepTargetX = target.x
                        chain.stepTargetY = target.y
                    end
                    local tx = chain.stepTargetX or target.x
                    local ty = chain.stepTargetY or target.y
                    local ddx, ddy = tx - p.x, ty - p.y
                    local dist = math.sqrt(ddx * ddx + ddy * ddy)
                    chain.stepTimer = (chain.stepTimer or 0) + dt
                    local hitRadius = chain.hitRadius or 18
                    if dist <= hitRadius or chain.stepTimer >= (chain.maxStepTime or 0.55) then
                        if world and world.enabled and world.moveCircle then
                            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, ddx, ddy)
                        else
                            p.x, p.y = tx, ty
                        end
                        if ddx ~= 0 then p.facing = (ddx >= 0) and 1 or -1 end
                        if state.spawnDashAfterimage then
                            local face = p.facing or 1
                            state.spawnDashAfterimage(p.x, p.y, face,
                                { alpha = 0.25, duration = 0.22, dirX = ddx, dirY = ddy })
                        end
                        if chain._calc and chain.instance then
                            chain._calc.applyHit(state, target, chain.instance)
                        else
                            target.health = (target.health or 0) - (chain.damage or 0)
                        end
                        if state.spawnEffect then state.spawnEffect('blast_hit', tx, ty, 0.6) end
                        chain.currentTarget = nil
                        chain.stepTargetX = nil
                        chain.stepTargetY = nil
                        chain.index = chain.index + 1
                        chain.pauseTimer = chain.pause or 0
                        chain.stepTimer = 0
                    else
                        local dirX, dirY = ddx / dist, ddy / dist
                        chain.lastDx, chain.lastDy = dirX, dirY
                        dx, dy = dirX, dirY
                        local speed = chain.speed or 700
                        local mx = dirX * speed * dt
                        local my = dirY * speed * dt
                        if world and world.enabled and world.moveCircle then
                            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
                        else
                            p.x = p.x + mx
                            p.y = p.y + my
                        end

                        if state.spawnDashAfterimage then
                            local spacing = 22
                            chain.trailX = chain.trailX or ox
                            chain.trailY = chain.trailY or oy
                            local ax, ay = chain.trailX, chain.trailY
                            local adx, ady = p.x - ax, p.y - ay
                            local adist = math.sqrt(adx * adx + ady * ady)
                            local guard = 0
                            local face = p.facing or 1
                            if dirX > 0 then face = 1 elseif dirX < 0 then face = -1 end
                            while adist >= spacing and guard < 24 do
                                ax = ax + dirX * spacing
                                ay = ay + dirY * spacing
                                state.spawnDashAfterimage(ax, ay, face,
                                    { alpha = 0.18, duration = 0.18, dirX = dirX, dirY = dirY })
                                adx = p.x - ax
                                ady = p.y - ay
                                adist = math.sqrt(adx * adx + ady * ady)
                                guard = guard + 1
                            end
                            chain.trailX, chain.trailY = ax, ay
                        end
                    end
                end
            end
        end

        if chain and chain.targets and chain.index > #chain.targets then
            p.slashDashChain = nil
        end
    elseif moving then
        -- ==================== 普通移动/滑行 ====================
        local SLIDE_ENERGY_DRAIN = 5.0 -- 滑行时每秒消耗的能量
        local hasEnergy = (p.energy or 0) > 0
        local isSliding = input.isDown('slide') and p.stats.moveSpeed > 0 and hasEnergy

        local speed = (p.stats.moveSpeed or 0) * (p.moveSpeedBuffMult or 1)
        if isSliding then
            -- 滑行时持续消耗能量
            p.energy = math.max(0, p.energy - SLIDE_ENERGY_DRAIN * dt)

            speed = speed * SLIDE_SPEED_MULT -- 滑行速度加成
            p.isSliding = true
            -- 专注闪避状态: 不缩小体积，但有速度加成 + 伤害减免(hurt函数中处理)
            if state.spawnDashAfterimage and math.random() < 0.2 then
                state.spawnDashAfterimage(p.x, p.y, p.facing, { alpha = 0.1, duration = 0.3 })
            end
        else
            p.isSliding = false
        end
        local len = math.sqrt(dx * dx + dy * dy)
        local mx = (dx / len) * speed * dt
        local my = (dy / len) * speed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x = p.x + mx
            p.y = p.y + my
        end
    else
        p.isSliding = false
        p.size = 20
    end

    if dash and (dash.timer or 0) <= 0 then
        dash.trailX = nil
        dash.trailY = nil
    end

    -- 更新瞄准角度 (鼠标方向，360度)
    p.aimAngle = input.getAimAngle(state, p.x, p.y)

    -- 【面向解耦】攻击或使用技能时，面向跟随瞄准而非移动方向
    local isAttacking = input.isDown('fire') or (p.meleeState and p.meleeState.phase ~= 'idle')
    if isAttacking then
        -- 面向鼠标/准星
        p.facing = (math.cos(p.aimAngle) >= 0) and 1 or -1
    elseif dx ~= 0 then
        -- 标准移动面向
        p.facing = (dx > 0) and 1 or -1
    end
    p.isMoving = moving
    local mdx, mdy = p.x - ox, p.y - oy
    p.movedDist = math.sqrt(mdx * mdx + mdy * mdy) -- 本帧移动距离

    -- 保存移动方向（用于8向动画）
    -- 使用实际移动方向，如果没移动则保持上一次的方向
    if p.movedDist > 0.1 then
        p.moveDirX = mdx
        p.moveDirY = mdy
    elseif moving and (dx ~= 0 or dy ~= 0) then
        -- 正在尝试移动但碰到墙，使用输入方向
        p.moveDirX = dx
        p.moveDirY = dy
    end

    -- 【Volt被动技能】静电释放 - 移动时累积电荷
    -- 仅对Volt职业生效
    if p.class == 'volt' and p.movedDist > 0 then
        p.staticCharge = p.staticCharge or 0
        local chargeRate = 0.15 -- 每移动1像素累积的电荷
        p.staticCharge = math.min(100, p.staticCharge + p.movedDist * chargeRate)
    end

    -- ==================== 摄像机跟随 ====================
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    local camX = p.x - sw / 2
    local camY = p.y - sh / 2
    if world and world.enabled and world.pixelW and world.pixelH then
        local maxCamX = math.max(0, world.pixelW - sw)
        local maxCamY = math.max(0, world.pixelH - sh)
        camX = clamp(camX, 0, maxCamX)
        camY = clamp(camY, 0, maxCamY)
    end
    state.camera.x = camX
    state.camera.y = camY
end

-- =============================================================================
-- 伤害系统
-- =============================================================================

--- 玩家受到伤害
--- 【伤害处理流程】
--- 1. 无敌帧检测
--- 2. 护甲减伤计算
--- 3. 滑行减伤
--- 4. 护盾优先承伤 + 护盾锁
--- 5. 生命值承伤
--- 6. 触发死亡/无敌帧
--- @param state table 游戏状态
--- @param dmg number 原始伤害值
function player.hurt(state, dmg)
    local p = state.player
    if state.benchmarkMode then return end   -- 调试模式无敌
    if p.invincibleTimer > 0 then return end -- 无敌帧内不受伤

    -- 【护甲减伤公式】 实际伤害 = 原始伤害 × (300 / (护甲 + 300))
    -- 这个公式来自《Warframe》，护甲收益递减
    local armor = (p.stats and p.stats.armor) or 0
    local hpBefore = p.hp
    local shieldBefore = p.shield or 0
    local dmgVal = dmg or 0
    local reduced = dmgVal
    if armor > 0 then
        reduced = dmgVal * (300 / (armor + 300))
    end
    local incoming = math.max(1, math.floor(reduced))

    local ctx = {
        amount = incoming,
        dmg = dmg or 0,
        armor = armor,
        hpBefore = hpBefore,
        shieldBefore = shieldBefore,
        hpAfter = hpBefore,
        shieldAfter = shieldBefore,
        player = p,
        isMoving = p.isMoving or false,
        movedDist = p.movedDist or 0
    }
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'preHurt', ctx)
    end
    incoming = math.max(0, math.floor(ctx.amount or incoming))
    if ctx.cancel or incoming <= 0 then
        local inv = ctx.invincibleTimer or 0
        if inv > 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, inv)
        end
        ctx.amount = 0
        ctx.hpAfter = p.hp
        ctx.shieldAfter = p.shield or 0
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'hurtCancelled', ctx)
        end
        return
    end

    -- 重置护盾恢复延迟计时器 (受伤后需要重新等待才能回护盾)
    p.shieldDelayTimer = 0

    local shieldDamage = 0
    local healthDamage = 0
    local remaining = incoming

    -- 【滑行减伤】战术冲刺: 30%伤害减免
    if p.isSliding then
        local SLIDE_DR = 0.30
        remaining = math.floor(remaining * (1 - SLIDE_DR))
    end

    -- 【护盾优先】(仿Warframe) 伤害先承受护盾
    if (p.shield or 0) > 0 then
        shieldDamage = math.min(p.shield, remaining)
        p.shield = p.shield - shieldDamage
        remaining = remaining - shieldDamage

        -- 【护盾锁机制】护盾破裂时获得短暂无敌，并吸收溢出伤害
        if shieldDamage > 0 and (p.shield or 0) <= 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, SHIELD_GATE_DURATION)
            remaining = 0 -- 护盾锁期间吸收剩余伤害
            if state.texts then
                table.insert(state.texts,
                    { x = p.x, y = p.y - 50, text = "护盾锁!", color = { 0.4, 0.8, 1 }, life = 0.8 })
            end
        end
    end

    -- 剩余伤害应用到生命值
    if remaining > 0 then
        healthDamage = remaining
        p.hp = math.max(0, p.hp - healthDamage)
    end

    local applied = shieldDamage + healthDamage
    ctx.amount = applied
    ctx.shieldDamage = shieldDamage
    ctx.healthDamage = healthDamage
    ctx.hpAfter = p.hp
    ctx.shieldAfter = p.shield or 0

    if applied > 0 then
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onHurt', ctx)
            state.augments.dispatch(state, 'postHurt', ctx)
        end
    end

    logger.damageTaken(state, applied, p.hp)
    if p.hp <= 0 then
        -- 玩家死亡
        p.invincibleTimer = 0
        state.shakeAmount = 0
        state.gameState = 'GAME_OVER'
        if state.stopMusic then state.stopMusic() end
        logger.gameOver(state, 'death')
    else
        -- 受伤后短暂无敌 (0.5秒)
        if healthDamage > 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.5)
        end
        state.shakeAmount = 5 -- 屏幕震动
    end
    if state.playSfx then state.playSfx('hit') end

    -- 根据伤害类型显示不同颜色的伤害数字
    local textColor = { 1, 0, 0 }   -- 红色: 生命伤害
    if shieldDamage > 0 and healthDamage == 0 then
        textColor = { 0.4, 0.7, 1 } -- 蓝色: 仅护盾伤害
    end
    table.insert(state.texts, { x = p.x, y = p.y - 30, text = "-" .. applied, color = textColor, life = 1 })
end

-- =============================================================================
-- 状态更新函数
-- =============================================================================

--- 更新无敌帧计时器
--- @param state table 游戏状态
--- @param dt number 帧间隔时间
function player.tickInvincibility(state, dt)
    if state.player.invincibleTimer > 0 then
        state.player.invincibleTimer = state.player.invincibleTimer - dt
        if state.player.invincibleTimer < 0 then state.player.invincibleTimer = 0 end
    end
end

--- 更新生命值自动回复
--- @param state table 游戏状态
--- @param dt number 帧间隔时间
function player.tickRegen(state, dt)
    local p = state.player
    local regen = p.stats.regen or 0 -- 每秒回复量
    if regen > 0 and p.hp < p.maxHp then
        p.hp = math.min(p.maxHp, p.hp + regen * dt)
    end
end

--- 更新护盾回复 (仿Warframe)
--- @param state table 游戏状态
--- @param dt number 帧间隔时间
function player.tickShields(state, dt)
    local p = state.player
    if not p then return end

    local maxShield = (p.stats and p.stats.maxShield) or p.maxShield or 0
    if maxShield <= 0 then return end

    -- 更新护盾延迟计时器 (受伤后重置为0)
    p.shieldDelayTimer = (p.shieldDelayTimer or 0) + dt

    -- 延迟时间到后开始回复护盾
    if p.shieldDelayTimer >= SHIELD_REGEN_DELAY and (p.shield or 0) < maxShield then
        local regen = maxShield * SHIELD_REGEN_RATE * dt
        p.shield = math.min(maxShield, (p.shield or 0) + regen)
    end
end

--- 更新浮动文字 (伤害数字、提示等)
--- @param state table 游戏状态
--- @param dt number 帧间隔时间
function player.tickTexts(state, dt)
    for i = #state.texts, 1, -1 do
        local t = state.texts[i]
        t.life = t.life - dt
        local speed = t.floatSpeed or 30 -- 上浮速度
        t.y = t.y - speed * dt           -- 向上浮动
        if t.life <= 0 then table.remove(state.texts, i) end
    end
end

-- 已整合: player.keypressed 和 player.useAbility 已合并，避免冗余


-- =============================================================================
-- 快速近战系统 (仿Warframe)
-- =============================================================================
--[[
    快速近战允许玩家在使用远程武器时快速进行一次近战攻击
    按E键会临时切换到近战槽攻击，然后自动切回远程
]]

--- 快速近战 (E键)
--- @param state table 游戏状态
--- @return boolean 是否成功触发
function player.quickMelee(state)
    local weapons = require('gameplay.weapons')
    local inv = state.inventory

    -- 检查是否装备了近战武器
    if not inv.weaponSlots.melee then
        return false
    end

    -- 记录之前的槽位，以便攻击后切回
    local prevSlot = inv.activeSlot
    if prevSlot == 'melee' then
        -- 已经在近战模式，直接触发攻击
        player.triggerMelee(state)
        return true
    end

    -- 切换到近战槽
    inv.activeSlot = 'melee'

    -- 设置标志，攻击结束后切回之前的槽位
    state.player.quickMeleeReturn = prevSlot

    -- 触发近战攻击
    player.triggerMelee(state)

    return true
end

--- 触发近战攻击 (供 quickMelee 和 普通近战使用)
--- @param state table 游戏状态
function player.triggerMelee(state)
    local p = state.player
    -- 初始化近战状态 (如果不存在)
    if not p.melee then
        p.melee = { state = 'ready', timer = 0 }
    end
    -- 如果不在攻击中，开始攻击
    if p.melee.state == 'ready' or p.melee.state == 'cooldown' then
        p.melee.state = 'anticipating'
        p.melee.timer = 0
    end
end

-- =============================================================================
-- 动画状态机 (8方向动画)
-- =============================================================================

--- 更新玩家动画状态机
--- 根据玩家当前状态选择合适的动画集和贴图
--- @param state table 游戏状态
--- @param dt number 帧间隔时间
function player.updateAnimation(state, dt)
    if not state.playerAnimSets and not state.playerAnim then return end

    local p = state.player
    local dash = p.dash or {}
    local melee = p.meleeState or {}

    -- 确定当前动画状态
    local animState = 'idle'
    local animSpeed = 1.0
    local animSetKey = 'run' -- 使用的动画集

    -- 检测冲刺/Bullet Jump状态
    local isDashing = (dash.timer or 0) > 0
    local isBulletJumping = (p.bulletJumpTimer or 0) > 0
    local isInDashState = isDashing or isBulletJumping

    if isInDashState then
        -- 冲刺/Bullet Jump：使用滑行动画
        animState = 'dash'
        animSetKey = 'slide'
        animSpeed = 2.0

        -- 检测是否刚进入冲刺状态（从非冲刺变为冲刺）
        local wasInAnyDash = p.wasDashing or p.wasBulletJumping
        if not wasInAnyDash then
            if state.playerAnim and state.playerAnim.gotoFrame then
                state.playerAnim:gotoFrame(1)
            end
        end

        p.wasDashing = isDashing
        p.wasBulletJumping = isBulletJumping
    elseif melee.phase and melee.phase ~= 'idle' then
        -- 近战攻击
        animState = 'attack'
        animSetKey = 'run'
        if melee.attackType == 'heavy' then
            animSpeed = 0.8
        else
            animSpeed = 1.5
        end
    elseif p.isSliding then
        -- Shift 滑行状态
        animState = 'slide_run'
        animSetKey = 'run'
        animSpeed = 1.2
        p.wasDashing = false
        p.wasBulletJumping = false
    elseif p.isMoving then
        -- 移动中
        animState = 'run'
        animSetKey = 'run'
        animSpeed = 1.0
        p.wasDashing = false
        p.wasBulletJumping = false
    else
        -- 静止
        animState = 'idle'
        animSetKey = 'idle'
        animSpeed = 1.0
        p.wasDashing = false
        p.wasBulletJumping = false
    end

    p.animState = animState

    -- 8向动画方向选择
    if state.playerAnimSets and state.playerAnimsLoader then
        local vx = p.moveDirX or 0
        local vy = p.moveDirY or 0
        local dir = p.animDirection or 'S'

        if math.abs(vx) > 0.01 or math.abs(vy) > 0.01 then
            dir = state.playerAnimsLoader.getDirectionFromVelocity(vx, vy)
            p.animDirection = dir
        end

        local animSet = state.playerAnimSets[animSetKey]
        if animSet and animSet[dir] then
            local newAnim = animSet[dir]
            if state.playerAnim ~= newAnim then
                state.playerAnim = newAnim
                if newAnim.play then newAnim:play(true) end
            end
        end
    end

    -- 更新当前动画
    if state.playerAnim then
        if not state.playerAnim.playing then state.playerAnim:play(false) end
        state.playerAnim:update(dt * animSpeed)
    end
end

return player
