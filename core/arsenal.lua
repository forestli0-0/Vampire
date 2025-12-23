local weapons = require('gameplay.weapons')
local pets = require('gameplay.pets')
local world = require('world.world')
local mission = require('world.mission')
local campaign = require('world.campaign')
local mods = require('systems.mods')

-- 军械库 (Arsenal) 模块
-- 负责处理玩家在出战前的武器选择、MOD 安装、战甲切换以及宠物配置。
-- 它还负责将持久化的存档数据转化为每场 Run 的初始状态。
local arsenal = {}

-- New UI screen (lazy loaded to avoid circular deps)
local arsenalScreen = nil
local function getArsenalScreen()
    if not arsenalScreen then
        arsenalScreen = require('ui.screens.arsenal_screen')
    end
    return arsenalScreen
end

-- Flag to use new UI (set to true to enable)
arsenal.useNewUI = true

local MAX_SLOTS = 8

--- tagsMatch: 检查武器标签是否与目标标签匹配。
local function tagsMatch(weaponTags, targetTags)
    if not weaponTags or not targetTags then return false end
    for _, tag in ipairs(targetTags) do
        for _, wTag in ipairs(weaponTags) do
            if tag == wTag then return true end
        end
    end
    return false
end

--- buildModList: 根据所属类别构建可选的 MOD 列表并排序。
local function buildModList(state, category)
    local list = {}
    local catalog = mods.getCatalog(category or 'weapons') or {}
    for key, _ in pairs(catalog) do
        table.insert(list, key)
    end
    table.sort(list, function(a, b)
        local catalog = mods.getCatalog(category or 'weapons') or {}
        local da, db = catalog[a], catalog[b]
        if da and db and da.name and db.name then return da.name < db.name end
        return a < b
    end)
    return list
end

local function buildWeaponList(state)
    local list = {}
    for key, def in pairs(state.catalog or {}) do
        if def and def.type == 'weapon' and not def.evolvedOnly then
            table.insert(list, key)
        end
    end
    table.sort(list, function(a, b)
        local da, db = state.catalog[a], state.catalog[b]
        if da and db and da.name and db.name then
            return da.name < db.name
        end
        return a < b
    end)
    return list
end

--- ensureWeaponLoadout: 确保存档中存在该武器的配置槽位。
local function ensureWeaponLoadout(profile, weaponKey)
    if not profile then return nil end
    profile.weaponMods = profile.weaponMods or {}
    profile.weaponMods[weaponKey] = profile.weaponMods[weaponKey] or {slots = {}}
    local lo = profile.weaponMods[weaponKey]
    lo.slots = lo.slots or {}
    return lo
end

local function ensureCategoryLoadout(profile, category, weaponKey)
    if not profile then return nil end
    if category == 'weapons' then
        return ensureWeaponLoadout(profile, weaponKey)
    elseif category == 'warframe' then
        profile.warframeMods = profile.warframeMods or {slots = {}}
        profile.warframeMods.slots = profile.warframeMods.slots or {}
        return profile.warframeMods
    elseif category == 'companion' then
        profile.companionMods = profile.companionMods or {slots = {}}
        profile.companionMods.slots = profile.companionMods.slots or {}
        return profile.companionMods
    end
    return nil
end

local function countEquipped(loadout)
    local n = 0
    for _, v in pairs((loadout and loadout.slots) or {}) do
        if v then n = n + 1 end
    end
    return n
end

local function isEquipped(loadout, key)
    if not (loadout and loadout.slots) then return false end
    for _, k in pairs(loadout.slots) do
        if k == key then return true end
    end
    return false
end

local function isOwned(profile, key)
    return profile and profile.ownedMods and profile.ownedMods[key]
end

local function getModCategory(profile)
    return (profile and profile.modTargetCategory) or 'weapons'
end

local function getWeaponClass(state, weaponKey)
    local def = state and state.catalog and state.catalog[weaponKey]
    if not def then return nil end
    if def.slotType == 'melee' or def.slot == 'melee' then return 'melee' end
    if def.tags then
        for _, tag in ipairs(def.tags) do
            if tag == 'melee' then return 'melee' end
        end
    end
    return 'ranged'
end

--- isWeaponModCompatible: 检查特定 MOD 是否能安装在当前武器上。
-- 例如：近战 MOD 不能装在远程武器上。
local function isWeaponModCompatible(state, weaponKey, modKey, category)
    if category ~= 'weapons' then return true end
    local catalog = mods.getCatalog(category) or {}
    local def = catalog[modKey]
    if not def or not def.weaponType then return true end
    local weaponClass = getWeaponClass(state, weaponKey)
    if not weaponClass then return false end
    return def.weaponType == weaponClass
