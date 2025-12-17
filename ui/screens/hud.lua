local ui = require('ui')
local theme = require('ui.theme')
local scaling = require('ui.scaling')

local hud = {}
local root = nil
local state = nil

-- References to active widgets for updating
local widgets = {
    hpBar = nil,
    shieldBar = nil,
    energyBar = nil,
    xpBar = nil,
    levelText = nil,
    goldText = nil,
    dashBar = nil,
    dashText = nil,
    weaponSlots = {},
    abilitySlots = {},
    objectiveText = nil,
    objectivePanel = nil
}

-------------------------------------------
-- Constants
-------------------------------------------

local LAYOUT = {
    -- Player Frame (Top Left)
    playerX = 20,
    playerY = 20,
    barWidth = 200,
    barHeight = 10,
    
    -- Combat Frame (Bottom Right)
    combatX = 640 - 20,
    combatY = 360 - 20,
    
    -- Objective (Top Center)
    objX = 320,
    objY = 10,
    
    -- Colors
    hpColor = {0.8, 0.2, 0.2, 1},
    shieldColor = {0.2, 0.6, 0.9, 1},
    energyColor = {0.3, 0.4, 0.8, 1},
    xpColor = {0.9, 0.8, 0.2, 1},
    goldColor = {1, 0.9, 0.4, 1},
    dashColor = {0.5, 0.8, 0.9, 1}
}

-------------------------------------------
-- Builders
-------------------------------------------

local function buildPlayerFrame(gameState, parent)
    local x, y = LAYOUT.playerX, LAYOUT.playerY
    
    -- Name / Level
    local name = gameState.player and gameState.player.class or "Tenno"
    local level = gameState.player and gameState.player.level or 1
    
    local nameText = ui.Text.new({
        x = x, y = y,
        text = string.upper(name) .. " [Rank " .. level .. "]",
        color = theme.colors.text_dim,
        font = theme.getFont('small')
    })
    parent:addChild(nameText)
    widgets.levelText = nameText
    y = y + 14
    
    -- Shield Bar
    widgets.shieldBar = ui.Bar.new({
        x = x, y = y,
        w = LAYOUT.barWidth, h = 6,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.shieldColor,
        bgColor = {0.1, 0.1, 0.2, 0.5},
        cornerRadius = 1
    })
    parent:addChild(widgets.shieldBar)
    y = y + 8
    
    -- HP Bar
    widgets.hpBar = ui.Bar.new({
        x = x, y = y,
        w = LAYOUT.barWidth, h = 10,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.hpColor,
        bgColor = {0.2, 0.1, 0.1, 0.5},
        cornerRadius = 2
    })
    parent:addChild(widgets.hpBar)
    y = y + 14
    
    -- XP Bar (Thin line)
    widgets.xpBar = ui.Bar.new({
        x = x, y = y,
        w = LAYOUT.barWidth, h = 2,
        value = 0, maxValue = 100,
        fillColor = LAYOUT.xpColor,
        bgColor = {0,0,0,0}
    })
    parent:addChild(widgets.xpBar)
    y = y + 6
    
    -- Dash / Stamina
    widgets.dashText = ui.Text.new({
        x = x, y = y,
        text = "DASH",
        color = {0.8, 0.9, 1, 0.8},
        font = theme.getFont('small')
    })
    parent:addChild(widgets.dashText)
    
    widgets.dashBar = ui.Bar.new({
        x = x + 36, y = y + 2,
        w = 100, h = 4,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.dashColor,
        bgColor = {0.1, 0.1, 0.1, 0.5}
    })
    parent:addChild(widgets.dashBar)
    
    -- Gold display (below frame)
    widgets.goldText = ui.Text.new({
        x = x, y = y + 20,
        text = "GOLD 0",
        color = LAYOUT.goldColor,
        shadow = true
    })
    parent:addChild(widgets.goldText)
end

