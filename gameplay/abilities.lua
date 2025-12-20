-- abilities.lua
-- 4-Ability system (Warframe-style)

local abilities = {}

-- Ability definitions structured by class
local defs = require('data.defs.abilities')
local defData = defs.build({
    addBuff = function(state, buff) return abilities.addBuff(state, buff) end
})
abilities.catalog = defData.catalog
abilities.passives = defData.passives

local function hasBuff(p, id)
    if not p or not p.buffs or not id then return false end
    for _, b in ipairs(p.buffs) do
        if b.id == id then return true end
    end
    return false
end

local function restoreCastMoveSpeed(p)
    if not p then return end
    local mult = p.castSlowMult
    if mult and mult ~= 0 then
        p.stats = p.stats or {}
        local current = p.stats.moveSpeed or p.castOriginalSpeed or 0
        p.stats.moveSpeed = current / mult
    end
    p.castOriginalSpeed = nil
    p.castSlowMult = nil
end

function abilities.detonateMagnetize(state, enemy, reason)
    local e = enemy
    if not e then return false end
    local m = e.magnetize
    if not m or m.detonated then return false end
    m.detonated = true

    local stored = m.storedDamage or 0
    local radius = m.radius or 0
    local explosionDmg = 0
    if stored > 0 and radius > 0 then
        explosionDmg = math.floor(stored * (m.explosionMult or 1))
    end

    if explosionDmg > 0 and radius > 0 then
        local ok, calc = pcall(require, 'gameplay.calculator')
        local inst = nil
        if ok and calc then
            inst = calc.createInstance({
                damage = explosionDmg,
                statusChance = 0.6,
                elements = {'MAGNETIC'},
                damageBreakdown = {MAGNETIC = 1},
                weaponTags = {'ability', 'magnetic', 'area'}
            })
        end
        local r2 = radius * radius
        for _, o in ipairs(state.enemies or {}) do
            if o and not o.isDummy then
                local dx = o.x - e.x
                local dy = o.y - e.y
                if dx * dx + dy * dy < r2 then
                    if inst and ok and calc then
                        calc.applyHit(state, o, inst)
                    else
                        o.health = (o.health or 0) - explosionDmg
                    end
                end
            end
        end
    end

    if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 1.4) end
    if state.texts then
        local text = (reason == 'recast' and "磁化引爆!") or "磁化爆发!"
        table.insert(state.texts, {x = e.x, y = e.y - 40, text = text, color = {0.8, 0.6, 1}, life = 1.2})
    end

    e.magnetize = nil
    return true
end


-- Simple helper to get ability definition
function abilities.getAbilityDef(state, index)
    local p = state.player
    local className = p.class or 'volt'
    local set = abilities.catalog[className]
    if set and set[index] then
        return set[index]
    end
    return nil
end



-- Apply passive for current class
function abilities.applyPassive(state)
    local p = state.player
    if not p then return end
    
    local className = p.class or 'volt'
    local passive = abilities.passives[className]
    
    if passive and passive.apply then
        passive.apply(state)
        p.passiveApplied = className
        
        -- Show notification
        if state.texts then
            table.insert(state.texts, {
                x = p.x, y = p.y - 60,
                text = passive.icon .. " " .. passive.name,
                color = {0.8, 0.9, 1},
                life = 2.0,
                scale = 1.2
            })
        end
    end
end

-- Get current passive info
function abilities.getPassiveInfo(state)
    local p = state.player
    if not p then return nil end
    
    local className = p.class or 'volt'
    return abilities.passives[className]
end

-- =============================================================================
-- BUFF SYSTEM
-- =============================================================================

function abilities.addBuff(state, buff)
    local p = state.player
    if not p then return end
    p.buffs = p.buffs or {}
    
    -- If a buff with the same id exists, remove it first (refresh)
    if buff.id then
        for i = #p.buffs, 1, -1 do
            if p.buffs[i].id == buff.id then
                if p.buffs[i].onExpire then p.buffs[i].onExpire(state) end
                table.remove(p.buffs, i)
            end
        end
    end
    
    table.insert(p.buffs, buff)
    if buff.onApply then buff.onApply(state) end
end

function abilities.updateBuffs(state, dt)
    local p = state.player
    if not p or not p.buffs then return end
    
    for i = #p.buffs, 1, -1 do
        local b = p.buffs[i]
        b.timer = b.timer - dt
        if b.timer <= 0 then
            if b.onExpire then b.onExpire(state) end
            table.remove(p.buffs, i)
        end
    end
end

