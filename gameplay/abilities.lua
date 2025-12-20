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



-- Simple helper to get ability definition
function abilities.getAbilityDef(state, index)
    local p = state.player
    local className = p.class or 'warrior'
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
    
    local className = p.class or 'warrior'
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
    
    local className = p.class or 'warrior'
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
    
    local className = p.class or 'warrior'
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
    
    -- Cannot use abilities inside Nullifier bubble
    local enemiesMod = require('gameplay.enemies')
    if enemiesMod.isInNullBubble and enemiesMod.isInNullBubble(state) then
        if state.texts and not p._nullBubbleWarningCd then
            table.insert(state.texts, {x = p.x, y = p.y - 40, text = "技能被屏蔽!", color = {0.6, 0.5, 0.9}, life = 0.8})
            p._nullBubbleWarningCd = 0.8  -- Cooldown to prevent spam
        end
        return false
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
    
    -- 2. Mage: World on Fire (Channeling/Timer)
    if p.wofRunning then
        p.energy = (p.energy or 0) - 2.5 * dt
        if p.energy <= 0 then
            p.energy = 0
            abilities.removeBuff(state, "mage_world_on_fire")
        else
            p.wofPulseTimer = (p.wofPulseTimer or 0) + dt
            if p.wofPulseTimer >= 0.4 then
                p.wofPulseTimer = 0
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local radius = 250 * rng
                local ok, calc = pcall(require, 'gameplay.calculator')
                if ok and calc then
                    local inst = calc.createInstance({damage=math.floor(30*str), elements={'HEAT'}, weaponTags={'ability','fire'}})
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                            if d2 < radius*radius then
                                calc.applyHit(state, e, inst)
                                if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 0.6) end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if p.exaltedBladeActive then
        p.energy = (p.energy or 0) - 2.5 * dt -- Energy drain
        if p.energy <= 0 then
            p.energy = 0
            abilities.removeBuff(state, "warrior_exalted_blade")
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
