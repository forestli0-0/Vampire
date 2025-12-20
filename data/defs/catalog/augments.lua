local catalog = {
        -- DEPRECATED PASSIVES (VS-style, hidden from upgrade pools)
        -- These effects are now handled by the WF MOD system
        -- Kept for backward save compatibility only
        -- ===================================================================
        -- DEPRECATED PASSIVES REMOVED
        -- These effects are now handled by the WF MOD system
        -- ===================================================================

        -- Mechanics Augments (per-run, change play patterns)
        aug_gilded_instinct = {
            type = 'augment', name = "Gilded Instinct",
            desc = "Gain more GOLD from kills and room rewards.",
            maxLevel = 3,
            triggers = {
                {
                    event = 'onPickup',
                    requires = {pickupKind = 'gold'},
                    action = function(state, ctx, level)
                        local amt = tonumber(ctx and ctx.amount) or 0
                        if amt <= 0 then return end
                        local mult = 1 + 0.25 * math.max(1, level or 1)
                        ctx.amount = math.max(1, math.floor(amt * mult + 0.5))
                    end
                }
            }
        },
        aug_kinetic_discharge = {
            type = 'augment', name = "Kinetic Discharge",
            desc = "Moving charges up. Every distance traveled releases an electric pulse.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'tick',
                    counter = 'moveDist',
                    threshold = 260,
                    cooldown = 0.2,
                    maxPerSecond = 2,
                    requires = {isMoving = true},
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end
                        local radius = 130
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(10 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.35,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'augment', 'area'}
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            if not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('static', p.x, p.y) end
                    end
                }
            }
        },
        aug_blood_burst = {
            type = 'augment', name = "Blood Burst",
            desc = "Killing an enemy detonates it, damaging nearby foes.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onKill',
                    cooldown = 0.15,
                    maxPerSecond = 6,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local enemy = ctx and ctx.enemy
                        if not enemy then return end
                        local p = state.player or {}
                        local radius = 110
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(12 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.25,
                            elements = {'BLAST'},
                            damageBreakdown = {BLAST = 1},
                            weaponTags = {'augment', 'area'}
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            if e ~= enemy and not e.isDummy then
                                local dx = e.x - enemy.x
                                local dy = e.y - enemy.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('hit', enemy.x, enemy.y) end
                    end
                }
            }
        },
        aug_combo_arc = {
            type = 'augment', name = "Combo Arc",
            desc = "Every 7 hits releases chain lightning to nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onHit',
                    counter = 'hits',
                    threshold = 7,
                    cooldown = 0.1,
                    maxPerSecond = 3,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local enemy = ctx and ctx.enemy
                        if not enemy then return end
                        local p = state.player or {}
                        local radius = 180
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(8 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.4,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'augment', 'chain'}
                        })
                        local hits = 0
                        for _, e in ipairs(state.enemies or {}) do
                            if e ~= enemy and not e.isDummy and e.health and e.health > 0 then
                                local dx = e.x - enemy.x
                                local dy = e.y - enemy.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                    hits = hits + 1
                                    if hits >= 4 then break end
                                end
                            end
                        end
                        if hits > 0 and state.spawnEffect then state.spawnEffect('static', enemy.x, enemy.y) end
                    end
                }
            }
        },
        aug_forked_trajectory = {
            type = 'augment', name = "Forked Trajectory",
            desc = "Projectiles split into 2 angled forks.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 60,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b._forked or b.augmentChild then return end
                        if b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        if not b.vx or not b.vy then return end

                        local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                        if spd <= 0 then return end
                        local baseAng = math.atan2(b.vy, b.vx)
                        local spread = 0.22
                        local forks = 2
                        local dmg = b.damage or 0
                        if dmg <= 0 then return end

                        local function cloneBullet(src)
                            local out = {}
                            for k, v in pairs(src) do
                                if type(v) == 'table' then
                                    local t = {}
                                    for kk, vv in pairs(v) do t[kk] = vv end
                                    out[k] = t
                                else
                                    out[k] = v
                                end
                            end
                            out.hitTargets = nil
                            return out
                        end

                        b._forked = true
                        for i = 1, forks do
                            local sign = (i == 1) and -1 or 1
                            local ang = baseAng + sign * spread
                            local c = cloneBullet(b)
                            c.x = b.x
                            c.y = b.y
                            c.vx = math.cos(ang) * spd
                            c.vy = math.sin(ang) * spd
                            c.rotation = ang
                            c.life = (b.life or 2) * 0.9
                            c.size = math.max(4, (b.size or 8) * 0.9)
                            c.damage = math.max(1, math.floor(dmg * 0.6 + 0.5))
                            c.augmentChild = true
                            c._forked = true
                            table.insert(state.bullets, c)
                            if state and state.augments and state.augments.dispatch then
                                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = c.type, bullet = c, spawnedBy = 'fork'})
                            end
                        end
                    end
                }
            }
        },
        aug_homing_protocol = {
            type = 'augment', name = "Homing Protocol",
            desc = "Projectiles steer toward nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        b.homing = math.max(b.homing or 0, 6.5)
                        b.homingRange = math.max(b.homingRange or 0, 720)
                    end
                }
            }
        },
        aug_ricochet_matrix = {
            type = 'augment', name = "Ricochet Matrix",
            desc = "Projectiles ricochet to nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local add = 2
                        b.ricochetRemaining = (b.ricochetRemaining or 0) + add
                        b.ricochetRange = math.max(b.ricochetRange or 0, 420)
                        b.pierce = (b.pierce or 1) + add
                    end
                }
            }
        },
        aug_boomerang_return = {
            type = 'augment', name = "Boomerang Return",
            desc = "Projectiles turn back and return to you.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local t = math.min(0.9, (b.life or 2) * 0.45)
                        if b.boomerangTimer == nil or b.boomerangTimer > t then
                            b.boomerangTimer = t
                        end
                        b.returnHoming = math.max(b.returnHoming or 0, 22)
                        b.life = (b.life or 2) + 0.9
                        b.pierce = (b.pierce or 1) + 1
                    end
                }
            }
        },
        aug_shatter_shards = {
            type = 'augment', name = "Shatter Shards",
            desc = "On hit, projectiles burst into shards.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileHit',
                    cooldown = 0.05,
                    maxPerSecond = 30,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        local enemy = ctx and ctx.enemy
                        if not b or not enemy then return end
                        if b._shattered or b.augmentChild then return end
                        if b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local dmg = b.damage or 0
                        if dmg <= 0 then return end
                        b._shattered = true

                        local spd = math.sqrt((b.vx or 0)^2 + (b.vy or 0)^2)
                        if spd <= 0 then spd = 520 end
                        local baseAng = math.atan2((b.vy or 0), (b.vx or 1))
                        local count = 3
                        local spread = 0.45

                        local function copyArray(src)
                            if not src then return nil end
                            local t = {}
                            for i, v in ipairs(src) do t[i] = v end
                            return t
                        end

                        local function copyMap(src)
                            if not src then return nil end
                            local t = {}
                            for k, v in pairs(src) do t[k] = v end
                            return t
                        end

                        for i = 1, count do
                            local offset = (i - (count + 1) / 2) * spread
                            local ang = baseAng + offset
                            local shardTags = copyArray(b.weaponTags) or {}
                            table.insert(shardTags, 'augment')
                            local shard = {
                                type = 'augment_shard',
                                x = enemy.x,
                                y = enemy.y,
                                vx = math.cos(ang) * spd,
                                vy = math.sin(ang) * spd,
                                life = 1.2,
                                size = math.max(4, (b.size or 10) * 0.7),
                                damage = math.max(1, math.floor(dmg * 0.35 + 0.5)),
                                effectType = b.effectType,
                                weaponTags = shardTags,
                                pierce = 1,
                                rotation = ang,
                                parentWeaponKey = b.type,
                                elements = copyArray(b.elements),
                                damageBreakdown = copyMap(b.damageBreakdown),
                                critChance = b.critChance,
                                critMultiplier = b.critMultiplier,
                                statusChance = b.statusChance
                            }
                            shard.augmentChild = true
                            table.insert(state.bullets, shard)
                            if state and state.augments and state.augments.dispatch then
                                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = b.type, bullet = shard, spawnedBy = 'shatter'})
                            end
                        end
                    end
                }
            }
        },
        aug_evasive_momentum = {
            type = 'augment', name = "Evasive Momentum",
            desc = "While moving, evade one hit periodically.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'preHurt',
                    cooldown = 2.0,
                    requires = {isMoving = true},
                    action = function(state, ctx)
                        ctx.cancel = true
                        ctx.invincibleTimer = 0.25
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end
                        table.insert(state.texts, {x=p.x, y=p.y-30, text="DODGE!", color={0.6,1,0.6}, life=0.6})
                    end
                }
            }
        },
        aug_greater_reflex = {
            type = 'augment', name = "Greater Reflex",
            desc = "Gain +1 Dash charge.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onUpgradeChosen',
                    action = function(state, ctx)
                        local opt = ctx and ctx.opt
                        if not opt or opt.key ~= 'aug_greater_reflex' then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p or not p.stats then return end
                        p.stats.dashCharges = math.max(0, (p.stats.dashCharges or 0) + 1)
                    end
                }
            }
        },
        aug_dash_strike = {
            type = 'augment', name = "Dash Strike",
            desc = "Dashing releases an impact shockwave that damages nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.05,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end
                        local radius = 95
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(14 * might + 0.5)
                        if dmg <= 0 then return end
                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.15,
                            elements = {'IMPACT'},
                            damageBreakdown = {IMPACT = 1},
                            weaponTags = {'augment', 'dash', 'area'},
                            knock = true,
                            knockForce = 18
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            local hp = e and (e.health or e.hp) or 0
                            if e and hp and hp > 0 and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end
                        if state.spawnEffect then state.spawnEffect('impact_hit', p.x, p.y, 1.0) end
                    end
                }
            }
        },
        aug_quickstep = {
            type = 'augment', name = "Quickstep",
            desc = "Dash recharges faster.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onUpgradeChosen',
                    action = function(state, ctx)
                        local opt = ctx and ctx.opt
                        if not opt or opt.key ~= 'aug_quickstep' then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p or not p.stats then return end
                        local cd = p.stats.dashCooldown or 0
                        if cd <= 0 then return end
                        cd = cd * 0.75
                        if cd < 0.15 then cd = 0.15 end
                        p.stats.dashCooldown = cd
                    end
                }
            }
        },
        aug_longstride = {
            type = 'augment', name = "Longstride",
            desc = "Dash travels farther and grants longer i-frames.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onUpgradeChosen',
                    action = function(state, ctx)
                        local opt = ctx and ctx.opt
                        if not opt or opt.key ~= 'aug_longstride' then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p or not p.stats then return end
                        local dist = p.stats.dashDistance or 0
                        if dist > 0 then
                            p.stats.dashDistance = dist * 1.25
                        end
                        p.stats.dashInvincible = math.max(0, (p.stats.dashInvincible or 0) + 0.04)
                    end
                }
            }
        },
        aug_reload_step = {
            type = 'augment', name = "Reload Step",
            desc = "Dashing refreshes weapon cooldowns.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.05,
                    action = function(state, ctx)
                        for _, w in pairs((state.inventory and state.inventory.weapons) or {}) do
                            if w and w.timer ~= nil then
                                w.timer = 0
                            end
                        end
                        local p = (ctx and ctx.player) or state.player
                        if p then
                            table.insert(state.texts, {x=p.x, y=p.y-38, text="RESET!", color={0.75,0.9,1}, life=0.55})
                        end
                    end
                }
            }
        },
        aug_shockstep = {
            type = 'augment', name = "Shockstep",
            desc = "Dashing releases an electric pulse that can chain.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.15,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end

                        local radius = 120
                        local r2 = radius * radius
                        local might = (p.stats and p.stats.might) or 1
                        local dmg = math.floor(10 * might + 0.5)
                        if dmg <= 0 then dmg = 1 end

                        local instance = calc.createInstance({
                            damage = dmg,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 0.55,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'augment', 'dash', 'area'}
                        })

                        for _, e in ipairs(state.enemies or {}) do
                            local hp = e and (e.health or e.hp) or 0
                            if e and hp and hp > 0 and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end

                        if state.spawnEffect then state.spawnEffect('static', p.x, p.y, 0.95) end
                        if state.spawnAreaField then state.spawnAreaField('static', p.x, p.y, radius, 0.35, 1.1) end
                    end
                }
            }
        },
        aug_froststep = {
            type = 'augment', name = "Froststep",
            desc = "Dashing freezes nearby enemies briefly.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onDash',
                    cooldown = 0.65,
                    action = function(state, ctx)
                        local ok, calc = pcall(require, 'calculator')
                        if not ok or not calc then return end
                        local p = (ctx and ctx.player) or state.player
                        if not p then return end

                        local radius = 90
                        local r2 = radius * radius
                        local instance = calc.createInstance({
                            damage = 0,
                            critChance = 0,
                            critMultiplier = 1.5,
                            statusChance = 1.0,
                            effectType = 'FREEZE',
                            effectData = {fullFreeze = true, freezeDuration = 0.45},
                            elements = {'COLD'},
                            damageBreakdown = {COLD = 1},
                            weaponTags = {'augment', 'dash', 'area'}
                        })

                        for _, e in ipairs(state.enemies or {}) do
                            local hp = e and (e.health or e.hp) or 0
                            if e and hp and hp > 0 and not e.isDummy then
                                local dx = e.x - p.x
                                local dy = e.y - p.y
                                if dx * dx + dy * dy <= r2 then
                                    calc.applyHit(state, e, instance)
                                end
                            end
                        end

                        if state.spawnEffect then state.spawnEffect('freeze', p.x, p.y, 0.7) end
                        if state.spawnAreaField then state.spawnAreaField('freeze', p.x, p.y, radius, 0.5, 1.0) end
                    end
                }
            }
        }
}

return catalog