function abilities.removeBuff(state, id)
    local p = state.player
    if not p or not p.buffs then return end
    for i = #p.buffs, 1, -1 do
        if p.buffs[i].id == id then
            if p.buffs[i].onExpire then p.buffs[i].onExpire(state) end
            table.remove(p.buffs, i)
        end
    end
end


-- Get ability definition by index (1-4) for current player class
function abilities.getAbilityByIndex(state, index)
    local p = state.player
    if not p then return nil end
    
    local className = p.class or 'volt'
    local classAbilities = abilities.catalog[className]
    if not classAbilities then return nil end
    
    return classAbilities[index]
end

-- Check if ability can be used (abilityIndex is 1, 2, 3, or 4)
function abilities.canUse(state, abilityIndex)
    local p = state.player
    if not p then return false end
    
    local def = abilities.getAbilityByIndex(state, abilityIndex)
    if not def then return false end
    
    -- Cannot use during casting animation
    if p.isCasting then return false end

    local togglingOff = def.toggleId and hasBuff(p, def.toggleId)
    if togglingOff then
        return true
    end
    
    -- Cannot use abilities inside Nullifier bubble
    local enemiesMod = require('gameplay.enemies')
    if enemiesMod.isInNullBubble and enemiesMod.isInNullBubble(state) then
        if state.texts and not p._nullBubbleWarningCd then
            table.insert(state.texts, {x = p.x, y = p.y - 40, text = "技能被屏蔽!", color = {0.6, 0.5, 0.9}, life = 0.8})
            p._nullBubbleWarningCd = 0.8  -- Cooldown to prevent spam
        end
        return false
    end

    if def.recastCheck and def.recastNoCost then
        local target = def.recastCheck(state)
        if target then
            return true
        end
    end
    
    -- Check energy (with efficiency preview)
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    if (p.energy or 0) < cost then return false end
    
    -- WF-style: Most abilities have NO cooldown, only energy limits
    -- Only check CD if explicitly set (rare cases like Helminth abilities)
    if def.cd and def.cd > 0 then
        p.abilityCooldowns = p.abilityCooldowns or {}
        if (p.abilityCooldowns[abilityIndex] or 0) > 0 then return false end
    end
    
    return true
end

-- Get cast time for an ability (affected by Natural Talent)
function abilities.getCastTime(state, def)
    local p = state.player
    if not def then return 0 end
    
    local baseCast = def.castTime or 0
    if baseCast <= 0 then return 0 end  -- Instant cast
    
    -- Natural Talent effect: reduce cast time
    local castSpeedMult = (p.stats and p.stats.castSpeed) or 1.0
    return baseCast / castSpeedMult
end

-- Try to activate ability (WF-style: no CD, with cast time)
-- abilityIndex is 1, 2, 3, or 4
function abilities.tryActivate(state, abilityIndex)
    if not abilities.canUse(state, abilityIndex) then return false end
    
    local p = state.player
    local def = abilities.getAbilityByIndex(state, abilityIndex)
    if not def then return false end
    
    local togglingOff = def.toggleId and hasBuff(p, def.toggleId)
    if togglingOff then
        abilities.removeBuff(state, def.toggleId)
        return true
    end

    if def.recastCheck and def.recastNoCost then
        local target = def.recastCheck(state)
        if target and def.recastAction then
            return def.recastAction(state, target)
        end
    end

    -- Consume energy (Efficiency reduces cost)
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    p.energy = (p.energy or 0) - cost
    
    -- Get cast time
    local castTime = abilities.getCastTime(state, def)
    
    if castTime > 0 then
        -- Start casting animation
        p.isCasting = true
        p.castTimer = castTime
        p.castDef = def
        p.castAbilityIndex = abilityIndex
        p.castProgress = 0
        
        -- Store original speed for slowing during cast
        if not p.castOriginalSpeed then
            p.castOriginalSpeed = p.stats.moveSpeed or 170
        end
        
        -- Slow movement during cast (50% speed)
        p.castSlowMult = 0.5
        p.stats.moveSpeed = p.castOriginalSpeed * p.castSlowMult
        
        -- Visual feedback: casting started
        if state.texts then
            table.insert(state.texts, {
                x = p.x, y = p.y - 40, 
                text = "施法中...", 
                color = {0.6, 0.8, 1, 0.8}, 
                life = castTime,
                scale = 0.8
            })
        end
        
        return true  -- Cast started
    else
        -- Instant cast: execute immediately
        local success = def.effect(state)
        
        -- Set CD only if explicitly defined (WF-style: most have none)
        if def.cd and def.cd > 0 then
            p.abilityCooldowns = p.abilityCooldowns or {}
            p.abilityCooldowns[abilityIndex] = def.cd
        end
        
        return success
    end
