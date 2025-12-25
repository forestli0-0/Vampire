-- 引入依赖模块
local weapons = require('gameplay.weapons')      -- 武器系统
local pets = require('gameplay.pets')             -- 宠物系统
local world = require('world.world')              -- 世界/地图系统
local mission = require('world.mission')          -- 任务系统
local campaign = require('world.campaign')        -- 战役系统
local mods = require('systems.mods')              -- MOD系统

-- 军械库 (Arsenal) 模块
-- 负责处理玩家在出战前的武器选择、MOD 安装、战甲切换以及宠物配置。
-- 它还负责将持久化的存档数据转化为每场 Run 的初始状态。
local arsenal = {}

-- 新UI屏幕（延迟加载以避免循环依赖）
local arsenalScreen = nil
local function getArsenalScreen()
    if not arsenalScreen then
        arsenalScreen = require('ui.screens.arsenal_screen')
    end
    return arsenalScreen
end

-- 标志：是否使用新UI（设为true以启用）
arsenal.useNewUI = true

-- 最大MOD槽位数量
local MAX_SLOTS = 8

--- tagsMatch: 检查武器标签是否与目标标签匹配
-- @param weaponTags 武器的标签列表
-- @param targetTags 目标标签列表
-- @return boolean 是否匹配
local function tagsMatch(weaponTags, targetTags)
    if not weaponTags or not targetTags then return false end
    for _, tag in ipairs(targetTags) do
        for _, wTag in ipairs(weaponTags) do
            if tag == wTag then return true end
        end
    end
    return false
end

--- buildModList: 根据所属类别构建可选的 MOD 列表并排序
-- @param state 游戏状态
-- @param category MOD类别（weapons/warframe/companion）
-- @return table 排序后的MOD键值列表
local function buildModList(state, category)
    local list = {}
    -- 获取指定类别的MOD目录
    local catalog = mods.getCatalog(category or 'weapons') or {}
    for key, _ in pairs(catalog) do
        table.insert(list, key)
    end
    -- 按MOD名称排序
    table.sort(list, function(a, b)
        local catalog = mods.getCatalog(category or 'weapons') or {}
        local da, db = catalog[a], catalog[b]
        if da and db and da.name and db.name then return da.name < db.name end
        return a < b
    end)
    return list
end

--- buildWeaponList: 构建可选武器列表并排序
-- @param state 游戏状态
-- @return table 排序后的武器键值列表
local function buildWeaponList(state)
    local list = {}
    -- 遍历目录，筛选出非进化专属的武器
    for key, def in pairs(state.catalog or {}) do
        if def and def.type == 'weapon' and not def.evolvedOnly then
            table.insert(list, key)
        end
    end
    -- 按武器名称排序
    table.sort(list, function(a, b)
        local da, db = state.catalog[a], state.catalog[b]
        if da and db and da.name and db.name then
            return da.name < db.name
        end
        return a < b
    end)
    return list
end

--- ensureWeaponLoadout: 确保存档中存在该武器的配置槽位
-- @param profile 玩家存档数据
-- @param weaponKey 武器键值
-- @return table 武器的MOD配置数据
local function ensureWeaponLoadout(profile, weaponKey)
    if not profile then return nil end
    profile.weaponMods = profile.weaponMods or {}
    profile.weaponMods[weaponKey] = profile.weaponMods[weaponKey] or {slots = {}}
    local lo = profile.weaponMods[weaponKey]
    lo.slots = lo.slots or {}
    return lo
end

--- ensureCategoryLoadout: 确保指定类别的MOD配置槽位存在
-- @param profile 玩家存档数据
-- @param category 类别（weapons/warframe/companion）
-- @param weaponKey 武器键值（仅weapons类别需要）
-- @return table 该类别的MOD配置数据
local function ensureCategoryLoadout(profile, category, weaponKey)
    if not profile then return nil end
    if category == 'weapons' then
        -- 武器类别的MOD配置
        return ensureWeaponLoadout(profile, weaponKey)
    elseif category == 'warframe' then
        -- 战甲类别的MOD配置
        profile.warframeMods = profile.warframeMods or {slots = {}}
        profile.warframeMods.slots = profile.warframeMods.slots or {}
        return profile.warframeMods
    elseif category == 'companion' then
        -- 伴侣（宠物）类别的MOD配置
        profile.companionMods = profile.companionMods or {slots = {}}
        profile.companionMods.slots = profile.companionMods.slots or {}
        return profile.companionMods
    end
    return nil
end

--- countEquipped: 统计已装备的MOD数量
-- @param loadout MOD配置数据
-- @return number 已装备的MOD数量
local function countEquipped(loadout)
    local n = 0
    for _, v in pairs((loadout and loadout.slots) or {}) do
        if v then n = n + 1 end
    end
    return n
end

