-- Shop Screen
-- Replaces legacy draw.lua rendering and main.lua input logic
local ui = require('ui')
local theme = ui.theme

local shopScreen = {}

local root = nil
local state = nil

-- Layout constants
local LAYOUT = {
    screenW = 640,
    screenH = 360,
    titleY = 40,
    listY = 100,
    itemH = 60,
    itemGap = 10,
    itemW = 400
}

-------------------------------------------
-- Shop Item Widget
-------------------------------------------
local ShopItem = setmetatable({}, {__index = ui.Panel})
ShopItem.__index = ShopItem

function ShopItem.new(opts)
    opts = opts or {}
    opts.w = opts.w or LAYOUT.itemW
    opts.h = opts.h or LAYOUT.itemH
    
    local self = setmetatable(ui.Panel.new(opts), ShopItem)
    
    self.option = opts.option
    self.index = opts.index
    self.shop = opts.shop
    self.state = opts.state
    self.hoverT = 0
    
    self:buildContent()
    return self
end

function ShopItem:buildContent()
    local opt = self.option
    local w, h = self.w, self.h
    local pad = 10
    
    -- Check Status
    local gold = math.floor(self.state.runCurrency or 0)
    local cost = math.floor(opt.cost or 0)
    local affordable = (gold >= cost)
    local enabled = (opt.enabled == nil) and true or (opt.enabled == true)
    
    self.active = enabled and affordable
    self.affordable = affordable
    self.enabled = enabled
    
    self.bgColor = {0.15, 0.15, 0.18, 0.9}
    if not self.active then
         self.bgColor = {0.1, 0.1, 0.1, 0.8}
    end
    self.borderColor = {0.3, 0.3, 0.3, 1}
    self.borderWidth = 1
    self.cornerRadius = 4
    
    -- Name (Index. Name)
    local name = opt.name or opt.id or "Item"
    local nameColor = theme.colors.text
    if not enabled then nameColor = {0.5, 0.5, 0.5, 1}
    elseif not affordable then nameColor = {0.7, 0.3, 0.3, 1} end
    
    local title = ui.Text.new({
        x = pad, y = 8, w = w - 100,
        text = string.format("%d. %s", self.index, name),
        color = nameColor,
        font = theme.getFont('default')
    })
    self:addChild(title)
    
    -- Cost
    local costColor = theme.colors.gold
    if not affordable then costColor = {0.8, 0.2, 0.2, 1} end
    
    local costText = ui.Text.new({
        x = w - 80, y = 8, w = 70,
        text = tostring(cost),
        color = costColor,
        align = 'right',
        font = theme.getFont('default')
    })
    self:addChild(costText)
    
    -- Description
    local desc = ui.Text.new({
        x = pad + 16, y = 30, w = w - pad*2 - 16,
        text = opt.desc or "",
        color = theme.colors.text_dim,
        font = theme.getFont('small')
    })
    self:addChild(desc)
    
    -- Disabled Reason
    if not enabled and opt.disabledReason then
        local reason = ui.Text.new({
            x = pad + 16, y = h - 18, w = w - pad*2,
            text = opt.disabledReason,
            color = theme.colors.danger,
            font = theme.getFont('small')
        })
        self:addChild(reason)
    end
end

function ShopItem:update(dt)
    ui.Panel.update(self, dt)
    
    if not self.active then return end
    
    local targetHover = (self.hovered or self.focused) and 1 or 0
    self.hoverT = self.hoverT + (targetHover - self.hoverT) * math.min(1, dt * 10)
    
    if self.hoverT > 0.01 then
        self.borderColor = theme.lerpColor({0.3, 0.3, 0.3, 1}, theme.colors.gold, self.hoverT)
        self.bgColor = theme.lerpColor({0.15, 0.15, 0.18, 0.9}, {0.2, 0.2, 0.25, 0.95}, self.hoverT)
    else
        self.borderColor = {0.3, 0.3, 0.3, 1}
        self.bgColor = {0.15, 0.15, 0.18, 0.9}
    end
