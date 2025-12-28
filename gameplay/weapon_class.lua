--- ============================================================================
--- 武器类 (Weapon Class)
--- ============================================================================
--- 封装武器实例的面向对象设计
--- 提供统一的武器操作接口：射击、换弹、属性访问等
--- ============================================================================

local Weapon = {}
Weapon.__index = Weapon

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
    return stats
end

-- ============================================================================
-- 构造函数
-- ============================================================================

--- 从武器配置创建武器实例
--- @param state table 游戏状态（用于读取 catalog）
--- @param weaponKey string 武器 key（如 'braton'）
--- @param owner string|nil 拥有者（默认 'player'）
--- @return Weapon|nil
function Weapon.new(state, weaponKey, owner)
    local proto = state.catalog and state.catalog[weaponKey]
    if not proto then
        print("[Weapon] 未找到武器配置: " .. tostring(weaponKey))
        return nil
    end
    
    local self = setmetatable({}, Weapon)
    
    -- 基础信息
    self.key = weaponKey
    self.name = proto.name or weaponKey
    self.owner = owner or 'player'
    self.slotType = proto.slotType or 'ranged'
    self.level = 1
    
    -- 复制基础属性
    self.stats = cloneStats(proto.base)
    
    -- 弹药系统
    self.magazine = self.stats.magazine or self.stats.maxMagazine or math.huge
    self.maxMagazine = self.stats.maxMagazine or self.magazine
    self.reserve = self.stats.reserve or self.stats.maxReserve or 0
    self.maxReserve = self.stats.maxReserve or self.reserve
    self.reloadTime = self.stats.reloadTime or 2.0
    
    -- 状态
    self.timer = 0           -- 射击冷却计时器
    self.isReloading = false
    self.reloadTimer = 0
    
    return self
end

--- 从旧格式数据创建武器实例（向后兼容）
--- @param data table 旧格式武器数据
--- @return Weapon
function Weapon.fromData(data)
    local self = setmetatable({}, Weapon)
    
    self.key = data.key
    self.name = data.name or data.key
    self.owner = data.owner or 'player'
    self.slotType = data.slotType or 'ranged'
    self.level = data.level or 1
    
    self.stats = data.stats or {}
    
    self.magazine = data.magazine or 0
    self.maxMagazine = data.maxMagazine or self.stats.maxMagazine or 0
    self.reserve = data.reserve or 0
    self.maxReserve = data.maxReserve or self.stats.maxReserve or 0
    self.reloadTime = data.reloadTime or self.stats.reloadTime or 2.0
    
    self.timer = data.timer or 0
    self.isReloading = data.isReloading or false
    self.reloadTimer = data.reloadTimer or 0
    
    return self
end

-- ============================================================================
-- 核心方法
-- ============================================================================

--- 更新武器状态（每帧调用）
--- @param dt number 帧间隔
function Weapon:update(dt)
    -- 更新射击冷却
    if self.timer > 0 then
        self.timer = math.max(0, self.timer - dt)
    end
    
    -- 更新换弹进度
    if self.isReloading then
        self.reloadTimer = self.reloadTimer + dt
        if self.reloadTimer >= self.reloadTime then
            self:completeReload()
        end
    end
end

--- 检查是否可以射击
--- @return boolean
function Weapon:canFire()
    if self.timer > 0 then return false end
    if self.isReloading then return false end
    if self.slotType == 'melee' then return true end  -- 近战无弹药限制
    if self.magazine and self.magazine <= 0 then return false end
    return true
end

--- 执行射击（消耗弹药、设置冷却）
--- @return boolean 是否成功射击
function Weapon:fire()
    if not self:canFire() then return false end
    
    -- 近战不消耗弹药
    if self.slotType ~= 'melee' then
        if self.magazine then
            self.magazine = self.magazine - 1
        end
    end
    
    -- 设置冷却
    self.timer = self.stats.cd or 0.1
    
    return true
end

--- 开始换弹
--- @return boolean 是否成功开始换弹
function Weapon:startReload()
    -- 已经在换弹
    if self.isReloading then return false end
    
    -- 弹夹已满
    if self.magazine >= self.maxMagazine then return false end
    
    -- 没有备弹
    if self.reserve <= 0 then return false end
    
    self.isReloading = true
    self.reloadTimer = 0
    
    return true
end

--- 完成换弹
function Weapon:completeReload()
    local needed = self.maxMagazine - self.magazine
    local transfer = math.min(needed, self.reserve)
    
    self.magazine = self.magazine + transfer
    self.reserve = self.reserve - transfer
    
    self.isReloading = false
    self.reloadTimer = 0
end

--- 取消换弹（比如被打断）
function Weapon:cancelReload()
    self.isReloading = false
    self.reloadTimer = 0
end

-- ============================================================================
-- 属性访问
-- ============================================================================

--- 获取伤害值
--- @return number
function Weapon:getDamage()
    return self.stats.damage or 0
end

--- 获取射程
--- @return number
function Weapon:getRange()
    return self.stats.range or 600
end

--- 获取射速（RPM）
--- @return number
function Weapon:getFireRate()
    local cd = self.stats.cd or 0.1
    return 60 / cd
end

--- 获取暴击率
--- @return number
function Weapon:getCritChance()
    return self.stats.critChance or 0
end

--- 获取暴击倍率
--- @return number
function Weapon:getCritMultiplier()
    return self.stats.critMultiplier or 1.5
end

--- 获取换弹进度（0-1）
--- @return number
function Weapon:getReloadProgress()
    if not self.isReloading then return 0 end
    return self.reloadTimer / self.reloadTime
end

--- 是否是近战武器
--- @return boolean
function Weapon:isMelee()
    return self.slotType == 'melee'
end

-- ============================================================================
-- 序列化（用于存档）
-- ============================================================================

--- 导出为旧格式数据（向后兼容）
--- @return table
function Weapon:toData()
    return {
        key = self.key,
        name = self.name,
        owner = self.owner,
        slotType = self.slotType,
        level = self.level,
        stats = self.stats,
        magazine = self.magazine,
        maxMagazine = self.maxMagazine,
        reserve = self.reserve,
        maxReserve = self.maxReserve,
        reloadTime = self.reloadTime,
        timer = self.timer,
        isReloading = self.isReloading,
        reloadTimer = self.reloadTimer
    }
end

--- 字符串表示
--- @return string
function Weapon:__tostring()
    return string.format("Weapon<%s> [%d/%d] %s",
        self.key,
        self.magazine or 0,
        self.maxMagazine or 0,
        self.isReloading and "(换弹中)" or ""
    )
end

return Weapon
