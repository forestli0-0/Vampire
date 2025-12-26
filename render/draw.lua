local weapons = require('gameplay.weapons')
local enemies = require('gameplay.enemies')
local vfx = require('render.vfx')
local pipeline = require('render.pipeline')
local weaponTrail = require('render.weapon_trail')  -- 武器拖影系统
local animTransform = require('render.animation_transform')  -- 挤压拉伸变换
local shaders = require('render.shaders')
local ui = require('ui')

local draw = {}

local function getOutlineShader()
    return shaders.getOutlineShader()
end

local function getDashTrailShader()
    return shaders.getDashTrailShader()
end

local function getHitFlashShader()
    return shaders.getHitFlashShader()
end

local function drawOutlineAnimFallback(anim, x, y, r, sx, sy, t)
    t = t or 1
    local offsets = {
        {-t, 0}, {t, 0}, {0, -t}, {0, t},
        {-t, -t}, {-t, t}, {t, -t}, {t, t},
    }
    for _, o in ipairs(offsets) do
        anim:draw(x + o[1], y + o[2], r or 0, sx or 1, sy or 1)
    end
end

local function drawOutlineAnim(anim, x, y, r, sx, sy, thicknessPx, outlineCol)
    local img = anim and anim.image
    if not img then
        love.graphics.setColor((outlineCol and outlineCol[1]) or 1, (outlineCol and outlineCol[2]) or 1, (outlineCol and outlineCol[3]) or 1, (outlineCol and outlineCol[4]) or 1)
        drawOutlineAnimFallback(anim, x, y, r, sx, sy, thicknessPx)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    local shader = getOutlineShader()
    local prevShader = love.graphics.getShader()
    local cr, cg, cb, ca = love.graphics.getColor()

    local sxv = sx or 1
    local syv = sy or 1
    local scale = math.max(math.abs(sxv), math.abs(syv))
    if scale < 1e-6 then scale = 1 end

    local t = (thicknessPx or 1) / scale
    if t < 1 then t = 1 end

    shader:send('texelSize', { 1 / img:getWidth(), 1 / img:getHeight() })
    shader:send('thickness', t)
    shader:send('outlineColor', outlineCol or { 1, 1, 1, 1 })

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    anim:draw(x, y, r or 0, sxv, syv)
    love.graphics.setShader(prevShader)
    love.graphics.setColor(cr, cg, cb, ca)
end

local function drawOutlineRect(x, y, size, t)
    t = t or 1
    love.graphics.rectangle('fill', x - size / 2 - t, y - size / 2 - t, size + t * 2, size + t * 2)
