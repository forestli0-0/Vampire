local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

local REASON_DEFAULTS = {
    mod_drop = {mode = 'mod', kind = 'mod', allowedTypes = {mod = true, augment = true}},
    pet_contract = {kind = 'pet', allowedTypes = {pet = true}},
    shop_pet = {kind = 'pet', allowedTypes = {pet = true}},
    pet_module_chip = {mode = 'mod', kind = 'mod', allowedTypes = {mod = true, augment = true}, category = 'companion', group = 'augment'},
    shop_pet_module = {mode = 'mod', kind = 'mod', allowedTypes = {mod = true, augment = true}, category = 'companion', group = 'augment'},
    pet_upgrade_chip = {mode = 'mod', kind = 'mod', allowedTypes = {mod = true}, category = 'companion'},
    shop_pet_upgrade = {mode = 'mod', kind = 'mod', allowedTypes = {mod = true}, category = 'companion'}
}

local function hasAllowedType(allowed, want)
    if type(allowed) ~= 'table' then return false end
    if allowed[want] then return true end
    for _, v in ipairs(allowed) do
        if v == want then return true end
    end
    return false
end

local function prepareRequest(request, reason)
    request = request or {}
    local rawReason = request.reason or reason or 'unknown'
    request.reason = rawReason
    request.source = request.source or rawReason

    local defaults = REASON_DEFAULTS[rawReason]
    if defaults then
        request.kind = request.kind or defaults.kind
        request.mode = request.mode or defaults.mode
        if defaults.allowedTypes and (type(request.allowedTypes) ~= 'table' or next(request.allowedTypes) == nil) then
            request.allowedTypes = defaults.allowedTypes
        end
    end

    if not request.mode then
        if hasAllowedType(request.allowedTypes, 'mod') or hasAllowedType(request.allowedTypes, 'augment') then
            request.mode = 'mod'
        end
    end

    return request
end

local function queuePending(state, request)
    state.pendingLevelUps = (state.pendingLevelUps or 0) + 1
    state.pendingUpgradeRequests = state.pendingUpgradeRequests or {}
    table.insert(state.pendingUpgradeRequests, request)
end

local function startLevelUp(state, request, upgrades)
    state.activeUpgradeRequest = request
    upgrades.generateUpgradeOptions(state, request)
    state.gameState = 'LEVEL_UP'
end

return {
    dispatch = dispatch,
    prepareRequest = prepareRequest,
    queuePending = queuePending,
    startLevelUp = startLevelUp
}
