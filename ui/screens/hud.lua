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
    
    -- Ability Slots (1, 2, 3, 4)
    local abilities = {'1', '2', '3', '4'} 
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
            sublabel = key,
            cornerRadius = 4
        })
        parent:addChild(slot)
        widgets.abilitySlots[i] = slot -- Keyed by index 1-4
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
    -- Default: 2 slots (ranged, melee). 3rd slot (extra) is conditional.
    local slotCount = 2  -- Only 2 by default
    local slotW = 90
    local weaponTotalW = slotCount * slotW + (slotCount - 1) * gap
    local weaponStartX = startX - weaponTotalW - 20
    local weaponY = endY - 50 -- Slightly higher
    
    widgets.weaponSlots = {}
    for i = 1, slotCount do
        local wx = weaponStartX + (i-1) * (slotW + gap)
        local slotH = 50
        
        local panel = ui.Panel.new({
            x = wx, y = weaponY,
            w = slotW, h = slotH,
            bgColor = {0.1, 0.1, 0.1, 0.6},
            borderColor = {0.3, 0.3, 0.3, 1},
            borderWidth = 1,
            cornerRadius = 4
        })
        parent:addChild(panel)

        local slotName = (i == 1 and "PRIMARY") or "MELEE"
        local label = ui.Text.new({
            x = 4, y = 2,
            text = (i == 1 and "F") or "E", -- F to cycle, E for quick melee
            color = theme.colors.text_dim,
            font = theme.getFont('small')
        })
        panel:addChild(label)
        
        local name = ui.Text.new({
            x = 16, y = 4, w = 70,
            text = slotName,
            color = theme.colors.text
        })
        panel:addChild(name)
        
        -- Ammo display: horizontal layout
        local ammo = ui.Text.new({
            x = 4, y = 22, w = 82,
            text = "--/--",
            color = theme.colors.text_dim
        })
        panel:addChild(ammo)
        
        -- Reserve display below
        local reserve = ui.Text.new({
            x = 4, y = 36, w = 82,
            text = "",
            color = {0.6, 0.7, 0.8, 0.8},
            font = theme.getFont('small')
        })
        panel:addChild(reserve)
        
        widgets.weaponSlots[i] = {
            panel = panel,
            name = name,
            ammo = ammo,
            reserve = reserve
        }
    end
end

local function buildObjectiveFrame(gameState, parent)
    -- Objective panel below the wave/room info (draw.lua shows room at Y=40)
    local panelW = 320
    local panelH = 20
    local panel = ui.Panel.new({
        x = LAYOUT.objX - panelW/2, y = 60,  -- Below wave info
        w = panelW, h = panelH,
        bgColor = {0, 0, 0, 0.4},  -- Slight background for readability
        cornerRadius = 4
    })
    parent:addChild(panel)
    
    widgets.objectiveText = ui.Text.new({
        x = 0, y = 2, w = panelW,
        text = "",
        align = 'center',
        color = {1, 1, 1, 0.9},
        shadow = true,
        font = theme.getFont('small')
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
                -- draw.lua 1476: t = dash.rechargeTimer. ratio = t/cd.
                
                -- Recharge timer counts UP from 0 to cd (see player.tickDashRecharge)
                local ratio = t / cd

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
        
        -- Ability Slots (updated for index 1-4)
        local abilitiesLib = require('abilities')
        for i, slot in pairs(widgets.abilitySlots) do
            local def = abilitiesLib.getAbilityDef(gameState, i)
            local cd = p.abilityCooldowns and p.abilityCooldowns[i] or 0
            
            if cd > 0 then
                slot.iconColor = {0.5, 0.5, 0.5, 0.5}
            else
                slot.iconColor = {1, 1, 1, 1}
            end
        end
        
        -- Weapon Slots
        local inv = gameState.inventory or {}
        local activeSlot = inv.activeSlot or 'ranged'
        
        for i, slotData in pairs(widgets.weaponSlots) do
            local slotKey = 'ranged'
            if i == 2 then slotKey = 'melee' end
            if i == 3 then slotKey = 'extra' end
            
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
                
                -- Ammo: Magazine on first line, Reserve below
                if weaponInst.magazine then
                    slotData.ammo:setText(string.format("%d / %d", weaponInst.magazine, weaponInst.maxMagazine or weaponInst.magazine))
                    if slotData.reserve then
                        slotData.reserve:setText(string.format("Reserve: %d", weaponInst.reserve or 0))
                    end
                else
                    slotData.ammo:setText("∞")
                    if slotData.reserve then
                        slotData.reserve:setText("")
                    end
                end
            else
                 slotData.name:setText("Empty")
                 slotData.ammo:setText("")
                 if slotData.reserve then
                     slotData.reserve:setText("")
                 end
            end
        end
    end
    
    -- Mission Objective (based on rooms mode mission type)
    if widgets.objectiveText and widgets.objectivePanel then
        local r = gameState.rooms or {}
        local missionType = r.missionType or 'exterminate'
        local phase = r.phase or 'init'
        
        -- Only show objective during active gameplay phases
        if phase == 'doors' or phase == 'between_rooms' or phase == 'init' then
            widgets.objectivePanel.visible = false
        else
            widgets.objectivePanel.visible = true
            
            local objText = ""
            local objColor = {1, 1, 1, 0.9}
            
            if missionType == 'exterminate' then
                local alive = 0
                for _, e in ipairs(gameState.enemies or {}) do
                    if e and (e.health or e.hp or 0) > 0 and not e.isDummy then
                        alive = alive + 1
                    end
                end
                objText = string.format("歼灭: 消灭所有敌人 (%d)", alive)
                objColor = {1.0, 0.6, 0.5, 1}
            elseif missionType == 'defense' then
                local obj = r.defenseObjective
                if obj then
                    local hpPct = math.floor((obj.hp / obj.maxHp) * 100)
                    objText = string.format("防御: 保护目标 (HP: %d%%)", hpPct)
                else
                    objText = "防御: 保护目标"
                end
                objColor = {0.5, 0.85, 1.0, 1}
            elseif missionType == 'survival' then
                local remaining = math.max(0, (r.survivalTarget or 60) - (r.survivalTimer or 0))
                local lifeSupport = r.lifeSupport or 100
                objText = string.format("生存: %d秒 | 生命支援: %.0f%%", math.ceil(remaining), lifeSupport)
                objColor = {0.5, 1.0, 0.6, 1}
            end
            
            widgets.objectiveText:setText(objText)
            widgets.objectiveText.color = objColor
        end
    end
end
-------------------------------------------
-- draw is handled by ui.draw()
-------------------------------------------

function hud.keypressed(key) return false end

return hud
