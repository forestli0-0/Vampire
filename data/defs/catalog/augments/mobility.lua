local catalog = {
        -- Mobility Augments (movement and dash)
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
                        local ok, calc = pcall(require, 'gameplay.calculator')
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
                        local ok, calc = pcall(require, 'gameplay.calculator')
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
                        local ok, calc = pcall(require, 'gameplay.calculator')
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