end

-- Interrupt casting (called when stunned, knocked down, etc.)
function abilities.interruptCast(state, reason)
    local p = state.player
    if not p or not p.isCasting then return false end
    
    -- Refund partial energy (50% if interrupted)
    if p.castDef then
        local eff = p.stats and p.stats.abilityEfficiency or 1.0
        local cost = math.floor(p.castDef.cost / eff)
        local refund = math.floor(cost * 0.5)
        p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + refund)
    end
    
    -- Restore movement speed (only undo cast slow)
    restoreCastMoveSpeed(p)
    
    -- Visual feedback
    if state.texts then
        table.insert(state.texts, {
            x = p.x, y = p.y - 30, 
            text = reason or "施法被打断!", 
            color = {1, 0.4, 0.4}, 
            life = 0.8
        })
    end
    
    -- Clear casting state
    p.isCasting = false
    p.castTimer = nil
    p.castDef = nil
    p.castAbilityIndex = nil
    p.castProgress = nil
    
    return true
end

-- Get ability index for keyboard input (1, 2, 3, 4)
function abilities.getAbilityForKey(key)
    local keyMap = {
        ['1'] = 1,
        ['2'] = 2,
        ['3'] = 3,
        ['4'] = 4
    }
    return keyMap[key]
end


-- Alias for backward compatibility (used by HUD)
abilities.getAbilityDef = abilities.getAbilityByIndex

-- Update casting, cooldowns and energy regen
function abilities.update(state, dt)
    local p = state.player
    if not p then return end
    
    -- Apply passive on first frame if not applied
    if not p.passiveApplied then
        abilities.applyPassive(state)
    end
    
    -- Buffs and Active Effects
    abilities.updateBuffs(state, dt)
    abilities.updateActiveEffects(state, dt)
    
    -- Apply warframe MODs on first frame if not applied
    if not p.warframeModsApplied then
        local mods = require('systems.mods')
        local slots = mods.getSlots(state, 'warframe', nil)
        local hasModsEquipped = false
        for _, m in ipairs(slots) do if m then hasModsEquipped = true break end end
        
        if hasModsEquipped then
            p.stats = p.stats or {}
            local modded = mods.applyWarframeMods(state, p.stats)
            for k, v in pairs(modded) do
                p.stats[k] = v
            end
            if modded.maxHp then p.maxHp = modded.maxHp end
            if modded.maxEnergy then p.maxEnergy = modded.maxEnergy end
            if modded.energyRegen then p.energyRegen = modded.energyRegen end
            if modded.moveSpeed then p.stats.moveSpeed = modded.moveSpeed end
            if modded.armor then p.stats.armor = modded.armor end
            
            if state.texts then
                table.insert(state.texts, {x=p.x, y=p.y-40, text="角色MOD已生效", color={0.5, 0.8, 1}, life=1.5})
            end
        end
        p.warframeModsApplied = true
    end
    
    -- === CASTING SYSTEM ===
    if p.isCasting and p.castTimer then
        p.castTimer = p.castTimer - dt
        local totalCast = abilities.getCastTime(state, p.castDef)
        p.castProgress = totalCast > 0 and (1 - (p.castTimer / totalCast)) or 1
        
        local interrupted = (p.stunTimer and p.stunTimer > 0) or (p.knockdownTimer and p.knockdownTimer > 0) or (p.frozenTimer and p.frozenTimer > 0)
        if interrupted then
            abilities.interruptCast(state, "被控制打断!")
        elseif p.castTimer <= 0 then
            if p.castDef and p.castDef.effect then p.castDef.effect(state) end
            if p.castDef and p.castDef.cd and p.castDef.cd > 0 then
                p.abilityCooldowns = p.abilityCooldowns or {}
                p.abilityCooldowns[p.castAbilityIndex] = p.castDef.cd
            end
            restoreCastMoveSpeed(p)
            p.isCasting, p.castTimer, p.castDef, p.castAbilityKey, p.castProgress = false, nil, nil, nil, nil
        end
    end
    
    -- Energy regen
    local regen = (p.stats and p.stats.energyRegen) or p.energyRegen or 2
    if p.isCasting then regen = regen * 0.5 end
    p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + regen * dt)
    
    -- Null bubble warning cooldown
    if p._nullBubbleWarningCd and p._nullBubbleWarningCd > 0 then
        p._nullBubbleWarningCd = p._nullBubbleWarningCd - dt
        if p._nullBubbleWarningCd <= 0 then p._nullBubbleWarningCd = nil end
    end
    
    -- Cooldown tick
    p.abilityCooldowns = p.abilityCooldowns or {}
    for key, cd in pairs(p.abilityCooldowns) do
        if cd > 0 then p.abilityCooldowns[key] = cd - dt end
    end
    
    -- Temp shield decay
    if p.tempShieldTimer and p.tempShieldTimer > 0 then
        p.tempShieldTimer = p.tempShieldTimer - dt
        if p.tempShieldTimer <= 0 then p.tempShield, p.tempShieldTimer = 0, nil end
    end