--- isEquipped: 检查指定MOD是否已装备
-- @param loadout MOD配置数据
-- @param key MOD键值
-- @return boolean 是否已装备
local function isEquipped(loadout, key)
    if not (loadout and loadout.slots) then return false end
    for _, k in pairs(loadout.slots) do
        if k == key then return true end
    end
    return false
end

--- isOwned: 检查玩家是否拥有该MOD
-- @param profile 玩家存档数据
-- @param key MOD键值
-- @return boolean 是否拥有
local function isOwned(profile, key)
    return profile and profile.ownedMods and profile.ownedMods[key]
end

--- getModCategory: 获取当前选中的MOD类别
-- @param profile 玩家存档数据
-- @return string MOD类别（默认为weapons）
local function getModCategory(profile)
    return (profile and profile.modTargetCategory) or 'weapons'
end

--- getWeaponClass: 获取武器类型（近战或远程）
-- @param state 游戏状态
-- @param weaponKey 武器键值
-- @return string|nil 武器类型（'melee'或'ranged'）
local function getWeaponClass(state, weaponKey)
    local def = state and state.catalog and state.catalog[weaponKey]
    if not def then return nil end
    -- 检查槽位类型
    if def.slotType == 'melee' or def.slot == 'melee' then return 'melee' end
    -- 检查标签
    if def.tags then
        for _, tag in ipairs(def.tags) do
            if tag == 'melee' then return 'melee' end
        end
    end
    return 'ranged'
end

--- isWeaponModCompatible: 检查特定 MOD 是否能安装在当前武器上
-- 例如：近战 MOD 不能装在远程武器上
-- @param state 游戏状态
-- @param weaponKey 武器键值
-- @param modKey MOD键值
-- @param category MOD类别
-- @return boolean 是否兼容
local function isWeaponModCompatible(state, weaponKey, modKey, category)
    if category ~= 'weapons' then return true end
    local catalog = mods.getCatalog(category) or {}
    local def = catalog[modKey]
    if not def or not def.weaponType then return true end
    local weaponClass = getWeaponClass(state, weaponKey)
    if not weaponClass then return false end
    return def.weaponType == weaponClass
end

--- getModRank: 获取MOD的当前等级
-- @param profile 玩家存档数据
-- @param modKey MOD键值
-- @return number MOD等级
local function getModRank(profile, modKey)
    local r = (profile and profile.modRanks and profile.modRanks[modKey]) or 0
    r = tonumber(r) or 0
    return math.max(0, math.floor(r))
end

--- getMaxRank: 获取MOD的最大等级
-- @param def MOD定义数据
-- @return number 最大等级
local function getMaxRank(def)
    local len = 0
    -- 根据cost数组长度计算最大等级
    if def and type(def.cost) == 'table' then len = #def.cost end
    -- 如果没有cost，根据value数组长度计算
    if len == 0 and def and type(def.value) == 'table' then len = #def.value end
    if len == 0 then return 0 end
    return math.max(0, len - 1)
end

--- getCapacity: 获取当前MOD容量上限
-- @param state 游戏状态
-- @return number 容量上限（默认30）
local function getCapacity(state)
    if state and state.progression and state.progression.modCapacity then
        return state.progression.modCapacity
    end
    return 30
end

--- buildSlotData: 构建槽位数据，用于计算MOD容量消耗
-- @param profile 玩家存档数据
-- @param loadout MOD配置数据
-- @param overrideSlot 覆盖的槽位索引
-- @param overrideMod 覆盖的MOD键值
-- @return table 槽位数据表
local function buildSlotData(profile, loadout, overrideSlot, overrideMod)
    local slots = {}
    -- 遍历已装备的MOD
    for idx, modKey in pairs((loadout and loadout.slots) or {}) do
        if modKey then
            slots[idx] = {key = modKey, rank = getModRank(profile, modKey)}
        end
    end
    -- 应用覆盖设置
    if overrideSlot then
        if overrideMod then
            slots[overrideSlot] = {key = overrideMod, rank = getModRank(profile, overrideMod)}
        else
            slots[overrideSlot] = nil
        end
    end
    return slots
end

--- findSlotForMod: 查找指定MOD所在的槽位
-- @param loadout MOD配置数据
-- @param modKey MOD键值
-- @return number|nil 槽位索引
local function findSlotForMod(loadout, modKey)
    if not (loadout and loadout.slots) then return nil end
    for idx, key in pairs(loadout.slots) do
        if key == modKey then return idx end
    end
    return nil
end

--- findFirstEmptySlot: 查找第一个空槽位
-- @param loadout MOD配置数据
-- @return number|nil 槽位索引
local function findFirstEmptySlot(loadout)
    if not loadout then return nil end
    for i = 1, MAX_SLOTS do
        if not loadout.slots[i] then return i end
    end
    return nil
end

--- setMessage: 设置军械库UI的提示消息
-- @param state 游戏状态
-- @param text 消息文本
local function setMessage(state, text)
    local a = state.arsenal
    if not a then return end
    a.message = text
    a.messageTimer = 1.6  -- 消息显示时长
