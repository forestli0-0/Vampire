-- UI Theme module
-- Centralized design tokens for pixel-art UI style

local theme = {}

-------------------------------------------
-- Fonts (Chinese support)
-------------------------------------------
theme.fonts = {}
local fontPath = "fonts/ZZGFBHV1.otf"

-- Load fonts at different sizes (called after love.load)
function theme.loadFonts()
    local ok, err = pcall(function()
        theme.fonts.small = love.graphics.newFont(fontPath, 10)
        theme.fonts.normal = love.graphics.newFont(fontPath, 12)
        theme.fonts.medium = love.graphics.newFont(fontPath, 14)
        theme.fonts.large = love.graphics.newFont(fontPath, 18)
        theme.fonts.title = love.graphics.newFont(fontPath, 24)
    end)
    
    if not ok then
        print("[UI Theme] Failed to load font: " .. tostring(err))
        -- Fallback to default font
        theme.fonts.small = love.graphics.newFont(10)
        theme.fonts.normal = love.graphics.newFont(12)
        theme.fonts.medium = love.graphics.newFont(14)
        theme.fonts.large = love.graphics.newFont(18)
        theme.fonts.title = love.graphics.newFont(24)
    end
end

-- Get font by name
function theme.getFont(name)
    if not theme.fonts.normal then
        theme.loadFonts()
    end
    return theme.fonts[name] or theme.fonts.normal or love.graphics.getFont()
end

-------------------------------------------
-- Color Palette
-------------------------------------------
theme.colors = {
    -- Backgrounds
    background = {0.08, 0.08, 0.10, 1.0},
    panel_bg = {0.15, 0.15, 0.18, 0.95},
    panel_bg_light = {0.20, 0.20, 0.24, 0.95},
    panel_border = {0.35, 0.35, 0.40, 1.0},
    panel_border_light = {0.50, 0.50, 0.55, 1.0},
    
    -- Text
    text = {0.95, 0.95, 0.95, 1.0},
    text_dim = {0.60, 0.60, 0.65, 1.0},
    text_highlight = {1.0, 1.0, 1.0, 1.0},
    text_shadow = {0.0, 0.0, 0.0, 0.8},
    
    -- Accent colors
    accent = {0.40, 0.75, 1.0, 1.0},         -- Blue
    accent_dim = {0.30, 0.55, 0.75, 1.0},
    warning = {1.0, 0.70, 0.30, 1.0},        -- Orange
    danger = {1.0, 0.35, 0.35, 1.0},         -- Red
    success = {0.40, 0.90, 0.50, 1.0},       -- Green
    
    -- Button states
    button_normal = {0.22, 0.22, 0.26, 1.0},
    button_hover = {0.32, 0.32, 0.38, 1.0},
    button_pressed = {0.18, 0.18, 0.22, 1.0},
    button_disabled = {0.15, 0.15, 0.15, 0.6},
    button_border = {0.45, 0.45, 0.50, 1.0},
    button_border_hover = {0.60, 0.70, 0.90, 1.0},
    
    -- Resource bars
    hp_bg = {0.20, 0.08, 0.08, 0.9},
    hp_fill = {0.85, 0.25, 0.25, 1.0},
    hp_fill_low = {1.0, 0.30, 0.20, 1.0},
    
    energy_bg = {0.08, 0.12, 0.20, 0.9},
    energy_fill = {0.30, 0.60, 1.0, 1.0},
    
    xp_bg = {0.15, 0.14, 0.08, 0.9},
    xp_fill = {0.90, 0.85, 0.30, 1.0},
    
    ammo_bg = {0.12, 0.12, 0.12, 0.9},
    ammo_fill = {0.70, 0.70, 0.75, 1.0},
    ammo_empty = {0.30, 0.30, 0.30, 0.7},
    
    -- Slots
    slot_empty = {0.12, 0.12, 0.14, 0.8},
    slot_filled = {0.22, 0.22, 0.26, 0.95},
    slot_selected = {0.30, 0.45, 0.60, 1.0},
    slot_border = {0.35, 0.35, 0.40, 1.0},
    slot_border_selected = {0.50, 0.75, 1.0, 1.0},
    
    -- Tooltip
    tooltip_bg = {0.10, 0.10, 0.12, 0.95},
    tooltip_border = {0.40, 0.40, 0.45, 1.0},
}

