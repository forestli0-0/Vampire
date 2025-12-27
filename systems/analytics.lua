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
        damageDealt = 0,
        kills = 0,
        deaths = 0,
        shotsFired = 0,
        shotsHit = 0
    },
    weaponStats = {} -- weaponKey -> { shotsFired, shotsHit, damageDealt }
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
            damageDealt = 0,
            kills = 0,
            deaths = 0,
            shotsFired = 0,
            shotsHit = 0
        },
        weaponStats = {}
    }
    currentRoomData = nil
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
    
    currentRoomData = nil
end

-- Record player death
function analytics.recordDeath()
    sessionData.totals.deaths = sessionData.totals.deaths + 1
end

-- Record a shot fired
function analytics.recordShot(weaponKey)
    if not weaponKey then return end
    sessionData.totals.shotsFired = sessionData.totals.shotsFired + 1
    
    local ws = sessionData.weaponStats[weaponKey]
    if not ws then
        ws = { shotsFired = 0, shotsHit = 0, damageDealt = 0 }
        sessionData.weaponStats[weaponKey] = ws
    end
    ws.shotsFired = ws.shotsFired + 1
end

-- Record a hit/damage dealt
function analytics.recordHit(weaponKey, damage, instance)
    damage = math.max(0, damage or 0)
    sessionData.totals.damageDealt = sessionData.totals.damageDealt + damage
    
    -- For accuracy: only count 1 hit per "shot" instance even if it hits multiple enemies
    -- If there is no instance (DoTs, chain damage, etc.), do NOT count it as a hit for accuracy
    if instance and not instance._hasCountedHit then
        sessionData.totals.shotsHit = sessionData.totals.shotsHit + 1
        instance._hasCountedHit = true
    end
    -- Note: if no instance, we skip incrementing shotsHit entirely
    
    if not weaponKey then return end
    local ws = sessionData.weaponStats[weaponKey]
    if not ws then
        ws = { shotsFired = 0, shotsHit = 0, damageDealt = 0 }
        sessionData.weaponStats[weaponKey] = ws
    end

    if instance and not instance._hasCountedHitWeapon then
        ws.shotsHit = ws.shotsHit + 1
        instance._hasCountedHitWeapon = true
    end
    -- Note: if no instance, we skip incrementing weapon shotsHit entirely
    
    ws.damageDealt = ws.damageDealt + (damage or 0)
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

-- Record a room cleared (for chapter mode)
function analytics.recordRoomClear(roomId, difficulty)
    table.insert(sessionData.roomStats, {
        roomIndex = roomId or #sessionData.roomStats + 1,
        difficulty = difficulty or 'normal',
        duration = 0,
        damageTaken = 0,
        kills = 0,
        minHp = 100,
        minShield = 100
    })
end

-- Get run duration
function analytics.getDuration()
    if sessionData.startTime == 0 then return 0 end
    return love.timer.getTime() - sessionData.startTime
end

-- Get weapon stats
function analytics.getWeaponStats()
    return sessionData.weaponStats
end

-- End run and print final summary
function analytics.endRun()
    if currentRoomData then
        analytics.endRoom(nil)
    end
    
    -- Sync kills from logger.summary (source of truth for kill counts)
    local logger = getLogger()
    if logger and logger.summary then
        if logger.summary.kills then
            sessionData.totals.kills = sumKills(logger.summary.kills)
        end
        if logger.summary.damageTaken then
            sessionData.totals.damageTaken = logger.summary.damageTaken
        end
    end
    
    analytics.saveToFile()
end

-- Manual save trigger (F9 key or similar)
function analytics.manualSave()
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
    
    data.weaponStats = sessionData.weaponStats
    
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
