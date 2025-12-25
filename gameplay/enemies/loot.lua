-- enemies/loot.lua
-- 敌人掉落系统模块
-- 负责计算和生成敌人死亡时的掉落物品（金币、资源、MOD卡等）

local dropRates = require('data.defs.drop_rates')

local loot = {}

-- 缓存掉落定义
local enemyDropDefs = (dropRates and dropRates.enemy) or {}

--------------------------------------------------------------------------------
-- 掉落物品生成
--------------------------------------------------------------------------------

--- 在指定位置生成掉落物
-- @param state 游戏状态
-- @param x 掉落X坐标
-- @param y 掉落Y坐标
-- @param kind 掉落类型 ('health_orb', 'energy_orb', 'ammo', 'mod_card')
-- @param opts 额外选项
local function spawnPickup(state, x, y, kind, opts)
    opts = opts or {}
    state.floorPickups = state.floorPickups or {}
    table.insert(state.floorPickups, {
        x = x,
        y = y,
        size = opts.size or 10,
        kind = kind,
        amount = opts.amount,
        bonusRareChance = opts.bonusRareChance or 0
    })
end

--- 给予玩家金币/积分
-- @param state 游戏状态
-- @param amount 金额
-- @param e 敌人实体（用于位置）
-- @param label 显示标签 ('GOLD' 或 'CREDITS')
local function giveGold(state, amount, e, label)
    if state.gainGold then
        state.gainGold(amount, {source = 'kill', enemy = e, x = e.x, y = e.y - 20, life = 0.55})
    else
        state.runCurrency = (state.runCurrency or 0) + amount
        table.insert(state.texts, {x = e.x, y = e.y - 20, text = "+" .. tostring(amount) .. " " .. (label or "GOLD"), color = {0.95, 0.9, 0.45}, life = 0.55})
    end
end

--------------------------------------------------------------------------------
-- 探索模式掉落
--------------------------------------------------------------------------------

--- 处理探索模式下的敌人掉落
-- @param state 游戏状态
-- @param e 敌人实体
function loot.processExploreDrop(state, e)
    if e.noDrops then return end
    
    local drop = enemyDropDefs
    local pity = drop.pity or {}
    local exploreDef = drop.explore or {}
    local eliteDef = exploreDef.elite or {}
    local normalDef = exploreDef.normal or {}
    
    -- 金币掉落
    local gain = e.isElite and 6 or 1
    if not e.isElite and math.random() < 0.12 then gain = gain + 1 end
    giveGold(state, gain, e, "GOLD")
    
    -- 资源掉落计算
    local pl = state.player
    local eRatio = (pl and pl.energy or 0) / (pl and pl.maxEnergy or 100)
    local hRatio = (pl and pl.hp or 0) / (pl and pl.maxHp or 100)
    
    -- Warframe风格的低概率掉落，低资源时有怜悯机制
    local healthChance = (hRatio < (pity.hpThreshold or 0.3)) and (pity.healthLow or 0.06) or (pity.health or 0.03)
    local energyChance = (eRatio < (pity.energyThreshold or 0.25)) and (pity.energyLow or 0.05) or (pity.energy or 0.02)
    local ammoChance = drop.ammoChance or 0.03
    
    state.floorPickups = state.floorPickups or {}
    
    if e.isElite then
        -- 精英怪掉落：较高但不保证（WF Eximus风格）
        if math.random() < (eliteDef.healthOrb or 0.20) then
            spawnPickup(state, e.x + 15, e.y, 'health_orb', {size = 12, amount = 25})
        end
        if math.random() < (eliteDef.energyOrb or 0.15) then
            spawnPickup(state, e.x - 15, e.y, 'energy_orb', {size = 12, amount = 35})
        end
        if math.random() < (eliteDef.ammo or 0.12) then
            spawnPickup(state, e.x, e.y + 15, 'ammo', {size = 12, amount = 30})
        end
    else
        -- 普通敌人掉落（WF风格低概率）
        local roll = math.random()
        if roll < healthChance then
            spawnPickup(state, e.x, e.y, 'health_orb', {amount = 15})
        elseif roll < healthChance + energyChance then
            spawnPickup(state, e.x, e.y, 'energy_orb', {amount = 25})
        end
        if math.random() < ammoChance then
            spawnPickup(state, e.x + 5, e.y - 5, 'ammo', {amount = 15})
        end
    end
    
    -- MOD卡掉落
    local modDropChance = e.isElite and (eliteDef.modDrop or 0.80) or (normalDef.modDrop or 0.25)
    if math.random() < modDropChance then
        spawnPickup(state, e.x, e.y, 'mod_card', {
            size = 12,
            bonusRareChance = e.isElite and (eliteDef.bonusRare or 0.5) or 0
        })
    end