end

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function drawStatsPanel(state)
    if not state or state.gameState ~= 'PLAYING' then return end

    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local panelW = 260
    local x = 10
    local y = 60
    local lineH = 16
    local padding = 8

    local lines = {}
    local p = state.player or {}
    local ps = p.stats or {}

    table.insert(lines, "PLAYER")
    table.insert(lines, string.format("HP: %d / %d", math.floor(p.hp or 0), math.floor(p.maxHp or 0)))
    local moveSpeed = (ps.moveSpeed or 0) * (p.moveSpeedBuffMult or 1)
    table.insert(lines, string.format("Move: %.0f", moveSpeed))
    table.insert(lines, string.format("Might: x%.2f", ps.might or 1))
    table.insert(lines, string.format("Cooldown: x%.2f", ps.cooldown or 1))
    table.insert(lines, string.format("Area: x%.2f", ps.area or 1))
    table.insert(lines, string.format("Proj Speed: x%.2f", ps.speed or 1))
    table.insert(lines, string.format("Pickup: %.0f", ps.pickupRange or 0))
    table.insert(lines, string.format("Armor: %.0f", ps.armor or 0))
    table.insert(lines, string.format("Regen: %.2f/s", ps.regen or 0))

    table.insert(lines, "")
    table.insert(lines, "WEAPONS")
    local weaponKeys = {}
    for k, _ in pairs(state.inventory.weapons or {}) do table.insert(weaponKeys, k) end
    table.sort(weaponKeys)
    for _, key in ipairs(weaponKeys) do
        local invW = state.inventory.weapons[key]
        local def = state.catalog[key] or {}
        local name = def.name or key
        local lv = invW.level or 1
        local stats = weapons.calculateStats(state, key) or invW.stats or {}
        local elems = stats.elements or {}
        local elemStr = (#elems > 0) and (" [" .. table.concat(elems, "+") .. "]") or ""
        local crit = stats.critChance or 0
        local critMult = stats.critMultiplier or 1.5
        local statusChance = stats.statusChance or 0
        local extra = ""
        if crit > 0 or statusChance > 0 then
            extra = string.format(" C%.0f%% x%.1f S%.0f%%", crit * 100, critMult, statusChance * 100)
        end
        table.insert(lines, string.format("%s Lv%d%s%s", name, lv, elemStr, extra))
    end
    if #weaponKeys == 0 then table.insert(lines, "None") end

    table.insert(lines, "")
    table.insert(lines, "PASSIVES")
    local passiveKeys = {}
    for k, _ in pairs(state.inventory.passives or {}) do table.insert(passiveKeys, k) end
    table.sort(passiveKeys)
    for _, key in ipairs(passiveKeys) do
        local lv = state.inventory.passives[key] or 0
        local def = state.catalog[key] or {}
        local name = def.name or key
        table.insert(lines, string.format("%s Lv%d", name, lv))
    end
    if #passiveKeys == 0 then table.insert(lines, "None") end

    table.insert(lines, "")
    table.insert(lines, "MODS")
    local weaponKeysForMods = {}
    for k, _ in pairs(state.inventory.weapons or {}) do table.insert(weaponKeysForMods, k) end
    table.sort(weaponKeysForMods)
    for _, weaponKey in ipairs(weaponKeysForMods) do
        local wDef = state.catalog[weaponKey] or {}
        local weaponName = wDef.name or weaponKey

        local wm = state.inventory.weaponMods and state.inventory.weaponMods[weaponKey]
        local mods = (wm and wm.mods) or {}
        local order = (wm and wm.modOrder) or {}

        local modList = {}
        local seen = {}
        if #order > 0 then
            for _, modKey in ipairs(order) do
                local lv = mods[modKey] or 0
                if lv > 0 and not seen[modKey] then
                    local mDef = state.catalog[modKey] or {}
                    local modName = mDef.name or modKey
                    table.insert(modList, string.format("%s R%d", modName, lv))
                    seen[modKey] = true
                end
            end
        end

        local extra = {}
        for modKey, lv in pairs(mods) do
            if (lv or 0) > 0 and not seen[modKey] then
                table.insert(extra, modKey)
            end
        end
        table.sort(extra)
        for _, modKey in ipairs(extra) do
            local lv = mods[modKey] or 0
            if lv > 0 then
                local mDef = state.catalog[modKey] or {}
                local modName = mDef.name or modKey
                table.insert(modList, string.format("%s R%d", modName, lv))
            end
        end

        local modsText = "None"
        if #modList > 0 then
            modsText = table.concat(modList, " | ")
        end
        table.insert(lines, string.format("%s: %s", weaponName, modsText))
    end
    if #weaponKeysForMods == 0 then table.insert(lines, "None") end

    table.insert(lines, "")
    table.insert(lines, "AUGMENTS")
    local augmentKeys = {}
    for k, lv in pairs(state.inventory.augments or {}) do
        if (lv or 0) > 0 then table.insert(augmentKeys, k) end
    end
    table.sort(augmentKeys)
    for _, key in ipairs(augmentKeys) do
        local lv = (state.inventory.augments and state.inventory.augments[key]) or 0
        local def = state.catalog[key] or {}
        local name = def.name or key
        table.insert(lines, string.format("%s Lv%d", name, lv))
    end
    if #augmentKeys == 0 then table.insert(lines, "None") end

    local target = enemies and enemies.findNearestEnemy and enemies.findNearestEnemy(state, 999999) or nil
    if target and target.status then
        local st = target.status
        table.insert(lines, "")
        table.insert(lines, "TARGET")
        local kind = target.kind or "enemy"
        local hp = math.floor(target.health or target.hp or 0)
        local maxHp = math.floor(target.maxHealth or target.maxHp or 0)
        local sh = math.floor(target.shield or 0)
        local maxSh = math.floor(target.maxShield or 0)
        local armor = math.floor(target.armor or 0)
        local baseArmor = math.floor(target.baseArmor or armor or 0)
        local header = string.format("%s  HP %d/%d  SH %d/%d  ARM %d/%d", kind, hp, maxHp, sh, maxSh, armor, baseArmor)
        table.insert(lines, header)
        local hType = target.healthType or 'FLESH'
        local sType = target.shieldType or (maxSh > 0 and 'SHIELD' or nil)
        local aType = target.armorType or (baseArmor > 0 and 'FERRITE_ARMOR' or nil)
        local typeStr = string.format("Types: H=%s  S=%s  A=%s", hType, sType or '-', aType or '-')
        table.insert(lines, typeStr)

        if st.frozen and (st.frozenTimer or 0) > 0 then
            table.insert(lines, string.format("Frozen: %.1fs", st.frozenTimer or 0))
        end
        if (st.coldStacks or 0) > 0 or (st.coldTimer or 0) > 0 then
            table.insert(lines, string.format("Cold: stacks %d  %.1fs", st.coldStacks or 0, st.coldTimer or 0))
        end
        if (st.heatTimer or 0) > 0 then
            table.insert(lines, string.format("Heat: %.1fs  DPS %.1f", st.heatTimer or 0, st.heatDps or 0))
        end
        if (st.burnTimer or 0) > 0 then
            table.insert(lines, string.format("Burn(Oil): %.1fs  DPS %.1f", st.burnTimer or 0, st.burnDps or 0))
        end
        if (st.toxinTimer or 0) > 0 then
            table.insert(lines, string.format("Toxin: %.1fs  DPS %.1f", st.toxinTimer or 0, st.toxinDps or 0))
        end
        if st.static and (st.staticTimer or 0) > 0 then
            table.insert(lines, string.format("Electric: %.1fs  DPS %.1f  R %.0f", st.staticTimer or 0, st.staticDps or 0, st.staticRadius or 0))
        end
        if (st.bleedStacks or 0) > 0 or (st.bleedTimer or 0) > 0 then
            table.insert(lines, string.format("Bleed: stacks %d  %.1fs  DPS %.1f", st.bleedStacks or 0, st.bleedTimer or 0, st.bleedDps or 0))
        end
        if (st.magneticStacks or 0) > 0 or (st.magneticTimer or 0) > 0 then
            table.insert(lines, string.format("Magnetic: stacks %d  %.1fs  x%.2f", st.magneticStacks or 0, st.magneticTimer or 0, st.magneticMult or 1))
        end
        if (st.viralStacks or 0) > 0 or (st.viralTimer or 0) > 0 then
            local stacks = math.min(10, st.viralStacks or 0)
            local bonus = math.min(2.25, 0.75 + stacks * 0.25)
            local mult = 1 + bonus
            table.insert(lines, string.format("Viral: stacks %d  %.1fs  x%.2f", st.viralStacks or 0, st.viralTimer or 0, mult))
        end
        if (st.corrosiveStacks or 0) > 0 then
            table.insert(lines, string.format("Corrosive: stacks %d", st.corrosiveStacks or 0))
        end
        if (st.punctureStacks or 0) > 0 or (st.punctureTimer or 0) > 0 then
            table.insert(lines, string.format("Puncture: stacks %d  %.1fs", st.punctureStacks or 0, st.punctureTimer or 0))
        end
        if (st.blastStacks or 0) > 0 or (st.blastTimer or 0) > 0 then
            table.insert(lines, string.format("Blast: stacks %d  %.1fs", st.blastStacks or 0, st.blastTimer or 0))
        end
        if (st.gasTimer or 0) > 0 then
            table.insert(lines, string.format("Gas: %.1fs  DPS %.1f  R %.0f", st.gasTimer or 0, st.gasDps or 0, st.gasRadius or 0))
        end
        if (st.radiationTimer or 0) > 0 then
            table.insert(lines, string.format("Radiation: %.1fs", st.radiationTimer or 0))
        end
        if st.oiled and (st.oiledTimer or 0) > 0 then
            table.insert(lines, string.format("Oiled: %.1fs", st.oiledTimer or 0))
        end
        if (st.impactTimer or 0) > 0 then
            table.insert(lines, string.format("Impact Stun: %.1fs", st.impactTimer or 0))
        end
    end

    local panelH = padding * 2 + (#lines * lineH)
    panelH = math.min(panelH, h - y - 10)

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle('fill', x, y, panelW, panelH, 6, 6)
    love.graphics.setColor(1, 1, 1)

    local ty = y + padding
    for _, line in ipairs(lines) do
        if line == "" then
            ty = ty + lineH * 0.5
        else
            love.graphics.print(line, x + padding, ty)
            ty = ty + lineH
        end
        if ty > y + panelH - lineH then break end
    end
end

local function drawPetPanel(state)
    if not state or state.gameState ~= 'PLAYING' then return end

    local ps = state.pets or {}
    local pet = (ps.list and ps.list[1]) or nil
    local lostKey = ps.lostKey

    if not pet and not lostKey then return end

    local w, _ = love.graphics.getWidth(), love.graphics.getHeight()
    local panelW = 240
    local x = w - panelW - 10
    local y = 60
    local padding = 8
    local lineH = 16

    local title = "PET"
    local lines = {}
    local bar = nil
    local extra = nil

    if pet then
        local def = state.catalog and state.catalog[pet.key]
        local name = (def and def.name) or pet.name or pet.key
        local module = pet.module or 'default'
        local mode = (pet.mode == 'hold') and "HOLD" or "FOLLOW"
        local lvl = pet.level or ps.runLevel or 1

        table.insert(lines, string.format("%s  Lv%d", name, lvl))
        table.insert(lines, string.format("Module: %s    Mode: %s", tostring(module), mode))

        local ups = ps.upgrades or {}
        local summary = {}
        local pwr = ups.pet_upgrade_power or 0
        local oc = ups.pet_upgrade_overclock or 0
        local st = ups.pet_upgrade_status or 0
        local vit = ups.pet_upgrade_vitality or 0
        if pwr > 0 then table.insert(summary, "Power " .. tostring(pwr)) end
        if oc > 0 then table.insert(summary, "Overclock " .. tostring(oc)) end
        if st > 0 then table.insert(summary, "Catalyst " .. tostring(st)) end
        if vit > 0 then table.insert(summary, "Vitality " .. tostring(vit)) end
        if #summary > 0 then
            table.insert(lines, "Upgrades: " .. table.concat(summary, "  "))
        end

        local hp = pet.hp or 0
        local maxHp = pet.maxHp or 1
        local hpRatio = (maxHp > 0) and clamp01(hp / maxHp) or 0
        bar = {label = string.format("HP %d/%d", math.floor(hp), math.floor(maxHp)), ratio = hpRatio, kind = 'hp'}

        if pet.downed then
            local bleedout = (ps.bleedoutTime or 10.0) - (pet.downedTimer or 0)
            if bleedout < 0 then bleedout = 0 end
            extra = {kind = 'downed', bleedout = bleedout}
            local hold = ps.reviveHoldTime or 1.1
            local prog = (hold > 0) and clamp01((pet.reviveProgress or 0) / hold) or 0
            extra.reviveRatio = prog
        else
            local cd = pet.abilityCooldown or 3.0
            local t = pet.abilityTimer or 0
            local ratio = 0
            if cd > 0 then
                ratio = clamp01(1 - (t / cd))
            end
            extra = {kind = 'ability', ratio = ratio, time = math.max(0, t)}
        end
    else
        title = "PET LOST"
        local def = state.catalog and state.catalog[lostKey]
        local name = (def and def.name) or tostring(lostKey)
        table.insert(lines, name)
        table.insert(lines, "Find an EVENT room to revive")
    end

    local panelH = padding * 2 + (#lines + 1) * lineH + 26
    if extra and extra.kind == 'downed' then
        panelH = panelH + 22
    end

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle('fill', x, y, panelW, panelH, 6, 6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(title, x + padding, y + padding)

    local ty = y + padding + lineH
    for _, line in ipairs(lines) do
        love.graphics.setColor(0.9, 0.9, 0.95, 1)
        love.graphics.print(line, x + padding, ty)
        ty = ty + lineH
    end

    -- HP bar
    if bar then
        local barX, barY = x + padding, ty + 2
        local barW, barH = panelW - padding * 2, 8
        love.graphics.setColor(0.1, 0.1, 0.1, 0.75)
        love.graphics.rectangle('fill', barX, barY, barW, barH)

        local fillCol = {0.75, 0.95, 1.0}
        if pet and pet.key == 'pet_corrosive' then fillCol = {0.55, 1.0, 0.55} end
        if pet and pet.key == 'pet_guardian' then fillCol = {0.8, 0.9, 1.0} end
        if pet and pet.downed then fillCol = {1.0, 0.35, 0.35} end

        love.graphics.setColor(fillCol[1], fillCol[2], fillCol[3], 0.9)
        love.graphics.rectangle('fill', barX, barY, barW * bar.ratio, barH)

        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.print(bar.label, barX, barY + 10)
        ty = barY + 10 + lineH
    end

    -- Extra status (ability / downed)
    if extra and extra.kind == 'ability' then
        local barX, barY = x + padding, ty + 2
        local barW, barH = panelW - padding * 2, 6
        love.graphics.setColor(0.1, 0.1, 0.1, 0.65)
        love.graphics.rectangle('fill', barX, barY, barW, barH)
        love.graphics.setColor(0.9, 0.85, 0.45, 0.9)
        love.graphics.rectangle('fill', barX, barY, barW * clamp01(extra.ratio or 0), barH)
        love.graphics.setColor(0.85, 0.85, 0.85, 0.95)
        love.graphics.print(string.format("Ability %.1fs", extra.time or 0), barX, barY + 8)
    elseif extra and extra.kind == 'downed' then
        love.graphics.setColor(1, 0.45, 0.45, 0.95)
        love.graphics.print(string.format("DOWN  Bleedout %.1fs", extra.bleedout or 0), x + padding, ty + 2)

        local barX, barY = x + padding, ty + 20
        local barW, barH = panelW - padding * 2, 6
        love.graphics.setColor(0.1, 0.1, 0.1, 0.65)
        love.graphics.rectangle('fill', barX, barY, barW, barH)
        love.graphics.setColor(0.55, 1.0, 0.55, 0.9)
        love.graphics.rectangle('fill', barX, barY, barW * clamp01(extra.reviveRatio or 0), barH)
        love.graphics.setColor(0.85, 0.85, 0.85, 0.95)
        love.graphics.print("Hold E to revive", barX, barY + 8)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function draw.renderWorld(state)
    love.graphics.setFont(state.font)
    love.graphics.push()
    if state.shakeAmount and state.shakeAmount > 0 then
        local shakeX = state._shakeOffsetX or (love.math.random() * state.shakeAmount)
        local shakeY = state._shakeOffsetY or (love.math.random() * state.shakeAmount)
        love.graphics.translate(shakeX, shakeY)
    end
    love.graphics.translate(-state.camera.x, -state.camera.y)

    -- Background: Infinite tiling for Survival, or Void for Arena
    local world = state.world
    local isArena = (world and world.enabled and world.tiles)
    
    if isArena then
        -- === ARENA MODE: Void outside, grass inside ===
        if state.runMode == 'hub' then
            -- print("DEBUG: Hub Rendering. isArena=" .. tostring(isArena) .. " tiles=" .. tostring(#world.tiles))
        end
        
        -- 1. First, draw a HUGE void rectangle covering everything visible and beyond
        -- This ensures anything outside the arena is pure black
        love.graphics.setColor(0.02, 0.02, 0.03, 1)
        local camX, camY = state.camera.x or 0, state.camera.y or 0
        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.rectangle('fill', camX - 100, camY - 100, sw + 200, sh + 200)
        
        local bg = state.bgTile
        local ts = world.tileSize
        local minCx = math.max(1, math.floor(camX / ts) + 1)
        local maxCx = math.min(world.w, math.floor((camX + sw) / ts) + 2)
        local minCy = math.max(1, math.floor(camY / ts) + 1)
        local maxCy = math.min(world.h, math.floor((camY + sh) / ts) + 2)

        for cy = minCy, maxCy do
            local row = (cy - 1) * world.w
            local tileY = (cy - 1) * ts
            for cx = minCx, maxCx do
                local tileIdx = row + cx
                if tileIdx >= 1 and tileIdx <= #world.tiles then
                    local tile = world.tiles[tileIdx]
                    local tileX = (cx - 1) * ts
                    
                    if tile == 0 then -- 基础地板 (暗灰色金属面板)
                        love.graphics.setColor(0.15, 0.16, 0.18, 1)
                        love.graphics.rectangle('fill', tileX, tileY, ts, ts)
                        love.graphics.setColor(1, 1, 1, 0.05)
                        love.graphics.rectangle('line', tileX, tileY, ts, ts)
                    elseif tile == 2 then -- 格栅地板
                        love.graphics.setColor(0.12, 0.13, 0.15, 1)
                        love.graphics.rectangle('fill', tileX, tileY, ts, ts)
                        love.graphics.setColor(0.3, 0.4, 0.5, 0.3)
                        for i = 2, ts - 2, 6 do
                            love.graphics.rectangle('fill', tileX + i, tileY + 2, 2, ts - 4)
                        end
                    elseif tile == 3 then -- 能源走廊
                        love.graphics.setColor(0.1, 0.12, 0.15, 1)
                        love.graphics.rectangle('fill', tileX, tileY, ts, ts)
                        local pulse = 0.4 + 0.3 * math.sin(love.timer.getTime() * 4)
                        love.graphics.setColor(0.2, 0.5, 1, 0.2 * pulse)
                        love.graphics.rectangle('fill', tileX + 4, tileY + 4, ts - 8, ts - 8)
                        love.graphics.setColor(0.3, 0.7, 1, 0.4 * pulse)
                        love.graphics.rectangle('line', tileX + 4, tileY + 4, ts - 8, ts - 8)
                    elseif tile == 1 then -- 墙壁 (厚重金属)
                        love.graphics.setColor(0.08, 0.09, 0.12, 1)
                        love.graphics.rectangle('fill', tileX, tileY, ts, ts)
                        -- 增加金属面板细节
                        love.graphics.setColor(1, 1, 1, 0.08)
                        love.graphics.rectangle('line', tileX + 2, tileY + 2, ts - 4, ts - 4)
                        love.graphics.setColor(0.4, 0.5, 0.6, 0.2)
                        love.graphics.rectangle('fill', tileX + 6, tileY + 6, ts - 12, ts - 12)
                    end
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)

    else
        -- === SURVIVAL MODE: Infinite grass tiling ===
        local bg = state.bgTile
        if bg then
            local tileW, tileH = bg.w, bg.h
            local offsetX = state.camera.x % tileW
            local offsetY = state.camera.y % tileH
            local startX = state.camera.x - offsetX - tileW
            local startY = state.camera.y - offsetY - tileH
            local w, h = love.graphics.getWidth(), love.graphics.getHeight()
            for x = startX, state.camera.x + w + tileW, tileW do
                for y = startY, state.camera.y + h + tileH, tileH do
                    love.graphics.draw(bg.image, x, y)
                end
            end
        end
    end

    -- 大蒜圈 / 灵魂吞噬者圈（统一用 shader 范围场，避免占位素材 + bloom 过曝）
    if state.inventory.weapons.garlic or state.inventory.weapons.soul_eater then
        local key = state.inventory.weapons.soul_eater and 'soul_eater' or 'garlic'
        local gStats = weapons.calculateStats(state, key) or state.inventory.weapons[key].stats
        local r = (gStats.radius or 0) * (gStats.area or 1) * (state.player.stats.area or 1)

        local pulse = 0
        if key == 'soul_eater' then
            pulse = (math.sin(love.timer.getTime() * 5) + 1) * 0.5
        end

        vfx.drawAreaField(key, state.player.x, state.player.y, r, 1 + pulse * 0.35, { alpha = 1 })

        -- 轻描边保证可读性（不走 add）
        if key == 'soul_eater' then
            love.graphics.setColor(0.95, 0.75, 0.95, 0.18)
            love.graphics.circle('line', state.player.x, state.player.y, r * 0.92)
        else
            love.graphics.setColor(0.9, 0.9, 0.9, 0.14)
            love.graphics.circle('line', state.player.x, state.player.y, r)
        end
        love.graphics.setColor(1, 1, 1)
    end

    -- 持续性范围场（如油地面覆盖）：绘制在实体之前
    if state.areaFields then
        for _, a in ipairs(state.areaFields) do
            local dur = a.duration or 2.0
            local p = (dur > 0) and math.max(0, math.min(1, (a.t or 0) / dur)) or 1
            local fade = 1 - p
            local alpha = 0.35 + 0.65 * fade
            local intensity = (a.intensity or 1) * (0.85 + 0.35 * fade)
            vfx.drawAreaField(a.kind or 'oil', a.x, a.y, a.radius or 0, intensity, { alpha = alpha })
        end
        love.graphics.setColor(1, 1, 1)
    end

    -- 敌方攻击预警（红圈/红线）：绘制在实体之前
    if state.telegraphs then
        for _, tg in ipairs(state.telegraphs) do
            local dur = tg.duration or 0.6
            local p = (dur > 0) and math.max(0, math.min(1, (tg.t or 0) / dur)) or 1
            local intensity = (tg.intensity or 1) * (0.65 + 0.75 * p)

            if tg.shape == 'circle' then
                local r = tg.radius or 0
                if r > 0 then
                    local kind = tg.kind or 'telegraph'
                    local col = {1, 0.22, 0.22}
                    if kind == 'danger' then col = {1.0, 0.55, 0.22} end

                    -- base field (subtle), then a radial fill to indicate cast progress (full = impact)
                    vfx.drawAreaField(kind, tg.x, tg.y, r, intensity, { alpha = 0.06 + 0.18 * p, alphaCap = 0.55, edgeSoft = 0.52 })

                    love.graphics.setColor(col[1], col[2], col[3], 0.08 + 0.22 * p)
                    local fillR = r * 0.98 * p
                    if fillR > 0.5 then
                        love.graphics.circle('fill', tg.x, tg.y, fillR)
                    end

                    love.graphics.setColor(col[1], col[2], col[3], 0.22 + 0.48 * p)
                    love.graphics.setLineWidth(2)
                    love.graphics.circle('line', tg.x, tg.y, r)
                    love.graphics.setLineWidth(1)
                end
            elseif tg.shape == 'line' then
                local x1, y1, x2, y2 = tg.x1, tg.y1, tg.x2, tg.y2
                local dx = (x2 or 0) - (x1 or 0)
                local dy = (y2 or 0) - (y1 or 0)
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0.001 then
                    local ang = math.atan2(dy, dx)
                    local w = tg.width or 28
                    local col = tg.color or {1, 0.22, 0.22}
                    local bgA = 0.05 + 0.10 * p
                    local fillA = 0.14 + 0.34 * p
                    local lineA = 0.22 + 0.62 * p
                    love.graphics.push()
                    love.graphics.translate(x1, y1)
                    love.graphics.rotate(ang)
                    love.graphics.setColor(col[1], col[2], col[3], bgA)
                    love.graphics.rectangle('fill', 0, -w / 2, len, w, w * 0.35, w * 0.35)
                    love.graphics.setColor(col[1], col[2], col[3], fillA)
                    love.graphics.rectangle('fill', 0, -w / 2, len * p, w, w * 0.35, w * 0.35)
                    love.graphics.setColor(col[1], col[2], col[3], lineA)
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle('line', 0, -w / 2, len, w, w * 0.35, w * 0.35)
                    love.graphics.setLineWidth(1)
                    love.graphics.pop()
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
    end

    -- 实体
    for _, c in ipairs(state.chests) do
        local sprite = state.pickupSprites and state.pickupSprites['chest']
        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local scale = (c.w or sw) / sw
            scale = scale * 2
            love.graphics.setColor(1,1,1)
            love.graphics.draw(sprite, c.x, c.y, 0, scale, scale, sw/2, sh/2)
        else
            love.graphics.setColor(1, 0.84, 0)
            love.graphics.rectangle('fill', c.x - c.w/2, c.y - c.h/2, c.w, c.h)
        end
    end

    -- 房间出口门（任务类型选择）
    if state.doors then
        for _, d in ipairs(state.doors) do
            -- Use mission color if available, otherwise fallback
            local col = d.missionColor or {1, 1, 1}
            local w = d.w or 54
            local h = d.h or 86
            local x = d.x or 0
            local y = d.y or 0

            -- Door background
            love.graphics.setColor(col[1], col[2], col[3], 0.75)
            love.graphics.rectangle('fill', x - w/2, y - h/2, w, h, 8, 8)
            
            -- Door border
            love.graphics.setColor(col[1], col[2], col[3], 0.95)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle('line', x - w/2, y - h/2, w, h, 8, 8)
            love.graphics.setLineWidth(1)
            
            -- Inner dark area
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.rectangle('fill', x - w/2 + 4, y - h/2 + 4, w - 8, h - 8, 4, 4)
            
            -- Mission name label above door
            love.graphics.setColor(1, 1, 1, 0.95)
            local label = d.missionName or d.missionType or "?"
            love.graphics.printf(label, x - 80, y - h/2 - 20, 160, "center")
            
            -- Mission type icon/indicator inside door
            love.graphics.setColor(col[1], col[2], col[3], 0.9)
            if d.missionType == 'exterminate' then
                -- Skull-like indicator (simple X)
                love.graphics.setLineWidth(3)
                love.graphics.line(x - 8, y - 8, x + 8, y + 8)
                love.graphics.line(x + 8, y - 8, x - 8, y + 8)
                love.graphics.setLineWidth(1)
            elseif d.missionType == 'defense' then
                -- Shield indicator (simple diamond)
                love.graphics.polygon('line', x, y - 12, x + 10, y, x, y + 12, x - 10, y)
            elseif d.missionType == 'survival' then
                -- Clock/timer indicator (circle with line)
                love.graphics.circle('line', x, y, 10)
                love.graphics.line(x, y, x, y - 8)
                love.graphics.line(x, y, x + 6, y + 4)
            end
        end
        love.graphics.setColor(1, 1, 1)
    end

    -- HUB 交互点绘制
    if state.runMode == 'hub' and state.hubInteractions then
        for _, inter in ipairs(state.hubInteractions) do
            local t = love.timer.getTime()
            local bounce = math.sin(t * 3) * 5
            local pulse = 0.7 + 0.3 * math.sin(t * 4)
            
            -- 全息基座
            love.graphics.setColor(0.2, 0.3, 0.5, 0.6)
            love.graphics.rectangle('fill', inter.x - 20, inter.y + 10, 40, 10, 4, 4)
            love.graphics.setColor(0.4, 0.7, 1.0, 0.8)
            love.graphics.rectangle('line', inter.x - 20, inter.y + 10, 40, 10, 4, 4)
            
            -- 向上散射的淡蓝色光柱
            love.graphics.setColor(0.4, 0.7, 1.0, 0.15 * pulse)
            love.graphics.polygon('fill', inter.x - 15, inter.y + 10, inter.x + 15, inter.y + 10, inter.x + 25, inter.y - 30, inter.x - 25, inter.y - 30)
            
            -- 悬浮的全息控制面板（简单的几何形状代替）
            love.graphics.push()
            love.graphics.translate(0, bounce)
            
            love.graphics.setColor(0.4, 0.7, 1.0, 0.5 * pulse)
            love.graphics.rectangle('fill', inter.x - 15, inter.y - 20, 30, 20, 2, 2)
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.rectangle('line', inter.x - 15, inter.y - 20, 30, 20, 2, 2)
            
            -- 面板上的装饰性“数据线”
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.line(inter.x - 10, inter.y - 12, inter.x + 10, inter.y - 12)
            love.graphics.line(inter.x - 10, inter.y - 8, inter.x + 4, inter.y - 8)
            
            love.graphics.pop()

            -- 接近时的发光圈
            local dx = state.player.x - inter.x
            local dy = state.player.y - inter.y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist < inter.radius + 20 then
                love.graphics.setColor(0.4, 0.8, 1.0, 0.4 * pulse)
                love.graphics.circle('line', inter.x, inter.y + 15, 30 + 5 * pulse)
                
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setFont(ui.theme.getFont('small'))
                love.graphics.printf(inter.label, inter.x - 100, inter.y - 50 + bounce, 200, 'center')
            end
        end
    end

    -- 地面道具
    for _, item in ipairs(state.floorPickups) do
        -- Flashing effect for items about to despawn
        if item.flashing then
            local flash = math.sin(love.timer.getTime() * 12) > 0
            if not flash then goto skip_pickup end
        end
        
        local sprite = state.pickupSprites and state.pickupSprites[item.kind]
        
        local isGlow = (item.kind == 'magnet' or item.kind == 'chicken' or item.kind == 'chest_xp' or item.kind == 'chest_reward' or item.kind == 'pet_contract' or item.kind == 'pet_revive' or item.kind == 'shop_terminal' or item.kind == 'pet_module_chip' or item.kind == 'pet_upgrade_chip')
        if isGlow then love.graphics.setBlendMode("add") end

        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local size = (item.size or 16)
            local scale = size / sw
            local scale = scale * 2
            love.graphics.setColor(1,1,1)
            love.graphics.draw(sprite, item.x, item.y, 0, scale, scale, sw/2, sh/2)
        else
            if item.kind == 'chicken' then
                love.graphics.setColor(1, 0.9, 0.6) -- Brighter gold
                love.graphics.circle('fill', item.x, item.y, 8)
                love.graphics.setColor(1, 1, 0.9)
                love.graphics.circle('fill', item.x, item.y - 2, 5)
                love.graphics.setColor(0.8, 0.4, 0.2)
                love.graphics.rectangle('fill', item.x - 2, item.y + 4, 4, 4)
            elseif item.kind == 'magnet' then
                love.graphics.setColor(0.2, 0.8, 1) -- Brighter blue
                love.graphics.setLineWidth(3)
                love.graphics.arc('line', 'open', item.x, item.y, 8, math.pi * 0.2, math.pi * 1.8)
                love.graphics.line(item.x - 6, item.y + 6, item.x - 2, item.y + 6)
                love.graphics.line(item.x + 2, item.y + 6, item.x + 6, item.y + 6)
                love.graphics.setLineWidth(1)
            elseif item.kind == 'shop_terminal' then
                love.graphics.setColor(0.35, 0.95, 1.0, 0.95)
                love.graphics.circle('line', item.x, item.y, 12)
                love.graphics.circle('fill', item.x, item.y, 6)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.printf("SHOP", item.x - 40, item.y + 12, 80, "center")
            elseif item.kind == 'pet_module_chip' or item.kind == 'pet_upgrade_chip' then
                local isModule = (item.kind == 'pet_module_chip')
                if isModule then
                    love.graphics.setColor(0.7, 0.95, 1.0, 0.95)
                else
                    love.graphics.setColor(1.0, 0.92, 0.55, 0.95)
                end
                love.graphics.circle('line', item.x, item.y, 11)
                love.graphics.circle('fill', item.x, item.y, 5)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.printf(isModule and "MOD" or "UP", item.x - 30, item.y + 12, 60, "center")
            elseif item.kind == 'pet_contract' or item.kind == 'pet_revive' then
                local rk = item.roomKind
                if item.kind == 'pet_revive' then
                    love.graphics.setColor(0.55, 1.0, 0.55, 0.95)
                elseif rk == 'shop' then
                    love.graphics.setColor(0.35, 0.95, 1.0, 0.9)
                else
                    love.graphics.setColor(0.95, 0.7, 1.0, 0.9)
                end
                love.graphics.circle('line', item.x, item.y, 10)
                love.graphics.circle('fill', item.x, item.y, 6)
                love.graphics.setColor(1, 1, 1, 0.9)
                local label = (item.kind == 'pet_revive') and "REVIVE" or "PET"
                if item.kind == 'pet_contract' and rk == 'shop' then label = "SWAP" end
                love.graphics.printf(label, item.x - 40, item.y + 12, 80, "center")
            elseif item.kind == 'health_orb' then
                -- WF-style health orb (green glow)
                love.graphics.setColor(0.2, 0.9, 0.3, 0.95)
                love.graphics.circle('fill', item.x, item.y, 7)
                love.graphics.setColor(0.4, 1, 0.5, 0.6)
                love.graphics.circle('line', item.x, item.y, 9)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.circle('fill', item.x - 2, item.y - 2, 2)
            elseif item.kind == 'energy_orb' then
                -- WF-style energy orb (blue glow)
                love.graphics.setColor(0.2, 0.5, 1, 0.95)
                love.graphics.circle('fill', item.x, item.y, 7)
                love.graphics.setColor(0.4, 0.7, 1, 0.6)
                love.graphics.circle('line', item.x, item.y, 9)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.circle('fill', item.x - 2, item.y - 2, 2)
            elseif item.kind == 'mod_card' then
                -- WF-style MOD card drop (gold shine)
                love.graphics.setColor(0.95, 0.85, 0.2, 0.95)
                love.graphics.rectangle('fill', item.x - 6, item.y - 8, 12, 16, 2, 2)
                love.graphics.setColor(1, 0.95, 0.5, 0.7)
                love.graphics.rectangle('line', item.x - 7, item.y - 9, 14, 18, 2, 2)
                love.graphics.setColor(0.3, 0.25, 0.1, 0.9)
                love.graphics.line(item.x - 3, item.y - 4, item.x + 3, item.y - 4)
                love.graphics.line(item.x - 3, item.y, item.x + 3, item.y)
                love.graphics.line(item.x - 2, item.y + 4, item.x + 2, item.y + 4)
            elseif item.kind == 'ammo' then
                -- Ammo Crate (placeholder box)
                love.graphics.setColor(0.5, 0.55, 0.45, 0.95)
                love.graphics.rectangle('fill', item.x - 10, item.y - 8, 20, 16, 3, 3)
                love.graphics.setColor(0.7, 0.75, 0.6, 0.9)
                love.graphics.rectangle('line', item.x - 11, item.y - 9, 22, 18, 3, 3)
                love.graphics.setColor(0.2, 0.2, 0.15, 0.9)
                love.graphics.setLineWidth(2)
                love.graphics.line(item.x - 7, item.y - 2, item.x + 7, item.y - 2)
                love.graphics.line(item.x - 5, item.y + 2, item.x + 5, item.y + 2)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(0.9, 0.95, 0.8, 0.85)
                love.graphics.printf("AMMO", item.x - 30, item.y + 10, 60, "center")
            end
        end
        if isGlow then love.graphics.setBlendMode("alpha") end
        ::skip_pickup::
    end

    -- 经验宝石 (DEPRECATED - Legacy VS system, kept for backward compatibility)
    for _, g in ipairs(state.gems or {}) do
        local sprite = state.pickupSprites and state.pickupSprites['gem']
        
        love.graphics.setBlendMode("add")
        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local baseSize = 8
            local scale = (state.pickupSpriteScale and state.pickupSpriteScale['gem']) or (baseSize / sw)
            love.graphics.setColor(1,1,1)
            love.graphics.draw(sprite, g.x, g.y, 0, scale, scale, sw/2, sh/2)
        else
            love.graphics.setColor(0, 0.8, 1) -- Brighter blue for bloom
            love.graphics.rectangle('fill', g.x-3, g.y-3, 6, 6)
        end
        love.graphics.setBlendMode("alpha")
    end

    for _, e in ipairs(state.enemies) do
        local visualSize = e.visualSize or e.size or 16  -- 使用视觉大小
        local shadowR = visualSize * 0.6
        local shadowY = shadowR * 0.4
        love.graphics.setColor(0,0,0,0.25)
        love.graphics.ellipse('fill', e.x, e.y + visualSize * 0.55, shadowR, shadowY)

        -- Outline for elites/bosses (drawn behind base, skip if dying)
        if (e.isBoss or e.isElite) and not e.isDying then
            local outlineCol
            if e.isBoss then
                outlineCol = {1, 0.6, 0.2, 0.85}
            else
                outlineCol = {1, 0.15, 0.15, 0.75}
            end
            local t = e.isBoss and 2 or 1
            
            -- 获取敌人的当前动画（使用新动画系统）
            -- 修复：使用与主体绘制相同的动画选择逻辑
            local outlineAnim = e.anim
            if not outlineAnim and state.enemyAnimSets and state.enemyAnims then
                local animKey = state.enemyAnims.getAnimKeyForType(e.kind or 'skeleton')
                local anims = state.enemyAnimSets[animKey] or state.enemyAnimSets['skeleton']
                if anims then
                    -- 根据敌人状态选择动画（与主体绘制保持一致）
                    -- Boss只在有hitAnimTimer时播放受击动画，普通敌人用flashTimer
                    local showHitAnim = false
                    if e.isBoss then
                        showHitAnim = e.hitAnimTimer and e.hitAnimTimer > 0
                    else
                        showHitAnim = e.flashTimer and e.flashTimer > 0
                    end
                    if showHitAnim then
                        outlineAnim = anims.hit or anims.move
                    elseif e.attack and e.attack.phase then
                        outlineAnim = anims.attack or anims.move
                    elseif e.isBlocking or (e.status and e.status.shielded) then
                        outlineAnim = anims.shield or anims.idle
                    elseif e.status and e.status.frozen then
                        outlineAnim = anims.idle or anims.move
                    elseif e.aiState == 'idle' then
                        outlineAnim = anims.idle or anims.move
                    else
                        outlineAnim = anims.move or anims.idle
                    end
                end
            end
            
            if outlineAnim then
                -- 计算正确的缩放（与主体绘制保持一致）
                local animKey = state.enemyAnims and state.enemyAnims.getAnimKeyForType(e.kind or 'skeleton') or 'skeleton'
                local frameSize = state.enemyAnims and state.enemyAnims.getFrameSize(animKey) or 150
                local spriteVisualHeight = frameSize * 0.27
                local targetSize = e.visualSize or e.size or 24  -- 使用视觉大小进行缩放
                local scale = targetSize / spriteVisualHeight
                local sx = (e.facing or 1) * scale
                local sy = scale
                drawOutlineAnim(outlineAnim, e.x, e.y, 0, sx, sy, t, outlineCol)
            else
                -- 回退：绘制空心轮廓矩形（而不是填充矩形）
                love.graphics.setColor(outlineCol)
                love.graphics.setLineWidth(t + 1)
                love.graphics.rectangle('line', e.x - (e.size or 16) / 2 - t, e.y - (e.size or 16) / 2 - t, (e.size or 16) + t * 2, (e.size or 16) + t * 2)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end

        local col = e.color
        if e.status then
            if e.status.frozen then
                col = {0.6, 0.8, 1}
            elseif e.status.burnTimer and e.status.burnTimer > 0 then
                local pulse = love.timer.getTime() % 0.2 < 0.1
                if pulse then col = {1, 0.2, 0.2} else col = {1, 0.4, 0.4} end
            elseif e.status.heatTimer and e.status.heatTimer > 0 then
                local pulse = love.timer.getTime() % 0.3 < 0.15
                if pulse then col = {1, 0.35, 0.2} else col = {1, 0.55, 0.35} end
            elseif e.status.blastTimer and e.status.blastTimer > 0 then
                col = {1, 0.7, 0.2}
            elseif e.status.radiationTimer and e.status.radiationTimer > 0 then
                col = {1, 1, 0.3}
            elseif e.status.gasTimer and e.status.gasTimer > 0 then
                col = {0.5, 1, 0.5}
            elseif e.status.oiled then
                col = {0.3, 0.2, 0.1}
            end
        end

        -- Hit flash: use shader if flashing
        local ft = e.flashTimer or 0
        local flashShader = nil
        if ft > 0 then
            flashShader = getHitFlashShader()
            if flashShader then
                local flashAmount = math.min(1, ft / 0.1) * 0.85  -- Strong flash, up to 85% white
                love.graphics.setShader(flashShader)
                flashShader:send('flashAmount', flashAmount)
            end
        end

        -- Base draw: 根据敌人类型选择对应的动画集
        local enemyAnimSets = state.enemyAnimSets
        local enemyAnimsMod = state.enemyAnims
        
        if enemyAnimSets and enemyAnimsMod and not e.anim then
            -- 根据敌人类型获取对应的动画集
            local animKey = enemyAnimsMod.getAnimKeyForType(e.kind or 'skeleton')
            local anims = enemyAnimSets[animKey] or enemyAnimSets['skeleton']
            
            if anims then
                -- 根据敌人状态选择动画（优先级从高到低）
                local anim = nil
                
                if e.isDying then
                    -- 死亡状态（正在播放死亡动画）
                    anim = anims.death
                else
                    -- Boss只在有hitAnimTimer时播放受击动画，普通敌人用flashTimer
                    local showHitAnim = false
                    if e.isBoss then
                        showHitAnim = e.hitAnimTimer and e.hitAnimTimer > 0
                    else
                        showHitAnim = e.flashTimer and e.flashTimer > 0
                    end
                    
                    if showHitAnim then
                        -- 受击状态 (正在闪烁)
                        anim = anims.hit
                    elseif e.attack and e.attack.phase then
                        -- 攻击状态 (任何攻击阶段)
                        anim = anims.attack
                    elseif e.isBlocking or (e.status and e.status.shielded) then
                        -- 防御状态
                        anim = anims.shield or anims.idle
                    elseif e.status and e.status.frozen then
                        -- 冻结状态 = 静止
                        anim = anims.idle or anims.move
                    elseif e.aiState == 'idle' then
                        -- 待机状态（敌人未激活）
                        anim = anims.idle or anims.move
                    else
                        -- 追击状态（aiState == 'chase' 或 nil）= 移动动画
                        anim = anims.move or anims.idle
                    end
                end
                
                -- 回退到默认动画
                if not anim then anim = anims.move or anims.idle end
                
                if anim then
                    -- 计算缩放
                    local frameSize = enemyAnimsMod.getFrameSize(animKey)
                    local spriteVisualHeight = frameSize * 0.27  -- 可见区域约占 27%
                    local targetSize = e.visualSize or e.size or 24  -- 使用视觉大小
                    local scale = targetSize / spriteVisualHeight
                    local sx = (e.facing or 1) * scale
                    local sy = scale
                    
                    love.graphics.setColor(col)
                    anim:draw(e.x, e.y, 0, sx, sy)
                end
            end
        elseif state.skeletonAnims and not e.anim then
            -- 旧版单帧格式回退
            local skeletonFrames = state.enemySprites['skeleton_frames']
            local animSpeed = 8  -- frames per second
            local numFrames = #skeletonFrames
            local timeOffset = (e.spawnTime or 0) * 0.37  -- Unique offset per enemy
            local frameIndex = math.floor((love.timer.getTime() + timeOffset) * animSpeed) % numFrames + 1
            local sprite = skeletonFrames[frameIndex]
            
            -- Calculate scale based on enemy size (skeleton base is ~24px tall)
            local baseSize = 24
            local targetSize = e.visualSize or e.size or 24  -- 使用视觉大小进行缩放
            local scale = targetSize / baseSize
            local sx = (e.facing or 1) * scale
            local sy = scale
            
            love.graphics.setColor(col)
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            love.graphics.draw(sprite, e.x, e.y, 0, sx, sy, sw/2, sh/2)
        elseif e.anim then
            love.graphics.setColor(col)
            local sx = e.facing or 1
            e.anim:draw(e.x, e.y, 0, sx, 1)
        else
            -- Fallback to rectangle if no sprite available
            love.graphics.setColor(col)
            love.graphics.rectangle('fill', e.x - e.size/2, e.y - e.size/2, e.size, e.size)
        end


        -- Reset shader after drawing
        if flashShader then
            love.graphics.setShader()
        end
        
        -- Attack windup visual indicator
        local atk = e.attack
        if atk and atk.phase == 'windup' then
            local timer = atk.timer or 0
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 12)
            local size = (e.size or 24) / 2 + 4
            
            -- Red pulsing ring around enemy during windup
            love.graphics.setColor(1, 0.2, 0.2, 0.4 + 0.3 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', e.x, e.y, size + 4 * pulse)
            
            -- Exclamation mark above enemy
            love.graphics.setColor(1, 0.3, 0.2, 0.6 + 0.4 * pulse)
            local excX, excY = e.x, e.y - (e.size or 24) / 2 - 12
            -- Use state.font to ensure Chinese font support (avoid default font)
            love.graphics.setFont(state.font)
            love.graphics.printf("!", excX - 10, excY, 20, "center")
            
            love.graphics.setLineWidth(1)
        end
        
        -- Attacking (dash/leap) visual indicator
        if atk and (atk.phase == 'dash' or atk.phase == 'leaping') then
            local size = (e.size or 24) / 2 + 6
            love.graphics.setColor(1, 0.5, 0.1, 0.6)
            love.graphics.setLineWidth(3)
            love.graphics.circle('line', e.x, e.y, size)
            love.graphics.setLineWidth(1)
        end
        
        -- === AI状态视觉反馈 ===
        -- 撤退状态：黄色脉冲光芒
        if e.aiState == 'retreat' then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 10)
            local size = (e.size or 24) / 2 + 2
            love.graphics.setColor(0.9, 0.8, 0.2, 0.3 + 0.2 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', e.x, e.y, size + 3 * pulse)
            -- 撤退方向指示线
            if e.retreatDirX and e.retreatDirY then
                local lineLen = 20
                love.graphics.setColor(0.9, 0.8, 0.2, 0.5)
                love.graphics.line(e.x, e.y, e.x + e.retreatDirX * lineLen, e.y + e.retreatDirY * lineLen)
            end
            love.graphics.setLineWidth(1)
        end
        
        -- 风筝状态：蓝色虚线圈
        if e.aiState == 'kiting' then
            local size = (e.size or 24) / 2 + 8
            love.graphics.setColor(0.4, 0.7, 1, 0.35)
            love.graphics.setLineWidth(1)
            -- 绘制虚线圈效果
            local segments = 8
            for i = 1, segments do
                local ang1 = (i - 1) / segments * math.pi * 2 + love.timer.getTime() * 2
                local ang2 = ang1 + math.pi / segments * 0.7
                love.graphics.arc('line', 'open', e.x, e.y, size, ang1, ang2)
            end
            love.graphics.setLineWidth(1)
        end
        
        -- 狂暴状态：红色火焰光环
        if e.aiState == 'berserk' then
            local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 8)
            local size = (e.size or 24) / 2 + 10
            -- 外层红色光晕
            love.graphics.setColor(1, 0.2, 0.1, 0.25 * pulse)
            love.graphics.circle('fill', e.x, e.y, size * pulse)
            -- 内层亮红圈
            love.graphics.setColor(1, 0.3, 0.1, 0.5 + 0.3 * pulse)
            love.graphics.setLineWidth(3)
            love.graphics.circle('line', e.x, e.y, size * 0.7)
            -- 火焰粒子效果（简化版）
            for i = 1, 4 do
                local ang = love.timer.getTime() * 3 + i * math.pi / 2
                local dist = size * 0.5 + size * 0.2 * math.sin(love.timer.getTime() * 6 + i)
                local fx = e.x + math.cos(ang) * dist
                local fy = e.y + math.sin(ang) * dist
                love.graphics.setColor(1, 0.5, 0.1, 0.6 * pulse)
                love.graphics.circle('fill', fx, fy, 3 + pulse * 2)
            end
            love.graphics.setLineWidth(1)
        end
        -- === END AI状态视觉反馈 ===
        
        if e.status and e.status.static then
            local r = (e.size or 16) * 0.75
            vfx.drawElectricAura(e.x, e.y, r, 0.9)

            love.graphics.setColor(1, 1, 0, 0.8)
            local lx = e.x; local ly = e.y
            love.graphics.line(lx - 4, ly - 6, lx - 1, ly - 1, lx - 6, ly + 3, lx, ly + 8, lx + 5, ly + 2)
            love.graphics.setLineWidth(1)
        end
        if e.status and e.status.blastTimer and e.status.blastTimer > 0 then
            love.graphics.setColor(1, 0.6, 0.1, 0.6)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', e.x, e.y, (e.size or 16) * 0.9)
            love.graphics.setLineWidth(1)
        end
        if e.status and e.status.gasTimer and e.status.gasTimer > 0 then
            local r = e.status.gasRadius or 100
            vfx.drawGas(e.x, e.y, r, 1)
            love.graphics.setColor(0.3, 1, 0.3, 0.45)
            love.graphics.setLineWidth(1.5)
            love.graphics.circle('line', e.x, e.y, r)
            love.graphics.setLineWidth(1)
        end
        if e.status and e.status.toxinTimer and e.status.toxinTimer > 0 then
            local r = math.max((e.size or 16) * 1.05, 16)
            vfx.drawAreaField('toxin', e.x, e.y, r, 1, { alpha = 0.75 })
            love.graphics.setColor(0.25, 0.95, 0.35, 0.32)
            love.graphics.setLineWidth(1)
            love.graphics.circle('line', e.x, e.y, r)
            love.graphics.setLineWidth(1)
        end
        if e.status and e.status.radiationTimer and e.status.radiationTimer > 0 then
            love.graphics.setColor(1, 1, 0.2, 0.5)
            love.graphics.setLineWidth(1.5)
            love.graphics.circle('line', e.x, e.y, (e.size or 16) * 0.55)
            love.graphics.setLineWidth(1)
        end
        local barW = math.max(14, math.min(30, (e.size or 16) * 1.2))
        local barX = e.x - barW / 2
        local barY = e.y - (e.size or 16) * 0.6 - 6
        if e.maxShield and e.maxShield > 0 then
            love.graphics.setColor(0.1, 0.2, 0.35, 0.5)
            love.graphics.rectangle('fill', barX, barY - 4, barW, 3)
            local sr = math.max(0, math.min(1, (e.shield or 0) / e.maxShield))
            love.graphics.setColor(0.4, 0.7, 1)
            love.graphics.rectangle('fill', barX, barY - 4, barW * sr, 3)
        end
        love.graphics.setColor(0.3, 0, 0, 0.5)
        love.graphics.rectangle('fill', barX, barY, barW, 4)
        local hr = math.max(0, math.min(1, (e.health or e.hp or 0) / (e.maxHealth or e.maxHp or 1)))
        love.graphics.setColor(1, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barW * hr, 4)
        local armorVal = e.armor or 0
        if e.status and e.status.heatTimer and e.status.heatTimer > 0 then armorVal = armorVal * 0.5 end
        if armorVal and armorVal > 0 then
            local dr = armorVal / (armorVal + 300)
            love.graphics.setColor(1, 0.9, 0.2)
            love.graphics.rectangle('fill', barX, barY + 5, barW * dr, 2)
        end
        love.graphics.setColor(1,1,1)
    end

    if state.chainLinks then
        for _, link in ipairs(state.chainLinks) do
            vfx.drawLightningSegment(link.x1, link.y1, link.x2, link.y2, 14, 0.95)
        end
    end

    if state.lightningLinks then
        for _, link in ipairs(state.lightningLinks) do
            vfx.drawLightningSegment(link.x1, link.y1, link.x2, link.y2, link.width or 14, link.alpha or 0.95)
        end
    end

    -- ========== VOLT ABILITY VFX ==========
    
    -- Volt 1: Lightning Chain VFX (from Shock ability)
    if state.voltLightningChains then
        for _, chain in ipairs(state.voltLightningChains) do
            for _, seg in ipairs(chain.segments or {}) do
                vfx.drawLightningSegment(seg.x1, seg.y1, seg.x2, seg.y2, seg.width or 14, chain.alpha or 1)
            end
        end
    end
    
    -- Volt 2: Speed Aura (while buffed)
    local p = state.player
    if p and p.speedBuffActive and p.speedAuraRadius then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 8)
        local r = p.speedAuraRadius * pulse
        vfx.drawElectricAura(p.x, p.y, r, 0.5)
        -- Speed trail effect
        love.graphics.setColor(0.4, 0.8, 1, 0.25)
        love.graphics.setLineWidth(2)
        love.graphics.circle('line', p.x, p.y, r * 1.2)
        love.graphics.setLineWidth(1)
    end

    -- Mag 2: Magnetize VFX
    if state.magMagnetizeFields then
        for _, f in ipairs(state.magMagnetizeFields) do
            local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 6)
            love.graphics.setColor(0.7, 0.4, 1, 0.35)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', f.x, f.y, (f.r or 0) * pulse)
            love.graphics.setLineWidth(1)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
    
    -- Volt 3: Electric Shield (arc barrier in front of player)
    if p and p.electricShield and p.electricShield.active then
        local shield = p.electricShield
        local px, py = p.x, p.y
        local angle = shield.angle or 0
        local arcRadius = shield.distance or 60
        local arcWidth = shield.arcWidth or 1.2  -- Radians, about 70 degrees
        
        -- Draw arc shield
        love.graphics.setBlendMode('add')
        local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 6)
        
        -- Outer glow arc (thicker, dimmer)
        love.graphics.setColor(0.3, 0.7, 1, 0.25 * pulse)
        love.graphics.setLineWidth(12)
        love.graphics.arc('line', 'open', px, py, arcRadius + 5, angle - arcWidth/2, angle + arcWidth/2)
        
        -- Main arc (medium thickness)
        love.graphics.setColor(0.5, 0.85, 1, 0.5 * pulse)
        love.graphics.setLineWidth(6)
        love.graphics.arc('line', 'open', px, py, arcRadius, angle - arcWidth/2, angle + arcWidth/2)
        
        -- Core arc (thin, bright)
        love.graphics.setColor(0.8, 0.95, 1, 0.9 * pulse)
        love.graphics.setLineWidth(2)
        love.graphics.arc('line', 'open', px, py, arcRadius, angle - arcWidth/2, angle + arcWidth/2)
        
        -- Electric sparks along the arc
        local sparkCount = 5
        for i = 1, sparkCount do
            local sparkAngle = angle - arcWidth/2 + (i - 0.5) * arcWidth / sparkCount
            local sparkOffset = math.sin(love.timer.getTime() * 8 + i * 1.5) * 3
            local sx = px + math.cos(sparkAngle) * (arcRadius + sparkOffset)
            local sy = py + math.sin(sparkAngle) * (arcRadius + sparkOffset)
            
            -- Small spark
            love.graphics.setColor(0.9, 1, 1, 0.7 * pulse)
            love.graphics.circle('fill', sx, sy, 2 + math.sin(love.timer.getTime() * 12 + i) * 1)
        end
        
        love.graphics.setLineWidth(1)
        love.graphics.setBlendMode('alpha')
        
        -- Timer indicator (small text near shield)
        local remaining = shield.timer or 0
        if remaining > 0 then
            local textX = px + math.cos(angle) * (arcRadius + 20)
            local textY = py + math.sin(angle) * (arcRadius + 20)
            love.graphics.setColor(0.4, 0.8, 1, 0.7)
            love.graphics.printf(string.format("%.0fs", remaining), textX - 20, textY - 8, 40, "center")
        end
    end
    
    -- Volt 4: Discharge Wave (expanding electric ring)
    if state.voltDischargeWaves then
        for _, wave in ipairs(state.voltDischargeWaves) do
            local r = wave.currentRadius or 0
            local alpha = wave.alpha or 1
            
            if r > 0 then
                -- Main ring (electric glow)
                love.graphics.setBlendMode('add')
                local ringWidth = 20
                
                -- Outer glow
                love.graphics.setColor(0.3, 0.7, 1, 0.3 * alpha)
                love.graphics.setLineWidth(ringWidth)
                love.graphics.circle('line', wave.x, wave.y, r)
                
                -- Core ring
                love.graphics.setColor(0.6, 0.9, 1, 0.6 * alpha)
                love.graphics.setLineWidth(ringWidth / 2)
                love.graphics.circle('line', wave.x, wave.y, r)
                
                -- Inner bright core
                love.graphics.setColor(0.9, 1, 1, 0.9 * alpha)
                love.graphics.setLineWidth(2)
                love.graphics.circle('line', wave.x, wave.y, r)
                
                -- Electric arcs around the ring
                local arcCount = math.floor(r / 50) + 4
                for i = 1, arcCount do
                    local ang = (love.timer.getTime() * 2 + i * (2 * math.pi / arcCount)) % (2 * math.pi)
                    local x1 = wave.x + math.cos(ang) * (r - 10)
                    local y1 = wave.y + math.sin(ang) * (r - 10)
                    local x2 = wave.x + math.cos(ang) * (r + 15)
                    local y2 = wave.y + math.sin(ang) * (r + 15)
                    vfx.drawLightningSegment(x1, y1, x2, y2, 6, 0.5 * alpha)
                end
                
                love.graphics.setLineWidth(1)
                love.graphics.setBlendMode('alpha')
            end
        end
    end
    
    -- Volt 4 Tesla Node Network: Electric arcs between stunned enemies
    if state.teslaArcs and #state.teslaArcs > 0 then
        for _, arc in ipairs(state.teslaArcs) do
            vfx.drawLightningSegment(arc.x1, arc.y1, arc.x2, arc.y2, 10, arc.alpha or 0.8)
        end
    end
    
    -- Tesla Node indicators on enemies
    for _, e in ipairs(state.enemies or {}) do
        if e and e.teslaNode and e.teslaNode.active then
            local node = e.teslaNode
            local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 8)
            
            -- Electric aura around Tesla node enemy
            love.graphics.setBlendMode('add')
            love.graphics.setColor(0.3, 0.7, 1, 0.3 * pulse)
            love.graphics.circle('fill', e.x, e.y, (e.size or 20) * 0.8)
            
            -- Electric ring
            love.graphics.setColor(0.5, 0.9, 1, 0.6 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', e.x, e.y, (e.size or 20) * 0.9)
            
            -- Timer indicator (small arc showing remaining time)
            if node.timer and node.timer > 0 then
                local maxTime = 4  -- Approximate max duration
                local ratio = math.min(1, node.timer / maxTime)
                love.graphics.setColor(0.7, 0.95, 1, 0.8)
                love.graphics.arc('line', 'open', e.x, e.y - (e.size or 20) * 0.7, 8, 
                    -math.pi/2, -math.pi/2 + ratio * 2 * math.pi)
            end
            
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode('alpha')
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)

    -- 状态特效
    if state.hitEffects then
        love.graphics.setBlendMode("add")
        for _, eff in ipairs(state.hitEffects) do
            local def = state.effectSprites and state.effectSprites[eff.key]
            if def then
                local frac = math.max(0, math.min(0.999, eff.t / (eff.duration or 0.3)))
                local frameIdx = math.floor(frac * (def.frameCount or 1)) + 1
                local img = def.frames and def.frames[frameIdx] or def.frames[#def.frames]
                local scale = eff.scale or def.defaultScale or 1
                love.graphics.setColor(1,1,1)
                love.graphics.draw(img, eff.x, eff.y, 0, scale, scale, def.frameW / 2, def.frameH / 2)
            else
                local frac = math.max(0, math.min(0.999, eff.t / (eff.duration or 0.18)))
                vfx.drawHitEffect(eff.key, eff.x, eff.y, frac, eff.scale or 1, 1)
                love.graphics.setBlendMode("add")
            end
        end
        love.graphics.setBlendMode("alpha")
    end

    -- 冰环提示（统一用 shader 范围场，避免泛白过曝）
    if state.inventory.weapons.ice_ring then
        local iStats = weapons.calculateStats(state, 'ice_ring') or state.inventory.weapons.ice_ring.stats
        local r = (iStats.radius or 0) * (iStats.area or 1) * (state.player.stats.area or 1)

        vfx.drawAreaField('ice', state.player.x, state.player.y, r, 1, { alpha = 1 })
        love.graphics.setColor(0.6, 0.85, 1, 0.14)
        love.graphics.circle('line', state.player.x, state.player.y, r)
        love.graphics.setColor(1, 1, 1)
    end

    -- 玩家阴影
    do
        local size = state.player.size or 20
        -- 8向动画使用64x64精灵，需要更大的影子偏移
        local use8Dir = state.playerAnimSets ~= nil
        local spriteSize = use8Dir and 64 or size
        local shadowR = size * 0.7
        local shadowY = shadowR * 0.35
        -- 影子偏移：精灵高度的一半减去一点（让影子在脚下）
        local shadowOffset = use8Dir and (spriteSize * 0.4) or (size * 0.55)
        love.graphics.setColor(0,0,0,0.25)
        love.graphics.ellipse('fill', state.player.x, state.player.y + shadowOffset, shadowR, shadowY)
    end

    -- 宠物（占位绘制：后续可替换为独立动画/皮肤）
    do
        local pet = state.pets and state.pets.list and state.pets.list[1]
        if pet then
            local size = pet.size or 18
            local shadowR = size * 0.62
            local shadowY = shadowR * 0.35
            love.graphics.setColor(0, 0, 0, 0.22)
            love.graphics.ellipse('fill', pet.x, pet.y + size * 0.55, shadowR, shadowY)

            local col = {0.75, 0.95, 1.0}
            if pet.key == 'pet_corrosive' then col = {0.55, 1.0, 0.55} end
            if pet.key == 'pet_guardian' then col = {0.8, 0.9, 1.0} end
            if pet.downed then col = {1.0, 0.35, 0.35} end

            love.graphics.setColor(col[1], col[2], col[3], pet.downed and 0.75 or 0.95)
            love.graphics.circle('fill', pet.x, pet.y, size * 0.55)
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.circle('line', pet.x, pet.y, size * 0.55)

            -- HP / revive bar
            local barW, barH = 36, 4
            local bx, by = pet.x - barW / 2, pet.y - size * 0.95
            love.graphics.setColor(0.1, 0.1, 0.1, 0.7)
            love.graphics.rectangle('fill', bx, by, barW, barH)
            if pet.downed then
                local hold = (state.pets and state.pets.reviveHoldTime) or 1.1
                local p = (hold > 0) and math.max(0, math.min(1, (pet.reviveProgress or 0) / hold)) or 0
                love.graphics.setColor(0.55, 1.0, 0.55, 0.85)
                love.graphics.rectangle('fill', bx, by, barW * p, barH)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.printf("Hold E", bx - 24, by - 16, barW + 48, "center")
            else
                local hp = pet.hp or 0
                local maxHp = pet.maxHp or 1
                local p = (maxHp > 0) and math.max(0, math.min(1, hp / maxHp)) or 0
                love.graphics.setColor(col[1], col[2], col[3], 0.85)
                love.graphics.rectangle('fill', bx, by, barW * p, barH)
            end

            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- 闪避拖影（shader）：绘制在玩家本体之前
    do
        local list = state.dashAfterimages
        if list and #list > 0 then
            local sh = getDashTrailShader()
            if sh then
                love.graphics.setBlendMode("add")
                love.graphics.setShader(sh)
                sh:send('time', love.timer.getTime())
                sh:send('tint', {0.45, 0.90, 1.00})
                sh:send('warp', 0.010)

                for _, a in ipairs(list) do
                    local dur = a.duration or 0.22
                    local p = (dur > 0) and math.max(0, math.min(1, (a.t or 0) / dur)) or 1
                    local fade = 1 - p
                    local aa = (a.alpha or 0.22) * fade
                    if aa > 0.001 then
                        sh:send('alpha', aa)
                        love.graphics.setColor(1, 1, 1, 1)
                        if state.playerAnim then
                            state.playerAnim:draw(a.x, a.y, 0, a.facing or state.player.facing, 1)
                        else
                            local size = state.player.size or 20
                            love.graphics.rectangle('fill', a.x - (size / 2), a.y - (size / 2), size, size)
                        end
                    end
                end

                love.graphics.setShader()
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    local inv = state.player.invincibleTimer > 0
    local blink = inv and love.timer.getTime() % 0.2 < 0.1

    -- ==================== 涂抹帧效果 (Smear Frame) ====================
    -- 在冲刺/Bullet Jump时沿移动方向拉伸玩家
    local p = state.player
    local smearRotation = 0
    local smearScaleX = 1
    local smearScaleY = 1
    local isSmearing = false
    
    -- 检查是否正在高速移动（冲刺或Bullet Jump）
    local dash = p.dash
    local isDashing = dash and (dash.timer or 0) > 0
    local isBulletJumping = (p.bulletJumpTimer or 0) > 0
    
    if isDashing or isBulletJumping then
        isSmearing = true
        local dx, dy, duration, timer
        
        if isBulletJumping then
            dx, dy = p.bjDx or 0, p.bjDy or 0
            duration = 0.4  -- BULLET_JUMP_DURATION
            timer = p.bulletJumpTimer or 0
        else
            dx, dy = dash.dx or 0, dash.dy or 0
            duration = dash.duration or 0.2
            timer = dash.timer
        end
        
        -- 计算进度 (0 = 刚开始, 1 = 快结束)
        local progress = 1 - (timer / duration)
        
        -- 涂抹帧强度：开始时最强，结束时消失
        -- 使用 Ease-Out 让效果更自然
        local smearIntensity = (1 - progress) * (1 - progress)  -- 二次衰减
        
        -- Bullet Jump 涂抹更强
        if isBulletJumping then
            smearIntensity = smearIntensity * 1.5
        end
        
        -- 沿移动方向拉伸
        -- 旋转角度 = 移动方向
        smearRotation = math.atan2(dy, dx)
        
        -- 拉伸：沿移动方向拉长 (1.0 + intensity*0.8)，垂直方向压缩 (1.0 - intensity*0.3)
        smearScaleX = 1.0 + smearIntensity * 0.8
        smearScaleY = 1.0 - smearIntensity * 0.3
    end
    
    -- 挤压拉伸变换（原有代码，保留兼容）
    local transformSX, transformSY = 1, 1
    local transformOX, transformOY = 0, 0
    if p.transform then
        local t = p.transform
        transformSX = t.scaleX or 1
        transformSY = t.scaleY or 1
        transformOX = t.offsetX or 0
        transformOY = t.offsetY or 0
    end

    -- Player outline (drawn behind base)
    if state.playerAnim then
        -- 8向动画不需要水平翻转
        local use8Dir = state.playerAnimSets ~= nil
        local outlineFacingScale = use8Dir and 1 or (state.player.facing >= 0 and 1 or -1)
        
        if isSmearing then
            -- 涂抹帧：使用拉伸
            love.graphics.push()
            love.graphics.translate(state.player.x, state.player.y)
            
            -- 沿位移方向旋转坐标轴以应用拉伸
            love.graphics.rotate(smearRotation)
            
            -- 如果是8向动画，将内容旋回，实现"沿位移方向拉伸但精灵不旋转"
            if use8Dir then
                love.graphics.rotate(-smearRotation)
            end
            
            love.graphics.setColor(0.9, 0.95, 1, 0.55)
            state.playerAnim:draw(0, 0, 0, smearScaleX * outlineFacingScale, smearScaleY)
            -- 绘制拖影副本（涂抹帧的"中间帧"）
            if smearScaleX > 1.2 then
                love.graphics.setColor(0.8, 0.9, 1, 0.25)
                state.playerAnim:draw(-8 * smearScaleX, 0, 0, smearScaleX * 0.9 * outlineFacingScale, smearScaleY * 0.95)
            end
            love.graphics.pop()
        else
            drawOutlineAnim(state.playerAnim, state.player.x + transformOX, state.player.y + transformOY, 0, outlineFacingScale * transformSX, transformSY, 1, {0.9, 0.95, 1, 0.55})
        end
    else
        love.graphics.setColor(0.9, 0.95, 1, 0.55)
        drawOutlineRect(state.player.x, state.player.y, state.player.size or 20, 1)
        love.graphics.setColor(1, 1, 1, 1)
    end

    if state.playerAnim then
        if blink then love.graphics.setColor(1,1,1,0.35) else love.graphics.setColor(1,1,1) end
        
        -- 8向动画不需要水平翻转，因为每个方向有独立动画
        local use8Dir = state.playerAnimSets ~= nil
        local facingScale = use8Dir and 1 or (state.player.facing >= 0 and 1 or -1)
        
        if isSmearing then
            -- 涂抹帧主体
            love.graphics.push()
            love.graphics.translate(state.player.x, state.player.y)
            
            -- 沿位移方向旋转坐标轴
            love.graphics.rotate(smearRotation)
            
            -- 8向动画时将内容旋回，仅保留拉伸轴的对齐
            if use8Dir then
                love.graphics.rotate(-smearRotation)
            end
            
            state.playerAnim:draw(0, 0, 0, smearScaleX * facingScale, smearScaleY)
            love.graphics.pop()
        else
            state.playerAnim:draw(state.player.x + transformOX, state.player.y + transformOY, 0, facingScale * transformSX, transformSY)
        end
    else
        if blink then love.graphics.setColor(1,1,1) else love.graphics.setColor(0,1,0) end
        local size = state.player.size or 20
        if isSmearing then
            love.graphics.push()
            love.graphics.translate(state.player.x, state.player.y)
            love.graphics.rotate(smearRotation)
            love.graphics.rectangle('fill', -size * smearScaleX / 2, -size * smearScaleY / 2, size * smearScaleX, size * smearScaleY)
            love.graphics.pop()
        else
            love.graphics.rectangle('fill', state.player.x - (size * transformSX / 2), state.player.y - (size * transformSY / 2), size * transformSX, size * transformSY)
        end
    end
    love.graphics.setColor(1,1,1)

    -- Melee swing arc visual
    do
        local p = state.player or {}
        local melee = p.meleeState
        if melee and melee.phase == 'swing' then
            local px, py = p.x, p.y
            local range = 90
            local arcWidth = 1.4
            
            local aimAngle = p.aimAngle or 0
            
            -- Arc color based on attack type
            local r, g, b, a = 1, 1, 1, 0.6
            if melee.attackType == 'light' then
                r, g, b = 0.9, 0.95, 1
            elseif melee.attackType == 'heavy' then
                r, g, b = 1, 0.7, 0.3
            elseif melee.attackType == 'finisher' then
                r, g, b = 1, 0.4, 0.2
                a = 0.8
            end
            
            love.graphics.setColor(r, g, b, a)
            love.graphics.setLineWidth(3)
            
            -- Draw arc
            local startAng = aimAngle - arcWidth / 2
            local endAng = aimAngle + arcWidth / 2
            love.graphics.arc('line', 'open', px, py, range, startAng, endAng)
            
            -- Draw lines from center to arc edges
            love.graphics.line(px, py, px + math.cos(startAng) * range, py + math.sin(startAng) * range)
            love.graphics.line(px, py, px + math.cos(endAng) * range, py + math.sin(endAng) * range)
            
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- 玩家投射物
    for _, b in ipairs(state.bullets) do
        local isGlow = false
        if b.type == 'absolute_zero' or b.type == 'fire_wand' or b.type == 'hellfire' or b.type == 'static_orb' or b.type == 'thunder_loop' or b.type == 'wand' or b.type == 'holy_wand' or b.type == 'death_spiral' or b.type == 'thousand_edge' then
            isGlow = true
        end

        if isGlow then love.graphics.setBlendMode("add") end

        if b.type == 'absolute_zero' then
            -- 大面积范围场：统一走 shader（alpha 混合），避免 bloom 洗白
            local r = b.radius or b.size or 0
            vfx.drawAreaField('absolute_zero', b.x, b.y, r, 1, { alpha = 1 })
            if isGlow then love.graphics.setBlendMode("add") end
        else
            local sprite = state.weaponSprites and state.weaponSprites[b.type]
            if sprite then
                if isGlow then
                    love.graphics.setColor(1, 1, 1, 1) -- Ensure full brightness for glow
                else
                    love.graphics.setColor(1,1,1)
                end
                local sw, sh = sprite:getWidth(), sprite:getHeight()
                local scale = ((b.size or sw) / sw) * ((state.weaponSpriteScale and state.weaponSpriteScale[b.type]) or 1)
                local sx = scale
                local sy = scale
                love.graphics.push()
                love.graphics.translate(b.x, b.y)
                local rot = b.rotation
                if b.type == 'oil_bottle' then
                    rot = 0
                elseif b.type == 'heavy_hammer' and (b.vx or 0) < 0 then
                    rot = (rot or 0) + math.pi
                    sx = -sx
                end
                if rot then love.graphics.rotate(rot) end
                love.graphics.draw(sprite, 0, 0, 0, sx, sy, sw/2, sh/2)
                love.graphics.pop()
            else
                if b.type == 'thousand_edge' then
                    love.graphics.setColor(0.7, 0.85, 1, 0.9)
                    love.graphics.push()
                    love.graphics.translate(b.x, b.y)
                    if b.rotation then love.graphics.rotate(b.rotation) end
                    local len = (b.size or 10) * 3
                    local thick = (b.size or 10) * 0.6
                    love.graphics.rectangle('fill', -len * 0.2, -thick / 2, len, thick, 6, 6)
                    love.graphics.setColor(0.4, 0.75, 1, 0.6)
                    love.graphics.rectangle('line', -len * 0.2, -thick / 2, len, thick, 6, 6)
                    love.graphics.pop()
                else
                    if b.type == 'axe' then love.graphics.setColor(0,1,1) else love.graphics.setColor(1,1,0) end
                    love.graphics.push()
                    love.graphics.translate(b.x, b.y)
                    if b.rotation then love.graphics.rotate(b.rotation) end
                    love.graphics.rectangle('fill', -b.size/2, -b.size/2, b.size, b.size)
                    love.graphics.pop()
                end
            end
        end

        if isGlow then love.graphics.setBlendMode("alpha") end
    end

    -- 地震特效
    if state.quakeEffects then
        for _, q in ipairs(state.quakeEffects) do
            if (q.t or 0) < 0 then goto continue_quake end
            local dur = q.duration or 1.2
            local t = (q.t or 0)
            local p = math.max(0, math.min(1, t / dur))
            local cx, cy = q.x or state.player.x, q.y or state.player.y
            local baseR = q.radius or 220
            local frontR = baseR * p

            -- 起震中心闪光（只在前段）
            local flashK = math.max(0, 1 - p * 6)
            if flashK > 0.01 then
                love.graphics.setColor(0.75, 0.55, 0.35, 0.10 * flashK)
                love.graphics.circle('fill', cx, cy, baseR * 0.18 * flashK)
            end

            -- 冲击前沿：半径与伤害判定一致（updateQuakes: currR = radius * progress）
            local alpha = 0.65 * (1 - p)
            if alpha > 0.01 then
                love.graphics.setColor(0.78, 0.52, 0.26, alpha)
                love.graphics.setLineWidth(10 * (1 - p) + 2)
                love.graphics.circle('line', cx, cy, frontR)
            end

            -- 前沿碎屑/尘土（贴着前沿走，增强“扫到即命中”的可读性）
            local dustAlpha = 0.22 * (1 - p)
            if dustAlpha > 0.01 then
                love.graphics.setColor(0.52, 0.36, 0.20, dustAlpha)
                local count = 14
                local twoPi = math.pi * 2
                for i = 1, count do
                    local a = (i / count) * twoPi
                    a = a + math.sin(t * 3.4 + i * 1.7) * 0.25
                    local wobble = math.sin(t * 8.2 + i) * (8 + 10 * (1 - p))
                    local rr = frontR + wobble
                    local px = cx + math.cos(a) * rr
                    local py = cy + math.sin(a) * rr
                    local s = 4 + 7 * (1 - p)
                    love.graphics.circle('fill', px, py, s)
                end
            end
            love.graphics.setLineWidth(1)
            ::continue_quake::
        end
        love.graphics.setColor(1,1,1)
    end

    -- 敌方子弹
    for _, eb in ipairs(state.enemyBullets) do
        local sprite = state.enemySprites and (state.enemySprites[eb.spriteKey or ''] or state.enemySprites['default_bullet'])
        if sprite then
            love.graphics.setColor(1,1,1)
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local baseScale = (eb.size or sw) / sw
            if eb.spriteKey == 'plant_bullet' then baseScale = baseScale * 2 end
            if not eb.spriteKey and state.enemySprites and sprite == state.enemySprites['default_bullet'] then
                baseScale = baseScale * 3
            end
            local scale = baseScale
            love.graphics.push()
            love.graphics.translate(eb.x, eb.y)
            if eb.rotation then love.graphics.rotate(eb.rotation) end
            love.graphics.draw(sprite, 0, 0, 0, scale, scale, sw/2, sh/2)
            love.graphics.pop()
        else
            love.graphics.setColor(1,0,0)
            love.graphics.push()
            love.graphics.translate(eb.x, eb.y)
            if eb.rotation then love.graphics.rotate(eb.rotation) end
            local size = eb.size or 10
            love.graphics.rectangle('fill', -size/2, -size/2, size, size)
            love.graphics.pop()
        end
    end

    -- 飘字 (Floating damage numbers with scale and outline)
    for _, t in ipairs(state.texts) do
        local scale = t.scale or 1
        local fadeAlpha = math.min(1, (t.life or 0.5) / 0.3)  -- Fade out in last 0.3s
        local colorAlpha = t.color[4] or 1  -- Get alpha from color (if specified)
        local alpha = fadeAlpha * colorAlpha  -- Combine both alphas
        local text = tostring(t.text)
        
        -- Skip very low alpha (saves draw calls for tiny/faded damage)
        if alpha < 0.05 then goto continue_text end
        
        -- Use state.font explicitly to ensure Chinese font support
        -- (Don't rely on getFont which might be corrupted by other code)
        local font = state.font or love.graphics.getFont()
        love.graphics.setFont(font)
        local tw = font:getWidth(text) * scale
        local th = font:getHeight() * scale
        local drawX = t.x - tw / 2
        local drawY = t.y - th / 2
        
        -- Draw black outline for visibility (skip for very small scale)
        if scale >= 0.6 then
            love.graphics.setColor(0, 0, 0, alpha * 0.8)
            for ox = -1, 1 do
                for oy = -1, 1 do
                    if ox ~= 0 or oy ~= 0 then
                        love.graphics.print(text, drawX + ox, drawY + oy, 0, scale, scale)
                    end
                end
            end
        end
        
        -- Draw main text
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], alpha)
        love.graphics.print(text, drawX, drawY, 0, scale, scale)
        
        ::continue_text::
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