local function buildCombatFrame(gameState, parent)
    local endX = LAYOUT.combatX
    local endY = LAYOUT.combatY
    
    -- Ability Slots
    local abilities = {'q', 'e', 'c', 'v'} 
    local slotSize = 40
    local gap = 8
    local totalW = #abilities * slotSize + (#abilities - 1) * gap
    local startX = endX - totalW
    local startY = endY - slotSize
    
    widgets.abilitySlots = {}
    for i, key in ipairs(abilities) do
        local sx = startX + (i-1) * (slotSize + gap)
        
        local slot = ui.Slot.new({
            x = sx, y = startY,
            w = slotSize, h = slotSize,
            content = nil,
            sublabel = string.upper(key),
            cornerRadius = 4
        })
        parent:addChild(slot)
        widgets.abilitySlots[key] = slot
    end
    
    -- Energy Bar (Above abilities)
    local energyY = startY - 10
    widgets.energyBar = ui.Bar.new({
        x = startX, y = energyY,
        w = totalW, h = 4,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.energyColor,
        bgColor = {0.1, 0.1, 0.2, 0.5},
        cornerRadius = 2
    })
    parent:addChild(widgets.energyBar)
    
    -- Weapon Slots (To the left of abilities)
    local weaponTotalW = 160 -- Estimated width for 2 weapons
    local weaponStartX = startX - weaponTotalW - 20
    local weaponY = endY - 50 -- Slightly higher
    
    widgets.weaponSlots = {}
    -- Assuming 2 slots: ranged (1), melee (2)
    local weaponKeys = {'1', '2'}
    for i, key in ipairs(weaponKeys) do
        local wx = weaponStartX + (i-1) * (70 + gap)
        local slotH = 50
        
        local panel = ui.Panel.new({
            x = wx, y = weaponY,
            w = 70, h = slotH,
            bgColor = {0.1, 0.1, 0.1, 0.6},
            borderColor = {0.3, 0.3, 0.3, 1},
            borderWidth = 1,
            cornerRadius = 4
        })
        parent:addChild(panel)
        
        local label = ui.Text.new({
            x = 4, y = 2,
            text = key,
            color = {1, 1, 1, 0.5},
            font = theme.getFont('small')
        })
        panel:addChild(label)
        
        local name = ui.Text.new({
            x = 16, y = 4, w = 50,
            text = "Weapon",
            color = theme.colors.text
        })
        panel:addChild(name)
        
        local ammo = ui.Text.new({
            x = 4, y = 28,
            text = "--/--",
            color = theme.colors.text_dim
        })
        panel:addChild(ammo)
        
        widgets.weaponSlots[i] = {
            panel = panel,
            name = name,
            ammo = ammo
        }
    end
end

local function buildObjectiveFrame(gameState, parent)
    -- Simple top center text
    local panelW = 300
    local panel = ui.Panel.new({
        x = LAYOUT.objX - panelW/2, y = LAYOUT.objY,
        w = panelW, h = 24,
        bgColor = {0, 0, 0, 0} -- Transparent
    })
    parent:addChild(panel)
    
    widgets.objectiveText = ui.Text.new({
        x = 0, y = 0, w = panelW,
        text = "OBJECTIVE",
        align = 'center',
        color = {1, 1, 1, 0.9},
        shadow = true
    })
    panel:addChild(widgets.objectiveText)
    widgets.objectivePanel = panel
end

-------------------------------------------
-- Public API
-------------------------------------------

function hud.init(gameState)
    hud.rebuild(gameState)
end

function hud.rebuild(gameState)
    state = gameState
    
    root = ui.Widget.new({x = 0, y = 0, w = 640, h = 360})
    root.transparent = true 
    
    -- Make root passthrough (only children can be hit)
    -- This prevents the full-screen HUD root from stealing focus and consuming input
    function root:contains(x, y)
        return false
    end 
    
    buildPlayerFrame(gameState, root)
    buildCombatFrame(gameState, root)
    buildObjectiveFrame(gameState, root)
    
    ui.core.setRoot(root)
end