end

--------------------------------------------------------------------------------
-- 房间模式掉落
--------------------------------------------------------------------------------

--- 处理房间模式下的敌人掉落
-- @param state 游戏状态
-- @param e 敌人实体
function loot.processRoomsDrop(state, e)
    if e.noDrops then return end
    
    local drop = enemyDropDefs
    local pity = drop.pity or {}
    local roomsDef = drop.rooms or {}
    local eliteDef = roomsDef.elite or {}
    local normalDef = roomsDef.normal or {}
    
    state.floorPickups = state.floorPickups or {}
    
    if e.isElite then
        -- 精英掉落（WF Eximus风格）
        local gain = 8 + math.floor((state.rooms and state.rooms.roomIndex) or 1)
        giveGold(state, gain, e, "CREDITS")
        
        -- 生命球（20%）
        if math.random() < (eliteDef.healthOrb or 0.20) then
            spawnPickup(state, e.x + 15, e.y, 'health_orb', {size = 12})
        end
        -- 能量球（12%）
        if math.random() < (eliteDef.energyOrb or 0.12) then
            spawnPickup(state, e.x - 15, e.y, 'energy_orb', {size = 12})
        end
        -- 弹药（30%）
        if math.random() < (eliteDef.ammo or 0.30) then
            spawnPickup(state, e.x, e.y + 15, 'ammo', {size = 12, amount = 30})
        end
        -- MOD卡（15%）
        if math.random() < (eliteDef.modDrop or 0.15) then
            spawnPickup(state, e.x, e.y, 'mod_card', {
                size = 12,
                bonusRareChance = eliteDef.bonusRare or 0.5
            })
        end
    else
        -- 普通敌人掉落
        local pl = state.player
        local eRatio = (pl and pl.energy or 0) / (pl and pl.maxEnergy or 100)
        local hRatio = (pl and pl.hp or 0) / (pl and pl.maxHp or 100)
        
        local healthChance = (hRatio < (pity.hpThreshold or 0.3)) and (pity.healthLow or 0.06) or (pity.health or 0.03)
        local energyChance = (eRatio < (pity.energyThreshold or 0.25)) and (pity.energyLow or 0.05) or (pity.energy or 0.02)
        local creditChance = normalDef.credit or 0.08
        
        local roll = math.random()
        if roll < healthChance then
            spawnPickup(state, e.x, e.y, 'health_orb')
        elseif roll < healthChance + energyChance then
            spawnPickup(state, e.x, e.y, 'energy_orb')
        elseif roll < healthChance + energyChance + creditChance then
            local gain = 1 + (math.random() < 0.3 and 1 or 0)
            giveGold(state, gain, e, "CREDITS")
        end
        
        -- 弹药（18%）
        if math.random() < (normalDef.ammo or 0.18) then
            spawnPickup(state, e.x + 5, e.y - 5, 'ammo', {amount = 20})
        end
        -- MOD卡（5%）
        if math.random() < (normalDef.modDrop or 0.05) then
            spawnPickup(state, e.x, e.y, 'mod_card', {
                size = 12,
                bonusRareChance = 0
            })
        end
    end
end

--------------------------------------------------------------------------------
-- 主入口
--------------------------------------------------------------------------------

--- 处理敌人死亡掉落
-- @param state 游戏状态
-- @param e 敌人实体
function loot.process(state, e)
    if e.noDrops then return end
    
    local exploreMode = (state.runMode == 'explore') or (state.world and state.world.enabled)
    
    if exploreMode then
        loot.processExploreDrop(state, e)
    else
        loot.processRoomsDrop(state, e)
    end
end

return loot
