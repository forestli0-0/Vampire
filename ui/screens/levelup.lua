-- Level Up Screen
-- Replaces legacy draw.lua rendering
local ui = require('ui')
local theme = ui.theme
local upgrades = require('upgrades')

local levelupScreen = {}

local root = nil
local state = nil
local cards = {}
local swapCards = {}

-- Layout constants
local LAYOUT = {
    screenW = 640,
    screenH = 360,
    cardW = 180,
    cardH = 240,
    cardSpacing = 20,
    titleY = 40,
    cardsY = 80
}

-------------------------------------------
-- Upgrade Card Widget
-------------------------------------------
local UpgradeCard = setmetatable({}, {__index = ui.Panel})
UpgradeCard.__index = UpgradeCard

function UpgradeCard.new(opts)
    opts = opts or {}
    opts.w = opts.w or LAYOUT.cardW
    opts.h = opts.h or LAYOUT.cardH
    opts.bgColor = {0.1, 0.1, 0.12, 0.95}
    opts.borderColor = {0.3, 0.3, 0.3, 1}
    opts.borderWidth = 1
    opts.cornerRadius = 4
    
    local self = setmetatable(ui.Panel.new(opts), UpgradeCard)
    
    self.option = opts.option
    self.index = opts.index
    self.selected = false
    self.hoverT = 0
    
    self:buildContent()
    return self
end

function UpgradeCard:buildContent()
    local opt = self.option
    local w, h = self.w, self.h
    local pad = 12
    
    -- Title
    local title = ui.Text.new({
        x = pad, y = pad, w = w - pad*2,
        text = opt.name or "Upgrade",
        color = theme.colors.accent,
        align = 'center',
        font = theme.getFont('large')
    })
    self:addChild(title)
    
    -- Description
    local desc = ui.Text.new({
        x = pad, y = 50, w = w - pad*2,
        text = opt.desc or "",
        color = theme.colors.text,
        align = 'left',
        wrap = true
    })
    self:addChild(desc)
    
    -- Current Level Info
    local levelText = "New!"
    if opt.type == 'weapon' and state.inventory.weapons[opt.key] then
        levelText = "Current Lv: " .. tostring(state.inventory.weapons[opt.key].level or 1)
    elseif opt.type == 'mod' then
        local count = 0
        for _, m in ipairs((state.runMods and state.runMods.inventory) or {}) do
            if m.key == opt.key then count = count + 1 end
        end
        if count > 0 then
            levelText = "Owned x" .. tostring(count)
        end
    end
    
    local levelInfo = ui.Text.new({
        x = pad, y = h - 30, w = w - pad*2,
        text = levelText,
        color = theme.colors.text_dim,
        align = 'center'
    })
    self:addChild(levelInfo)
    
    -- Key Hint (1, 2, 3)
    local hint = ui.Text.new({
        x = w - 20, y = 4,
        text = tostring(self.index),
        color = {1, 1, 1, 0.3},
        font = theme.getFont('large')
    })
    self:addChild(hint)
end

function UpgradeCard:update(dt)
    ui.Panel.update(self, dt)
    
    local targetHover = (self.hovered or self.focused) and 1 or 0
    self.hoverT = self.hoverT + (targetHover - self.hoverT) * math.min(1, dt * 10)
    
    -- Visual update based on hover
    if self.hoverT > 0.01 then
        self.borderColor = theme.lerpColor({0.3, 0.3, 0.3, 1}, theme.colors.accent, self.hoverT)
        self.bgColor = theme.lerpColor({0.1, 0.1, 0.12, 0.95}, {0.15, 0.15, 0.2, 0.95}, self.hoverT)
    else
        self.borderColor = {0.3, 0.3, 0.3, 1}
        self.bgColor = {0.1, 0.1, 0.12, 0.95}
    end
end


-------------------------------------------
-- Main Screen Logic
-------------------------------------------

function levelupScreen.init(gameState)
    state = gameState
    levelupScreen.rebuild(gameState)
end