function hud.update(gameState, dt)
    if not root then return end
    
    if gameState.player then
        local p = gameState.player
        local stats = p.stats or {}
        
        -- HP/Shield/XP/Energy
        if widgets.hpBar then
            widgets.hpBar.value = p.hp
            widgets.hpBar.maxValue = stats.maxHp or 100
        end
        if widgets.shieldBar then
            -- Shield logic if exists, otherwise 0
            widgets.shieldBar.value = p.shield or 0
            widgets.shieldBar.maxValue = stats.maxShield or 100
        end
        if widgets.xpBar then
            widgets.xpBar.value = p.xp or 0
            widgets.xpBar.maxValue = p.xpToNextLevel or 100
        end
        if widgets.energyBar then
            widgets.energyBar.value = p.energy or 0
            widgets.energyBar.maxValue = stats.maxEnergy or 100
        end
        
        -- Level Text
        if widgets.levelText then
            widgets.levelText:setText(string.upper(p.class or "Tenno") .. " [Rank " .. (p.level or 1) .. "]")
        end
        
        -- Gold
        if widgets.goldText then
            widgets.goldText:setText(string.format("GOLD %d", math.floor(gameState.runCurrency or 0)))
        end
        
        -- Dash
        if widgets.dashBar then
            local dash = p.dash or {}
            local max = (stats and stats.dashCharges) or dash.maxCharges or 3
            local current = dash.charges or 0
            if current < max then
                -- Show recharge progress for next charge
                local cd = (stats and stats.dashCooldown) or 1
                local t = dash.rechargeTimer or 0
                local ratio = 1 - (t / cd) -- Timer counts down usually? Or up?
                -- Check draw.lua logic: t counts UP to cd? No, Step 1465 says t / cd.
                -- Usually rechargeTimer counts down? 
                -- draw.lua 1476: t = dash.rechargeTimer. ratio = t/cd.
                
                -- Let's assume ratio is correct.
                -- Map to partial bar? Complex. Just show total %?
                -- Let's show current charges as chunks? Bar widget doesn't support chunks yet.
                -- Just show total fill.
                local totalVal = current + ratio
                widgets.dashBar.value = totalVal
                widgets.dashBar.maxValue = max
            else
                widgets.dashBar.value = max
                widgets.dashBar.maxValue = max
            end
            
            widgets.dashText:setText(string.format("DASH %d/%d", current, max))
        end
        
        -- Ability Slots
        local abilitiesLib = require('abilities')
        for key, slot in pairs(widgets.abilitySlots) do
            local abilityId = abilitiesLib.getAbilityForKey(key)
            local def = abilityId and abilitiesLib.catalog[abilityId]
            local cd = p.abilityCooldowns and p.abilityCooldowns[abilityId] or 0
            
            if cd > 0 then
                slot.iconColor = {0.5, 0.5, 0.5, 0.5}
                -- Could show text CD here if Slot supported it
            else
                slot.iconColor = {1, 1, 1, 1}
            end
            -- TODO: Set icon if available
        end
        
        -- Weapon Slots
        local inv = gameState.inventory or {}
        local activeSlot = inv.activeSlot or 'ranged'
        
        for i, slotData in pairs(widgets.weaponSlots) do
            local slotKey = (i == 1) and 'ranged' or 'melee'
            local isActive = (slotKey == activeSlot)
            
            -- Highlight active
            if isActive then
                slotData.panel.borderColor = {0.3, 0.6, 0.9, 1}
                slotData.panel.bgColor = {0.2, 0.3, 0.5, 0.8}
            else
                slotData.panel.borderColor = {0.3, 0.3, 0.3, 1}
                slotData.panel.bgColor = {0.1, 0.1, 0.1, 0.6}
            end
            
            -- Update Info
            local weaponInst = inv.weaponSlots and inv.weaponSlots[slotKey]
            if weaponInst then
                local def = gameState.catalog and gameState.catalog[weaponInst.key]
                slotData.name:setText(def and def.name or weaponInst.key)
                
                -- Ammo
                if weaponInst.magazine then
                    slotData.ammo:setText(string.format("%d / %d", weaponInst.magazine, weaponInst.reserve or 0))
                else
                    slotData.ammo:setText("∞")
                end
            else
                 slotData.name:setText("Empty")
                 slotData.ammo:setText("")
            end
        end
    end
    
    -- Mission Objective
    if widgets.objectiveText then
        local st = gameState.campaign and gameState.campaign.stageType or 'boss'
        if st == 'boss' then
            widgets.objectiveText:setText("OBJECTIVE: DEFEAT THE TARGET")
        else
            widgets.objectiveText:setText("OBJECTIVE: SURVIVE / EXTRACT")
        end
    end
end
-------------------------------------------
-- draw is handled by ui.draw()
-------------------------------------------

function hud.keypressed(key) return false end

return hud
