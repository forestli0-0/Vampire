local helpers = require('systems.upgrades.queue_helpers')

return function(upgrades)
    function upgrades.queueLevelUp(state, reason, request)
        if state.noLevelUps or state.benchmarkMode then return end
    
        state.pendingLevelUps = state.pendingLevelUps or 0
        state.pendingUpgradeRequests = state.pendingUpgradeRequests or {}
        request = helpers.prepareRequest(request, reason)
    
        helpers.dispatch(state, 'onUpgradeQueued', {reason = request.reason, player = state.player, request = request})
    
        if state.gameState == 'LEVEL_UP' then
            helpers.queuePending(state, request)
            return
        end
    
        helpers.startLevelUp(state, request, upgrades)
    end
    
end
