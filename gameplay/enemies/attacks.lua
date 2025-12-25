-- enemies/attacks.lua
-- 敌人攻击系统模块
-- 负责管理敌人的各种攻击类型配置和攻击初始化逻辑

local player = require('gameplay.player')
local pets = require('gameplay.pets')
local status = require('gameplay.status')

local attacks = {}

--------------------------------------------------------------------------------
-- 攻击类型常量
--------------------------------------------------------------------------------

attacks.TYPES = {
    CHARGE = 'charge',      -- 冲锋攻击
    SLAM = 'slam',          -- 砸地攻击
    BURST = 'burst',        -- 弹幕攻击
    MELEE = 'melee',        -- 近战攻击
    THROW = 'throw',        -- 投掷攻击
    LEAP = 'leap',          -- 跳跃攻击
    SHIELD_BASH = 'shield_bash', -- 盾击
    GRAPPLE = 'grapple',    -- 钩索攻击
    SUICIDE = 'suicide',    -- 自爆攻击
    SHOOT = 'shoot',        -- 射击攻击
    SNIPE = 'snipe',        -- 狙击攻击
    ROCKET = 'rocket',      -- 火箭攻击
}

--------------------------------------------------------------------------------
-- 工具函数
--------------------------------------------------------------------------------

--- 获取穿刺减伤
local function getPunctureReduction(e)
    return status.getPunctureReduction(e)
end

--- 获取冲击减伤
local function getBlastReduction(e)
    return status.getBlastReduction(e)
end

