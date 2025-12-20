local logger = {}

local function formatDict(dict)
    local parts = {}
    for k, v in pairs(dict or {}) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function pushEvent(state, event, data)
    if not logger.runActive then return end
    table.insert(logger.events, {t = state.gameTimer or 0, event = event, data = data or {}})
end

local function ensureSummary()
    logger.summary = logger.summary or {
        xp = 0,
        damageTaken = 0,
        kills = {},
        pickups = {},
        levelTimes = {}
    }
end

function logger.init(state)
    if love and love.filesystem and love.filesystem.setIdentity then
        pcall(function() love.filesystem.setIdentity("vampire") end)
    end
    logger.runId = os.date("run_%Y%m%d_%H%M%S")
    logger.events = {}
    logger.summary = {
            xp = 0,
            damageTaken = 0,
            kills = {},
            pickups = {},
        levelTimes = {}
        }
    logger.runActive = true
    if love and love.filesystem and love.filesystem.createDirectory then
        pcall(function() love.filesystem.createDirectory("logs") end)
    end
    if love and love.filesystem and love.filesystem.getSaveDirectory then
        local dir = love.filesystem.getSaveDirectory()
        print("[logger] save dir: " .. tostring(dir))
    end
    pushEvent(state, "run_start", {runId = logger.runId})
end

function logger.gainXp(state, amount)
    ensureSummary()
    logger.summary.xp = (logger.summary.xp or 0) + (amount or 0)
end

function logger.levelUp(state, level)
    if not level then return end
    ensureSummary()
    logger.summary.levelTimes[level] = state.gameTimer or 0
    pushEvent(state, "level_up", {level = level})
end

function logger.pickup(state, kind)
    if not kind then return end
    ensureSummary()
    logger.summary.pickups[kind] = (logger.summary.pickups[kind] or 0) + 1
    pushEvent(state, "pickup", {kind = kind})
end

function logger.upgrade(state, opt, newLevel)
    if not opt then return end
    pushEvent(state, "upgrade", {key = opt.key, type = opt.type, level = newLevel or 0})
end

function logger.kill(state, enemy)
    if not enemy then return end
    ensureSummary()
    local key = enemy.kind or "unknown"
    if enemy.isElite then key = key .. "_elite" end
    logger.summary.kills[key] = (logger.summary.kills[key] or 0) + 1
    pushEvent(state, "kill", {kind = enemy.kind, elite = enemy.isElite})
end

function logger.damageTaken(state, dmg, hpAfter)
    ensureSummary()
    logger.summary.damageTaken = (logger.summary.damageTaken or 0) + (dmg or 0)
    pushEvent(state, "player_hit", {dmg = dmg, hp = hpAfter})
end

function logger.gameOver(state, reason)
    pushEvent(state, "run_end", {reason = reason or "unknown"})
    logger.flush(state, reason)
end

function logger.flush(state, reason)
    if not logger.runActive then return end
    logger.runActive = false
    local lines = {}
    local duration = state.gameTimer or 0
    local level = state.player.level
    if level == nil then level = 1 end
    table.insert(lines, string.format("RUN %s result=%s duration=%.2f level=%d xp=%d damageTaken=%d",
        logger.runId,
        tostring(reason or "unknown"),
        duration,
        level,
        logger.summary.xp or 0,
        logger.summary.damageTaken or 0))
    table.insert(lines, "KILLS " .. formatDict(logger.summary.kills))
    table.insert(lines, "PICKUPS " .. formatDict(logger.summary.pickups))
    local lvlParts = {}
    for lvl, t in pairs(logger.summary.levelTimes or {}) do
        table.insert(lvlParts, tostring(lvl) .. "@" .. string.format("%.2f", t))
    end
    table.sort(lvlParts, function(a, b)
        return tonumber(a:match("^(%d+)")) < tonumber(b:match("^(%d+)"))
    end)
    table.insert(lines, "LEVEL_TIMES " .. table.concat(lvlParts, ","))
    for _, ev in ipairs(logger.events or {}) do
        table.insert(lines, string.format("EVENT t=%.2f %s %s", ev.t or 0, ev.event or "?", formatDict(ev.data)))
    end
    local path = string.format("logs/%s.log", logger.runId or "run")
    if love and love.filesystem and love.filesystem.write then
        local ok, err = pcall(function() love.filesystem.write(path, table.concat(lines, "\n")) end)
        if not ok then
            print("[logger] write failed: " .. tostring(err))
        else
            print("[logger] wrote log: " .. path)
        end
    else
        print("[logger] filesystem unavailable; log not written")
    end
end

function logger.flushIfActive(state, reason)
    if logger.runActive then
        logger.flush(state, reason)
    end
end

return logger
