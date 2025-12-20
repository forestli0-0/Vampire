local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

return function(upgrades)
    function upgrades.queueLevelUp(state, reason, request)
        if state.noLevelUps or state.benchmarkMode then return end
    
        state.pendingLevelUps = state.pendingLevelUps or 0
        state.pendingUpgradeRequests = state.pendingUpgradeRequests or {}
        request = request or {}
        request.reason = request.reason or reason or 'unknown'
    
        dispatch(state, 'onUpgradeQueued', {reason = request.reason, player = state.player, request = request})
    
        if state.gameState == 'LEVEL_UP' then
            state.pendingLevelUps = state.pendingLevelUps + 1
            table.insert(state.pendingUpgradeRequests, request)
            return
        end
    
        state.activeUpgradeRequest = request
        upgrades.generateUpgradeOptions(state, request)
        state.gameState = 'LEVEL_UP'
    end
    
end