--- 权重随机选择
-- @param pool 选项池 [{key, cfg, w}, ...]
-- @return table|nil 选中的项
function attacks.chooseWeighted(pool)
    local total = 0
    for _, it in ipairs(pool or {}) do
        total = total + (it.w or 0)
    end
    if total <= 0 then return pool and pool[1] end
    local r = math.random() * total
    for _, it in ipairs(pool) do
        r = r - (it.w or 0)
        if r <= 0 then return it end
    end
    return pool[#pool]
end

--------------------------------------------------------------------------------
-- 攻击配置构建器
--------------------------------------------------------------------------------

--- 构建冲锋攻击配置
-- @param cfg 原始攻击配置
-- @param e 敌人实体
-- @param angToTarget 目标角度
-- @return table 攻击实例
function attacks.buildCharge(cfg, e, angToTarget)
    local windupMult = e.eliteWindupMult or 1
    local eliteDamageMult = e.eliteDamageMult or 1
    local bossPhase = e.bossPhase or 1
    local phaseK = math.max(0, bossPhase - 1)
    
    local windup = math.max(0.4, (cfg.windup or 0.55) * windupMult)
    local distance = cfg.distance or 260
    local spd = cfg.speed or 520
    local width = cfg.telegraphWidth or 36
    local damage = (cfg.damage or 18) * eliteDamageMult
    local cooldown = cfg.cooldown or 2.5
    
    -- Boss 阶段加成
    if e.isBoss then
        windup = math.max(0.45, windup * (1 - phaseK * 0.07))
        distance = distance * (1 + phaseK * 0.12)
        spd = spd * (1 + phaseK * 0.08)
        width = width * (1 + phaseK * 0.08)
        damage = damage * (1 + phaseK * 0.12)
        cooldown = math.max(1.2, cooldown * (1 - phaseK * 0.08))
    end
    
    local interruptible = cfg.interruptible
    if interruptible == nil then interruptible = true end
    if e.isBoss then interruptible = false end
    
    return {
        type = 'charge',
        phase = 'windup',
        timer = windup,
        interruptible = interruptible,
        dirX = math.cos(angToTarget),
        dirY = math.sin(angToTarget),
        distance = distance,
        speed = spd,
        width = width,
        damage = damage,
        cooldown = cooldown
    }
end

--- 构建砸地攻击配置
-- @param cfg 原始攻击配置
-- @param e 敌人实体
-- @param targetX 目标X坐标
-- @param targetY 目标Y坐标
-- @return table 攻击实例
function attacks.buildSlam(cfg, e, targetX, targetY)
    local windupMult = e.eliteWindupMult or 1
    local eliteDamageMult = e.eliteDamageMult or 1
    local bossPhase = e.bossPhase or 1
    local phaseK = math.max(0, bossPhase - 1)
    
    local windup = math.max(0.45, (cfg.windup or 0.85) * windupMult)
    local radius = cfg.radius or 110
    local damage = (cfg.damage or 16) * eliteDamageMult
    local cooldown = cfg.cooldown or 3.0
    
    if e.isBoss then
        windup = math.max(0.5, windup * (1 - phaseK * 0.06))
        radius = radius * (1 + phaseK * 0.12)
        damage = damage * (1 + phaseK * 0.12)
        cooldown = math.max(1.4, cooldown * (1 - phaseK * 0.07))
    end
    
    local interruptible = cfg.interruptible
    if interruptible == nil then interruptible = true end
    if e.isBoss then interruptible = false end
    
    return {
        type = 'slam',
        phase = 'windup',
        timer = windup,
        interruptible = interruptible,
        x = targetX,
        y = targetY,
        radius = radius,
        damage = damage,
        cooldown = cooldown
    }
end

--- 构建弹幕攻击配置
-- @param cfg 原始攻击配置
-- @param e 敌人实体
-- @param angToTarget 目标角度
-- @return table 攻击实例
function attacks.buildBurst(cfg, e, angToTarget)
    local windupMult = e.eliteWindupMult or 1
    local eliteDamageMult = e.eliteDamageMult or 1
    local bossPhase = e.bossPhase or 1
    local phaseK = math.max(0, bossPhase - 1)
    
    local windup = math.max(0.45, (cfg.windup or 0.6) * windupMult)
    local count = cfg.count or 5
    local spread = cfg.spread or 0.8
    local bulletSpeed = (cfg.bulletSpeed or (e.bulletSpeed or 180)) * (e.eliteBulletSpeedMult or 1)
    local bulletDamage = (cfg.bulletDamage or (e.bulletDamage or 10)) * eliteDamageMult
    local bulletLife = cfg.bulletLife or (e.bulletLife or 5)
    local bulletSize = cfg.bulletSize or (e.bulletSize or 10)
    local cooldown = cfg.cooldown or 2.5
    local len = cfg.telegraphLength or cfg.distance or 360
    local width = cfg.telegraphWidth or 46
    
    if e.isBoss then
        windup = math.max(0.55, windup * (1 - phaseK * 0.05))
        count = count + phaseK * 2
        spread = spread * (1 + phaseK * 0.16)
        bulletSpeed = bulletSpeed * (1 + phaseK * 0.06)
        bulletDamage = bulletDamage * (1 + phaseK * 0.10)
        len = len * (1 + phaseK * 0.05)
        width = width * (1 + phaseK * 0.10)
        cooldown = math.max(1.2, cooldown * (1 - phaseK * 0.10))
    end
    
    local interruptible = cfg.interruptible
    if interruptible == nil then interruptible = false end -- burst 默认不可打断
    if e.isBoss then interruptible = false end
    
    return {
        type = 'burst',
        phase = 'windup',
        timer = windup,
        interruptible = interruptible,
        ang = angToTarget,
        count = count,
        spread = spread,
        bulletSpeed = bulletSpeed,
        bulletDamage = bulletDamage,
        bulletLife = bulletLife,
        bulletSize = bulletSize,
        cooldown = cooldown,
        width = width,
        length = len
    }
end

--- 构建近战攻击配置
-- @param cfg 原始攻击配置
-- @param e 敌人实体
-- @return table 攻击实例
function attacks.buildMelee(cfg, e)
    local windupMult = e.eliteWindupMult or 1
    local eliteDamageMult = e.eliteDamageMult or 1
    
    local windup = math.max(0.25, (cfg.windup or 0.4) * windupMult)
    local range = cfg.range or 50
    local damage = (cfg.damage or 8) * eliteDamageMult
    local cooldown = cfg.cooldown or 1.5
    
    return {
        type = 'melee',
        phase = 'windup',
        timer = windup,
        interruptible = true,
        range = range,
        damage = damage,
        cooldown = cooldown
    }
end

--- 构建投掷攻击配置
-- @param cfg 原始攻击配置
-- @param e 敌人实体
-- @param angToTarget 目标角度
-- @return table 攻击实例
function attacks.buildThrow(cfg, e, angToTarget)
    local windupMult = e.eliteWindupMult or 1
    local eliteDamageMult = e.eliteDamageMult or 1
    
    local windup = math.max(0.3, (cfg.windup or 0.5) * windupMult)
    local damage = (cfg.damage or 6) * eliteDamageMult
    local bulletSpeed = (cfg.bulletSpeed or 200) * (e.eliteBulletSpeedMult or 1)
    local bulletLife = cfg.bulletLife or 2
    local bulletSize = cfg.bulletSize or 8
    local cooldown = cfg.cooldown or 3.0
    
    return {
        type = 'throw',
        phase = 'windup',
        timer = windup,
        interruptible = true,
        ang = angToTarget,
        damage = damage,
        bulletSpeed = bulletSpeed,
        bulletLife = bulletLife,
        bulletSize = bulletSize,
        cooldown = cooldown
    }
end

--- 构建跳跃攻击配置
-- @param cfg 原始攻击配置
-- @param e 敌人实体
-- @param angToTarget 目标角度
-- @param distToTarget 到目标的距离
-- @return table 攻击实例
function attacks.buildLeap(cfg, e, angToTarget, distToTarget)
    local windupMult = e.eliteWindupMult or 1
    local eliteDamageMult = e.eliteDamageMult or 1
    
    local windup = math.max(0.2, (cfg.windup or 0.3) * windupMult)
    local distance = cfg.distance or 100
    local spd = cfg.speed or 600
    local damage = (cfg.damage or 7) * eliteDamageMult
    local cooldown = cfg.cooldown or 2.0
    local radius = cfg.radius or 40
    
    -- 计算实际跳跃距离和目标位置
    local actualDist = math.min(distToTarget, distance)
    local leapX = e.x + math.cos(angToTarget) * actualDist
    local leapY = e.y + math.sin(angToTarget) * actualDist
    
    return {
        type = 'leap',
        phase = 'windup',
        timer = windup,
        interruptible = true,
        targetX = leapX,
        targetY = leapY,
        startX = e.x,
        startY = e.y,
        distance = actualDist,
        speed = spd,
        leapProgress = 0,
        damage = damage,
        radius = radius,
        cooldown = cooldown
    }
end

--------------------------------------------------------------------------------
-- 攻击选择逻辑
--------------------------------------------------------------------------------

--- 从攻击池中选择攻击
-- @param attacks 攻击定义表 {key = cfg, ...}
-- @param e 敌人实体
-- @param distToTarget 到目标的距离
-- @return key, cfg 选中的攻击键和配置
function attacks.selectAttack(attackDefs, e, distToTarget)
    if not attackDefs then return nil, nil end
    
    local distSq = distToTarget * distToTarget
    local pool = {}
    
    for key, cfg in pairs(attackDefs) do
        if type(cfg) == 'table' then
            local minR = cfg.rangeMin or 0
            local maxR = cfg.range or cfg.rangeMax or cfg.maxRange or 999999
            if distSq >= minR * minR and distSq <= maxR * maxR then
                local w = cfg.w or cfg.weight or 1
                
                -- Boss 阶段权重调整
                if e.isBoss then
                    local phase = e.bossPhase or 1
                    if key == 'burst' then
                        if phase == 1 then w = w * 1.20
                        elseif phase == 3 then w = w * 0.85 end
                    elseif key == 'slam' then
                        if phase == 2 then w = w * 1.15 end
                    elseif key == 'charge' then
                        if phase == 3 then w = w * 1.25 end
                    end
                end
                
                if w > 0 then
                    table.insert(pool, {key = key, cfg = cfg, w = w})
                end
            end
        end
    end
    
    local pick = attacks.chooseWeighted(pool)
    if pick then
        return pick.key, pick.cfg
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- 伤害计算辅助
--------------------------------------------------------------------------------

--- 检查并应用区域伤害到玩家
-- @param state 游戏状态
-- @param e 敌人实体
-- @param centerX 伤害中心X
-- @param centerY 伤害中心Y
-- @param radius 伤害半径
-- @param damage 基础伤害
-- @return boolean 是否命中玩家
function attacks.applyAreaDamageToPlayer(state, e, centerX, centerY, radius, damage)
    local p = state.player
    local dx = p.x - centerX
    local dy = p.y - centerY
    local pr = (p.size or 20) / 2
    local rr = radius + pr
    
    local dmgMult = 1 - getPunctureReduction(e)
    if dmgMult < 0.25 then dmgMult = 0.25 end
    
    if dx * dx + dy * dy <= rr * rr then
        player.hurt(state, damage * dmgMult)
        return true
    end
    return false
end

--- 检查并应用区域伤害到宠物
-- @param state 游戏状态
-- @param e 敌人实体
-- @param centerX 伤害中心X
-- @param centerY 伤害中心Y
-- @param radius 伤害半径
-- @param damage 基础伤害
-- @return boolean 是否命中宠物
function attacks.applyAreaDamageToPet(state, e, centerX, centerY, radius, damage)
    local pet = pets.getActive(state)
    if not pet or pet.downed then return false end
    
    local dx = (pet.x or 0) - centerX
    local dy = (pet.y or 0) - centerY
    local petR = (pet.size or 18) / 2
    local rr = radius + petR
    
    local dmgMult = 1 - getPunctureReduction(e)
    if dmgMult < 0.25 then dmgMult = 0.25 end
    
    if dx * dx + dy * dy <= rr * rr then
        pets.hurt(state, pet, damage * dmgMult)
        return true
    end
    return false
end

return attacks
