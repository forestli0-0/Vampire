local augments = {}

local function ensureState(state)
    if not state then return end
    state.inventory = state.inventory or {weapons = {}, passives = {}, mods = {}, modOrder = {}, weaponMods = {}, augments = {}, augmentOrder = {}}
    state.inventory.augments = state.inventory.augments or {}
    state.inventory.augmentOrder = state.inventory.augmentOrder or {}
    state.inventory.weaponMods = state.inventory.weaponMods or {}
    state.augmentState = state.augmentState or {}
    state.maxAugmentsPerRun = state.maxAugmentsPerRun or 4
end

local function ensureAugmentState(state, key)
    ensureState(state)
    if not state then return nil end
    local s = state.augmentState[key]
    if not s then
        s = {
            cooldowns = {},
            counters = {},
            stacks = {},
            data = {},
            rateTimers = {},
            rateCounts = {}
        }
        state.augmentState[key] = s
    end
    s.cooldowns = s.cooldowns or {}
    s.counters = s.counters or {}
    s.stacks = s.stacks or {}
    s.data = s.data or {}
    s.rateTimers = s.rateTimers or {}
    s.rateCounts = s.rateCounts or {}
    return s
end

local function getDispatchOrder(state)
    local inv = state and state.inventory and state.inventory.augments or {}
    local order = state and state.inventory and state.inventory.augmentOrder or nil
    local keys = {}
    local seen = {}

    if order then
        for _, key in ipairs(order) do
            local lvl = inv[key]
            if lvl and lvl > 0 and not seen[key] then
                table.insert(keys, key)
                seen[key] = true
            end
        end
    end

    local extra = {}
    for key, lvl in pairs(inv) do
        if lvl and lvl > 0 and not seen[key] then
            table.insert(extra, key)
            seen[key] = true
        end
    end
    table.sort(extra)
    for _, key in ipairs(extra) do
        table.insert(keys, key)
    end

    return keys
end

local function tagsContain(tags, want)
    if not tags or not want then return false end
    local w = string.upper(tostring(want))
    for _, t in ipairs(tags) do
        if string.upper(tostring(t)) == w then return true end
    end
    return false
end

local function getHpPct(curr, max)
    curr = curr or 0
    max = max or 0
    if max <= 0 then return 0 end
    return curr / max
end

local function checkRequires(req, ctx)
    if not req then return true end
    ctx = ctx or {}

    if req.isMoving ~= nil then
        if (ctx.isMoving or false) ~= req.isMoving then return false end
    end
    if req.minMovedDist ~= nil then
        if (ctx.movedDist or 0) < req.minMovedDist then return false end
    end
    if req.isCrit ~= nil then
        if (ctx.isCrit or false) ~= req.isCrit then return false end
    end
    if req.proc ~= nil then
        if string.upper(ctx.effectType or '') ~= string.upper(req.proc) then return false end
    end
    if req.enemyHasShield ~= nil then
        local e = ctx.enemy
        local has = e and ((e.maxShield or 0) > 0) or false
        if has ~= req.enemyHasShield then return false end
    end
    if req.enemyHasArmor ~= nil then
        local e = ctx.enemy
        local has = e and ((e.armor or 0) > 0) or false
        if has ~= req.enemyHasArmor then return false end
    end
    if req.enemyIsElite ~= nil then
        local e = ctx.enemy
        local is = e and (e.isElite or false) or false
        if is ~= req.enemyIsElite then return false end
    end
    if req.enemyIsBoss ~= nil then
        local e = ctx.enemy
        local is = e and (e.isBoss or false) or false
        if is ~= req.enemyIsBoss then return false end
    end
    if req.enemyKind ~= nil then
        local e = ctx.enemy
        if not e or string.upper(e.kind or '') ~= string.upper(req.enemyKind) then return false end
    end
    if req.enemyFrozen ~= nil then
        local e = ctx.enemy
        local frozen = e and e.status and (e.status.frozen or false) or false
        if frozen ~= req.enemyFrozen then return false end
    end
    if req.playerHpPctBelow ~= nil then
        local p = ctx.player
        local hp = p and p.hp or 0
        local maxHp = p and p.maxHp or 0
        local pct = (maxHp > 0) and (hp / maxHp) or 0
        if pct > req.playerHpPctBelow then return false end
    end
    if req.playerHpPctAbove ~= nil then
        local p = ctx.player
        local hp = p and p.hp or 0
        local maxHp = p and p.maxHp or 0
        local pct = (maxHp > 0) and (hp / maxHp) or 0
        if pct < req.playerHpPctAbove then return false end
    end
    if req.enemyHpPctBelow ~= nil then
        local e = ctx.enemy
        local pct = e and getHpPct(e.health or e.hp or 0, e.maxHealth or e.maxHp or 0) or 0
        if pct > req.enemyHpPctBelow then return false end
    end
    if req.enemyHpPctAbove ~= nil then
        local e = ctx.enemy
        local pct = e and getHpPct(e.health or e.hp or 0, e.maxHealth or e.maxHp or 0) or 0
        if pct < req.enemyHpPctAbove then return false end
    end
    if req.enemyShieldPctBelow ~= nil then
        local e = ctx.enemy
        local pct = e and getHpPct(e.shield or 0, e.maxShield or 0) or 0
        if pct > req.enemyShieldPctBelow then return false end
    end
    if req.enemyShieldPctAbove ~= nil then
        local e = ctx.enemy
        local pct = e and getHpPct(e.shield or 0, e.maxShield or 0) or 0
        if pct < req.enemyShieldPctAbove then return false end
    end
    if req.weaponTag ~= nil then
        local tags = (ctx.instance and ctx.instance.weaponTags) or ctx.weaponTags or (ctx.bullet and ctx.bullet.weaponTags) or nil
        if not tagsContain(tags, req.weaponTag) then return false end
    end
    if req.weaponKey ~= nil then
        local key = ctx.weaponKey or (ctx.bullet and ctx.bullet.type) or ''
        if string.upper(tostring(key)) ~= string.upper(tostring(req.weaponKey)) then return false end
    end
    if req.pickupKind ~= nil then
        if string.upper(tostring(ctx.kind or '')) ~= string.upper(tostring(req.pickupKind)) then return false end
    end
    if req.minDamage ~= nil then
        local dmg = ctx.damage or (ctx.result and ctx.result.damage) or ctx.amount or 0
        if dmg < req.minDamage then return false end
    end
    if req.maxDamage ~= nil then
        local dmg = ctx.damage or (ctx.result and ctx.result.damage) or ctx.amount or 0
        if dmg > req.maxDamage then return false end
    end
    return true
