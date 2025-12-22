--[[
    Combat Analytics System
    Tracks gameplay metrics for balance analysis
    
    Uses logger.summary for accurate damage/kill data
]]

local analytics = {}

-- Try to get the logger module
local function getLogger()
    local ok, logger = pcall(require, 'core.logger')
    return ok and logger or nil
end

-- Sum all values in a kills dictionary
local function sumKills(killsDict)
    local total = 0
    for _, count in pairs(killsDict or {}) do
        total = total + (count or 0)
    end
    return total
end

-- Session data
local sessionData = {
    startTime = 0,
    roomStats = {},
    totals = {
        damageTaken = 0,
        kills = 0,
        deaths = 0
    }
}

-- Current room tracking
local currentRoomData = nil

-- Initialize analytics for a new run
function analytics.startRun(state)
    sessionData = {
        startTime = love.timer.getTime(),
        roomStats = {},
        totals = {
            damageTaken = 0,
            kills = 0,
            deaths = 0
        }
    }
    currentRoomData = nil
    print("[Analytics] Run started")
end

-- Start tracking a new room
function analytics.startRoom(roomIndex, missionType, state)
    if currentRoomData then
        analytics.endRoom(state)
    end
    
    -- Get baseline from logger
    local logger = getLogger()
    local startDamage = 0
    local startKills = 0
    if logger and logger.summary then
        startDamage = logger.summary.damageTaken or 0
        startKills = sumKills(logger.summary.kills)
    end
    
    -- Capture starting player HP
    local startHp, startShield = 100, 100
    if state and state.player then
        startHp = state.player.hp or 100
        startShield = state.player.shield or 100
    end
    
    currentRoomData = {
        roomIndex = roomIndex or 0,
        missionType = missionType or 'exterminate',
        startTime = love.timer.getTime(),
        duration = 0,
        
        -- Baselines from logger
        startDamage = startDamage,
        startKills = startKills,
        
        -- Stats to be computed
        damageTaken = 0,
        kills = 0,
        
        -- Player state
        startHp = startHp,
        startShield = startShield,
        minHp = startHp,
        minShield = startShield
    }
    
    print(string.format("[Analytics] Room %d started (%s) - baseline: %d dmg, %d kills", 
        roomIndex or 0, missionType or 'exterminate', startDamage, startKills))
end

-- End current room and save stats
function analytics.endRoom(state)
    if not currentRoomData then return end
    
    currentRoomData.duration = love.timer.getTime() - currentRoomData.startTime
    
    -- Get current values from logger
    local logger = getLogger()
    if logger and logger.summary then
        local endDamage = logger.summary.damageTaken or 0
        local endKills = sumKills(logger.summary.kills)
        
        currentRoomData.damageTaken = endDamage - currentRoomData.startDamage
        currentRoomData.kills = endKills - currentRoomData.startKills
    end
    
    -- Track min HP from current state
    if state and state.player then
        currentRoomData.minHp = math.min(currentRoomData.minHp, state.player.hp or 0)
        currentRoomData.minShield = math.min(currentRoomData.minShield, state.player.shield or 0)
    end
    
    -- Store in session
    table.insert(sessionData.roomStats, currentRoomData)
    
    -- Update totals
    sessionData.totals.damageTaken = sessionData.totals.damageTaken + currentRoomData.damageTaken
    sessionData.totals.kills = sessionData.totals.kills + currentRoomData.kills
    
    -- Print summary
    print(string.format("[Analytics] Room %d completed:", currentRoomData.roomIndex))
    print(string.format("  Duration: %.1fs", currentRoomData.duration))
    print(string.format("  Damage Taken: %d", currentRoomData.damageTaken))
    print(string.format("  Kills: %d", currentRoomData.kills))
    print(string.format("  Min HP: %d, Min Shield: %d", currentRoomData.minHp, currentRoomData.minShield))
    
    currentRoomData = nil
end

-- Record player death
function analytics.recordDeath()
    sessionData.totals.deaths = sessionData.totals.deaths + 1
    print("[Analytics] Player died!")
end

-- Get current room data
function analytics.getCurrentRoom()
    return currentRoomData
end

-- Get session totals
function analytics.getTotals()
    return sessionData.totals
end

-- Get all room stats
function analytics.getRoomStats()
    return sessionData.roomStats
end

-- End run and print final summary
function analytics.endRun()
    if currentRoomData then
        analytics.endRoom(nil)
    end
    
    local duration = love.timer.getTime() - sessionData.startTime
    
    print("\n========== RUN ANALYTICS ==========")
    print(string.format("Total Duration: %.1fs", duration))
    print(string.format("Rooms Cleared: %d", #sessionData.roomStats))
    print(string.format("Total Damage Taken: %d", sessionData.totals.damageTaken))
    print(string.format("Total Kills: %d", sessionData.totals.kills))
    print(string.format("Deaths: %d", sessionData.totals.deaths))
    
    if #sessionData.roomStats > 0 then
        print("\n--- Per-Room Breakdown ---")
        for _, room in ipairs(sessionData.roomStats) do
            print(string.format("Room %d: %.1fs, %d dmg, %d kills, min HP %d",
                room.roomIndex, room.duration, room.damageTaken, room.kills, room.minHp))
        end
    end
    
    print("=====================================\n")
    
    analytics.saveToFile()
end

-- Manual save trigger (F9 key or similar)
function analytics.manualSave()
    print("[Analytics] Manual save triggered")
    analytics.saveToFile()
end

-- Save to file
function analytics.saveToFile()
    local data = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        duration = love.timer.getTime() - sessionData.startTime,
        totals = sessionData.totals,
        rooms = {}
    }
    
    for _, room in ipairs(sessionData.roomStats) do
        table.insert(data.rooms, {
            roomIndex = room.roomIndex,
            duration = room.duration,
            damageTaken = room.damageTaken,
            kills = room.kills,
            minHp = room.minHp,
            minShield = room.minShield
        })
    end
    
    -- Simple JSON
    local function serialize(t, indent)
        indent = indent or 0
        local spaces = string.rep("  ", indent)
        local result = "{\n"
        local first = true
        for k, v in pairs(t) do
            if not first then result = result .. ",\n" end
            first = false
            result = result .. spaces .. "  \"" .. tostring(k) .. "\": "
            if type(v) == "table" then
                result = result .. serialize(v, indent + 1)
            elseif type(v) == "string" then
                result = result .. "\"" .. v .. "\""
            else
                result = result .. tostring(v)
            end
        end
        result = result .. "\n" .. spaces .. "}"
        return result
    end
    
    local json = serialize(data)
    local filename = string.format("analytics_%s.json", os.date("%Y%m%d_%H%M%S"))
    
    -- Get the source directory (project directory) for saving
    local sourceDir = love.filesystem.getSource()
    local filepath = sourceDir .. "/" .. filename
    
    -- Use native Lua io to write to project directory (not LÖVE save directory)
    local file, err = io.open(filepath, "w")
    if file then
        file:write(json)
        file:close()
        print(string.format("[Analytics] Saved to %s", filepath))
    else
        -- Fallback to LÖVE filesystem if native io fails
        local success, loveErr = love.filesystem.write(filename, json)
        if success then
            local saveDir = love.filesystem.getSaveDirectory()
            print(string.format("[Analytics] Saved to %s/%s (fallback)", saveDir, filename))
        else
            print(string.format("[Analytics] Failed to save: %s", loveErr or err or "unknown"))
        end
    end
end

-- Stubs for backward compatibility
function analytics.recordDamageTaken() end
function analytics.recordKill() end
function analytics.recordAbilityUse() end
function analytics.recordDashUse() end

return analytics
