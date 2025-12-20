local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

local function prepareRequest(request, reason)
    request = request or {}
    request.reason = request.reason or reason or 'unknown'
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
