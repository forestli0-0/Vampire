local weapons = require('weapons')
local pets = require('pets')
local world = require('world')
local mission = require('mission')

local arsenal = {}

local MAX_SLOTS = 4

local function tagsMatch(weaponTags, targetTags)
    if not weaponTags or not targetTags then return false end
    for _, tag in ipairs(targetTags) do
        for _, wTag in ipairs(weaponTags) do
            if tag == wTag then return true end
        end
    end
    return false
end

local function buildModList(state)
    local list = {}
    for key, def in pairs(state.catalog or {}) do
        if def.type == 'mod' then
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

local function ensureWeaponLoadout(profile, weaponKey)
    if not profile then return nil end
    profile.weaponMods = profile.weaponMods or {}
    profile.weaponMods[weaponKey] = profile.weaponMods[weaponKey] or {equippedMods = {}, modOrder = {}}
    local lo = profile.weaponMods[weaponKey]
    lo.equippedMods = lo.equippedMods or {}
    lo.modOrder = lo.modOrder or {}
    return lo
end

local function countEquipped(loadout)
    local n = 0
    for _, v in pairs((loadout and loadout.equippedMods) or {}) do
        if v then n = n + 1 end
    end
    return n
end

local function isEquipped(loadout, key)
    return loadout and loadout.equippedMods and loadout.equippedMods[key]
end

local function isOwned(profile, key)
    return profile and profile.ownedMods and profile.ownedMods[key]
end

local function ensureOrder(loadout, key)
    if not loadout then return end
    loadout.modOrder = loadout.modOrder or {}
    for _, k in ipairs(loadout.modOrder) do
        if k == key then return end
    end
    table.insert(loadout.modOrder, key)
end

local function removeOrder(loadout, key)
    local order = (loadout and loadout.modOrder) or {}
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) end
    end
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

function arsenal.init(state)
    state.arsenal = {
        modList = buildModList(state),
        weaponList = buildWeaponList(state),
        petList = buildPetList(state),
        idx = 1,
        weaponIdx = 1,
        petIdx = 1,
        message = nil,
        messageTimer = 0
    }
    if #state.arsenal.modList == 0 then
        state.arsenal.idx = 0
    end

    local profile = state.profile
    if profile then
        profile.modTargetWeapon = profile.modTargetWeapon or 'wand'
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
end

function arsenal.toggleEquip(state, modKey)
    local profile = state.profile
    if not profile then return end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local loadout = ensureWeaponLoadout(profile, weaponKey)
    if not isOwned(profile, modKey) then
        setMessage(state, "Locked mod")
        return
    end

    local weaponDef = state.catalog and state.catalog[weaponKey]
    local modDef = state.catalog and state.catalog[modKey]
    local weaponTags = weaponDef and weaponDef.tags or {}
    local targetTags = modDef and modDef.targetTags or nil
    if targetTags and not tagsMatch(weaponTags, targetTags) then
        setMessage(state, "Incompatible with " .. tostring(weaponDef and weaponDef.name or weaponKey))
        return
    end

    loadout.equippedMods = loadout.equippedMods or {}
    profile.modRanks = profile.modRanks or {}
    loadout.modOrder = loadout.modOrder or {}

    if loadout.equippedMods[modKey] then
        loadout.equippedMods[modKey] = nil
        removeOrder(loadout, modKey)
        setMessage(state, "Unequipped " .. ((state.catalog[modKey] and state.catalog[modKey].name) or modKey))
    else
        if countEquipped(loadout) >= MAX_SLOTS then
            setMessage(state, "Slots full (" .. MAX_SLOTS .. ")")
            return
        end
        loadout.equippedMods[modKey] = true
        profile.modRanks[modKey] = profile.modRanks[modKey] or 1
        ensureOrder(loadout, modKey)
        setMessage(state, "Equipped " .. ((state.catalog[modKey] and state.catalog[modKey].name) or modKey))
    end

    state.saveProfile(profile)
    state.applyPersistentMods()
end

