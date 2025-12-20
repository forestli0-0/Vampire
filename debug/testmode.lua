local scenarios = require('debug.test_scenarios')

local testmode = {}

local function clampIndex(idx, list)
    if #list == 0 then return 1 end
    if idx < 1 then return #list end
    if idx > #list then return 1 end
    return idx
end

function testmode.init(state)
    state.testmode = state.testmode or {}
    state.testmode.open = false
    state.testmode.idx = state.testmode.idx or 1
    state.testmode.seed = state.testmode.seed or 12345
    state.testmode.list = scenarios.list
end

local function startScenario(state, scenario)
    if not scenario then return false end
    state.pendingScenarioId = scenario.id
    state.pendingScenarioSeed = state.testmode and state.testmode.seed or 12345
    love.load()
    return true
end

local function resetScenario(state)
    if not state.activeScenarioId then return false end
    state.pendingScenarioId = state.activeScenarioId
    state.pendingScenarioSeed = state.activeScenarioSeed
    love.load()
    return true
end

function testmode.keypressed(state, key)
    if key == 'f2' then
        state.testmode.open = not state.testmode.open
        return true
    end

    if key == 'f6' and not (state.testmode and state.testmode.open) then
        return resetScenario(state)
    end

    if not (state.testmode and state.testmode.open) then
        return false
    end

    local list = state.testmode.list or {}

    if key == 'escape' then
        state.testmode.open = false
        return true
    elseif key == 'up' then
        state.testmode.idx = clampIndex((state.testmode.idx or 1) - 1, list)
        return true
    elseif key == 'down' then
        state.testmode.idx = clampIndex((state.testmode.idx or 1) + 1, list)
        return true
    elseif key == 'return' or key == 'kpenter' then
        local sc = list[state.testmode.idx or 1]
        return startScenario(state, sc)
    end

    return true
end

function testmode.draw(state)
    if not (state.testmode and state.testmode.open) then return end

    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local list = state.testmode.list or {}

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle('fill', 30, 30, w - 60, h - 60)
    love.graphics.setColor(1, 1, 1)

    local y = 50
    love.graphics.print("TEST SCENARIOS (F2 close)", 50, y)
    y = y + 28
    love.graphics.print("Up/Down select | Enter start | F6 reset current scenario", 50, y)
    y = y + 28

    local active = state.activeScenarioId
    if active then
        love.graphics.print("Active: " .. tostring(active) .. "  (seed " .. tostring(state.activeScenarioSeed or '') .. ")", 50, y)
        y = y + 24
    end

    y = y + 6

    for i, sc in ipairs(list) do
        local selected = (i == (state.testmode.idx or 1))
        if selected then
            love.graphics.setColor(1, 1, 0.6, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.print(string.format("%s. %s", tostring(i), sc.name or sc.id), 60, y)
        y = y + 22
        love.graphics.setColor(0.85, 0.85, 0.85, 1)
        if sc.desc then
            love.graphics.print(sc.desc, 80, y)
            y = y + 20
        end
        y = y + 6
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return testmode
