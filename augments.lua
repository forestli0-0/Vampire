local augments = {}

local function ensureState(state)
    if not state then return end
    state.inventory = state.inventory or {weapons = {}, passives = {}, mods = {}, modOrder = {}, augments = {}, augmentOrder = {}}
    state.inventory.augments = state.inventory.augments or {}
    state.inventory.augmentOrder = state.inventory.augmentOrder or {}
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
    if req.playerHpPctBelow ~= nil then
        local p = ctx.player
        local hp = p and p.hp or 0
        local maxHp = p and p.maxHp or 0
        local pct = (maxHp > 0) and (hp / maxHp) or 0
        if pct > req.playerHpPctBelow then return false end
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
        end
    elseif eventName == 'ONKILL' then
        if counterKey == 'kills' then
            return 1
        end
    elseif eventName == 'ONPICKUP' then
        if counterKey == 'pickups' then
            return 1
        end
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
    for key, level in pairs(state.inventory.augments) do
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
    if not state or not state.inventory or not state.inventory.augments then return end
    local inv = state.inventory.augments
    local catalog = state.catalog or {}
    eventName = eventName or ''

    for key, level in pairs(inv) do
        if level and level > 0 then
            local def = catalog[key]
            if def and def.type == 'augment' then
                local aState = ensureAugmentState(state, key)

                if def.onEvent then
                    def.onEvent(state, eventName, ctx or {}, level, aState)
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
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

return augments

