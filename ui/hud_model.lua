local abilities = require('gameplay.abilities')

local hudModel = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function hudModel.build(state)
    state = state or {}
    local p = state.player or {}
    local stats = p.stats or {}

    local classKey = p.class or "Tenno"
    local classDef = state.classes and state.classes[classKey]
    local className = (classDef and classDef.name) or classKey

    local data = {
        player = {
            class = className,
            level = (p.level ~= nil) and p.level or 0,
            hp = p.hp or 0,
            maxHp = stats.maxHp or p.maxHp or 100,
            shield = p.shield or 0,
            maxShield = stats.maxShield or p.maxShield or 100,
            xp = p.xp or 0,
            xpToNext = p.xpToNextLevel or 100,
            energy = p.energy or 0,
            maxEnergy = stats.maxEnergy or p.maxEnergy or 100
        },
        resources = {
            gold = math.floor(state.runCurrency or 0)
        },
        dash = {},
        staticCharge = {
            enabled = p.class == 'volt',
            current = p.staticCharge or 0,
            max = 100
        },
        abilities = {},
        quickAbilityIndex = 1,
        weapons = {
            activeSlot = (state.inventory and state.inventory.activeSlot) or 'ranged',
            slots = {}
        },
        objective = {}
    }

    do
        local dash = p.dash or {}
        local max = stats.dashCharges or dash.maxCharges or 3
        local current = dash.charges or 0
        local cd = (stats and stats.dashCooldown) or 1
        local t = dash.rechargeTimer or 0
        local ratio = 0
        if current < max and cd > 0 then
            ratio = clamp(t / cd, 0, 1)
        end
        data.dash.current = current
        data.dash.max = max
        data.dash.totalValue = (current < max) and (current + ratio) or max
    end

    for i = 1, 4 do
        local def = abilities.getAbilityDef(state, i)
        local cd = p.abilityCooldowns and p.abilityCooldowns[i] or 0
        local canUse = abilities.canUse(state, i)
        local cooldownRatio = 0
        if def and def.cd and def.cd > 0 and cd > 0 then
            cooldownRatio = clamp(cd / def.cd, 0, 1)
        end
        data.abilities[i] = {
            cooldownRatio = cooldownRatio,
            canUse = canUse
        }
    end

    do
        local quickIndex = math.floor(tonumber(p.quickAbilityIndex) or 1)
        if quickIndex < 1 or quickIndex > 4 then quickIndex = 1 end
        data.quickAbilityIndex = quickIndex
    end

    do
        local inv = state.inventory or {}
        local weaponSlots = inv.weaponSlots or {}
        local weaponInstances = inv.weapons or {}
        local slotKeys = {'ranged', 'melee', 'extra'}

        for i, slotKey in ipairs(slotKeys) do
            local weaponInst = weaponSlots[slotKey]
            local weaponData = weaponInst and weaponInstances[weaponInst.key] or nil
            local def = weaponInst and state.catalog and state.catalog[weaponInst.key] or nil
            local slot = {
                slotKey = slotKey,
                isActive = (slotKey == data.weapons.activeSlot),
                hasWeapon = weaponInst ~= nil
            }

            if weaponInst then
                slot.name = (def and def.name) or weaponInst.key
                local reloadTimer = weaponData and weaponData.reloadTimer or 0
                local reloadTime = (weaponData and weaponData.reloadTime) or (def and def.base and def.base.reloadTime) or 1.5
                local isReloading = weaponData and weaponData.isReloading or false
                slot.isReloading = isReloading
                slot.reloadProgress = (isReloading and reloadTime > 0) and clamp(1 - (reloadTimer / reloadTime), 0, 1) or 0
                slot.mag = weaponData and weaponData.magazine or nil
                slot.maxMag = (weaponData and weaponData.maxMagazine) or (def and def.base and def.base.maxMagazine)
                slot.reserve = weaponData and weaponData.reserve or 0
                slot.ammoInfinite = (slot.mag == nil)
            else
                slot.name = "Empty"
                slot.isReloading = false
                slot.reloadProgress = 0
                slot.mag = nil
                slot.maxMag = nil
                slot.reserve = nil
                slot.ammoInfinite = false
            end

            data.weapons.slots[i] = slot
        end
    end

    do
        local r = state.rooms or {}
        local phase = r.phase or 'init'
        local missionType = r.missionType or 'exterminate'

        local objective = {
            visible = not (phase == 'doors' or phase == 'between_rooms' or phase == 'init'),
            missionType = missionType
        }

        if missionType == 'exterminate' then
            local alive = 0
            for _, e in ipairs(state.enemies or {}) do
                if e and (e.health or e.hp or 0) > 0 and not e.isDummy then
                    alive = alive + 1
                end
            end
            objective.alive = alive
        elseif missionType == 'defense' then
            local obj = r.defenseObjective
            objective.defenseHasObjective = obj ~= nil
            if obj and obj.maxHp and obj.maxHp > 0 then
                objective.defenseHpPct = math.floor((obj.hp / obj.maxHp) * 100)
            end
        elseif missionType == 'survival' then
            objective.survivalRemaining = math.max(0, (r.survivalTarget or 60) - (r.survivalTimer or 0))
            objective.lifeSupport = r.lifeSupport or 100
        end

        data.objective = objective
    end

    return data
end

return hudModel