function arsenal.adjustRank(state, modKey, delta)
    local profile = state.profile
    if not profile then return end
    local weaponKey = profile.modTargetWeapon or 'wand'
    local loadout = ensureWeaponLoadout(profile, weaponKey)
    if not isEquipped(loadout, modKey) then return end
    local def = state.catalog[modKey] or {}
    local maxLv = def.maxLevel or 1
    local cur = profile.modRanks[modKey] or 1
    cur = math.max(1, math.min(maxLv, cur + delta))
    profile.modRanks[modKey] = cur
    state.saveProfile(profile)
    state.applyPersistentMods()
end

function arsenal.startRun(state, opts)
    opts = opts or {}
    state.applyPersistentMods()

    if opts.runMode then
        state.runMode = opts.runMode
    end

    if state.runMode == 'explore' then
        state.rooms = state.rooms or {}
        state.rooms.enabled = false
        state.world = world.new({
            tileSize = 32,
            w = 160,
            h = 160,
            roomCount = 28,
            roomMin = 6,
            roomMax = 14,
            corridorWidth = 2,
            navRefresh = 0.35
        })
        if state.player and state.world then
            state.player.x, state.player.y = state.world.spawnX, state.world.spawnY
            local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
            local maxCamX = math.max(0, (state.world.pixelW or 0) - sw)
            local maxCamY = math.max(0, (state.world.pixelH or 0) - sh)
            state.camera = state.camera or {x = 0, y = 0}
            state.camera.x = math.max(0, math.min((state.player.x or 0) - sw / 2, maxCamX))
            state.camera.y = math.max(0, math.min((state.player.y or 0) - sh / 2, maxCamY))
        end
        mission.start(state)
    else
        state.world = nil
        state.mission = nil
        if state.rooms then state.rooms.enabled = true end
    end

    if not state.inventory.weapons or not next(state.inventory.weapons) then
        local startKey = 'wand'
        if not opts.skipStartingWeapon then
            startKey = (state.profile and state.profile.modTargetWeapon) or startKey
        end

        local def = state.catalog and state.catalog[startKey]
        if not def or def.type ~= 'weapon' or def.evolvedOnly then
            startKey = 'wand'
        end
        weapons.addWeapon(state, startKey, 'player')
    end

    if not opts.skipStartingPet then
        pets.spawnStartingPet(state)
    end
    state.gameState = 'PLAYING'
end

function arsenal.keypressed(state, key)
    local a = state.arsenal
    if not a then return false end

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
        arsenal.startRun(state, {runMode = 'explore'})
        return true
    end

    return false
end

function arsenal.draw(state)
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
    local loadout = ensureWeaponLoadout(state.profile, weaponKey) or {}

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

    for i, key in ipairs(list) do
        local def = state.catalog[key]
        local name = (def and def.name) or key
        local owned = isOwned(state.profile, key)
        local equipped = isEquipped(loadout, key)
        local rank = (state.profile and state.profile.modRanks and state.profile.modRanks[key]) or 1
        local maxLv = (def and def.maxLevel) or 1
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
    local order = (loadout and loadout.modOrder) or {}
    for _, key in ipairs(order) do
        if isEquipped(loadout, key) then
            local def = state.catalog[key]
            local name = (def and def.name) or key
            local rank = (state.profile.modRanks and state.profile.modRanks[key]) or 1
            local maxLv = (def and def.maxLevel) or 1
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
        local def = state.catalog[selKey]
        if def and def.desc then
            love.graphics.setColor(0.75, 0.75, 0.75)
            love.graphics.printf(def.desc, leftX, h - 120, w - leftX * 2, "left")
        end
    end

    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.printf("Up/Down: select   E: equip/unequip   Left/Right: rank   Tab/Backspace: weapon   P/O: pet   Enter: rooms run   F: explore (proc map)", 0, h - 60, w, "center")

    if a.message then
        love.graphics.setColor(1, 0.8, 0.3)
        love.graphics.printf(a.message, 0, h - 90, w, "center")
    end
end

return arsenal
