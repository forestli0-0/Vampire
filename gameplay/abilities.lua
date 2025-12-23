-- 技能系统 (Abilities System)
-- 包含：4-技能循环、Buff 系统、施法逻辑 以及 复杂技能的持续效果 (如 Volt 的 Discharge, Mag 的 Magnetize)。
-- 技能设计思路参考 Warframe。

local abilities = {}

-- 加载不同职业的技能定义
local defs = require('data.defs.abilities')
local defData = defs.build({
    addBuff = function(state, buff) return abilities.addBuff(state, buff) end
})
abilities.catalog = defData.catalog
abilities.passives = defData.passives

-------------------------------------------
-- 基础辅助函数
-------------------------------------------

local function hasBuff(p, id)
    if not p or not p.buffs or not id then return false end
    for _, b in ipairs(p.buffs) do
        if b.id == id then return true end
    end
    return false
end

--- restoreCastMoveSpeed: 恢复施法导致的减速。
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

--- detonateMagnetize: 引爆 Mag 的磁化区域。
-- 会根据该区域内积攒的伤害释放一个范围爆发。
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

    -- 应用全方位的磁力爆炸
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

--- getAbilityDef: 获取特定索引的技能定义。
function abilities.getAbilityDef(state, index)
    local p = state.player
    local className = p.class or 'volt'
    local set = abilities.catalog[className]
    if set and set[index] then
        return set[index]
    end
    return nil
end

--- applyPassive: 应用当前职业的被动技能。
function abilities.applyPassive(state)
    local p = state.player
    if not p then return end
    
    local className = p.class or 'volt'
    local passive = abilities.passives[className]
    
    if passive and passive.apply then
        passive.apply(state)
        p.passiveApplied = className
        
        -- 显示通知
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

function abilities.getPassiveInfo(state)
    local p = state.player
    if not p then return nil end
    local className = p.class or 'volt'
    return abilities.passives[className]
end

-- =============================================================================
-- 增益/减益系统 (BUFF SYSTEM)
-- =============================================================================

--- addBuff: 为玩家添加一个 Buff。
-- 如果存在相同 ID 的 Buff，则执行刷新 (Expire -> Remove -> Add)。
function abilities.addBuff(state, buff)
    local p = state.player
    if not p then return end
    p.buffs = p.buffs or {}
    
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

--- updateBuffs: 更新所有 Buff 的生命周期。
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

--- getAbilityByIndex: 获取当前职业 1-4 档位的技能。
function abilities.getAbilityByIndex(state, index)
    local p = state.player
    if not p then return nil end
    
    local className = p.class or 'volt'
    local classAbilities = abilities.catalog[className]
    if not classAbilities then return nil end
    
    return classAbilities[index]
end

--- canUse: 检查当前能否释放特定索引的技能。
-- 检查：蓝量、干扰区 (Nullifier)、施法中状态、特殊重放 (Recast) 逻辑。
function abilities.canUse(state, abilityIndex)
    local p = state.player
    if not p then return false end
    
    local def = abilities.getAbilityByIndex(state, abilityIndex)
    if not def then return false end
    
    -- 施法动画中禁止重复释放
    if p.isCasting then return false end

    -- 开关类技能总是可以通过再次按键关闭
    local togglingOff = def.toggleId and hasBuff(p, def.toggleId)
    if togglingOff then
        return true
    end
    
    -- 干扰区 (Nullifier bubble) 内禁用技能
    local enemiesMod = require('gameplay.enemies')
    if enemiesMod.isInNullBubble and enemiesMod.isInNullBubble(state) then
        if state.texts and not p._nullBubbleWarningCd then
            table.insert(state.texts, {x = p.x, y = p.y - 40, text = "技能被屏蔽!", color = {0.6, 0.5, 0.9}, life = 0.8})
            p._nullBubbleWarningCd = 0.8
        end
        return false
    end

    -- 检查是否处于“免费重放”阶段 (例如 Mag 的磁化引爆)
    if def.recastCheck and def.recastNoCost then
        local target = def.recastCheck(state)
        if target then
            return true
        end
    end
    
    -- 能量 (Energy) 消耗计算
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    if (p.energy or 0) < cost then return false end
    
    -- 冷却处理 (WF 风格大多数技能无 CD)
    if def.cd and def.cd > 0 then
        p.abilityCooldowns = p.abilityCooldowns or {}
        if (p.abilityCooldowns[abilityIndex] or 0) > 0 then return false end
    end
    
    return true