function levelupScreen.rebuild(gameState)
    state = gameState
    
    root = ui.Widget.new({x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH})
    
    -- Dark overlay
    local bg = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH,
        bgColor = {0, 0, 0, 0.85}
    })
    root:addChild(bg)
    
    -- Title
    local titleText = "LEVEL UP!"
    if state.pendingWeaponSwap then
        titleText = "WEAPON LIMIT REACHED - SELECT TO REPLACE"
    elseif state.activeUpgradeRequest and (state.activeUpgradeRequest.mode == 'mod' or state.activeUpgradeRequest.reason == 'mod_drop') then
        titleText = "CHOOSE MOD"
    end
    
    local title = ui.Text.new({
        x = 0, y = LAYOUT.titleY, w = LAYOUT.screenW,
        text = titleText,
        color = theme.colors.title,
        align = 'center',
        font = theme.getFont('title'),
        outline = true
    })
    root:addChild(title)
    
    -- Cards
    cards = {}
    local options = state.pendingWeaponSwap and upgrades.getWeaponKeys(state) or state.upgradeOptions
    -- Wait, if pendingWeaponSwap, we need to show existing weapons to replace
    -- If normal, we show options
    
    if state.pendingWeaponSwap then
        -- Weapon swap flow
        -- Show currently equipped weapons to replace
        local weaponKeys = {}
        for k, _ in pairs(state.inventory.weapons or {}) do table.insert(weaponKeys, k) end
        table.sort(weaponKeys)
        
        local totalW = #weaponKeys * (LAYOUT.cardW + LAYOUT.cardSpacing) - LAYOUT.cardSpacing
        local startX = (LAYOUT.screenW - totalW) / 2
        
        for i, key in ipairs(weaponKeys) do
            local def = state.catalog[key]
            local inv = state.inventory.weapons[key]
            local opt = {
                name = def.name or key,
                desc = "Lv " .. (inv.level or 1) .. "\nClick to replace with new weapon.",
                type = 'weapon',
                key = key
            }
            
            local card = UpgradeCard.new({
                x = startX + (i-1) * (LAYOUT.cardW + LAYOUT.cardSpacing),
                y = LAYOUT.cardsY,
                option = opt,
                index = i
            })
            
            card:on('click', function()
                levelupScreen.selectOption(i)
            end)
            
            root:addChild(card)
            table.insert(cards, card)
        end
        
        -- Cancel button
        local cancelBtn = ui.Button.new({
            x = (LAYOUT.screenW - 200) / 2,
            y = LAYOUT.screenH - 60,
            w = 200, h = 40,
            text = "Cancel (0)",
            color = theme.colors.danger
        })
        cancelBtn:on('click', function()
             state.pendingWeaponSwap = nil
             levelupScreen.rebuild(state)
        end)
        root:addChild(cancelBtn)
        
    else
        -- Normal upgrade flow
        local totalW = #state.upgradeOptions * (LAYOUT.cardW + LAYOUT.cardSpacing) - LAYOUT.cardSpacing
        local startX = (LAYOUT.screenW - totalW) / 2
        
        for i, opt in ipairs(state.upgradeOptions) do
            local card = UpgradeCard.new({
                x = startX + (i-1) * (LAYOUT.cardW + LAYOUT.cardSpacing),
                y = LAYOUT.cardsY,
                option = opt,
                index = i
            })
            
            card:on('click', function()
                levelupScreen.selectOption(i)
            end)
            
            root:addChild(card)
            table.insert(cards, card)
        end
    end
    
    ui.core.setRoot(root)
end

function levelupScreen.selectOption(index)
    local key = tostring(index)
    -- Simulate key press logic which main.lua handles
    -- Or better, refactor logic here?
    -- For now, let's keep logic in main.lua but trigger it via simulating input or direct call
    -- But main.lua handles logic in keypressed.
    -- We can just call the logic directly if we extract it, but it's embedded.
    -- Let's replicate the logic here or call a helper.
    
    -- Ideally, main.lua delegates to this screen.
    -- But currently main.lua has the logic inline.
    -- We should move the logic here.
    
    levelupScreen.applySelection(index)
end

function levelupScreen.applySelection(idx)
    local upgrades = require('upgrades')
    
    if state.pendingWeaponSwap then
         -- Handle swap
         local weaponKeys = upgrades.getWeaponKeys(state)
         local oldKey = weaponKeys[idx]
         if oldKey then
             state.inventory.weapons[oldKey] = nil
             upgrades.applyUpgrade(state, state.pendingWeaponSwap.opt)
             levelupScreen.finalize()
         end
         return
    end
    
    if idx >= 1 and idx <= #state.upgradeOptions then
        local opt = state.upgradeOptions[idx]
        if opt and opt.type == 'weapon' and not opt.evolveFrom and not state.inventory.weapons[opt.key] then
            local maxWeapons = upgrades.getMaxWeapons(state)
            if maxWeapons > 0 and upgrades.countWeapons(state) >= maxWeapons then
                state.pendingWeaponSwap = {opt = opt}
                levelupScreen.rebuild(state)
                return
            end
        end
        upgrades.applyUpgrade(state, opt)
        levelupScreen.finalize()
    end
end

function levelupScreen.finalize()
    local upgrades = require('upgrades')
    state.pendingWeaponSwap = nil
    if state.pendingLevelUps > 0 then
        state.pendingLevelUps = state.pendingLevelUps - 1
        local nextReq = nil
        if state.pendingUpgradeRequests and #state.pendingUpgradeRequests > 0 then
            nextReq = table.remove(state.pendingUpgradeRequests, 1)
        end
        state.activeUpgradeRequest = nextReq
        upgrades.generateUpgradeOptions(state, nextReq)
        -- Remain in LEVEL UP state, rebuild
        levelupScreen.rebuild(state)
    else
        state.activeUpgradeRequest = nil
        state.pendingUpgradeRequests = {}
        state.gameState = 'PLAYING'
        ui.core.setRoot(nil) -- Clear UI root
        
        -- Re-enable HUD
        local hud = require('ui.screens.hud')
        if hud.rebuild then hud.rebuild(state) end
    end
end

function levelupScreen.update(dt)
    if ui.core.getRoot() == root then
        ui.update(dt)
    end
end

function levelupScreen.draw()
    if ui.core.getRoot() == root then
        ui.draw()
    end
end

function levelupScreen.keypressed(key)
    if not (ui.core.getRoot() == root) then return false end
    
    -- Handle number keys
    local idx = tonumber(key)
    if idx then
        levelupScreen.selectOption(idx)
        return true
    end
    
    if key == 'escape' or key == 'backspace' then
        if state.pendingWeaponSwap then
             state.pendingWeaponSwap = nil
             levelupScreen.rebuild(state)
             return true
        end
    end
    
    return ui.keypressed(key)
end

function levelupScreen.isActive()
    return ui.core.getRoot() == root and root ~= nil
end

return levelupScreen
