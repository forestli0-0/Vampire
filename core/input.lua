-- input.lua
-- Modular action-based input system (UE-style)

local input = {}

-- Action Map: Action Name -> List of keys/buttons
input.keymap = {
    -- Movement
    move_up = {'w', 'up'},
    move_down = {'s', 'down'},
    move_left = {'a', 'left'},
    move_right = {'d', 'right'},
    
    -- Actions
    fire = {'mouse1', 'j'},
    melee = {'e'},
    reload = {'r'},
    slide = {'lshift', 'rshift'},
    jump = {'space'},
    
    -- Abilities
    ability1 = {'1'},
    ability2 = {'2'},
    ability3 = {'3'},
    ability4 = {'4'},
    quick_cast = {'q'},
    
    -- Utility
    cycle_weapon = {'f'},
    toggle_pet = {'p'},
    debug_mods = {'m'},
    cancel = {'escape'}
}

-- Check if an action is currently pressed
function input.isDown(action)
    local keys = input.keymap[action]
    if not keys then return false end
    
    for _, k in ipairs(keys) do
        if k:sub(1, 5) == 'mouse' then
            local btn = tonumber(k:sub(6))
            if love.mouse.isDown(btn) then return true end
        else
            if love.keyboard.isDown(k) then return true end
        end
    end
    return false
end

-- Get axis value (-1 to 1)
function input.getAxis(axisName)
    if axisName == 'move_x' then
        local val = 0
        if input.isDown('move_right') then val = val + 1 end
        if input.isDown('move_left') then val = val - 1 end
        return val
    elseif axisName == 'move_y' then
        local val = 0
        if input.isDown('move_down') then val = val + 1 end
        if input.isDown('move_up') then val = val - 1 end
        return val
    end
    return 0
end

-- Get world mouse position
function input.getMouseWorld(state)
    local mx, my = love.mouse.getPosition()
    local camX = state.camera and state.camera.x or 0
    local camY = state.camera and state.camera.y or 0
    return mx + camX, my + camY
end

-- Get angle from point to mouse (returns angle in radians)
function input.getAimAngle(state, fromX, fromY)
    local mx, my = input.getMouseWorld(state)
    return math.atan2(my - (fromY or 0), mx - (fromX or 0))
end

-- Helper to check if any of a list of keys matches
-- Useful for keypressed events
function input.isActionKey(key, action)
    local keys = input.keymap[action]
    if not keys then return false end
    for _, k in ipairs(keys) do
        if k == key then return true end
    end
    return false
end

return input