end

--- getCastTime: 获取某技能的施法前摇时间 (受天赋 Natural Talent 影响)。
function abilities.getCastTime(state, def)
    local p = state.player
    if not def then return 0 end
    
    local baseCast = def.castTime or 0
    if baseCast <= 0 then return 0 end
    
    local castSpeedMult = (p.stats and p.stats.castSpeed) or 1.0
    return baseCast / castSpeedMult
end

--- tryActivate: 尝试释放技能。
-- 进行合法性校验、扣除能量，并处理 瞬间释放 vs 需要前摇 的不同逻辑。
function abilities.tryActivate(state, abilityIndex)
    if not abilities.canUse(state, abilityIndex) then return false end
    
    local p = state.player
    local def = abilities.getAbilityByIndex(state, abilityIndex)
    if not def then return false end
    
    -- 处理开关逻辑
    local togglingOff = def.toggleId and hasBuff(p, def.toggleId)
    if togglingOff then
        abilities.removeBuff(state, def.toggleId)
        return true
    end

    -- 处理特殊重放逻辑
    if def.recastCheck and def.recastNoCost then
        local target = def.recastCheck(state)
        if target and def.recastAction then
            return def.recastAction(state, target)
        end
    end

    -- 消耗能量 (受效率修正)
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    p.energy = (p.energy or 0) - cost
    
    local castTime = abilities.getCastTime(state, def)
    
    if castTime > 0 then
        -- 进入施法动画状态
        p.isCasting = true
        p.castTimer = castTime
        p.castDef = def
        p.castAbilityIndex = abilityIndex
        p.castProgress = 0
        
        -- 缓存原始速度并在施法中减速
        if not p.castOriginalSpeed then
            p.castOriginalSpeed = p.stats.moveSpeed or 170
        end
        p.castSlowMult = 0.5
        p.stats.moveSpeed = p.castOriginalSpeed * p.castSlowMult
        
        if state.texts then
            table.insert(state.texts, {
                x = p.x, y = p.y - 40, 
                text = "施法中...", 
                color = {0.6, 0.8, 1, 0.8}, 
                life = castTime,
                scale = 0.8
            })
        end
        
        return true
    else
        -- 瞬发技能：直接执行效果
        local success = def.effect(state)
        
        if def.cd and def.cd > 0 then
            p.abilityCooldowns = p.abilityCooldowns or {}
            p.abilityCooldowns[abilityIndex] = def.cd
        end
        
        return success
    end
end

--- interruptCast: 打断正在进行的施法。
-- 当被控制 (Stun/Knockdown) 时调用。返还 50% 能量。
function abilities.interruptCast(state, reason)
    local p = state.player
    if not p or not p.isCasting then return false end
    
    -- 返还部分能量
    if p.castDef then
        local eff = p.stats and p.stats.abilityEfficiency or 1.0
        local cost = math.floor(p.castDef.cost / eff)
        local refund = math.floor(cost * 0.5)
        p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + refund)
    end
    
    restoreCastMoveSpeed(p)
    
    if state.texts then
        table.insert(state.texts, {
            x = p.x, y = p.y - 30, 
            text = reason or "施法被打断!", 
            color = {1, 0.4, 0.4}, 
            life = 0.8
        })
    end
    
    -- 清理施法状态
    p.isCasting = false
    p.castTimer = nil
    p.castDef = nil
    p.castAbilityIndex = nil
    p.castProgress = nil
    
    return true
end

function abilities.getAbilityForKey(key)
    local keyMap = { ['1'] = 1, ['2'] = 2, ['3'] = 3, ['4'] = 4 }
    return keyMap[key]
end

abilities.getAbilityDef = abilities.getAbilityByIndex

-------------------------------------------
-- 更新逻辑 (Update System)
-------------------------------------------