end

local function getCounterDelta(counterKey, eventName, ctx)
    ctx = ctx or {}
    eventName = string.upper(eventName or '')
    counterKey = string.lower(counterKey or '')

    if eventName == 'TICK' then
        if counterKey == 'movedist' then
            return ctx.movedDist or 0
        elseif counterKey == 'movetime' then
            return (ctx.isMoving and (ctx.dt or 0) or 0)
        elseif counterKey == 'idletime' then
            return ((not ctx.isMoving) and (ctx.dt or 0) or 0)
        elseif counterKey == 'time' then
            return ctx.dt or 0
        end
    elseif eventName == 'ONHIT' then
        if counterKey == 'hits' then
            return 1
        elseif counterKey == 'damagedealt' then
            local r = ctx.result or {}
            return r.damage or 0
        elseif counterKey == 'crits' then
            return (ctx.isCrit and 1 or 0)
        end
    elseif eventName == 'ONDAMAGEDEALT' then
        if counterKey == 'damagedealt' then
            return ctx.damage or 0
        elseif counterKey == 'shielddamagedealt' then
            return ctx.shieldDamage or 0
        elseif counterKey == 'healthdamagedealt' then
            return ctx.healthDamage or 0
        end
    elseif eventName == 'ONSHOOT' then
        if counterKey == 'shots' then return 1 end
    elseif eventName == 'ONPROJECTILESPAWNED' then
        if counterKey == 'projectiles' then return 1 end
    elseif eventName == 'ONPROC' then
        if counterKey == 'procs' then return 1 end
    elseif eventName == 'ONKILL' then
        if counterKey == 'kills' then
            return 1
        end
    elseif eventName == 'ONPICKUP' then
        if counterKey == 'pickups' then
            return 1
        elseif counterKey == 'pickupamount' then
            return ctx.amount or 0
        end
    elseif eventName == 'ONHURT' then
        if counterKey == 'hitstaken' then
            return 1
        elseif counterKey == 'damagetaken' then
            return ctx.amount or 0
        end
    elseif eventName == 'ONLEVELUP' then
        if counterKey == 'levelups' then return 1 end
    elseif eventName == 'ONUPGRADECHOSEN' then
        if counterKey == 'upgrades' then return 1 end
    elseif eventName == 'ONENEMYSPAWNED' then
        if counterKey == 'spawns' then return 1 end
    end

    return 0
end