end

-- Unified function for persistent ability updates (Volt chains, WoF, Exalted Blade drain, etc.)
function abilities.updateActiveEffects(state, dt)
    local p = state.player
    if not p then return end
    
    -- 1. Volt Lightning VFX
    if state.voltLightningChains then
        for i = #state.voltLightningChains, 1, -1 do
            local c = state.voltLightningChains[i]
            c.timer = c.timer - dt
            c.alpha = math.max(0, c.timer / 0.5)
            if c.timer <= 0 then table.remove(state.voltLightningChains, i) end
        end
    end
    
    if p.exaltedBladeActive then
        p.energy = (p.energy or 0) - 2.5 * dt -- Energy drain
        if p.energy <= 0 then
            p.energy = 0
            abilities.removeBuff(state, "excalibur_exalted_blade")
            if state.texts then table.insert(state.texts, {x=p.x, y=p.y-30, text="能量竭尽", color={1,0,0}, life=1}) end
        end
    end
    
    
    if p.electricShield and p.electricShield.active then
        p.electricShield.timer = p.electricShield.timer - dt
        if p.electricShield.timer <= 0 then 
            p.electricShield.active = false
            if state.texts then
                table.insert(state.texts, {x=p.x, y=p.y-30, text="电盾消散", color={0.6,0.6,0.8}, life=1})
            end
        elseif p.electricShield.followPlayer then
            local ang = p.aimAngle or 0
            local dst = p.electricShield.distance or 60
            p.electricShield.x, p.electricShield.y, p.electricShield.angle = p.x + math.cos(ang)*dst, p.y + math.sin(ang)*dst, ang
        end
    end

    -- 4. Mag: Magnetize fields
    if state.enemies then
        state.magMagnetizeFields = nil
        for _, e in ipairs(state.enemies) do
            local m = e and e.magnetize
            if m and m.timer and m.timer > 0 then
                m.timer = m.timer - dt
                m.tick = (m.tick or 0) + dt

                state.magMagnetizeFields = state.magMagnetizeFields or {}
                table.insert(state.magMagnetizeFields, {x = e.x, y = e.y, r = m.radius or 0, t = m.timer})

                local pullStrength = m.pullStrength or 160
                if m.radius and m.radius > 0 then
                    local r2 = m.radius * m.radius
                    for _, o in ipairs(state.enemies or {}) do
                        if o and o ~= e and not o.isDummy then
                            local dx = e.x - o.x
                            local dy = e.y - o.y
                            local d2 = dx*dx + dy*dy
                            if d2 < r2 and d2 > 1 then
                                local len = math.sqrt(d2)
                                local step = pullStrength * dt
                                local mx = dx / len * step
                                local my = dy / len * step
                                if state.world and state.world.moveCircle then
                                    o.x, o.y = state.world:moveCircle(o.x, o.y, (o.size or 16) / 2, mx, my)
                                else
                                    o.x = o.x + mx
                                    o.y = o.y + my
                                end
                            end
                        end
                    end
                end

                if m.tick >= 0.5 then
                    local tickTime = m.tick
                    m.tick = 0
                    local tickDmg = math.floor((m.dps or 0) * tickTime)
                    if tickDmg > 0 then
                        local ok, calc = pcall(require, 'gameplay.calculator')
                        local inst = nil
                        if ok and calc then
                            inst = calc.createInstance({
                                damage = tickDmg,
                                statusChance = 0.3,
                                elements = {'MAGNETIC'},
                                damageBreakdown = {MAGNETIC = 1},
                                weaponTags = {'ability', 'magnetic', 'area'}
                            })
                        end
                        local r2 = (m.radius or 0) * (m.radius or 0)
                        for _, o in ipairs(state.enemies or {}) do
                            if o and not o.isDummy then
                                local dx = o.x - e.x
                                local dy = o.y - e.y
                                if dx*dx + dy*dy < r2 then
                                    if inst and ok and calc then
                                        calc.applyHit(state, o, inst)
                                    else
                                        o.health = (o.health or 0) - tickDmg
                                    end
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('static', e.x, e.y, 0.6) end
                    end
                end

                if m.timer <= 0 then
                    abilities.detonateMagnetize(state, e, 'timeout')
                end
            elseif m then
                e.magnetize = nil
            end
        end
    end

    -- 5. Volt: Discharge & Tesla Nodes
    if p.dischargeWave and p.dischargeWave.active then
        local wave = p.dischargeWave
        wave.timer = wave.timer - dt
        
        local oldRadius = wave.currentRadius
        wave.currentRadius = wave.currentRadius + wave.expandSpeed * dt
        local effNew = math.min(wave.currentRadius, wave.maxRadius)
        local effOld = math.min(oldRadius, wave.maxRadius)
        
        if effOld < wave.maxRadius then
            local ok, calc = pcall(require, 'gameplay.calculator')
            for _, e in ipairs(state.enemies or {}) do
                if e and not e.isDummy and not wave.hitEnemies[e] then
                    local dx, dy = e.x - wave.x, e.y - wave.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= effNew and dist >= effOld then
                        wave.hitEnemies[e] = true
                        if ok and calc then
                            local inst = calc.createInstance({
                                damage = wave.damage,
                                critChance = 0.2, critMultiplier = 2.5, statusChance = 1.0,
                                elements = {'ELECTRIC'}, weaponTags = {'ability', 'area', 'electric'}
                            })
                            calc.applyHit(state, e, inst)
                        else
                            e.health = (e.health or 0) - wave.damage
                        end
                        e.frozenTimer = wave.stunDuration
                        e.teslaNode = {
                            active = true,
                            timer = wave.teslaNodeDuration or wave.stunDuration,
                            dps = wave.teslaNodeDPS or 15,
                            range = wave.teslaNodeRange or 120,
                            damageTickTimer = 0
                        }
                        if state.spawnEffect then state.spawnEffect('shock', e.x, e.y, 1.0) end
                    end
                end
            end
        end
        if wave.timer <= 0 then p.dischargeWave = nil end
    end

    -- Discharge Wave VFX update
    if state.voltDischargeWaves then
        for i = #state.voltDischargeWaves, 1, -1 do
            local w = state.voltDischargeWaves[i]
            w.timer = w.timer - dt
            if w.currentRadius < w.maxRadius then
                w.currentRadius = math.min(w.maxRadius, w.currentRadius + w.expandSpeed * dt)
            end
            w.alpha = math.max(0, w.timer * 2)
            if w.timer <= 0 then table.remove(state.voltDischargeWaves, i) end
        end
    end

    -- Tesla Node Network
    local nodes = {}
    for _, e in ipairs(state.enemies or {}) do
        if e and e.teslaNode and e.teslaNode.active then table.insert(nodes, e) end
    end
    if #nodes > 0 then
        local ok, calc = pcall(require, 'gameplay.calculator')
        state.teslaArcs = {}
        for i, e1 in ipairs(nodes) do
            local n1 = e1.teslaNode
            n1.timer = n1.timer - dt
            n1.damageTickTimer = n1.damageTickTimer + dt
            if n1.timer <= 0 then
                n1.active = false
                e1.teslaNode = nil
            else
                local r2 = n1.range * n1.range
                for j = i + 1, #nodes do
                    local e2 = nodes[j]
                    if e2.teslaNode and e2.teslaNode.active then
                        local d2 = (e2.x-e1.x)^2 + (e2.y-e1.y)^2
                        if d2 <= r2 then
                            table.insert(state.teslaArcs, {x1=e1.x, y1=e1.y, x2=e2.x, y2=e2.y, alpha=0.7 + 0.3*math.sin(love.timer.getTime()*10)})
                            if n1.damageTickTimer >= 0.5 then
                                local dmg = math.floor(n1.dps * 0.5)
                                if ok and calc then
                                    local inst = calc.createInstance({damage=dmg, statusChance=0.5, elements={'ELECTRIC'}, weaponTags={'ability','electric','tesla'}})
                                    calc.applyHit(state, e1, inst); calc.applyHit(state, e2, inst)
                                else
                                    e1.health = (e1.health or 0) - dmg
                                    e2.health = (e2.health or 0) - dmg
                                end
                            end
                        end
                    end
                end
                if n1.damageTickTimer >= 0.5 then n1.damageTickTimer = 0 end
                if e1.frozenTimer and e1.frozenTimer < 0.2 then e1.frozenTimer = 0.2 end
            end
        end
    end
end


return abilities