function draw.renderUI(state)
    love.graphics.setFont(state.font)

    -- Bow charge bar (above player)
    local p = state.player
    if p and p.bowCharge and p.bowCharge.isCharging then
        local chargeTime = p.bowCharge.chargeTime or 0
        local maxCharge = 2.0  -- Match weapon definition
        local chargeRatio = math.min(1, chargeTime / maxCharge)
        
        -- World to screen conversion
        local px = p.x - state.camera.x
        local py = p.y - state.camera.y - 40
        
        -- Bar dimensions
        local barW, barH = 60, 8
        local barX, barY = px - barW / 2, py
        
        -- Background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle('fill', barX - 1, barY - 1, barW + 2, barH + 2)
        
        -- Fill color (changes when full charge)
        local fillColor = {0.5, 0.85, 1.0}
        if chargeRatio >= 1.0 then
            -- Full charge: pulse effect
            local pulse = (math.sin(love.timer.getTime() * 12) + 1) * 0.5
            fillColor = {0.7 + pulse * 0.3, 1.0, 0.4 + pulse * 0.3}
        end
        
        love.graphics.setColor(fillColor[1], fillColor[2], fillColor[3], 0.9)
        love.graphics.rectangle('fill', barX, barY, barW * chargeRatio, barH)
        
        -- Border
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.rectangle('line', barX, barY, barW, barH)
        
        -- Text
        if chargeRatio >= 1.0 then
            love.graphics.setColor(1, 1, 0.5, 0.95)
            love.graphics.print("MAX", barX + barW / 2 - 12, barY - 12)
        end
        
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- === CASTING BAR (Ability cast progress) ===
    if p and p.isCasting and p.castTimer and p.castDef then
        local castProgress = p.castProgress or 0
        
        -- World to screen conversion
        local px = p.x - state.camera.x
        local py = p.y - state.camera.y - 50  -- Above player (higher than bow charge)
        
        -- Bar dimensions
        local barW, barH = 80, 10
        local barX, barY = px - barW / 2, py
        
        -- Background
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.rectangle('fill', barX - 2, barY - 2, barW + 4, barH + 4, 3, 3)
        
        -- Fill color based on class
        local fillColor = {0.4, 0.7, 1}  -- Default blue
        if p.class == 'excalibur' then
            fillColor = {0.9, 0.8, 0.4}  -- Gold for Excalibur
        elseif p.class == 'mag' then
            fillColor = {0.7, 0.4, 1}  -- Violet for Mag
        elseif p.class == 'volt' then
            fillColor = {0.3, 0.8, 1}  -- Cyan for Volt
        end
        
        -- Pulsing effect
        local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 10)
        love.graphics.setColor(fillColor[1] * pulse, fillColor[2] * pulse, fillColor[3] * pulse, 0.9)
        love.graphics.rectangle('fill', barX, barY, barW * castProgress, barH, 2, 2)
        
        -- Border (brighter when near completion)
        local borderAlpha = (castProgress > 0.8) and 1.0 or 0.7
        love.graphics.setColor(1, 1, 1, borderAlpha)
        love.graphics.rectangle('line', barX, barY, barW, barH, 2, 2)
        
        -- Ability name above bar
        local abilityName = p.castDef.name or "施法中"
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.printf(abilityName, barX - 20, barY - 16, barW + 40, "center")
        
        -- Progress percentage
        if castProgress < 1.0 then
            love.graphics.setColor(0.9, 0.9, 0.9, 0.8)
            love.graphics.printf(string.format("%.0f%%", castProgress * 100), barX, barY - 1, barW, "center")
        end
        
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- 屏幕边缘指示道具方向（磁铁/鸡腿/宝箱/宠物芯片）
    do
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local cx, cy = w / 2, h / 2
        local colors = {
            magnet = {0,0.8,1},
            chest = {1,0.84,0},
            chicken = {1,0.7,0.2},
            pet_module_chip = {0.7, 0.95, 1.0},
            pet_upgrade_chip = {1.0, 0.92, 0.55}
        }
        local function drawArrow(wx, wy, kind)
            local col = colors[kind] or {1,1,1}
            local sx = wx - state.camera.x
            local sy = wy - state.camera.y
            local dx, dy = sx - cx, sy - cy
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist < 20 then return end
            dx, dy = dx / dist, dy / dist
            local margin = 24
            local ex = cx + dx * (cx - margin)
            local ey = cy + dy * (cy - margin)
            ex = math.min(w - margin, math.max(margin, ex))
            ey = math.min(h - margin, math.max(margin, ey))
            local angle = math.atan2(dy, dx)
            love.graphics.setColor(col[1], col[2], col[3], 0.95)
            love.graphics.push()
            love.graphics.translate(ex, ey)
            love.graphics.rotate(angle)
            love.graphics.polygon('fill', -8, -6, -8, 6, 12, 0)
            love.graphics.pop()
        end
        for _, c in ipairs(state.chests) do
            drawArrow(c.x, c.y, 'chest')
        end
        for _, item in ipairs(state.floorPickups) do
            if item.kind == 'magnet' or item.kind == 'chicken' or item.kind == 'pet_module_chip' or item.kind == 'pet_upgrade_chip' then
                drawArrow(item.x, item.y, item.kind)
            end
        end
    end

    -- (Legacy HUD logic removed, handled by ui.screens.hud)

    if state.runMode == 'rooms' and state.rooms and (state.rooms.roomIndex or 0) > 0 then
        local r = state.rooms
        local room = r.roomIndex or 0
        local wave = r.waveIndex or 0
        local waves = r.wavesTotal or 0
        local kindSuffix = ""
        local rk = (r.roomKind or '')
        if rk == 'elite' then kindSuffix = "  ELITE"
        elseif rk == 'shop' then kindSuffix = "  SHOP"
        elseif rk == 'event' then kindSuffix = "  EVENT"
        end
        local label = string.format("ROOM %d", room)
        if (r.phase or '') == 'boss' then
            label = string.format("ROOM %d  BOSS", room)
        elseif (r.phase or '') == 'reward' then
            label = string.format("ROOM %d%s  CLEAR", room, kindSuffix)
        elseif (r.phase or '') == 'special' then
            label = string.format("ROOM %d%s  INTERACT", room, kindSuffix)
        elseif (r.phase or '') == 'doors' then
            label = string.format("ROOM %d  CHOOSE NEXT", room)
        elseif waves > 0 then
            label = string.format("ROOM %d%s  WAVE %d/%d", room, kindSuffix, math.max(1, wave), waves)
        end
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.printf(label, 0, 40, love.graphics.getWidth(), "center")
        love.graphics.setColor(1, 1, 1, 1)
        
        -- Mission-specific HUD is now handled by ui.screens.hud
    end

    -- (Legacy Scene drawing removed, handled by ui.screens)
