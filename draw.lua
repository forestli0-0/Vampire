local weapons = require('weapons')
local enemies = require('enemies')
local vfx = require('vfx')

local draw = {}

local outlineShader
local function getOutlineShader()
    if outlineShader then return outlineShader end
    outlineShader = love.graphics.newShader([[
        extern vec2 texelSize;
        extern number thickness;
        extern vec4 outlineColor;

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
        {
            vec4 base = Texel(tex, uv);
            if (base.a > 0.001) {
                return vec4(0.0);
            }

            number a = 0.0;
            vec2 o = texelSize;

            a = max(a, Texel(tex, uv + vec2( o.x, 0.0)).a);
            a = max(a, Texel(tex, uv + vec2(-o.x, 0.0)).a);
            a = max(a, Texel(tex, uv + vec2(0.0,  o.y)).a);
            a = max(a, Texel(tex, uv + vec2(0.0, -o.y)).a);
            a = max(a, Texel(tex, uv + vec2( o.x,  o.y)).a);
            a = max(a, Texel(tex, uv + vec2(-o.x,  o.y)).a);
            a = max(a, Texel(tex, uv + vec2( o.x, -o.y)).a);
            a = max(a, Texel(tex, uv + vec2(-o.x, -o.y)).a);

            if (thickness > 1.5) {
                vec2 o2 = o * 2.0;
                a = max(a, Texel(tex, uv + vec2( o2.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(-o2.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(0.0,  o2.y)).a);
                a = max(a, Texel(tex, uv + vec2(0.0, -o2.y)).a);
                a = max(a, Texel(tex, uv + vec2( o2.x,  o2.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o2.x,  o2.y)).a);
                a = max(a, Texel(tex, uv + vec2( o2.x, -o2.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o2.x, -o2.y)).a);
            }

            if (thickness > 2.5) {
                vec2 o3 = o * 3.0;
                a = max(a, Texel(tex, uv + vec2( o3.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(-o3.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(0.0,  o3.y)).a);
                a = max(a, Texel(tex, uv + vec2(0.0, -o3.y)).a);
                a = max(a, Texel(tex, uv + vec2( o3.x,  o3.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o3.x,  o3.y)).a);
                a = max(a, Texel(tex, uv + vec2( o3.x, -o3.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o3.x, -o3.y)).a);
            }

            if (a > 0.001) {
                return outlineColor * a;
            }
            return vec4(0.0);
        }
    ]])
    return outlineShader
end

local dashTrailShader
local function getDashTrailShader()
    if dashTrailShader ~= nil then return dashTrailShader or nil end
    if not love or not love.graphics or not love.graphics.newShader then
        dashTrailShader = false
        return nil
    end
    local ok, sh = pcall(love.graphics.newShader, [[
        extern number time;
        extern number alpha;
        extern vec3 tint;
        extern number warp;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            number a = hash(i);
            number b = hash(i + vec2(1.0, 0.0));
            number c = hash(i + vec2(0.0, 1.0));
            number d = hash(i + vec2(1.0, 1.0));
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
        }

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
        {
            vec4 base = Texel(tex, uv) * color;
            if (base.a <= 0.001) {
                return vec4(0.0);
            }

            number n = noise(uv * 10.0 + vec2(time * 2.3, -time * 1.9));
            vec2 duv = uv + (vec2(n, 1.0 - n) - 0.5) * warp;
            duv = clamp(duv, vec2(0.0), vec2(1.0));

            vec4 b2 = Texel(tex, duv) * color;
            vec3 col = mix(b2.rgb, tint, 0.85);
            col += tint * (n - 0.5) * 0.35;

            number a = b2.a * alpha * (0.75 + 0.25 * n);
            col = clamp(col, vec3(0.0), vec3(1.0));
            return vec4(col, a);
        }
    ]])
    if ok then dashTrailShader = sh else dashTrailShader = false end
    return dashTrailShader or nil
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
    table.insert(lines, string.format("Move: %.0f", ps.moveSpeed or 0))
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
        love.graphics.translate(love.math.random() * state.shakeAmount, love.math.random() * state.shakeAmount)
    end
    love.graphics.translate(-state.camera.x, -state.camera.y)

    -- 背景平铺
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

    -- 房间出口门（分支奖励）
    if state.doors then
        local colors = {
            weapon = {1.0, 0.55, 0.5},
            passive = {0.55, 1.0, 0.55},
            mod = {0.55, 0.8, 1.0},
            augment = {1.0, 0.9, 0.45},
            shop = {0.55, 0.95, 1.0},
            event = {0.9, 0.7, 1.0}
        }
        for _, d in ipairs(state.doors) do
            local col = colors[d.rewardType] or {1, 1, 1}
            if d.roomKind == 'shop' then col = colors.shop end
            if d.roomKind == 'event' then col = colors.event end
            local w = d.w or 54
            local h = d.h or 86
            local x = d.x or 0
            local y = d.y or 0

            love.graphics.setColor(col[1], col[2], col[3], 0.75)
            love.graphics.rectangle('fill', x - w/2, y - h/2, w, h, 8, 8)
            love.graphics.setColor(0, 0, 0, 0.45)
            love.graphics.rectangle('line', x - w/2, y - h/2, w, h, 8, 8)
            if d.roomKind == 'elite' then
                love.graphics.setColor(1, 0.2, 0.2, 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle('line', x - w/2 - 3, y - h/2 - 3, w + 6, h + 6, 10, 10)
                love.graphics.setLineWidth(1)
            elseif d.roomKind == 'shop' then
                love.graphics.setColor(0.35, 0.95, 1.0, 0.85)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle('line', x - w/2 - 2, y - h/2 - 2, w + 4, h + 4, 10, 10)
                love.graphics.setLineWidth(1)
            elseif d.roomKind == 'event' then
                love.graphics.setColor(0.95, 0.7, 1.0, 0.85)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle('line', x - w/2 - 2, y - h/2 - 2, w + 4, h + 4, 10, 10)
                love.graphics.setLineWidth(1)
            end
            love.graphics.setColor(1, 1, 1, 0.95)
            local label = d.rewardType and string.upper(tostring(d.rewardType)) or "?"
            if d.roomKind == 'shop' then label = "SHOP" end
            if d.roomKind == 'event' then label = "EVENT" end
            love.graphics.printf(label, x - 80, y - h/2 - 18, 160, "center")
            if d.roomKind == 'elite' then
                love.graphics.setColor(1, 0.2, 0.2, 0.95)
                love.graphics.printf("ELITE", x - 80, y + h/2 + 2, 160, "center")
            end
        end
        love.graphics.setColor(1, 1, 1)
    end

    -- 地面道具
    for _, item in ipairs(state.floorPickups) do
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
            end
        end
        if isGlow then love.graphics.setBlendMode("alpha") end
    end

    -- 经验宝石
    for _, g in ipairs(state.gems) do
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
        local shadowR = (e.size or 16) * 0.6
        local shadowY = shadowR * 0.4
        love.graphics.setColor(0,0,0,0.25)
        love.graphics.ellipse('fill', e.x, e.y + (e.size or 16) * 0.55, shadowR, shadowY)

        -- Outline for elites/bosses (drawn behind base)
        if e.isBoss or e.isElite then
            local outlineCol
            if e.isBoss then
                outlineCol = {1, 0.6, 0.2, 0.85}
            else
                outlineCol = {1, 0.15, 0.15, 0.75}
            end
            local t = e.isBoss and 2 or 1
            if e.anim then
                local sx = e.facing or 1
                drawOutlineAnim(e.anim, e.x, e.y, 0, sx, 1, t, outlineCol)
            else
                love.graphics.setColor(outlineCol)
                drawOutlineRect(e.x, e.y, e.size or 16, t)
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

        -- Base draw (keep enemy readable even under sustained hits)
        love.graphics.setColor(col)
        if e.anim then
            local sx = e.facing or 1
            e.anim:draw(e.x, e.y, 0, sx, 1)
        else
            love.graphics.rectangle('fill', e.x - e.size/2, e.y - e.size/2, e.size, e.size)
        end

        -- Hit flash overlay: white highlight instead of forcing full-white base
        local ft = e.flashTimer or 0
        if ft > 0 then
            local f = math.min(1, ft / 0.1)
            local a = 0.22 + 0.28 * f
            love.graphics.setColor(1, 1, 1, a)
            if e.anim then
                local sx = e.facing or 1
                e.anim:draw(e.x, e.y, 0, sx, 1)
            else
                love.graphics.rectangle('fill', e.x - e.size/2, e.y - e.size/2, e.size, e.size)
            end
        end
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
        local shadowR = size * 0.7
        local shadowY = shadowR * 0.35
        love.graphics.setColor(0,0,0,0.25)
        love.graphics.ellipse('fill', state.player.x, state.player.y + size * 0.55, shadowR, shadowY)
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

    -- Player outline (drawn behind base)
    if state.playerAnim then
        drawOutlineAnim(state.playerAnim, state.player.x, state.player.y, 0, state.player.facing, 1, 1, {0.9, 0.95, 1, 0.55})
    else
        love.graphics.setColor(0.9, 0.95, 1, 0.55)
        drawOutlineRect(state.player.x, state.player.y, state.player.size or 20, 1)
        love.graphics.setColor(1, 1, 1, 1)
    end

    if state.playerAnim then
        if blink then love.graphics.setColor(1,1,1,0.35) else love.graphics.setColor(1,1,1) end
        state.playerAnim:draw(state.player.x, state.player.y, 0, state.player.facing, 1)
    else
        if blink then love.graphics.setColor(1,1,1) else love.graphics.setColor(0,1,0) end
        love.graphics.rectangle('fill', state.player.x - (state.player.size/2), state.player.y - (state.player.size/2), state.player.size, state.player.size)
    end
    love.graphics.setColor(1,1,1)

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
                if b.type == 'axe' then love.graphics.setColor(0,1,1) else love.graphics.setColor(1,1,0) end
                love.graphics.push()
                love.graphics.translate(b.x, b.y)
                if b.rotation then love.graphics.rotate(b.rotation) end
                love.graphics.rectangle('fill', -b.size/2, -b.size/2, b.size, b.size)
                love.graphics.pop()
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
        local sprite = state.enemySprites and state.enemySprites[eb.spriteKey or '']
        if sprite then
            love.graphics.setColor(1,1,1)
            local sw, sh = sprite:getWidth(), sprite:getHeight()
            local baseScale = (eb.size or sw) / sw
            if eb.spriteKey == 'plant_bullet' then baseScale = baseScale * 2 end
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

    -- 飘字
    for _, t in ipairs(state.texts) do love.graphics.setColor(t.color); love.graphics.print(t.text, t.x, t.y) end
    love.graphics.pop()
end

function draw.renderUI(state)
    love.graphics.setFont(state.font)

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

    drawStatsPanel(state)
    drawPetPanel(state)

    -- HUD
    local showXpHud = true
    if state.runMode == 'rooms' and state.rooms and state.rooms.useXp == false then
        showXpHud = false
    end

    if showXpHud then
        love.graphics.setColor(0, 0, 1)
        local xpRatio = 0
        if state.player.xpToNextLevel and state.player.xpToNextLevel > 0 then
            xpRatio = math.min(1, (state.player.xp or 0) / state.player.xpToNextLevel)
        end
        love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth() * xpRatio, 10)
    end

    local hpRatio = math.min(1, math.max(0, state.player.hp / state.player.maxHp))
    love.graphics.setColor(1, 0, 0)
    love.graphics.rectangle('fill', 10, 20, 150 * hpRatio, 15)
    love.graphics.setColor(1, 1, 1)

    if showXpHud then
        love.graphics.print("LV " .. state.player.level, 10, 40)
    end

    do
        local p = state.player or {}
        local dash = p.dash or {}
        local maxCharges = (p.stats and p.stats.dashCharges) or dash.maxCharges or 0
        if maxCharges and maxCharges > 0 then
            local charges = dash.charges or 0
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(string.format("DASH %d/%d (Space)", charges, maxCharges), 10, 58)

            if charges < maxCharges then
                local cd = (p.stats and p.stats.dashCooldown) or 0
                local t = dash.rechargeTimer or 0
                local ratio = 0
                if cd > 0 then
                    ratio = math.max(0, math.min(1, t / cd))
                end
                local barX, barY, barW, barH = 10, 76, 150, 5
                love.graphics.setColor(0.1, 0.1, 0.1, 0.65)
                love.graphics.rectangle('fill', barX, barY, barW, barH)
                love.graphics.setColor(0.55, 0.85, 1.0, 0.9)
                love.graphics.rectangle('fill', barX, barY, barW * ratio, barH)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    do
        local gold = math.floor(state.runCurrency or 0)
        love.graphics.setColor(1, 0.95, 0.55, 0.95)
        love.graphics.print(string.format("GOLD %d", gold), 10, 90)
        love.graphics.setColor(1, 1, 1, 1)
    end

    local minutes = math.floor(state.gameTimer / 60)
    local seconds = math.floor(state.gameTimer % 60)
    local timeStr = string.format("%02d:%02d", minutes, seconds)
    love.graphics.printf(timeStr, 0, 20, love.graphics.getWidth(), "center")

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
    end

    if state.gameState == 'GAME_CLEAR' then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setColor(0,0,0,0.8)
        love.graphics.rectangle('fill', 0, 0, w, h)
        love.graphics.setFont(state.titleFont)
        love.graphics.setColor(0.4, 1, 0.4)
        love.graphics.printf("VICTORY!", 0, h/2 - 70, w, "center")
        love.graphics.setFont(state.font)
        love.graphics.setColor(1,1,1)
        local rewards = state.victoryRewards or {}
        local rewardStr = ""
        if rewards.currency and rewards.currency > 0 then
            rewardStr = rewardStr .. string.format("+%d Credits", rewards.currency)
        end
        if rewards.newModName then
            if rewardStr ~= "" then rewardStr = rewardStr .. "  |  " end
            rewardStr = rewardStr .. "New Mod: " .. rewards.newModName
        end
        if rewardStr ~= "" then
            love.graphics.printf(rewardStr, 0, h/2 - 10, w, "center")
        end
        love.graphics.printf("Boss defeated. Press R to return to Arsenal", 0, h/2 + 20, w, "center")
    end

    if state.gameState == 'GAME_OVER' then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setColor(0,0,0,0.75)
        love.graphics.rectangle('fill', 0, 0, w, h)
        love.graphics.setFont(state.titleFont)
        love.graphics.setColor(1,0.2,0.2)
        love.graphics.printf("GAME OVER", 0, h/2 - 60, w, "center")
        love.graphics.setFont(state.font)
        love.graphics.setColor(1,1,1)
        love.graphics.printf("Press R to restart", 0, h/2, w, "center")
    end

    if state.gameState == 'SHOP' then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle('fill', 0, 0, w, h)
        love.graphics.setFont(state.titleFont)
        love.graphics.setColor(0.55, 0.95, 1.0)
        love.graphics.printf("SHOP", 0, 80, w, "center")

        love.graphics.setFont(state.font)
        local gold = math.floor(state.runCurrency or 0)
        love.graphics.setColor(1, 0.95, 0.55, 0.95)
        love.graphics.printf(string.format("GOLD %d", gold), 0, 120, w, "center")

        local shop = state.shop or {}
        local options = shop.options or {}
        local maxShow = math.min(6, #options)
        local boxX, boxW, boxH = 200, 400, 84
        local gap = 12
        local totalH = maxShow * boxH + math.max(0, maxShow - 1) * gap
        local startY = 160
        local maxY = h - 120
        if startY + totalH > maxY then
            startY = math.max(130, maxY - totalH)
        end
        for i = 1, maxShow do
            local opt = options[i]
            local y = startY + (i - 1) * (boxH + gap)
            local cost = math.floor(opt.cost or 0)
            local affordable = (gold >= cost)
            local enabled = (opt.enabled == nil) and true or (opt.enabled == true)
            local active = enabled and affordable

            love.graphics.setColor(0.3, 0.3, 0.3, 0.9)
            love.graphics.rectangle('fill', boxX, y, boxW, boxH, 8, 8)

            if active then
                love.graphics.setColor(1, 1, 1, 1)
            else
                love.graphics.setColor(0.6, 0.6, 0.6, 1)
            end
            local name = opt.name or opt.id or "Item"
            local desc = opt.desc or ""
            love.graphics.print(string.format("%d. %s", i, name), boxX + 16, y + 12)
            love.graphics.setColor(0.75, 0.75, 0.75, 1)
            love.graphics.print(desc, boxX + 16, y + 38)

            if not enabled and opt.disabledReason then
                love.graphics.setColor(1, 0.55, 0.55, 0.95)
                love.graphics.print(opt.disabledReason, boxX + 16, y + 62)
            end

            if affordable then
                love.graphics.setColor(1, 0.95, 0.55, 0.95)
            else
                love.graphics.setColor(1, 0.35, 0.35, 0.95)
            end
            love.graphics.print(string.format("Cost: %d", cost), boxX + 300, y + 12)
        end

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(string.format("Press 1-%d to buy, or 0 to leave", maxShow), 0, h - 70, w, "center")

        if shop.message then
            love.graphics.setColor(1, 0.8, 0.3)
            love.graphics.printf(shop.message, 0, h - 100, w, "center")
        end
    end

    if state.gameState == 'LEVEL_UP' then
        love.graphics.setColor(0,0,0,0.9)
        love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setFont(state.titleFont)

        if state.pendingWeaponSwap and state.pendingWeaponSwap.opt then
            local swapOpt = state.pendingWeaponSwap.opt
            love.graphics.printf("WEAPON SWAP! Choose a weapon to replace:", 0, 90, love.graphics.getWidth(), "center")
            love.graphics.setFont(state.font)
            love.graphics.setColor(0.9, 0.9, 0.9)
            love.graphics.printf("New: " .. tostring(swapOpt.name or swapOpt.key), 0, 140, love.graphics.getWidth(), "center")

            local weaponKeys = {}
            for k, _ in pairs(state.inventory.weapons or {}) do table.insert(weaponKeys, k) end
            table.sort(weaponKeys)

            for i, key in ipairs(weaponKeys) do
                local y = 210 + (i - 1) * 100
                love.graphics.setColor(0.3, 0.3, 0.3)
                love.graphics.rectangle('fill', 200, y, 400, 80)
                love.graphics.setColor(1, 1, 1)
                local def = state.catalog[key] or {}
                local inv = state.inventory.weapons[key] or {}
                local name = def.name or key
                love.graphics.print(string.format("%d. %s  (Lv%d)", i, name, inv.level or 1), 220, y + 18)
            end

            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("Press 1-3 to replace, or 0 to cancel", 0, 550, love.graphics.getWidth(), "center")
        else
            local title = "LEVEL UP! Choose One:"
            local req = state.activeUpgradeRequest or {}
            if req and req.allowedTypes and (req.allowedTypes.pet or (type(req.allowedTypes) == 'table' and #req.allowedTypes > 0 and req.allowedTypes[1] == 'pet')) then
                title = "CHOOSE A PET:"
            elseif req and req.allowedTypes and req.allowedTypes.pet_module then
                title = "CHOOSE A PET MODULE:"
            elseif req and req.allowedTypes and req.allowedTypes.pet_upgrade then
                title = "CHOOSE A PET UPGRADE:"
            end
            love.graphics.printf(title, 0, 100, love.graphics.getWidth(), "center")

            love.graphics.setFont(state.font)
            for i, opt in ipairs(state.upgradeOptions) do
                local y = 200 + (i-1) * 100
                love.graphics.setColor(0.3, 0.3, 0.3)
                love.graphics.rectangle('fill', 200, y, 400, 80)
                love.graphics.setColor(1,1,1)
                love.graphics.print(i .. ". " .. opt.name, 220, y+10)
                love.graphics.setColor(0.7,0.7,0.7)
                love.graphics.print(opt.desc, 220, y+35)

                if opt.type == 'weapon' and opt.def and opt.def.base then
                    local w = state.inventory.weapons[opt.key]
                    local base = opt.def.base
                    local crit = (w and w.critChance) or base.critChance or 0
                    local critMult = (w and w.critMultiplier) or base.critMultiplier or 1.5
                    local status = (w and w.statusChance) or base.statusChance or 0
                    local amount = (w and w.amount) or base.amount or 0
                    
                    local statStr = string.format("Crit: %d%% (x%.1f)  Status: %d%%", crit*100, critMult, status*100)
                    if amount > 0 then
                        statStr = statStr .. string.format("  Multi: +%d", amount)
                    end
                    love.graphics.setColor(0.8, 0.8, 0.5)
                    love.graphics.print(statStr, 220, y+55)
                end

                local curLv = 0
                if opt.type == 'weapon' and state.inventory.weapons[opt.key] then curLv = state.inventory.weapons[opt.key].level end
                if opt.type == 'passive' and state.inventory.passives[opt.key] then curLv = state.inventory.passives[opt.key] end
                if opt.type == 'mod' then
                    local profile = state.profile
                    local r = profile and profile.modRanks and profile.modRanks[opt.key]
                    if r ~= nil then
                        curLv = r
                    elseif profile and profile.ownedMods and profile.ownedMods[opt.key] then
                        curLv = 1
                    end
                end
                if opt.type == 'augment' and state.inventory.augments and state.inventory.augments[opt.key] then curLv = state.inventory.augments[opt.key] end
                if opt.type == 'pet_upgrade' then
                    curLv = (state.pets and state.pets.upgrades and state.pets.upgrades[opt.key]) or 0
                end
                if opt.type == 'pet_module' then
                    local pet = state.pets and state.pets.list and state.pets.list[1]
                    local modId = opt.def and opt.def.moduleId
                    if pet and modId and (pet.module or 'default') == modId then curLv = 1 else curLv = 0 end
                end
                love.graphics.print("Current Lv: " .. curLv, 500, y+10)
            end
            love.graphics.setColor(1,1,1)
            love.graphics.printf("Press 1, 2, or 3 to select", 0, 550, love.graphics.getWidth(), "center")
        end
    end
end

-- Backward compatible entry point
function draw.render(state)
    draw.renderWorld(state)
    draw.renderUI(state)
end

return draw