-------------------------------------------
-- Animation Timings (seconds)
-------------------------------------------
theme.animation = {
    hover_duration = 0.12,      -- Button hover transition
    press_duration = 0.06,      -- Button press flash
    fade_duration = 0.20,       -- Panel fade in/out
    slide_duration = 0.25,      -- Panel slide in/out
    bar_fill_duration = 0.15,   -- Progress bar fill transition
    tooltip_delay = 0.30,       -- Delay before tooltip appears
    tooltip_fade = 0.10,        -- Tooltip fade duration
}

-------------------------------------------
-- Sizes (in logical pixels)
-------------------------------------------
theme.sizes = {
    -- Borders
    border_thin = 1,
    border_normal = 2,
    
    -- Corner radius (for future 9-patch)
    corner_radius = 3,
    
    -- Padding
    padding_small = 4,
    padding_normal = 8,
    padding_large = 12,
    
    -- Buttons
    button_height = 24,
    button_min_width = 60,
    
    -- Bars
    bar_height = 8,
    bar_height_large = 12,
    
    -- Slots
    slot_size = 32,
    slot_spacing = 4,
    
    -- Text
    line_height = 14,
    
    -- Tooltip
    tooltip_max_width = 200,
}

-------------------------------------------
-- Easing Functions
-------------------------------------------
theme.easing = {}

--- Linear easing
function theme.easing.linear(t)
    return t
end

--- Ease out quad (decelerating)
function theme.easing.outQuad(t)
    return 1 - (1 - t) * (1 - t)
end

--- Ease in quad (accelerating)
function theme.easing.inQuad(t)
    return t * t
end

--- Ease out cubic
function theme.easing.outCubic(t)
    return 1 - math.pow(1 - t, 3)
end

--- Ease in out quad
function theme.easing.inOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - math.pow(-2 * t + 2, 2) / 2
    end
end

--- Ease out back (slight overshoot)
function theme.easing.outBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

-------------------------------------------
-- Helper Functions
-------------------------------------------

--- Interpolate between two colors
---@param c1 table Color 1 {r, g, b, a}
---@param c2 table Color 2 {r, g, b, a}
---@param t number Interpolation factor 0-1
---@return table Interpolated color
function theme.lerpColor(c1, c2, t)
    t = math.max(0, math.min(1, t))
    return {
        c1[1] + (c2[1] - c1[1]) * t,
        c1[2] + (c2[2] - c1[2]) * t,
        c1[3] + (c2[3] - c1[3]) * t,
        (c1[4] or 1) + ((c2[4] or 1) - (c1[4] or 1)) * t
    }
end

--- Apply color to love.graphics
---@param color table Color table {r, g, b, a}
function theme.setColor(color)
    if not love or not love.graphics then return end
    love.graphics.setColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

--- Get a slightly lighter version of a color
---@param color table Original color
---@param amount number Amount to lighten (0-1)
---@return table Lightened color
function theme.lighten(color, amount)
    amount = amount or 0.1
    return {
        math.min(1, color[1] + amount),
        math.min(1, color[2] + amount),
        math.min(1, color[3] + amount),
        color[4] or 1
    }
end

--- Get a slightly darker version of a color
---@param color table Original color
---@param amount number Amount to darken (0-1)
---@return table Darkened color
function theme.darken(color, amount)
    amount = amount or 0.1
    return {
        math.max(0, color[1] - amount),
        math.max(0, color[2] - amount),
        math.max(0, color[3] - amount),
        color[4] or 1
    }
end

return theme