end

function draw.renderBase(state)
    draw.renderWorld(state)

    draw.renderUI(state)

    -- Room transition fade overlay
    if state.roomTransitionFade and state.roomTransitionFade > 0 then
        local alpha = state.roomTransitionFade
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function draw.renderEmissive(state)
    if not state then return false end

    -- Collect dynamic lights for this frame
    pipeline.clearLights()
    
    -- Player light (very subtle)
    if state.player then
        pipeline.addLight(state.player.x, state.player.y, 80, {0.4, 0.7, 1.0}, 0.25)
    end
    
    -- Bullet lights (subtle glow)
    for _, b in ipairs(state.bullets or {}) do
        local color = {1.0, 0.9, 0.6}  -- Default warm
        local radius = 25
        local intensity = 0.2
        if b.type == 'absolute_zero' then 
            color = {0.4, 0.85, 1.0}
            radius = 35
        elseif b.type == 'fire_wand' or b.type == 'hellfire' then 
            color = {1.0, 0.6, 0.3}
            radius = 30
        elseif b.type == 'static_orb' or b.type == 'thunder_loop' then
            color = {0.6, 0.8, 1.0}
            radius = 30
        elseif b.type == 'wand' or b.type == 'holy_wand' then
            color = {0.95, 0.95, 1.0}
            radius = 20
            intensity = 0.15
        end
        pipeline.addLight(b.x, b.y, radius, color, intensity)
    end
    
    -- Pickup lights (subtle hints)
    for _, item in ipairs(state.floorPickups or {}) do
        local color = {1.0, 1.0, 0.85}  -- Default gold
        local radius = 20
        local intensity = 0.18
        if item.kind == 'health_orb' then 
            color = {1.0, 0.45, 0.45}
        elseif item.kind == 'energy_orb' then 
            color = {0.45, 0.6, 1.0}
        elseif item.kind == 'mod_card' then
            color = {0.85, 0.65, 1.0}
            radius = 25
        elseif item.kind == 'chicken' then
            color = {1.0, 0.85, 0.6}
        end
        pipeline.addLight(item.x, item.y, radius, color, intensity)
    end
    
    -- Chest lights (subtle)
    for _, c in ipairs(state.chests or {}) do
        pipeline.addLight(c.x, c.y, 35, {1.0, 0.9, 0.6}, 0.25)
    end

    love.graphics.push()
    if state.shakeAmount and state.shakeAmount > 0 then
        local shakeX = state._shakeOffsetX or (love.math.random() * state.shakeAmount)
        local shakeY = state._shakeOffsetY or (love.math.random() * state.shakeAmount)
        love.graphics.translate(shakeX, shakeY)
    end
    if state.camera then
        love.graphics.translate(-state.camera.x, -state.camera.y)
    end

    -- Area fields (player-centered)
    if state.inventory and state.inventory.weapons and (state.inventory.weapons.garlic or state.inventory.weapons.soul_eater) then
        local key = state.inventory.weapons.soul_eater and 'soul_eater' or 'garlic'
        local gStats = weapons.calculateStats(state, key) or state.inventory.weapons[key].stats
        local r = (gStats.radius or 0) * (gStats.area or 1) * (state.player.stats.area or 1)
        local pulse = 0
        if key == 'soul_eater' then
            pulse = (math.sin(love.timer.getTime() * 5) + 1) * 0.5
        end
        vfx.drawAreaField(key, state.player.x, state.player.y, r, 1 + pulse * 0.35, { alpha = 1 })
    end

    if state.areaFields then
        for _, a in ipairs(state.areaFields) do
            local dur = a.duration or 2.0
            local p = (dur > 0) and math.max(0, math.min(1, (a.t or 0) / dur)) or 1
            local fade = 1 - p
            local alpha = 0.35 + 0.65 * fade
            local intensity = (a.intensity or 1) * (0.85 + 0.35 * fade)
            vfx.drawAreaField(a.kind or 'oil', a.x, a.y, a.radius or 0, intensity, { alpha = alpha })
        end
    end

    if state.telegraphs then
        for _, tg in ipairs(state.telegraphs) do
            local dur = tg.duration or 0.6
            local p = (dur > 0) and math.max(0, math.min(1, (tg.t or 0) / dur)) or 1
            local intensity = (tg.intensity or 1) * (0.65 + 0.75 * p)
            if tg.shape == 'circle' then
                local r = tg.radius or 0
                if r > 0 then
                    local kind = tg.kind or 'telegraph'
                    vfx.drawAreaField(kind, tg.x, tg.y, r, intensity, { alpha = 0.06 + 0.18 * p, alphaCap = 0.55, edgeSoft = 0.52 })
                end
            elseif tg.shape == 'line' then
                local x1, y1, x2, y2 = tg.x1, tg.y1, tg.x2, tg.y2
                local dx = (x2 or 0) - (x1 or 0)
                local dy = (y2 or 0) - (y1 or 0)
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0.001 then
                    local ang = math.atan2(dy, dx)
                    local w = tg.width or 28
                    local col = tg.color or {1, 0.22, 0.22}
                    local lineA = 0.16 + 0.36 * p
                    love.graphics.setBlendMode('add')
                    love.graphics.push()
                    love.graphics.translate(x1, y1)
                    love.graphics.rotate(ang)
                    love.graphics.setColor(col[1], col[2], col[3], lineA)
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle('line', 0, -w / 2, len, w, w * 0.35, w * 0.35)
                    love.graphics.pop()
                    love.graphics.setLineWidth(1)
                    love.graphics.setBlendMode('alpha')
                end
            end
        end
    end

    -- Enemy attack windup/dash indicators (emissive overlay)
    for _, e in ipairs(state.enemies or {}) do
        local atk = e.attack
        if atk and atk.phase == 'windup' then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 12)
            local size = (e.size or 24) / 2 + 4
            love.graphics.setBlendMode('add')
            love.graphics.setColor(1, 0.2, 0.2, 0.22 + 0.22 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', e.x, e.y, size + 4 * pulse)
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode('alpha')
        end
        if atk and (atk.phase == 'dash' or atk.phase == 'leaping') then
            local size = (e.size or 24) / 2 + 6
            love.graphics.setBlendMode('add')
            love.graphics.setColor(1, 0.5, 0.1, 0.30)
            love.graphics.setLineWidth(3)
            love.graphics.circle('line', e.x, e.y, size)
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode('alpha')
        end
    end

    -- Enemy status glows
    for _, e in ipairs(state.enemies or {}) do
        if e.status and e.status.static then
            local r = (e.size or 16) * 0.75
            vfx.drawElectricAura(e.x, e.y, r, 0.9)
        end
        if e.status and e.status.gasTimer and e.status.gasTimer > 0 then
            local r = e.status.gasRadius or 100
            vfx.drawGas(e.x, e.y, r, 1)
        end
        if e.status and e.status.toxinTimer and e.status.toxinTimer > 0 then
            local r = math.max((e.size or 16) * 1.05, 16)
            vfx.drawAreaField('toxin', e.x, e.y, r, 1, { alpha = 0.75 })
        end
    end

    -- Emissive sprite layers
    for _, e in ipairs(state.enemies or {}) do
        if e.animEmissive then
            local sx = e.facing or 1
            e.animEmissive:draw(e.x, e.y, 0, sx, 1)
        end
    end
    if state.playerAnimEmissive and state.player then
        state.playerAnimEmissive:draw(state.player.x, state.player.y, 0, state.player.facing, 1)
    end

    -- Lightning chains / arcs
    if state.chainLinks then
        for _, link in ipairs(state.chainLinks) do
            vfx.drawLightningSegment(link.x1, link.y1, link.x2, link.y2, 14, 0.95)
        end
    end
    if state.lightningLinks then
        for _, link in ipairs(state.lightningLinks) do
            vfx.drawLightningSegment(link.x1, link.y1, link.x2, link.y2, link.width or 14, link.alpha or 0.95)
        end
    end
    if state.voltLightningChains then
        for _, chain in ipairs(state.voltLightningChains) do
            for _, seg in ipairs(chain.segments or {}) do
                if seg.active then
                    vfx.drawLightningSegment(seg.x1, seg.y1, seg.x2, seg.y2, seg.width or 14, chain.alpha or 1, seg.progress)
                end
            end
        end
    end

    -- Player aura (Volt speed buff)
    local p = state.player
    if p and p.speedBuffActive and p.speedAuraRadius then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 8)
        local r = p.speedAuraRadius * pulse
        vfx.drawElectricAura(p.x, p.y, r, 0.5)
        love.graphics.setBlendMode('add')
        love.graphics.setColor(0.4, 0.8, 1, 0.18)
        love.graphics.setLineWidth(2)
        love.graphics.circle('line', p.x, p.y, r * 1.2)
        love.graphics.setLineWidth(1)
        love.graphics.setBlendMode('alpha')
    end

    -- Mag magnetize ring (emissive overlay)
    if state.magMagnetizeFields then
        for _, f in ipairs(state.magMagnetizeFields) do
            local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 6)
            love.graphics.setBlendMode('add')
            love.graphics.setColor(0.7, 0.4, 1, 0.25 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', f.x, f.y, (f.r or 0) * pulse)
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode('alpha')
        end
    end

    -- Volt electric shield (additive arcs)
    if p and p.electricShield and p.electricShield.active then
        local shield = p.electricShield
        local px, py = p.x, p.y
        local angle = shield.angle or 0
        local arcRadius = shield.distance or 60
        local arcWidth = shield.arcWidth or 1.2

        love.graphics.setBlendMode('add')
        local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 6)

        love.graphics.setColor(0.3, 0.7, 1, 0.25 * pulse)
        love.graphics.setLineWidth(12)
        love.graphics.arc('line', 'open', px, py, arcRadius + 5, angle - arcWidth/2, angle + arcWidth/2)

        love.graphics.setColor(0.5, 0.85, 1, 0.5 * pulse)
        love.graphics.setLineWidth(6)
        love.graphics.arc('line', 'open', px, py, arcRadius, angle - arcWidth/2, angle + arcWidth/2)

        love.graphics.setColor(0.8, 0.95, 1, 0.9 * pulse)
        love.graphics.setLineWidth(2)
        love.graphics.arc('line', 'open', px, py, arcRadius, angle - arcWidth/2, angle + arcWidth/2)

        local sparkCount = 5
        for i = 1, sparkCount do
            local sparkAngle = angle - arcWidth/2 + (i - 0.5) * arcWidth / sparkCount
            local sparkOffset = math.sin(love.timer.getTime() * 8 + i * 1.5) * 3
            local sx = px + math.cos(sparkAngle) * (arcRadius + sparkOffset)
            local sy = py + math.sin(sparkAngle) * (arcRadius + sparkOffset)
            love.graphics.setColor(0.9, 1, 1, 0.7 * pulse)
            love.graphics.circle('fill', sx, sy, 2 + math.sin(love.timer.getTime() * 12 + i) * 1)
        end

        love.graphics.setLineWidth(1)
        love.graphics.setBlendMode('alpha')
    end

    -- Volt discharge wave
    if state.voltDischargeWaves then
        for _, wave in ipairs(state.voltDischargeWaves) do
            local r = wave.currentRadius or 0
            local alpha = wave.alpha or 1
            if r > 0 then
                love.graphics.setBlendMode('add')
                local ringWidth = 20
                love.graphics.setColor(0.3, 0.7, 1, 0.3 * alpha)
                love.graphics.setLineWidth(ringWidth)
                love.graphics.circle('line', wave.x, wave.y, r)
                love.graphics.setColor(0.6, 0.9, 1, 0.6 * alpha)
                love.graphics.setLineWidth(ringWidth / 2)
                love.graphics.circle('line', wave.x, wave.y, r)
                love.graphics.setColor(0.9, 1, 1, 0.9 * alpha)
                love.graphics.setLineWidth(2)
                love.graphics.circle('line', wave.x, wave.y, r)

                local arcCount = math.floor(r / 50) + 4
                for i = 1, arcCount do
                    local ang = (love.timer.getTime() * 2 + i * (2 * math.pi / arcCount)) % (2 * math.pi)
                    local x1 = wave.x + math.cos(ang) * (r - 10)
                    local y1 = wave.y + math.sin(ang) * (r - 10)
                    local x2 = wave.x + math.cos(ang) * (r + 15)
                    local y2 = wave.y + math.sin(ang) * (r + 15)
                    vfx.drawLightningSegment(x1, y1, x2, y2, 6, 0.5 * alpha)
                end

                love.graphics.setLineWidth(1)
                love.graphics.setBlendMode('alpha')
            end
        end
    end

    if state.teslaArcs and #state.teslaArcs > 0 then
        for _, arc in ipairs(state.teslaArcs) do
            vfx.drawLightningSegment(arc.x1, arc.y1, arc.x2, arc.y2, 10, arc.alpha or 0.8)
        end
    end

    for _, e in ipairs(state.enemies or {}) do
        if e and e.teslaNode and e.teslaNode.active then
            local node = e.teslaNode
            local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 8)
            love.graphics.setBlendMode('add')
            love.graphics.setColor(0.3, 0.7, 1, 0.3 * pulse)
            love.graphics.circle('fill', e.x, e.y, (e.size or 20) * 0.8)
            love.graphics.setColor(0.5, 0.9, 1, 0.6 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', e.x, e.y, (e.size or 20) * 0.9)
            if node.timer and node.timer > 0 then
                local maxTime = 4
                local ratio = math.min(1, node.timer / maxTime)
                love.graphics.setColor(0.7, 0.95, 1, 0.8)
                love.graphics.arc('line', 'open', e.x, e.y - (e.size or 20) * 0.7, 8,
                    -math.pi/2, -math.pi/2 + ratio * 2 * math.pi)
            end
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode('alpha')
        end
    end

    -- Hit effects (additive)
    if state.hitEffects then
        love.graphics.setBlendMode("add")
        for _, eff in ipairs(state.hitEffects) do
            local def = state.effectSprites and state.effectSprites[eff.key]
            if def then
                local frac = math.max(0, math.min(0.999, eff.t / (eff.duration or 0.3)))
                local frameIdx = math.floor(frac * (def.frameCount or 1)) + 1
                local img = def.frames and def.frames[frameIdx] or def.frames[#def.frames]
                local scale = eff.scale or def.defaultScale or 1
                love.graphics.setColor(1,1,1)
                love.graphics.draw(img, eff.x, eff.y, 0, scale, scale, def.frameW / 2, def.frameH / 2)
            else
                local frac = math.max(0, math.min(0.999, eff.t / (eff.duration or 0.18)))
                vfx.drawHitEffect(eff.key, eff.x, eff.y, frac, eff.scale or 1, 1)
                love.graphics.setBlendMode("add")
            end
        end
        love.graphics.setBlendMode("alpha")
    end

    -- Ice ring glow
    if state.inventory and state.inventory.weapons and state.inventory.weapons.ice_ring then
        local iStats = weapons.calculateStats(state, 'ice_ring') or state.inventory.weapons.ice_ring.stats
        local r = (iStats.radius or 0) * (iStats.area or 1) * (state.player.stats.area or 1)
        vfx.drawAreaField('ice', state.player.x, state.player.y, r, 1, { alpha = 1 })
    end

    -- Dash afterimages (glow)
    do
        local list = state.dashAfterimages
        if list and #list > 0 then
            local sh = getDashTrailShader()
            if sh then
                love.graphics.setBlendMode("add")
                love.graphics.setShader(sh)
                sh:send('time', love.timer.getTime())
                sh:send('tint', {0.45, 0.90, 1.00})
                sh:send('warp', 0.010)

                for _, a in ipairs(list) do
                    local dur = a.duration or 0.22
                    local p = (dur > 0) and math.max(0, math.min(1, (a.t or 0) / dur)) or 1
                    local fade = 1 - p
                    local aa = (a.alpha or 0.22) * fade
                    if aa > 0.001 then
                        sh:send('alpha', aa)
                        love.graphics.setColor(1, 1, 1, 1)
                        if state.playerAnim then
                            state.playerAnim:draw(a.x, a.y, 0, a.facing or state.player.facing, 1)
                        else
                            local size = state.player.size or 20
                            love.graphics.rectangle('fill', a.x - (size / 2), a.y - (size / 2), size, size)
                        end
                    end
                end

                love.graphics.setShader()
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    -- Glow pickups (sprites only)
    local glowKinds = {
        magnet = true,
        chicken = true,
        chest_xp = true,
        chest_reward = true,
        pet_contract = true,
        pet_revive = true,
        shop_terminal = true,
        pet_module_chip = true,
        pet_upgrade_chip = true,
        health_orb = true,
        energy_orb = true,
        mod_card = true
    }
    for _, item in ipairs(state.floorPickups or {}) do
        if glowKinds[item.kind] then
            local sprite = state.pickupSprites and state.pickupSprites[item.kind]
            if sprite then
                local sw, sh = sprite:getWidth(), sprite:getHeight()
                local size = (item.size or 16)
                local scale = (size / sw) * 2
                love.graphics.setBlendMode("add")
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(sprite, item.x, item.y, 0, scale, scale, sw/2, sh/2)
                love.graphics.setBlendMode("alpha")
            end
        end
    end

    -- Gems (legacy)
    for _, g in ipairs(state.gems or {}) do
        local sprite = state.pickupSprites and state.pickupSprites['gem']
        if sprite then
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local baseSize = 8
            local scale = (state.pickupSpriteScale and state.pickupSpriteScale['gem']) or (baseSize / sw)
            love.graphics.setBlendMode("add")
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sprite, g.x, g.y, 0, scale, scale, sw/2, sh/2)
            love.graphics.setBlendMode("alpha")
        end
    end

    -- Glowing bullets
    for _, b in ipairs(state.bullets or {}) do
        local isGlow = (b.type == 'absolute_zero' or b.type == 'fire_wand' or b.type == 'hellfire' or b.type == 'static_orb' or b.type == 'thunder_loop' or b.type == 'wand' or b.type == 'holy_wand' or b.type == 'death_spiral' or b.type == 'thousand_edge')
        if isGlow then
            if b.type == 'absolute_zero' then
                local r = b.radius or b.size or 0
                vfx.drawAreaField('absolute_zero', b.x, b.y, r, 1, { alpha = 1 })
            else
                local sprite = (state.weaponSpritesEmissive and state.weaponSpritesEmissive[b.type]) or (state.weaponSprites and state.weaponSprites[b.type])
                if sprite then
                    local sw, sh = sprite:getWidth(), sprite:getHeight()
                    local scale = ((b.size or sw) / sw) * ((state.weaponSpriteScale and state.weaponSpriteScale[b.type]) or 1)
                    local sx = scale
                    local sy = scale
                    love.graphics.setBlendMode("add")
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.push()
                    love.graphics.translate(b.x, b.y)
                    local rot = b.rotation
                    if b.type == 'oil_bottle' then
                        rot = 0
                    elseif b.type == 'heavy_hammer' and (b.vx or 0) < 0 then
                        rot = (rot or 0) + math.pi
                        sx = -sx
                    end
                    if rot then love.graphics.rotate(rot) end
                    love.graphics.draw(sprite, 0, 0, 0, sx, sy, sw/2, sh/2)
                    love.graphics.pop()
                    love.graphics.setBlendMode("alpha")
                end
            end
        end
    end

    -- Melee swing arc (emissive overlay)
    do
        local melee = p and p.meleeState
        if melee and melee.phase == 'swing' then
            local px, py = p.x, p.y
            local range = 90
            local arcWidth = 1.4
            local aimAngle = p.aimAngle or 0
            local r, g, b, a = 1, 1, 1, 0.22
            if melee.attackType == 'light' then
                r, g, b = 0.9, 0.95, 1
            elseif melee.attackType == 'heavy' then
                r, g, b = 1, 0.7, 0.3
            elseif melee.attackType == 'finisher' then
                r, g, b = 1, 0.4, 0.2
                a = 0.30
            end

            love.graphics.setBlendMode('add')
            love.graphics.setColor(r, g, b, a)
            love.graphics.setLineWidth(3)
            local startAng = aimAngle - arcWidth / 2
            local endAng = aimAngle + arcWidth / 2
            love.graphics.arc('line', 'open', px, py, range, startAng, endAng)
            love.graphics.line(px, py, px + math.cos(startAng) * range, py + math.sin(startAng) * range)
            love.graphics.line(px, py, px + math.cos(endAng) * range, py + math.sin(endAng) * range)
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode('alpha')
        end
    end

    -- ==================== 武器拖影绘制 ====================
    -- 绘制近战挥砍弧形拖影
    love.graphics.setBlendMode('add')
    weaponTrail.drawSlash()
    love.graphics.setBlendMode('alpha')
    
    -- 绘制投射物尾迹
    love.graphics.setBlendMode('add')
    weaponTrail.drawBulletTrails()
    love.graphics.setBlendMode('alpha')

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()

    return true
end

-- Backward compatible entry point
function draw.render(state)
    draw.renderBase(state)
end

return draw