function abilities.update(state, dt)
    local p = state.player
    if not p then return end
    
    -- 初始化被动
    if not p.passiveApplied then
        abilities.applyPassive(state)
    end
    
    -- 更新 Buff 计时与特殊持续效果
    abilities.updateBuffs(state, dt)
    abilities.updateActiveEffects(state, dt)
    
    -- 首次加载角色 MOD (若未应用)
    if not p.warframeModsApplied then
        local mods = require('systems.mods')
        local slots = mods.getSlots(state, 'warframe', nil)
        local hasModsEquipped = false
        for _, m in ipairs(slots) do if m then hasModsEquipped = true break end end
        
        if hasModsEquipped then
            p.stats = p.stats or {}
            local modded = mods.applyWarframeMods(state, p.stats)
            for k, v in pairs(modded) do p.stats[k] = v end
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
    
    -- 处理施法计时
    if p.isCasting and p.castTimer then
        p.castTimer = p.castTimer - dt
        local totalCast = abilities.getCastTime(state, p.castDef)
        p.castProgress = totalCast > 0 and (1 - (p.castTimer / totalCast)) or 1
        
        -- 检查施法是否被控制技能打断
        local interrupted = (p.stunTimer and p.stunTimer > 0) or (p.knockdownTimer and p.knockdownTimer > 0) or (p.frozenTimer and p.frozenTimer > 0)
        if interrupted then
            abilities.interruptCast(state, "被控制打断!")
        elseif p.castTimer <= 0 then
            -- 施法成功：触发正式效果
            if p.castDef and p.castDef.effect then p.castDef.effect(state) end
            if p.castDef and p.castDef.cd and p.castDef.cd > 0 then
                p.abilityCooldowns = p.abilityCooldowns or {}
                p.abilityCooldowns[p.castAbilityIndex] = p.castDef.cd
            end
            restoreCastMoveSpeed(p)
            p.isCasting, p.castTimer, p.castDef, p.castAbilityKey, p.castProgress = false, nil, nil, nil, nil
        end
    end
    
    -- 能量自然回复
    local regen = (p.stats and p.stats.energyRegen) or p.energyRegen or 2
    if p.isCasting then regen = regen * 0.5 end -- 施法中减半回蓝
    p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + regen * dt)
    
    -- 干扰区警告计时器
    if p._nullBubbleWarningCd and p._nullBubbleWarningCd > 0 then
        p._nullBubbleWarningCd = p._nullBubbleWarningCd - dt
        if p._nullBubbleWarningCd <= 0 then p._nullBubbleWarningCd = nil end
    end
    
    -- 冷却计时
    p.abilityCooldowns = p.abilityCooldowns or {}
    for key, cd in pairs(p.abilityCooldowns) do
        if cd > 0 then p.abilityCooldowns[key] = cd - dt end
    end
    
    -- 临时护盾衰减
    if p.tempShieldTimer and p.tempShieldTimer > 0 then
        p.tempShieldTimer = p.tempShieldTimer - dt
        if p.tempShieldTimer <= 0 then p.tempShield, p.tempShieldTimer = 0, nil end
    end
end

function abilities.spawnChain(state, segments, opts)
    state.voltLightningChains = state.voltLightningChains or {}
    opts = opts or {}
    local chainData = {
        segments = {},
        timer = opts.timer or 0.8,
        elapsed = 0,
        alpha = opts.alpha or 1.0
    }
    
    local speed = opts.speed or 2000
    local currentDelay = opts.initialDelay or 0
    
    for _, s in ipairs(segments) do
        local dx = s.x2 - s.x1
        local dy = s.y2 - s.y1
        local dist = math.sqrt(dx*dx + dy*dy)
        local t = math.max(0.03, dist / speed)
        
        table.insert(chainData.segments, {
            x1 = s.x1, y1 = s.y1,
            x2 = s.x2, y2 = s.y2,
            width = s.width or 12,
            delay = currentDelay,
            travelTime = t,
            source = s.source,
            target = s.target,
            instance = s.instance,
            damage = s.damage
        })
        currentDelay = currentDelay + t
    end
    
    chainData.timer = math.max(chainData.timer, currentDelay + 0.4)
    table.insert(state.voltLightningChains, chainData)
    if not opts.noSfx and state.playSfx then state.playSfx('shock') end
end