end

-------------------------------------------
-- Main Screen Logic
-------------------------------------------

function shopScreen.init(gameState)
    state = gameState
    shopScreen.rebuild(gameState)
end

function shopScreen.isActive()
    return ui.core.getRoot() == root and root ~= nil
end

function shopScreen.rebuild(gameState)
    state = gameState
    
    root = ui.Widget.new({x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH})
    
    -- Dark overlay
    local bg = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH,
        bgColor = {0, 0, 0, 0.9}
    })
    root:addChild(bg)
    
    -- Title
    local title = ui.Text.new({
        x = 0, y = LAYOUT.titleY, w = LAYOUT.screenW,
        text = "SHOP",
        color = theme.colors.gold,
        align = 'center',
        font = theme.getFont('title'),
        outline = true
    })
    root:addChild(title)
    
    -- Gold Display
    local gold = math.floor(state.runCurrency or 0)
    local goldText = ui.Text.new({
        x = 0, y = LAYOUT.titleY + 40, w = LAYOUT.screenW,
        text = string.format("GOLD: %d", gold),
        color = theme.colors.text,
        align = 'center'
    })
    root:addChild(goldText)
    
    -- Shop List
    local shop = state.shop or {}
    local options = shop.options or {}
    local startY = LAYOUT.listY
    local itemX = (LAYOUT.screenW - LAYOUT.itemW) / 2
    
    -- Simple scroll container? Widget doesn't have scroll yet.
    -- Limit to max items or just flow? The legacy code limited to 6.
    -- We can list them all if we adjust height, or just list first 6 for now to match legacy.
    
    local maxShow = math.min(6, #options)
    
    for i = 1, maxShow do
        local opt = options[i]
        local y = startY + (i - 1) * (LAYOUT.itemH + LAYOUT.itemGap)
        
        local item = ShopItem.new({
            x = itemX, y = y,
            option = opt,
            index = i,
            shop = shop,
            state = state
        })
        
        item:on('click', function()
            shopScreen.buyItem(i)
        end)
        
        root:addChild(item)
    end
    
    -- Message
    if shop.message then
        local msg = ui.Text.new({
            x = 0, y = LAYOUT.screenH - 100, w = LAYOUT.screenW,
            text = shop.message,
            color = theme.colors.accent,
            align = 'center'
        })
        root:addChild(msg)
    end
    
    -- Instructions
    local help = ui.Text.new({
        x = 0, y = LAYOUT.screenH - 40, w = LAYOUT.screenW,
        text = "Press 1-"..maxShow.." to buy, 0/ESC to leave",
        color = theme.colors.text_dim,
        align = 'center'
    })
    root:addChild(help)
    
    ui.core.setRoot(root)
end

function shopScreen.buyItem(idx)
    local shop = state.shop or {}
    if idx and shop.options and idx >= 1 and idx <= #shop.options then
        local opt = shop.options[idx]
        local gold = math.floor(state.runCurrency or 0)
        local cost = math.floor(opt.cost or 0)
        local affordable = (gold >= cost)
        local enabled = (opt.enabled == nil) and true or (opt.enabled == true)

        if enabled and affordable then
             if opt.onBuy then
                 opt.onBuy(state, opt, shop)
                 -- Refresh UI to update gold/status
                 shopScreen.rebuild(state)
             end
        end
    end
end

function shopScreen.close()
    state.shop = nil
    state.gameState = 'PLAYING'
    ui.core.setRoot(nil)
    
    -- Re-enable HUD
    local hud = require('ui.screens.hud')
    if hud.rebuild then hud.rebuild(state) end
end

function shopScreen.keypressed(key)
    if not (ui.core.getRoot() == root) then return false end
    
    if key == 'escape' or key == 'backspace' or key == '0' then
        shopScreen.close()
        return true
    end
    
    local idx = tonumber(key)
    if idx then
        shopScreen.buyItem(idx)
        return true
    end
    
    return ui.keypressed(key)
end

return shopScreen