local function canTrigger(aState, trigId, trig)
    if not aState or not trig then return false end
    local cd = aState.cooldowns[trigId] or 0
    if (trig.cooldown or 0) > 0 and cd > 0 then return false end

    if trig.maxPerSecond then
        if aState.rateTimers[trigId] == nil then
            aState.rateTimers[trigId] = 1
            aState.rateCounts[trigId] = 0
        end
        local count = aState.rateCounts[trigId] or 0
        if count >= trig.maxPerSecond then return false end
    end

    if trig.chance ~= nil and trig.chance < 1 then
        if math.random() >= trig.chance then return false end
    end

    return true
end

local function markTriggered(aState, trigId, trig)
    if not aState or not trig then return end
    if (trig.cooldown or 0) > 0 then
        aState.cooldowns[trigId] = trig.cooldown
    end
    if trig.maxPerSecond then
        aState.rateCounts[trigId] = (aState.rateCounts[trigId] or 0) + 1
    end
end

local function runTrigger(state, def, level, aState, trig, ctx)
    if not trig then return end
    if trig.action then
        trig.action(state, ctx or {}, level or 1, aState, def, trig)
    end
end

function augments.update(state, dt)
    ensureState(state)
    if not state or not state.inventory or not state.inventory.augments then return end

    -- tick internal cooldowns/rate windows
    local inv = state.inventory.augments
    for _, key in ipairs(getDispatchOrder(state)) do
        local level = inv[key]
        if level and level > 0 then
            local aState = ensureAugmentState(state, key)
            for id, t in pairs(aState.cooldowns or {}) do
                t = (t or 0) - dt
                if t <= 0 then
                    aState.cooldowns[id] = nil
                else
                    aState.cooldowns[id] = t
                end
            end
            for id, t in pairs(aState.rateTimers or {}) do
                t = (t or 0) - dt
                if t <= 0 then
                    aState.rateTimers[id] = 1
                    aState.rateCounts[id] = 0
                else
                    aState.rateTimers[id] = t
                end
            end
        end
    end

    local p = state.player or {}
    local ctx = {
        dt = dt,
        t = state.gameTimer or 0,
        player = p,
        movedDist = p.movedDist or 0,
        isMoving = p.isMoving or false
    }
    augments.dispatch(state, 'tick', ctx)
end

function augments.dispatch(state, eventName, ctx)
    ensureState(state)
    if not state or not state.inventory or not state.inventory.augments then return ctx end
    local inv = state.inventory.augments
    local catalog = state.catalog or {}
    eventName = eventName or ''
    ctx = ctx or {}
    if ctx.player == nil then ctx.player = state.player end
    if ctx.t == nil then ctx.t = state.gameTimer or 0 end

    for _, key in ipairs(getDispatchOrder(state)) do
        local level = inv[key]
        if level and level > 0 then
            local def = catalog[key]
            if def and def.type == 'augment' then
                local aState = ensureAugmentState(state, key)

                if def.onEvent then
                    def.onEvent(state, eventName, ctx or {}, level, aState)
                    if ctx.stopPropagation then break end
                elseif def.triggers then
                    for idx, trig in ipairs(def.triggers) do
                        if string.upper(trig.event or '') == string.upper(eventName) then
                            local trigId = trig.id or tostring(idx)

                            local localCtx = ctx or {}
                            if localCtx.player == nil then localCtx.player = state.player end

                            if checkRequires(trig.requires, localCtx) then
                                if trig.counter then
                                    local delta = getCounterDelta(trig.counter, eventName, localCtx)
                                    if delta ~= 0 then
                                        aState.counters[trig.counter] = (aState.counters[trig.counter] or 0) + delta
                                    end

                                    local threshold = trig.threshold
                                    if threshold and threshold > 0 then
                                        local count = aState.counters[trig.counter] or 0
                                        local maxTimes = trig.maxTriggersPerEvent or 4
                                        local fired = 0
                                        while count >= threshold and fired < maxTimes do
                                            if not canTrigger(aState, trigId, trig) then break end
                                            count = count - threshold
                                            aState.counters[trig.counter] = count
                                            runTrigger(state, def, level, aState, trig, localCtx)
                                            markTriggered(aState, trigId, trig)
                                            fired = fired + 1
                                        end
                                    end
                                else
                                    if canTrigger(aState, trigId, trig) then
                                        runTrigger(state, def, level, aState, trig, localCtx)
                                        markTriggered(aState, trigId, trig)
                                        if localCtx.stopPropagation then break end
                                    end
                                end
                            end
                        end
                    end
                    if ctx.stopPropagation then break end
                end
            end
        end
    end

    return ctx
end

return augments