end

local function getModRank(profile, modKey)
    local r = (profile and profile.modRanks and profile.modRanks[modKey]) or 0
    r = tonumber(r) or 0
    return math.max(0, math.floor(r))
end

local function getMaxRank(def)
    local len = 0
    if def and type(def.cost) == 'table' then len = #def.cost end
    if len == 0 and def and type(def.value) == 'table' then len = #def.value end
    if len == 0 then return 0 end
    return math.max(0, len - 1)
end

local function getCapacity(state)
    if state and state.progression and state.progression.modCapacity then
        return state.progression.modCapacity
    end
    return 30
end

local function buildSlotData(profile, loadout, overrideSlot, overrideMod)
    local slots = {}
    for idx, modKey in pairs((loadout and loadout.slots) or {}) do
        if modKey then
            slots[idx] = {key = modKey, rank = getModRank(profile, modKey)}
        end
    end
    if overrideSlot then
        if overrideMod then
            slots[overrideSlot] = {key = overrideMod, rank = getModRank(profile, overrideMod)}
        else
            slots[overrideSlot] = nil
        end
    end
    return slots
end

local function findSlotForMod(loadout, modKey)
    if not (loadout and loadout.slots) then return nil end
    for idx, key in pairs(loadout.slots) do
        if key == modKey then return idx end
    end
    return nil
end

local function findFirstEmptySlot(loadout)
    if not loadout then return nil end
    for i = 1, MAX_SLOTS do
        if not loadout.slots[i] then return i end
    end
    return nil
end

local function setMessage(state, text)
    local a = state.arsenal
    if not a then return end
    a.message = text
    a.messageTimer = 1.6
end

local function buildPetList(state)
    local list = {}
    for key, def in pairs(state.catalog or {}) do
        if def and def.type == 'pet' then
            table.insert(list, key)
        end
    end
    table.sort(list, function(a, b)
        local da, db = state.catalog[a], state.catalog[b]
        if da and db and da.name and db.name then
            return da.name < db.name
        end
        return a < b
    end)
    return list
end

local function getPetModules(petKey)
    if petKey == 'pet_magnet' then return {'default', 'pulse'} end
    if petKey == 'pet_corrosive' then return {'default', 'field'} end
    if petKey == 'pet_guardian' then return {'default', 'barrier'} end
    return {'default'}
end

