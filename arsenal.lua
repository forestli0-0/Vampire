local weapons = require('weapons')

local arsenal = {}

local MAX_SLOTS = 4

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

local function countEquipped(profile)
    local n = 0
    for _, v in pairs(profile.equippedMods or {}) do
        if v then n = n + 1 end
    end
    return n
end

local function isEquipped(profile, key)
    return profile and profile.equippedMods and profile.equippedMods[key]
end

local function isOwned(profile, key)
    return profile and profile.ownedMods and profile.ownedMods[key]
end

local function ensureOrder(profile, key)
    profile.modOrder = profile.modOrder or {}
    for _, k in ipairs(profile.modOrder) do
        if k == key then return end
    end
    table.insert(profile.modOrder, key)
end

local function removeOrder(profile, key)
    local order = profile.modOrder or {}
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

function arsenal.init(state)
    state.arsenal = {
        modList = buildModList(state),
        idx = 1,
        message = nil,
        messageTimer = 0
    }
    if #state.arsenal.modList == 0 then
        state.arsenal.idx = 0
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
    if not isOwned(profile, modKey) then
        setMessage(state, "Locked mod")
        return
    end

    profile.equippedMods = profile.equippedMods or {}
    profile.modRanks = profile.modRanks or {}
    profile.modOrder = profile.modOrder or {}

    if profile.equippedMods[modKey] then
        profile.equippedMods[modKey] = nil
        removeOrder(profile, modKey)
        setMessage(state, "Unequipped " .. ((state.catalog[modKey] and state.catalog[modKey].name) or modKey))
    else
        if countEquipped(profile) >= MAX_SLOTS then
            setMessage(state, "Slots full (" .. MAX_SLOTS .. ")")
            return
        end
        profile.equippedMods[modKey] = true
        profile.modRanks[modKey] = profile.modRanks[modKey] or 1
        ensureOrder(profile, modKey)
        setMessage(state, "Equipped " .. ((state.catalog[modKey] and state.catalog[modKey].name) or modKey))
    end

    state.saveProfile(profile)
    state.applyPersistentMods()
end

function arsenal.adjustRank(state, modKey, delta)
    local profile = state.profile
    if not (profile and isEquipped(profile, modKey)) then return end
    local def = state.catalog[modKey] or {}
    local maxLv = def.maxLevel or 1
    local cur = profile.modRanks[modKey] or 1
    cur = math.max(1, math.min(maxLv, cur + delta))
    profile.modRanks[modKey] = cur
    state.saveProfile(profile)
    state.applyPersistentMods()
end

function arsenal.startRun(state)
    state.applyPersistentMods()
    if not state.inventory.weapons or not next(state.inventory.weapons) then
        weapons.addWeapon(state, 'wand')
    end
    state.gameState = 'PLAYING'
end

function arsenal.keypressed(state, key)
    local a = state.arsenal
    if not a then return false end

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

    love.graphics.setColor(1, 1, 1)
    local credits = (state.profile and state.profile.currency) or 0
    love.graphics.print("Available Mods   Credits: " .. tostring(credits), leftX, topY - 30)

    for i, key in ipairs(list) do
        local def = state.catalog[key]
        local name = (def and def.name) or key
        local owned = isOwned(state.profile, key)
        local equipped = isEquipped(state.profile, key)
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
    love.graphics.print(string.format("Equipped (%d/%d)", countEquipped(state.profile or {}), MAX_SLOTS), rightX, topY - 30)

    local eqY = topY
    local order = (state.profile and state.profile.modOrder) or {}
    for _, key in ipairs(order) do
        if isEquipped(state.profile, key) then
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
    love.graphics.printf("Up/Down: select   E: equip/unequip   Left/Right: rank   Enter: start run", 0, h - 60, w, "center")

    if a.message then
        love.graphics.setColor(1, 0.8, 0.3)
        love.graphics.printf(a.message, 0, h - 90, w, "center")
    end
end

return arsenal
