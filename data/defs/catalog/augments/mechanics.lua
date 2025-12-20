local catalog = {
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
                        local ok, calc = pcall(require, 'gameplay.calculator')
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
                        local ok, calc = pcall(require, 'gameplay.calculator')
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
                        local ok, calc = pcall(require, 'gameplay.calculator')
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
}

return catalog