local function cyclePetModule(profile, petKey, dir)
    if not profile or not petKey then return 'default' end
    profile.petModules = profile.petModules or {}
    local mods = getPetModules(petKey)
    local cur = profile.petModules[petKey] or 'default'
    local idx = 1
    for i, m in ipairs(mods) do
        if m == cur then idx = i break end
    end
    dir = dir or 1
    idx = ((idx - 1 + dir) % #mods) + 1
    profile.petModules[petKey] = mods[idx]
    return mods[idx]
end

local function buildClassList(state)
    local list = {}
    for key, def in pairs(state.classes or {}) do
        table.insert(list, key)
    end
    table.sort(list)
    return list
end

--- applyPreRunMods: 将军械库配置的 MOD 应用到战斗开始时的实时 MOD 插槽中。
local function applyPreRunMods(state)
    local profile = state.profile
    if not profile then return end
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

    local wfSlots = (profile.warframeMods and profile.warframeMods.slots) or {}
    for i = 1, MAX_SLOTS do
        local modKey = wfSlots[i]
        if modKey then
            local rank = getModRank(profile, modKey)
            mods.equipToRunSlot(state, 'warframe', nil, i, modKey, rank)
        end
    end

    local compSlots = (profile.companionMods and profile.companionMods.slots) or {}
    for i = 1, MAX_SLOTS do
        local modKey = compSlots[i]
        if modKey then
            local rank = getModRank(profile, modKey)
            mods.equipToRunSlot(state, 'companion', nil, i, modKey, rank)
        end
    end
end

--- arsenal.init: 初始化军械库系统状态。
-- 这里的 state.arsenal 存储了 UI 列表所需的索引信息（当前选中的 MOD/武器/宠物等）。
function arsenal.init(state)
    local profile = state.profile
    local category = getModCategory(profile)
    state.arsenal = {
        modList = buildModList(state, category),
        weaponList = buildWeaponList(state),
        petList = buildPetList(state),
        classList = buildClassList(state),
        idx = 1,
        weaponIdx = 1,
        petIdx = 1,
        classIdx = 1,
        modCategory = category,
        message = nil,
        messageTimer = 0
    }
    if #state.arsenal.modList == 0 then
        state.arsenal.idx = 0
    end

    -- 同步存档中的上次选择
    if profile then
        profile.modTargetWeapon = profile.modTargetWeapon or 'wand'
        profile.modTargetCategory = profile.modTargetCategory or 'weapons'
        profile.startPetKey = profile.startPetKey or 'pet_magnet'
        profile.petModules = profile.petModules or {}
        local list = state.arsenal.weaponList or {}
        local foundWeapon = false
        for i, k in ipairs(list) do
            if k == profile.modTargetWeapon then
                state.arsenal.weaponIdx = i
                foundWeapon = true
                break
            end
        end
        if not foundWeapon and #list > 0 then
            profile.modTargetWeapon = list[1]
            state.arsenal.weaponIdx = 1
        end
    end

    if profile then
        local petList = state.arsenal.petList or {}
        for i, k in ipairs(petList) do
            if k == profile.startPetKey then
                state.arsenal.petIdx = i
                break
            end
        end
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

function arsenal.show(state)
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.rebuild(state)
    end
end

function arsenal.update(state, dt)
    local a = state.arsenal
    if not a then return end
    if a.messageTimer and a.messageTimer > 0 then
        a.messageTimer = a.messageTimer - dt
        if a.messageTimer <= 0 then
            a.message = nil
        end
    end
    
    -- Update new UI if enabled
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.update(state, dt)
    end
end

function arsenal.setModCategory(state, category)
    local profile = state.profile
    if not profile then return end
    category = category or 'weapons'
    if category ~= 'weapons' and category ~= 'warframe' and category ~= 'companion' then
        return
    end
    profile.modTargetCategory = category
    if state.arsenal then
        state.arsenal.modCategory = category
        state.arsenal.modList = buildModList(state, category)
        state.arsenal.idx = (#state.arsenal.modList > 0) and 1 or 0
    end
    if state.saveProfile then state.saveProfile(profile) end
end

function arsenal.toggleEquip(state, modKey)
    local profile = state.profile
    if not profile then return end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    if not isOwned(profile, modKey) then
        setMessage(state, "Locked mod")
        return
    end

    if not isWeaponModCompatible(state, weaponKey, modKey, category) then
        local weaponDef = state.catalog and state.catalog[weaponKey]
        setMessage(state, "Incompatible with " .. tostring(weaponDef and weaponDef.name or weaponKey))
        return
    end

    if isEquipped(loadout, modKey) then
        local slotIdx = findSlotForMod(loadout, modKey)
        if slotIdx then
            loadout.slots[slotIdx] = nil
        end
        local modDef = mods.getCatalog(category)[modKey]
        setMessage(state, "Unequipped " .. ((modDef and modDef.name) or modKey))
    else
        -- Check for duplicate baseId (same mod or variant already equipped)
        local catalog = mods.getCatalog(category)
        local conflictingModKey = mods.hasDuplicateBaseId(loadout.slots, modKey, catalog)
        if conflictingModKey then
            local conflictDef = catalog[conflictingModKey]
            local conflictName = (conflictDef and conflictDef.name) or conflictingModKey
            setMessage(state, "已装备同类MOD: " .. conflictName)
            return
        end
        
        local slotIdx = findFirstEmptySlot(loadout)
        if not slotIdx then
            setMessage(state, "Slots full (" .. MAX_SLOTS .. ")")
            return
        end
        local slots = buildSlotData(profile, loadout, slotIdx, modKey)
        local used = mods.getTotalCost(slots, catalog)
        local cap = getCapacity(state)
        if used > cap then
            setMessage(state, "Capacity full (" .. used .. "/" .. cap .. ")")
            return
        end
        loadout.slots[slotIdx] = modKey
        profile.modRanks[modKey] = profile.modRanks[modKey] or 0
        local modDef = catalog[modKey]
        setMessage(state, "Equipped " .. ((modDef and modDef.name) or modKey))
    end

    state.saveProfile(profile)
    state.applyPersistentMods()
end

function arsenal.equipToSlot(state, modKey, slotIndex)
    local profile = state.profile
    if not profile then return false end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    if not isOwned(profile, modKey) then
        setMessage(state, "Locked mod")
        return false
    end
    if slotIndex < 1 or slotIndex > MAX_SLOTS then return false end
    if not isWeaponModCompatible(state, weaponKey, modKey, category) then
        local weaponDef = state.catalog and state.catalog[weaponKey]
        setMessage(state, "Incompatible with " .. tostring(weaponDef and weaponDef.name or weaponKey))
        return false
    end

    local existingSlot = findSlotForMod(loadout, modKey)
    if existingSlot == slotIndex then
        return true
    end

    -- Check for duplicate baseId (same mod or variant already equipped, excluding current slot)
    local catalog = mods.getCatalog(category)
    local conflictingModKey = mods.hasDuplicateBaseId(loadout.slots, modKey, catalog, slotIndex)
    -- Also exclude if the mod is already in another slot (we're moving it)
    if conflictingModKey and conflictingModKey ~= modKey then
        local conflictDef = catalog[conflictingModKey]
        local conflictName = (conflictDef and conflictDef.name) or conflictingModKey
        setMessage(state, "已装备同类MOD: " .. conflictName)
        return false
    end

    local oldMod = loadout.slots[slotIndex]
    if existingSlot then
        loadout.slots[existingSlot] = nil
    end

    local slots = buildSlotData(profile, loadout, slotIndex, modKey)
    local used = mods.getTotalCost(slots, catalog)
    local cap = getCapacity(state)
    if used > cap then
        if existingSlot then
            loadout.slots[existingSlot] = modKey
        end
        setMessage(state, "Capacity full (" .. used .. "/" .. cap .. ")")
        return false
    end

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

function arsenal.unequipMod(state, modKey)
    local profile = state.profile
    if not profile then return false end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    local slotIdx = findSlotForMod(loadout, modKey)
    if not slotIdx then return false end
    loadout.slots[slotIdx] = nil
    local modDef = mods.getCatalog(category)[modKey]
    setMessage(state, "Unequipped " .. ((modDef and modDef.name) or modKey))
    state.saveProfile(profile)
    state.applyPersistentMods()
    return true
end

function arsenal.adjustRank(state, modKey, delta)
    local profile = state.profile
    if not profile then return end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local category = getModCategory(profile)
    local loadout = ensureCategoryLoadout(profile, category, weaponKey)
    if not isEquipped(loadout, modKey) then return end
    local def = mods.getCatalog(category)[modKey] or {}
    local maxLv = getMaxRank(def)
    local cur = profile.modRanks[modKey] or 0
    cur = math.max(0, math.min(maxLv, cur + delta))
    profile.modRanks[modKey] = cur
    state.saveProfile(profile)
    state.applyPersistentMods()
end

--- arsenal.startRun: 核心函数。正式开始一场战斗/冒险。
-- 该函数负责：
-- 1. 切换游戏状态至 'PLAYING'。
-- 2. 根据所选模式（Explore/Rooms/Survival）初始化地图与摄像机。
-- 3. 根据军械库配置，为玩家配备初始武器。
-- 4. 应用赛前安装的所有 MOD 属性（refreshActiveStats）。
-- 5. 初始化战甲技能、护盾、能量等资源。
function arsenal.startRun(state, opts)
    opts = opts or {}
    state.applyPersistentMods()
    
    -- 初始化运行中的 MOD 系统 (Roguelike 升级部分)
    local modsModule = require('systems.mods')
    modsModule.initRunMods(state)

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
        state.mission = nil
        state.campaign = nil
        
        -- 创建世界：立即生成竞技场竞技场，避免渲染时的瞬间空白。
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
        state.rooms.phase = 'between_rooms' -- 跳过 init 状态，因为已手动生成。
        state.rooms.roomIndex = 0
        state.rooms.timer = 0.1
        state.roomTransitionFade = 1.0 -- 强制一个淡入效果
    end

    -- 武器发放逻辑 (Warframe 风格: 1个远程 + 1个近战)
    if not state.inventory.weaponSlots.ranged and not state.inventory.weaponSlots.melee then
        local defaultLoadout = {
            ranged = 'wand',      
            melee = 'heavy_hammer' 
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
    
    state.gameState = 'PLAYING'
    
    -- 切换 UI 状态至战姿 HUD
    if arsenal.useNewUI then
        local hud = require('ui.screens.hud')
        hud.init(state)
    end
end

function arsenal.keypressed(state, key)
    local a = state.arsenal
    if not a then return false end
    
    -- Delegate to new UI first if enabled
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        if screen.keypressed(state, key) then
            return true
        end
    end

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
            -- Rebuild UI to reflect change
            if arsenal.useNewUI then
                local screen = getArsenalScreen()
                screen.rebuild(state)
            end
        end
        return true
    end

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

    if key == 'tab' or key == 'backspace' then
        local list = a.weaponList or {}
        if #list > 0 and state.profile then
            local dir = (key == 'tab') and 1 or -1
            a.weaponIdx = ((a.weaponIdx - 1 + dir) % #list) + 1
            local weaponKey = list[a.weaponIdx]
            state.profile.modTargetWeapon = weaponKey
            setMessage(state, "Weapon: " .. tostring((state.catalog[weaponKey] and state.catalog[weaponKey].name) or weaponKey))
            if state.saveProfile then state.saveProfile(state.profile) end
            -- Rebuild UI to reflect change
            if arsenal.useNewUI then
                local screen = getArsenalScreen()
                screen.rebuild(state)
            end
        end
        return true
    end
    
    -- Class selection (C key)
    if key == 'c' then
        local list = a.classList or {}
        if #list > 0 then
            a.classIdx = (a.classIdx % #list) + 1
            local classKey = list[a.classIdx]
            state.player.class = classKey
            local classDef = state.classes and state.classes[classKey]
            local className = (classDef and classDef.name) or classKey
            setMessage(state, "Class: " .. tostring(className))
            mods.refreshActiveStats(state)
            state.player.hp = state.player.maxHp or state.player.hp
            state.player.shield = state.player.maxShield or state.player.shield
            state.player.energy = state.player.maxEnergy or state.player.energy
            -- Rebuild UI to reflect change
            if arsenal.useNewUI then
                local screen = getArsenalScreen()
                screen.rebuild(state)
            end
        end
        return true
    end
    
    local list = a.modList or {}
    local count = #list
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
    elseif key == 'e' then
        local modKey = list[a.idx]
        if modKey then arsenal.toggleEquip(state, modKey) end
        return true
    elseif key == 'left' then
        local modKey = list[a.idx]
        if modKey then arsenal.adjustRank(state, modKey, -1) end
        return true
    elseif key == 'right' then
        local modKey = list[a.idx]
        if modKey then arsenal.adjustRank(state, modKey, 1) end
        return true
    elseif key == 'return' or key == 'kpenter' then
        arsenal.startRun(state)
        return true
    elseif key == 'f' then
        -- F now starts Chapter mode (handled by new UI)
        arsenal.startRun(state, {runMode = 'chapter'})
        return true
    elseif key == 'r' then
        arsenal.startRun(state, {runMode = 'rooms'})
        return true
    end

    return false
end

function arsenal.draw(state)
    -- Use new UI if enabled
    if arsenal.useNewUI then
        local screen = getArsenalScreen()
        screen.draw(state)
        return
    end
    
    -- Legacy draw code below
    local a = state.arsenal or {}
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle('fill', 0, 0, w, h)

    love.graphics.setFont(state.titleFont or love.graphics.getFont())
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("ARSENAL", 0, 40, w, "center")

    love.graphics.setFont(state.font or love.graphics.getFont())

    local leftX, topY = 80, 120
    local lineH = 24
    local list = a.modList or {}

    local weaponKey = (state.profile and state.profile.modTargetWeapon) or 'wand'
    local weaponDef = state.catalog and state.catalog[weaponKey]
    local weaponName = (weaponDef and weaponDef.name) or weaponKey
    local category = getModCategory(state.profile)
    local loadout = ensureCategoryLoadout(state.profile, category, weaponKey) or {}

    local petKey = (state.profile and state.profile.startPetKey) or 'pet_magnet'
    local petDef = state.catalog and state.catalog[petKey]
    local petName = (petDef and petDef.name) or petKey

    love.graphics.setColor(1, 1, 1)
    local credits = (state.profile and state.profile.currency) or 0
    love.graphics.print("Available Mods   Credits: " .. tostring(credits), leftX, topY - 30)
    love.graphics.setColor(0.85, 0.85, 0.95)
    love.graphics.print("Weapon: " .. tostring(weaponName) .. "  (Tab/Backspace)", leftX, topY - 54)
    love.graphics.setColor(0.85, 0.95, 0.9)
    love.graphics.print("Pet: " .. tostring(petName) .. "  (P/O)", leftX, topY - 42)
    
    -- Class display
    local classKey = state.player.class or 'volt'
    local classDef = state.classes and state.classes[classKey]
    local className = (classDef and classDef.name) or classKey
    love.graphics.setColor(0.95, 0.85, 0.75)
    love.graphics.print("Class: " .. tostring(className) .. "  (C)", leftX, topY - 66)
    

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

    local selKey = list[a.idx]
    if selKey then
        local def = modCatalog[selKey]
        if def and def.desc then
            love.graphics.setColor(0.75, 0.75, 0.75)
            love.graphics.printf(def.desc, leftX, h - 120, w - leftX * 2, "left")
        end
    end

    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.printf("E: equip   1/2/3: mod type   Tab: weapon   P: pet   C: class   F: explore   Enter: start(rooms)", 0, h - 60, w, "center")

    if a.message then
        love.graphics.setColor(1, 0.8, 0.3)
        love.graphics.printf(a.message, 0, h - 90, w, "center")
    end
end

return arsenal