--- updateActiveEffects: 更新所有激活的持续性技能效果。
-- 涵盖：Volt 的闪电链视觉、显赫刀剑的持续耗蓝、电磁盾、Mag 的磁化力场、Discharge 波动等。
function abilities.updateActiveEffects(state, dt)
    local p = state.player
    if not p then return end
    
    -- 1. Volt 闪电链 VFX 与 延迟伤害
    if state.voltLightningChains then
        for i = #state.voltLightningChains, 1, -1 do
            local c = state.voltLightningChains[i]
            c.elapsed = (c.elapsed or 0) + dt
            c.timer = c.timer - dt
            
            -- 检查每一段的动画和激活状态
            for _, seg in ipairs(c.segments or {}) do
                -- 核心优化：如果实体还在，实时同步坐标
                if seg.source and seg.source.x then
                    seg.x1, seg.y1 = seg.source.x, seg.source.y
                end
                if seg.target and seg.target.x then
                    seg.x2, seg.y2 = seg.target.x, seg.target.y
                end

                if c.elapsed >= (seg.delay or 0) then
                    seg.active = true
                    -- 计算伸缩进度 (从 delay 开始到 travelTime 结束)
                    local duration = seg.travelTime or 0.06
                    local t = (c.elapsed - seg.delay) / duration
                    seg.progress = math.min(1, math.max(0, t))
                    
                    -- 只有当进度达到 100% 且还没造成过伤害时，触发命中
                    if seg.progress >= 1 and not seg.hitApplied then
                        seg.hitApplied = true
                        if seg.target and not seg.target.isDummy then
                            local ok, calc = pcall(require, 'gameplay.calculator')
                            if ok and calc and seg.instance then
                                calc.applyHit(state, seg.target, seg.instance)
                            else
                                seg.target.health = (seg.target.health or 0) - (seg.damage or 0)
                            end
                            if state.spawnEffect then state.spawnEffect('shock', seg.target.x, seg.target.y, 0.8) end
                        end
                    end
                end
            end
            
            c.alpha = math.max(0, c.timer / 0.5)
            if c.timer <= 0 then table.remove(state.voltLightningChains, i) end
        end
    end
    
    -- 2. 持续耗蓝技能：显赫刀剑 (Exalted Blade)
    if p.exaltedBladeActive then
        p.energy = (p.energy or 0) - 2.5 * dt
        if p.energy <= 0 then
            p.energy = 0
            abilities.removeBuff(state, "excalibur_exalted_blade")
            if state.texts then table.insert(state.texts, {x=p.x, y=p.y-30, text="能量竭尽", color={1,0,0}, life=1}) end
        end
    end
    
    -- 3. 电盾 (Electric Shield) 动态跟随
    if p.electricShield and p.electricShield.active then
        p.electricShield.timer = p.electricShield.timer - dt
        if p.electricShield.timer <= 0 then 
            p.electricShield.active = false
            if state.texts then table.insert(state.texts, {x=p.x, y=p.y-30, text="电盾消散", color={0.6,0.6,0.8}, life=1}) end
        elseif p.electricShield.followPlayer then
            local ang = p.aimAngle or 0
            local dst = p.electricShield.distance or 60
            p.electricShield.x, p.electricShield.y, p.electricShield.angle = p.x + math.cos(ang)*dst, p.y + math.sin(ang)*dst, ang
        end
    end

    -- 4. Mag: 磁化力场 (Magnetize Fields) 牵引与跳字伤害
    if state.enemies then
        state.magMagnetizeFields = nil
        for _, e in ipairs(state.enemies) do
            local m = e and e.magnetize
            if m and m.timer and m.timer > 0 then
                m.timer = m.timer - dt
                m.tick = (m.tick or 0) + dt

                state.magMagnetizeFields = state.magMagnetizeFields or {}
                table.insert(state.magMagnetizeFields, {x = e.x, y = e.y, r = m.radius or 0, t = m.timer})

                -- 这里的引力将其他敌人拉向磁化中心
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
                                local mx, my = dx / len * step, dy / len * step
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

                -- 磁化力场的周期性 Tick 伤害
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
            elseif m then e.magnetize = nil end
        end
    end

    -- 5. Volt: Discharge 扩张冲击波与特斯拉节点 (Tesla Node)
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
                                damage = wave.damage, critChance = 0.2, critMultiplier = 2.5, statusChance = 1.0,
                                elements = {'ELECTRIC'}, weaponTags = {'ability', 'area', 'electric'}
                            })
                            calc.applyHit(state, e, inst)
                        else e.health = (e.health or 0) - wave.damage end
                        
                        -- 被命中的敌人转化为“特斯拉节点”，向周围放电并被眩晕
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

    -- Discharge 的视觉波动效果
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

    -- 特斯拉节点网络逻辑 (Node Network)
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
                            -- 在节点间生成电弧视觉效果
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