end

--- buildPetList: 构建可选宠物列表并排序
-- @param state 游戏状态
-- @return table 排序后的宠物键值列表
local function buildPetList(state)
    local list = {}
    for key, def in pairs(state.catalog or {}) do
        if def and def.type == 'pet' then
            table.insert(list, key)
        end
    end
    -- 按宠物名称排序
    table.sort(list, function(a, b)
        local da, db = state.catalog[a], state.catalog[b]
        if da and db and da.name and db.name then
            return da.name < db.name
        end
        return a < b
    end)
    return list
end

--- getPetModules: 获取宠物可用的模块列表
-- @param petKey 宠物键值
-- @return table 模块名称列表
local function getPetModules(petKey)
    if petKey == 'pet_magnet' then return {'default', 'pulse'} end
    if petKey == 'pet_corrosive' then return {'default', 'field'} end
    if petKey == 'pet_guardian' then return {'default', 'barrier'} end
    return {'default'}
end

--- cyclePetModule: 切换宠物的模块模式
-- @param profile 玩家存档数据
-- @param petKey 宠物键值
-- @param dir 切换方向（1或-1）
-- @return string 新的模块名称
local function cyclePetModule(profile, petKey, dir)
    if not profile or not petKey then return 'default' end
    profile.petModules = profile.petModules or {}
    local mods = getPetModules(petKey)
    local cur = profile.petModules[petKey] or 'default'
    local idx = 1
    -- 查找当前模块的索引
    for i, m in ipairs(mods) do
        if m == cur then idx = i break end
    end
    dir = dir or 1
    idx = ((idx - 1 + dir) % #mods) + 1
    profile.petModules[petKey] = mods[idx]
    return mods[idx]
end

--- buildClassList: 构建可选职业列表并排序
-- @param state 游戏状态
-- @return table 排序后的职业键值列表
local function buildClassList(state)
    local list = {}
    for key, def in pairs(state.classes or {}) do
        table.insert(list, key)
    end
    table.sort(list)
    return list
end

--- applyPreRunMods: 将军械库配置的 MOD 应用到战斗开始时的实时 MOD 插槽中
-- 该函数会在游戏开始前，将玩家在军械库中配置的MOD应用到实际的游戏状态中
-- @param state 游戏状态
local function applyPreRunMods(state)
    local profile = state.profile
    if not profile then return end
    
    -- 应用武器MOD
    local loadouts = profile.weaponMods or {}
    for weaponKey, lo in pairs(loadouts) do
        local slots = (lo and lo.slots) or {}
        for i = 1, MAX_SLOTS do
            local modKey = slots[i]
            if modKey then
                local rank = getModRank(profile, modKey)
                mods.equipToRunSlot(state, 'weapons', weaponKey, i, modKey, rank)
            end
        end
    end

    -- 应用战甲MOD
    local wfSlots = (profile.warframeMods and profile.warframeMods.slots) or {}
    for i = 1, MAX_SLOTS do
        local modKey = wfSlots[i]
        if modKey then
            local rank = getModRank(profile, modKey)
            mods.equipToRunSlot(state, 'warframe', nil, i, modKey, rank)
        end
    end

    -- 应用伴侣（宠物）MOD
    local compSlots = (profile.companionMods and profile.companionMods.slots) or {}
    for i = 1, MAX_SLOTS do
        local modKey = compSlots[i]
        if modKey then
            local rank = getModRank(profile, modKey)
            mods.equipToRunSlot(state, 'companion', nil, i, modKey, rank)
        end
    end
end

--- arsenal.init: 初始化军械库系统状态
-- 这里的 state.arsenal 存储了 UI 列表所需的索引信息（当前选中的 MOD/武器/宠物等）
-- @param state 游戏状态
function arsenal.init(state)
    local profile = state.profile
    local category = getModCategory(profile)
    
    -- 初始化军械库状态数据
    state.arsenal = {
        modList = buildModList(state, category),      -- MOD列表
        weaponList = buildWeaponList(state),          -- 武器列表
        petList = buildPetList(state),                -- 宠物列表
        classList = buildClassList(state),            -- 职业列表
        idx = 1,                                      -- 当前选中的MOD索引
        weaponIdx = 1,                                -- 当前选中的武器索引
        petIdx = 1,                                   -- 当前选中的宠物索引
        classIdx = 1,                                 -- 当前选中的职业索引
        modCategory = category,                       -- 当前MOD类别
        message = nil,                                -- 提示消息
        messageTimer = 0                              -- 消息计时器
    }
    
    -- 如果MOD列表为空，设置索引为0
    if #state.arsenal.modList == 0 then
        state.arsenal.idx = 0
    end

    -- 同步存档中的上次选择
    if profile then
        profile.modTargetWeapon = profile.modTargetWeapon or 'wand'
        profile.modTargetCategory = profile.modTargetCategory or 'weapons'
        profile.startPetKey = profile.startPetKey or 'pet_magnet'
        profile.petModules = profile.petModules or {}
        
        -- 恢复上次选择的武器
        local list = state.arsenal.weaponList or {}
        local foundWeapon = false
        for i, k in ipairs(list) do
            if k == profile.modTargetWeapon then
                state.arsenal.weaponIdx = i
                foundWeapon = true
                break
            end
        end
        -- 如果上次选择的武器不存在，选择第一个可用武器
        if not foundWeapon and #list > 0 then
            profile.modTargetWeapon = list[1]
            state.arsenal.weaponIdx = 1
        end
    end

    -- 恢复上次选择的宠物
    if profile then
        local petList = state.arsenal.petList or {}
        for i, k in ipairs(petList) do
            if k == profile.startPetKey then
                state.arsenal.petIdx = i
                break
            end
        end
        -- 如果上次选择的宠物不存在，选择第一个可用宠物
        if #petList > 0 and (profile.startPetKey == nil or state.catalog[profile.startPetKey] == nil) then
            profile.startPetKey = petList[1]
            state.arsenal.petIdx = 1
        end
    end
    
    -- 初始化职业选择
    local classList = state.arsenal.classList or {}
    local playerClass = state.player.class or 'volt'
    for i, k in ipairs(classList) do
        if k == playerClass then
            state.arsenal.classIdx = i
            break
        end
    end
    
    -- 若启用了新 UI，则初始化新 UI 屏幕
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.init(state)
    end
end

--- arsenal.show: 显示军械库UI
-- @param state 游戏状态
function arsenal.show(state)
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.rebuild(state)
    end
end

--- arsenal.update: 更新军械库状态
-- @param state 游戏状态
-- @param dt 帧时间间隔
function arsenal.update(state, dt)
    local a = state.arsenal
    if not a then return end
    
    -- 更新消息计时器
    if a.messageTimer and a.messageTimer > 0 then
        a.messageTimer = a.messageTimer - dt
        if a.messageTimer <= 0 then
            a.message = nil
        end
    end
    
    -- 更新新UI（如果启用）
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.update(state, dt)
    end
end

--- arsenal.setModCategory: 设置当前MOD类别
-- @param state 游戏状态
-- @param category MOD类别（weapons/warframe/companion）
function arsenal.setModCategory(state, category)
    local profile = state.profile
    if not profile then return end
    category = category or 'weapons'
    
    -- 验证类别有效性
    if category ~= 'weapons' and category ~= 'warframe' and category ~= 'companion' then
        return
    end
    
    -- 更新存档和状态
    profile.modTargetCategory = category
    if state.arsenal then
        state.arsenal.modCategory = category
        state.arsenal.modList = buildModList(state, category)
        state.arsenal.idx = (#state.arsenal.modList > 0) and 1 or 0
    end
    
    -- 保存存档
    if state.saveProfile then state.saveProfile(profile) end
end

--- arsenal.toggleEquip: 切换MOD的装备状态（装备/卸下）
-- @param state 游戏状态
-- @param modKey MOD键值
function arsenal.toggleEquip(state, modKey)
    local profile = state.profile
    if not profile then return end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    
    -- 检查是否拥有该MOD
    if not isOwned(profile, modKey) then
        setMessage(state, "Locked mod")
        return
    end

    -- 检查MOD与武器是否兼容
    if not isWeaponModCompatible(state, weaponKey, modKey, category) then
        local weaponDef = state.catalog and state.catalog[weaponKey]
        setMessage(state, "Incompatible with " .. tostring(weaponDef and weaponDef.name or weaponKey))
        return
    end

    -- 如果MOD已装备，则卸下
    if isEquipped(loadout, modKey) then
        local slotIdx = findSlotForMod(loadout, modKey)
        if slotIdx then
            loadout.slots[slotIdx] = nil
        end
        local modDef = mods.getCatalog(category)[modKey]
        setMessage(state, "Unequipped " .. ((modDef and modDef.name) or modKey))
    else
        -- 装备MOD
        -- 检查是否有重复的baseId（同类MOD已装备）
        local catalog = mods.getCatalog(category)
        local conflictingModKey = mods.hasDuplicateBaseId(loadout.slots, modKey, catalog)
        if conflictingModKey then
            local conflictDef = catalog[conflictingModKey]
            local conflictName = (conflictDef and conflictDef.name) or conflictingModKey
            setMessage(state, "已装备同类MOD: " .. conflictName)
            return
        end
        
        -- 查找空槽位
        local slotIdx = findFirstEmptySlot(loadout)
        if not slotIdx then
            setMessage(state, "Slots full (" .. MAX_SLOTS .. ")")
            return
        end
        
        -- 检查容量是否足够
        local slots = buildSlotData(profile, loadout, slotIdx, modKey)
        local used = mods.getTotalCost(slots, catalog)
        local cap = getCapacity(state)
        if used > cap then
            setMessage(state, "Capacity full (" .. used .. "/" .. cap .. ")")
            return
        end
        
        -- 装备MOD
        loadout.slots[slotIdx] = modKey
        profile.modRanks[modKey] = profile.modRanks[modKey] or 0
        local modDef = catalog[modKey]
        setMessage(state, "Equipped " .. ((modDef and modDef.name) or modKey))
    end

    -- 保存存档并应用MOD
    state.saveProfile(profile)
    state.applyPersistentMods()
end

--- arsenal.equipToSlot: 将MOD装备到指定槽位
-- @param state 游戏状态
-- @param modKey MOD键值
-- @param slotIndex 槽位索引
-- @return boolean 是否成功装备
function arsenal.equipToSlot(state, modKey, slotIndex)
    local profile = state.profile
    if not profile then return false end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    
    -- 检查是否拥有该MOD
    if not isOwned(profile, modKey) then
        setMessage(state, "Locked mod")
        return false
    end
    
    -- 验证槽位索引
    if slotIndex < 1 or slotIndex > MAX_SLOTS then return false end
    
    -- 检查MOD与武器是否兼容
    if not isWeaponModCompatible(state, weaponKey, modKey, category) then
        local weaponDef = state.catalog and state.catalog[weaponKey]
        setMessage(state, "Incompatible with " .. tostring(weaponDef and weaponDef.name or weaponKey))
        return false
    end

    -- 查找MOD当前所在的槽位
    local existingSlot = findSlotForMod(loadout, modKey)
    if existingSlot == slotIndex then
        return true
    end

    -- 检查是否有重复的baseId（同类MOD已装备，排除当前槽位）
    local catalog = mods.getCatalog(category)
    local conflictingModKey = mods.hasDuplicateBaseId(loadout.slots, modKey, catalog, slotIndex)
    -- 同时排除MOD已在其他槽位的情况（我们正在移动它）
    if conflictingModKey and conflictingModKey ~= modKey then
        local conflictDef = catalog[conflictingModKey]
        local conflictName = (conflictDef and conflictDef.name) or conflictingModKey
        setMessage(state, "已装备同类MOD: " .. conflictName)
        return false
    end

    -- 记录原槽位的MOD
    local oldMod = loadout.slots[slotIndex]
    if existingSlot then
        loadout.slots[existingSlot] = nil
    end

    -- 检查容量是否足够
    local slots = buildSlotData(profile, loadout, slotIndex, modKey)
    local used = mods.getTotalCost(slots, catalog)
    local cap = getCapacity(state)
    if used > cap then
        -- 容量不足，恢复原状态
        if existingSlot then
            loadout.slots[existingSlot] = modKey
        end
        setMessage(state, "Capacity full (" .. used .. "/" .. cap .. ")")
        return false
    end

    -- 装备MOD到指定槽位
    loadout.slots[slotIndex] = modKey
    if oldMod and oldMod == modKey then
        return true
    end

    profile.modRanks[modKey] = profile.modRanks[modKey] or 0
    local modDef = catalog[modKey]
    setMessage(state, "Equipped " .. ((modDef and modDef.name) or modKey))
    state.saveProfile(profile)
    state.applyPersistentMods()
    return true
end

--- arsenal.unequipMod: 卸下指定MOD
-- @param state 游戏状态
-- @param modKey MOD键值
-- @return boolean 是否成功卸下
function arsenal.unequipMod(state, modKey)
    local profile = state.profile
    if not profile then return false end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    
    -- 查找MOD所在的槽位
    local slotIdx = findSlotForMod(loadout, modKey)
    if not slotIdx then return false end
    
    -- 卸下MOD
    loadout.slots[slotIdx] = nil
    local modDef = mods.getCatalog(category)[modKey]
    setMessage(state, "Unequipped " .. ((modDef and modDef.name) or modKey))
    state.saveProfile(profile)
    state.applyPersistentMods()
    return true
end

--- arsenal.adjustRank: 调整MOD等级
-- @param state 游戏状态
-- @param modKey MOD键值
-- @param delta 等级变化量（正数升级，负数降级）
function arsenal.adjustRank(state, modKey, delta)
    local profile = state.profile
    if not profile then return end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    
    -- 只能调整已装备的MOD等级
    if not isEquipped(loadout, modKey) then return end
    
    -- 计算新等级（限制在0到最大等级之间）
    local def = mods.getCatalog(category)[modKey] or {}
    local maxLv = getMaxRank(def)
    local cur = profile.modRanks[modKey] or 0
    cur = math.max(0, math.min(maxLv, cur + delta))
    profile.modRanks[modKey] = cur
    
    -- 保存并应用
    state.saveProfile(profile)
    state.applyPersistentMods()
end

--- arsenal.startRun: 核心函数。正式开始一场战斗/冒险
-- 该函数负责：
-- 1. 切换游戏状态至 'PLAYING'
-- 2. 根据所选模式（Explore/Rooms/Survival）初始化地图与摄像机
-- 3. 根据军械库配置，为玩家配备初始武器
-- 4. 应用赛前安装的所有 MOD 属性（refreshActiveStats）
-- 5. 初始化战甲技能、护盾、能量等资源
-- @param state 游戏状态
-- @param opts 选项表（可包含 runMode 等参数）
function arsenal.startRun(state, opts)
    opts = opts or {}
    
    -- 应用持久化的MOD配置
    state.applyPersistentMods()
    
    -- 初始化运行中的 MOD 系统 (Roguelike 升级部分)
    local modsModule = require('systems.mods')
    modsModule.initRunMods(state)

    -- 设置运行模式
    if opts.runMode then
        state.runMode = opts.runMode
    end

    -- 地图生成策略
    if state.runMode == 'chapter' then
        -- 章节探索模式: 线性地下城
        state.rooms = state.rooms or {}
        state.rooms.enabled = false
        state.mission = nil
        state.campaign = nil
        
        -- 生成章节地图
        local chapter = require('world.chapter')
        local chapterMap = chapter.generate({
            nodeCount = 8,
            mapWidth = 200,
            mapHeight = 80,
        })
        state.chapterMap = chapterMap
        
        -- 创建 world 用于碰撞检测
        state.world = world.new({w = chapterMap.w, h = chapterMap.h})
        state.world.enabled = true
        state.world.tiles = chapterMap.tiles
        state.world.w = chapterMap.w
        state.world.h = chapterMap.h
        state.world.tileSize = chapterMap.tileSize
        state.world.pixelW = chapterMap.pixelW
        state.world.pixelH = chapterMap.pixelH
        
        -- 玩家出生点
        state.player.x = chapterMap.spawnX
        state.player.y = chapterMap.spawnY
        state.world.spawnX = chapterMap.spawnX
        state.world.spawnY = chapterMap.spawnY
        
        -- 初始化小地图
        local hud = require('ui.screens.hud')
        hud.initMinimap(chapterMap)
        
        -- 重置 spawner
        local spawner = require('world.spawner')
        spawner.reset()
        
        -- 预生成敌人 (敌人初始为idle状态，玩家接近时激活)
        spawner.populateMapOnGenerate(state, chapterMap)
    else
        -- 房间模式（默认）
        state.mission = nil
        state.campaign = nil
        
        -- 创建世界：立即生成竞技场，避免渲染时的瞬间空白
        state.world = world.new({w=42, h=32})
        state.world.enabled = true
        if state.world.generateArena then
            state.world:generateArena({w=42, h=32, layout='random'})
        end
        
        -- 重定位玩家到出生点
        if state.world.spawnX and state.world.spawnY then
            state.player.x = state.world.spawnX
            state.player.y = state.world.spawnY
        end
        
        -- 重置房间状态机
        state.rooms = state.rooms or {}
        state.rooms.enabled = true
        state.rooms.phase = 'between_rooms' -- 跳过 init 状态，因为已手动生成
        state.rooms.roomIndex = 0
        state.rooms.timer = 0.1
        state.roomTransitionFade = 1.0 -- 强制一个淡入效果
    end

    -- 武器发放逻辑 (Warframe 风格: 1个远程 + 1个近战)
    if not state.inventory.weaponSlots.ranged and not state.inventory.weaponSlots.melee then
        local defaultLoadout = {
            ranged = 'braton',      
            melee = 'skana' 
        }

        -- 应用军械库选中的武器作为初始装备之一
        local selectedKey = state.profile and state.profile.modTargetWeapon
        local startSlot = 'ranged'
        
        if selectedKey then
            local def = state.catalog[selectedKey]
            if def and def.type == 'weapon' then
                local slot = def.slot or 'ranged'
                -- 简单的槽位推导逻辑，如果 catalog 里没写 slot 字段
                if def.slot == 'melee' or def.tags and tagsMatch(def.tags, {'melee'}) then
                    slot = 'melee'
                end
                
                defaultLoadout[slot] = selectedKey
                startSlot = slot
            end
        end
        
        -- 正式装备到槽位
        for slot, weaponKey in pairs(defaultLoadout) do
            local def = state.catalog and state.catalog[weaponKey]
            if def and def.type == 'weapon' and not def.evolvedOnly and not def.hidden then
                weapons.equipToSlot(state, slot, weaponKey)
            end
        end
        
        -- 默认拿在手里的槽位
        state.inventory.activeSlot = startSlot
    end

    -- 生成初始宠物（如果未跳过）
    if not opts.skipStartingPet then
        pets.spawnStartingPet(state)
    end

    -- 应用 MOD 属性
    applyPreRunMods(state)
    
    -- 根据 MOD/被动 重新计算玩家属性，并回满资源
    mods.refreshActiveStats(state)
    state.player.hp = state.player.maxHp or state.player.hp
    state.player.shield = state.player.maxShield or state.player.shield
    state.player.energy = state.player.maxEnergy or state.player.energy
    
    -- 重置技能冷却
    state.player.ability = state.player.ability or {cooldown = 0, timer = 0}
    state.player.ability.timer = 0
    
    -- 切换游戏状态
    state.gameState = 'PLAYING'
    
    -- 切换 UI 状态至战姿 HUD
    if arsenal.useNewUI then
        local hud = require('ui.screens.hud')
        hud.init(state)
    end
end

--- arsenal.keypressed: 处理军械库界面的键盘输入
-- @param state 游戏状态
-- @param key 按下的键
-- @return boolean 是否处理了该按键
function arsenal.keypressed(state, key)
    local a = state.arsenal
    if not a then return false end
    
    -- 如果启用了新UI，优先委托给新UI处理
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        if screen.keypressed(state, key) then
            return true
        end
    end

    -- P/O: 切换宠物选择
    if key == 'p' or key == 'o' then
        local list = a.petList or {}
        if #list > 0 and state.profile then
            local dir = (key == 'p') and 1 or -1
            a.petIdx = ((a.petIdx - 1 + dir) % #list) + 1
            local petKey = list[a.petIdx]
            state.profile.startPetKey = petKey
            local petName = (state.catalog[petKey] and state.catalog[petKey].name) or petKey
            setMessage(state, "Pet: " .. tostring(petName))
            if state.saveProfile then state.saveProfile(state.profile) end
            -- 重建UI以反映更改
            if arsenal.useNewUI then
                local screen = getArsenalScreen()
                screen.rebuild(state)
            end
        end
        return true
    end

    -- 1/2/3: 切换MOD类别（战甲/武器/伴侣）
    if key == '1' or key == '2' or key == '3' then
        local category = (key == '1' and 'warframe') or (key == '2' and 'weapons') or 'companion'
        arsenal.setModCategory(state, category)
        local label = (category == 'warframe' and "Warframe") or (category == 'weapons' and "Weapon") or "Companion"
        setMessage(state, "Mod Category: " .. label)
        if arsenal.useNewUI then
            local screen = getArsenalScreen()
            screen.rebuild(state)
        end
        return true
    end

    -- Tab/Backspace: 切换武器选择
    if key == 'tab' or key == 'backspace' then
        local list = a.weaponList or {}
        if #list > 0 and state.profile then
            local dir = (key == 'tab') and 1 or -1
            a.weaponIdx = ((a.weaponIdx - 1 + dir) % #list) + 1
            local weaponKey = list[a.weaponIdx]
            state.profile.modTargetWeapon = weaponKey
            setMessage(state, "Weapon: " .. tostring((state.catalog[weaponKey] and state.catalog[weaponKey].name) or weaponKey))
            if state.saveProfile then state.saveProfile(state.profile) end
            -- 重建UI以反映更改
            if arsenal.useNewUI then
                local screen = getArsenalScreen()
                screen.rebuild(state)
            end
        end
        return true
    end
    
    -- C: 切换职业选择
    if key == 'c' then
        local list = a.classList or {}
        if #list > 0 then
            a.classIdx = (a.classIdx % #list) + 1
            local classKey = list[a.classIdx]
            state.player.class = classKey
            local classDef = state.classes and state.classes[classKey]
            local className = (classDef and classDef.name) or classKey
            setMessage(state, "Class: " .. tostring(className))
            -- 刷新属性和资源
            mods.refreshActiveStats(state)
            state.player.hp = state.player.maxHp or state.player.hp
            state.player.shield = state.player.maxShield or state.player.shield
            state.player.energy = state.player.maxEnergy or state.player.energy
            -- 重建UI以反映更改
            if arsenal.useNewUI then
                local screen = getArsenalScreen()
                screen.rebuild(state)
            end
        end
        return true
    end
    
    -- MOD列表导航和操作
    local list = a.modList or {}
    local count = #list
    
    -- 上/下箭头: 选择MOD
    if key == 'up' then
        if count > 0 then
            a.idx = ((a.idx - 2) % count) + 1
        end
        return true
    elseif key == 'down' then
        if count > 0 then
            a.idx = (a.idx % count) + 1
        end
        return true
    -- E: 装备/卸下当前选中的MOD
    elseif key == 'e' then
        local modKey = list[a.idx]
        if modKey then arsenal.toggleEquip(state, modKey) end
        return true
    -- 左箭头: 降低MOD等级
    elseif key == 'left' then
        local modKey = list[a.idx]
        if modKey then arsenal.adjustRank(state, modKey, -1) end
        return true
    -- 右箭头: 提升MOD等级
    elseif key == 'right' then
        local modKey = list[a.idx]
        if modKey then arsenal.adjustRank(state, modKey, 1) end
        return true
    -- Enter: 开始游戏（房间模式）
    elseif key == 'return' or key == 'kpenter' then
        arsenal.startRun(state)
        return true
    -- F: 开始游戏（章节探索模式）
    elseif key == 'f' then
        arsenal.startRun(state, {runMode = 'chapter'})
        return true
    -- R: 开始游戏（房间模式）
    elseif key == 'r' then
        arsenal.startRun(state, {runMode = 'rooms'})
        return true
    end

    return false
end

--- arsenal.draw: 绘制军械库界面
-- @param state 游戏状态
function arsenal.draw(state)
    -- 如果启用了新UI，使用新UI绘制
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.draw(state)
        return
    end
    
    -- 以下是旧版绘制代码（已弃用）
    local a = state.arsenal or {}
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- 绘制半透明背景
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle('fill', 0, 0, w, h)

    -- 绘制标题
    love.graphics.setFont(state.titleFont or love.graphics.getFont())
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("ARSENAL", 0, 40, w, "center")

    love.graphics.setFont(state.font or love.graphics.getFont())

    local leftX, topY = 80, 120
    local lineH = 24
    local list = a.modList or {}

    -- 获取当前选中的武器和宠物信息
    local weaponKey = (state.profile and state.profile.modTargetWeapon) or 'braton'
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local weaponName = (weaponDef and weaponDef.name) or weaponKey
    local category = getModCategory(state.profile)
    local loadout = ensureCategoryLoadout(state.profile, category, weaponKey) or {}

    local petKey = (state.profile and state.profile.startPetKey) or 'pet_magnet'
    local petDef = state.catalog and state.catalog[petKey]
    local petName = (petDef and petDef.name) or petKey

    -- 绘制顶部信息栏
    love.graphics.setColor(1, 1, 1)
    local credits = (state.profile and state.profile.currency) or 0
    love.graphics.print("Available Mods   Credits: " .. tostring(credits), leftX, topY - 30)
    love.graphics.setColor(0.85, 0.85, 0.95)
    love.graphics.print("Weapon: " .. tostring(weaponName) .. "  (Tab/Backspace)", leftX, topY - 54)
    love.graphics.setColor(0.85, 0.95, 0.9)
    love.graphics.print("Pet: " .. tostring(petName) .. "  (P/O)", leftX, topY - 42)
    
    -- 绘制职业信息
    local classKey = state.player.class or 'volt'
    local classDef = state.classes and state.classes[classKey]
    local className = (classDef and classDef.name) or classKey
    love.graphics.setColor(0.95, 0.85, 0.75)
    love.graphics.print("Class: " .. tostring(className) .. "  (C)", leftX, topY - 66)
    

    -- 绘制MOD列表
    local modCatalog = mods.getCatalog(category) or {}
    for i, key in ipairs(list) do
        local def = modCatalog[key]
        local name = (def and def.name) or key
        local owned = isOwned(state.profile, key)
        local equipped = isEquipped(loadout, key)
        local rank = (state.profile and state.profile.modRanks and state.profile.modRanks[key]) or 0
        local maxLv = getMaxRank(def)
        local y = topY + (i - 1) * lineH

        if i == a.idx then
            love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
            love.graphics.rectangle('fill', leftX - 10, y - 2, 320, lineH)
        end

        if owned then
            love.graphics.setColor(1, 1, 1)
            local tag = equipped and string.format("[E] R%d/%d ", rank, maxLv) or "    "
            love.graphics.print(tag .. name, leftX, y)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 0.9)
            love.graphics.print("[LOCK] " .. name, leftX, y)
        end
    end

    -- 绘制已装备的MOD列表（右侧）
    local rightX = w * 0.55
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("Equipped (%d/%d)", countEquipped(loadout), MAX_SLOTS), rightX, topY - 30)

    local eqY = topY
    for i = 1, MAX_SLOTS do
        local key = loadout and loadout.slots and loadout.slots[i]
        if key then
            local def = modCatalog[key]
            local name = (def and def.name) or key
            local rank = (state.profile.modRanks and state.profile.modRanks[key]) or 0
            local maxLv = getMaxRank(def)
            love.graphics.print(string.format("%s  R%d/%d", name, rank, maxLv), rightX, eqY)
            eqY = eqY + lineH
        end
    end
    if eqY == topY then
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.print("None", rightX, eqY)
    end

    -- 绘制当前选中MOD的描述
    local selKey = list[a.idx]
    if selKey then
        local def = modCatalog[selKey]
        if def and def.desc then
            love.graphics.setColor(0.75, 0.75, 0.75)
            love.graphics.printf(def.desc, leftX, h - 120, w - leftX * 2, "left")
        end
    end

    -- 绘制操作提示
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.printf("E: equip   1/2/3: mod type   Tab: weapon   P: pet   C: class   F: explore   Enter: start(rooms)", 0, h - 60, w, "center")

    -- 绘制提示消息
    if a.message then
        love.graphics.setColor(1, 0.8, 0.3)
        love.graphics.printf(a.message, 0, h - 90, w, "center")
    end
end

return arsenal
