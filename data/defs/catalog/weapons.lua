local catalog = {
        wand = {
            type = 'weapon', name = "Magic Wand",
            desc = "[Legacy] Energy weapon. Fires at nearest enemy.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',  -- WF category
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.0 },
            legacy = true,  -- Easter egg weapon from VS era
            base = { 
                damage=8, cd=1.2, speed=380, range=600, 
                critChance=0.05, critMultiplier=1.5, statusChance=0,
                magazine=30, maxMagazine=30,
                reserve=120, maxReserve=120,
                reloadTime=1.5
            },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.9 end
        },
        holy_wand = {
            type = 'weapon', name = "Holy Wand",
            desc = "[Legacy] Rapid-fire energy projectiles.",
            maxLevel = 3,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'energy'},
            classWeight = { warrior = 0.3, mage = 2.0, beastmaster = 0.8 },
            rare = true, legacy = true,
            base = { damage=15, cd=0.16, speed=600, range=700, elements={'IMPACT'}, damageBreakdown={IMPACT=1}, critChance=0.05, critMultiplier=1.5, statusChance=0,
                magazine=60, maxMagazine=60, reserve=180, maxReserve=180, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 3 end
        },
        garlic = {
            -- DEPRECATED: VS-style aura weapon
            type = 'deprecated', name = "Garlic",
            desc = "[Removed] VS-style aura weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'AURA',
            tags = {'weapon', 'area', 'aura', 'magic'},
            base = { damage=3, cd=0.35, radius=70, knockback=30 }
        },
        axe = {
            -- DEPRECATED: VS-style random projectile
            type = 'deprecated', name = "Axe",
            desc = "[Removed] VS-style thrown weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_RANDOM',
            tags = {'weapon', 'projectile', 'physical', 'arc'},
            base = { damage=30, cd=1.4, speed=450, area=1.5 }
        },
        death_spiral = {
            -- DEPRECATED: Will be reimplemented as ability
            type = 'deprecated', name = "Death Spiral",
            desc = "[Removed] Will be reimplemented as ability.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_RADIAL',
            tags = {'weapon', 'projectile', 'physical', 'arc'},
            base = { damage=40, cd=1.2, speed=500, area=2.0 }
        },
        oil_bottle = {
            -- RESERVED for specialized Pet content in future.
            type = 'reserved', name = "Oil Bottle",
            desc = "Coats enemies in Oil.",
            maxLevel = 5,
            hidden = true,
            behavior = 'SHOOT_NEAREST',
            behaviorParams = {rotate = false},
            tags = {'weapon', 'projectile', 'chemical'},
            base = { damage=0, cd=2.0, speed=300, range=700, pierce=1, effectType='OIL', size=12, splashRadius=80, duration=6.0, critChance=0.05, critMultiplier=1.5, statusChance=0.8 },
            onUpgrade = function(w) w.cd = w.cd * 0.95 end
        },
        fire_wand = {
            type = 'weapon', name = "Fire Wand",
            desc = "[Legacy] Energy weapon with heat damage.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'fire', 'magic', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.0 },
            legacy = true,
            base = { damage=15, cd=0.9, speed=450, range=700, elements={'HEAT'}, damageBreakdown={HEAT=1}, splashRadius=70, critChance=0.05, critMultiplier=1.5, statusChance=0.3,
                magazine=40, maxMagazine=40, reserve=120, maxReserve=120, reloadTime=1.8 },
            onUpgrade = function(w) w.damage = w.damage + 5; w.cd = w.cd * 0.95 end
        },
        ice_ring = {
            -- DEPRECATED: VS-style aura weapon
            type = 'deprecated', name = "Ice Ring",
            desc = "[Removed] VS-style aura weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'AURA',
            tags = {'weapon', 'area', 'magic', 'ice'},
            base = { damage=2, cd=2.5, radius=100 }
        },
        heavy_hammer = {
            type = 'weapon', name = "Fragor",
            desc = "[Legacy] Heavy hammer with massive knockback.",
            maxLevel = 5,
            slotType = 'melee',
            weaponCategory = 'melee',
            behavior = 'MELEE_SWING',
            behaviorParams = { arcWidth = 1.4 },
            tags = {'weapon', 'physical', 'heavy', 'melee'},
            classWeight = { warrior = 2.0, mage = 0.5, beastmaster = 1.0 },
            legacy = true,
            base = { damage=40, cd=0.2, range=90, knockback=100, effectType='HEAVY', size=12, critChance=0.15, critMultiplier=2.0, statusChance=0.5 },
            onUpgrade = function(w) w.damage = w.damage + 10 end
        },
        dagger = {
            -- DEPRECATED: VS-style throwing weapon
            type = 'deprecated', name = "Throwing Knife",
            desc = "[Removed] VS-style throwing weapon.",
            maxLevel = 5,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_DIRECTIONAL',
            tags = {'weapon', 'projectile', 'physical', 'fast'},
            base = { damage=4, cd=0.18, speed=600, range=550 }
        },
        static_orb = {
            type = 'weapon', name = "Amprex",
            desc = "[Legacy] Chain lightning energy weapon.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'electric', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.5 },
            legacy = true,
            base = { damage=6, cd=0.08, speed=380, range=650, elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1}, duration=3.0, staticRange=160, chain=4, critChance=0.20, critMultiplier=2.0, statusChance=0.4,
                magazine=100, maxMagazine=100, reserve=300, maxReserve=300, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 3; w.chain = w.chain + 1 end
        },
        soul_eater = {
            -- DEPRECATED: VS-style aura weapon
            type = 'deprecated', name = "Soul Eater",
            desc = "[Removed] VS-style vampiric aura.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'AURA',
            tags = {'weapon', 'area', 'aura', 'magic'},
            base = { damage=8, cd=0.3, radius=130, knockback=50, lifesteal=0.4 }
        },
        thousand_edge = {
            -- DEPRECATED: VS-style throwing weapon
            type = 'deprecated', name = "Thousand Edge",
            desc = "[Removed] VS-style throwing weapon.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'SHOOT_DIRECTIONAL',
            tags = {'weapon', 'projectile', 'physical', 'fast'},
            base = { damage=7, cd=0.05, speed=650, range=550, pierce=6 }
        },
        hellfire = {
            type = 'weapon', name = "Ignis",
            desc = "[Legacy] Flame thrower energy weapon.",
            maxLevel = 3,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'fire', 'magic', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.5, beastmaster = 1.0 },
            rare = true, legacy = true,
            base = { damage=15, cd=0.05, speed=520, range=400, elements={'HEAT'}, damageBreakdown={HEAT=1}, splashRadius=80, pierce=99, size=10, area=1.3, life=0.5, statusChance=0.5,
                magazine=200, maxMagazine=200, reserve=400, maxReserve=400, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 5 end
        },
        absolute_zero = {
            -- DEPRECATED: Will be reimplemented as ability
            type = 'deprecated', name = "Absolute Zero",
            desc = "[Removed] Will be reimplemented as ability.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'SPAWN',
            tags = {'weapon', 'area', 'magic', 'ice'},
            base = { damage=5, cd=2.2, radius=160, duration=2.5 }
        },
        thunder_loop = {
            type = 'weapon', name = "Synapse",
            desc = "[Legacy] Chain lightning beam weapon.",
            maxLevel = 3,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'magic', 'electric', 'energy'},
            classWeight = { warrior = 0.5, mage = 2.5, beastmaster = 1.5 },
            rare = true, legacy = true,
            base = { damage=10, cd=0.05, speed=420, range=650, elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1}, duration=3.0, staticRange=220, pierce=1, chain=10, allowRepeat=true, statusChance=0.5,
                magazine=80, maxMagazine=80, reserve=240, maxReserve=240, reloadTime=2.0 },
            onUpgrade = function(w) w.damage = w.damage + 3; w.chain = w.chain + 2 end
        },
        earthquake = {
            -- DEPRECATED: Will be reimplemented as ability
            type = 'deprecated', name = "Earthquake",
            desc = "[Removed] Will be reimplemented as ability.",
            maxLevel = 3,
            hidden = true, deprecated = true,
            behavior = 'GLOBAL',
            tags = {'weapon', 'area', 'physical', 'heavy'},
            base = { damage=60, cd=2.5, area=2.2, knockback=120 }
        },

        -- ===================================================================
        -- WARFRAME-STYLE WEAPONS
        -- Primary: Rifles, Shotguns, Snipers, Bows
        -- Secondary: Pistols
        -- Melee: Swords, Hammers, Dual Wield
        -- ===================================================================

        -- === RIFLES (Primary) ===
        braton = {
            type = 'weapon', name = "Braton",
            desc = "Standard automatic rifle. Balanced and reliable.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'rifle',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'rifle'},
            classWeight = { warrior = 1.2, mage = 0.8, beastmaster = 1.5 },
            base = { 
                damage=25, cd=0.08, speed=1200, range=700, size=8,
                elements={'IMPACT','PUNCTURE'}, damageBreakdown={IMPACT=1, PUNCTURE=1},
                falloffStart=400, falloffEnd=700, falloffMin=0.5,
                critChance=0.22, critMultiplier=1.8, statusChance=0.20,
                magazine=45, maxMagazine=45, reserve=270, maxReserve=270, reloadTime=1.8
            },
            onUpgrade = function(w) w.damage = w.damage + 5 end
        },
        boltor = {
            type = 'weapon', name = "Boltor",
            desc = "Fires heavy bolts. High puncture damage.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'rifle',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'rifle'},
            classWeight = { warrior = 1.5, mage = 0.5, beastmaster = 1.2 },
            base = { 
                damage=35, cd=0.10, speed=1000, range=750, size=10,
                elements={'PUNCTURE'}, damageBreakdown={PUNCTURE=1},
                falloffStart=400, falloffEnd=750, falloffMin=0.5,
                critChance=0.18, critMultiplier=2.0, statusChance=0.30,
                magazine=60, maxMagazine=60, reserve=360, maxReserve=360, reloadTime=2.4
            },
            onUpgrade = function(w) w.damage = w.damage + 7 end
        },

        -- === SHOTGUNS (Primary) ===
        hek = {
            type = 'weapon', name = "Hek",
            desc = "Quad-barrel shotgun. Devastating at close range.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'shotgun',
            behavior = 'SHOOT_SPREAD',
            behaviorParams = { pellets = 7, spread = 0.4 },
            tags = {'weapon', 'projectile', 'physical', 'shotgun'},
            classWeight = { warrior = 2.0, mage = 0.3, beastmaster = 1.5 },
            base = { 
                damage=65, cd=0.9, speed=800, range=300, size=6,
                elements={'IMPACT','PUNCTURE','SLASH'}, damageBreakdown={IMPACT=3, PUNCTURE=2, SLASH=2},
                falloffStart=80, falloffEnd=250, falloffMin=0.15,
                critChance=0.25, critMultiplier=2.2, statusChance=0.40,
                magazine=4, maxMagazine=4, reserve=120, maxReserve=120, reloadTime=2.0
            },
            onUpgrade = function(w) w.damage = w.damage + 12 end
        },
        strun = {
            type = 'weapon', name = "Strun",
            desc = "Pump-action shotgun. Good spread pattern.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'shotgun',
            behavior = 'SHOOT_SPREAD',
            behaviorParams = { pellets = 10, spread = 0.5 },
            tags = {'weapon', 'projectile', 'physical', 'shotgun'},
            classWeight = { warrior = 1.5, mage = 0.5, beastmaster = 1.5 },
            base = { 
                damage=45, cd=0.7, speed=750, range=250, size=5,
                elements={'IMPACT'}, damageBreakdown={IMPACT=1},
                falloffStart=60, falloffEnd=200, falloffMin=0.20,
                critChance=0.15, critMultiplier=1.8, statusChance=0.30,
                magazine=6, maxMagazine=6, reserve=120, maxReserve=120, reloadTime=2.2
            },
            onUpgrade = function(w) w.damage = w.damage + 8 end
        },

        -- === SNIPERS (Primary) ===
        vectis = {
            type = 'weapon', name = "Vectis",
            desc = "Sniper rifle. [Shift: Sniper Mode]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'sniper',
            behavior = 'SHOOT_NEAREST',
            sniperMode = true,
            tags = {'weapon', 'projectile', 'physical', 'sniper'},
            classWeight = { warrior = 1.0, mage = 1.5, beastmaster = 0.8 },
            base = { 
                damage=200, cd=1.3, speed=1800, range=900, size=12,
                sniperRange=1500,
                elements={'PUNCTURE','IMPACT'}, damageBreakdown={PUNCTURE=3, IMPACT=1},
                critChance=0.50, critMultiplier=3.5, statusChance=0.30,
                magazine=1, maxMagazine=1, reserve=72, maxReserve=72, reloadTime=0.8,
                pierce=3
            },
            onUpgrade = function(w) w.damage = w.damage + 30; w.critChance = w.critChance + 0.05 end
        },
        lanka = {
            type = 'weapon', name = "Lanka",
            desc = "Corpus energy sniper. [Shift: Sniper Mode]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'sniper',
            behavior = 'SHOOT_NEAREST',
            sniperMode = true,
            tags = {'weapon', 'projectile', 'energy', 'sniper'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.0 },
            rare = true,
            base = { 
                damage=180, cd=1.0, speed=1500, range=900, size=14,
                sniperRange=1600,
                elements={'ELECTRIC'}, damageBreakdown={ELECTRIC=1},
                critChance=0.40, critMultiplier=3.0, statusChance=0.40,
                magazine=10, maxMagazine=10, reserve=72, maxReserve=72, reloadTime=1.8,
                pierce=5
            },
            onUpgrade = function(w) w.damage = w.damage + 25 end
        },

        -- === BOWS (Primary) ===
        dread = {
            type = 'weapon', name = "Dread",
            desc = "Stalker's bow. [Hold: Charge Shot]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'bow',
            behavior = 'CHARGE_SHOT',
            chargeEnabled = true,
            maxChargeTime = 2.0,
            minChargeMult = 0.5,
            maxChargeMult = 2.0,
            chargeSpeedBonus = true,
            tags = {'weapon', 'projectile', 'physical', 'bow', 'silent'},
            classWeight = { warrior = 1.0, mage = 1.0, beastmaster = 2.0 },
            rare = true,
            base = { 
                damage=120, cd=0.7, speed=900, range=800, size=10,
                elements={'SLASH'}, damageBreakdown={SLASH=1},
                critChance=0.60, critMultiplier=2.5, statusChance=0.55,
                pierce=2
            },
            onUpgrade = function(w) w.damage = w.damage + 20; w.critChance = w.critChance + 0.05 end
        },
        paris = {
            type = 'weapon', name = "Paris",
            desc = "Tenno longbow. [Hold: Charge Shot]",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'bow',
            behavior = 'CHARGE_SHOT',
            chargeEnabled = true,
            maxChargeTime = 2.0,
            minChargeMult = 0.5,
            maxChargeMult = 2.0,
            chargeSpeedBonus = true,
            tags = {'weapon', 'projectile', 'physical', 'bow', 'silent'},
            classWeight = { warrior = 1.0, mage = 1.0, beastmaster = 2.0 },
            base = { 
                damage=90, cd=0.6, speed=850, range=750, size=10,
                elements={'PUNCTURE','IMPACT'}, damageBreakdown={PUNCTURE=3, IMPACT=1},
                critChance=0.40, critMultiplier=2.2, statusChance=0.35,
                pierce=1
            },
            onUpgrade = function(w) w.damage = w.damage + 15 end
        },

        -- === PISTOLS (Secondary) ===
        lato = {
            type = 'weapon', name = "Lato",
            desc = "Standard sidearm. Reliable and fast.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'pistol',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'pistol'},
            classWeight = { warrior = 1.0, mage = 1.0, beastmaster = 1.0 },
            base = { 
                damage=25, cd=0.12, speed=1100, range=500, size=6,
                elements={'IMPACT','PUNCTURE'}, damageBreakdown={IMPACT=1, PUNCTURE=1},
                falloffStart=250, falloffEnd=500, falloffMin=0.4,
                critChance=0.18, critMultiplier=2.0, statusChance=0.12,
                magazine=15, maxMagazine=15, reserve=210, maxReserve=210, reloadTime=1.0
            },
            onUpgrade = function(w) w.damage = w.damage + 5 end
        },
        lex = {
            type = 'weapon', name = "Lex",
            desc = "High-caliber pistol. Hits like a truck.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'pistol',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'physical', 'pistol'},
            classWeight = { warrior = 1.5, mage = 1.0, beastmaster = 1.0 },
            base = { 
                damage=75, cd=0.4, speed=1000, range=600, size=8,
                elements={'IMPACT','PUNCTURE'}, damageBreakdown={IMPACT=2, PUNCTURE=1},
                falloffStart=250, falloffEnd=600, falloffMin=0.4,
                critChance=0.30, critMultiplier=2.5, statusChance=0.15,
                magazine=6, maxMagazine=6, reserve=120, maxReserve=120, reloadTime=2.0
            },
            onUpgrade = function(w) w.damage = w.damage + 15 end
        },
        atomos = {
            type = 'weapon', name = "Atomos",
            desc = "Particle cannon. Chains to nearby enemies.",
            maxLevel = 5,
            slotType = 'primary',
            weaponCategory = 'energy',
            behavior = 'SHOOT_NEAREST',
            tags = {'weapon', 'projectile', 'energy', 'pistol'},
            classWeight = { warrior = 0.5, mage = 2.0, beastmaster = 1.5 },
            rare = true,
            base = { 
                damage=12, cd=0.05, speed=800, range=400, size=4,
                elements={'HEAT'}, damageBreakdown={HEAT=1},
                falloffStart=200, falloffEnd=400, falloffMin=0.5,
                critChance=0.15, critMultiplier=1.8, statusChance=0.40,
                magazine=70, maxMagazine=70, reserve=210, maxReserve=210, reloadTime=1.8,
                life=0.8, duration=2.0, chain=3, staticRange=100
            },
            onUpgrade = function(w) w.damage = w.damage + 3; w.chain = w.chain + 1 end
        },

        -- === MELEE ===
        skana = {
            type = 'weapon', name = "Skana",
            desc = "Standard Tenno sword. Balanced melee.",
            maxLevel = 5,
            slotType = 'melee',
            weaponCategory = 'melee',
            behavior = 'MELEE_SWING',
            behaviorParams = { arcWidth = 1.2 },
            tags = {'weapon', 'physical', 'melee', 'sword'},
            classWeight = { warrior = 1.5, mage = 0.8, beastmaster = 1.0 },
            base = { 
                damage=60, cd=0.12, range=100, 
                elements={'SLASH','IMPACT'}, damageBreakdown={SLASH=2, IMPACT=1},
                critChance=0.15, critMultiplier=1.8, statusChance=0.18,
                knockback=70
            },
            onUpgrade = function(w) w.damage = w.damage + 12 end
        },
        dual_zoren = {
            type = 'weapon', name = "Dual Zoren",
            desc = "Twin hatchets. Very fast attack speed.",
            maxLevel = 5,
            slotType = 'melee',
            weaponCategory = 'melee',
            behavior = 'MELEE_SWING',
            behaviorParams = { arcWidth = 1.0 },
            tags = {'weapon', 'physical', 'melee', 'dual'},
            classWeight = { warrior = 1.5, mage = 0.5, beastmaster = 1.5 },
            base = { 
                damage=50, cd=0.06, range=90, 
                elements={'SLASH'}, damageBreakdown={SLASH=1},
                critChance=0.35, critMultiplier=2.5, statusChance=0.10,
                knockback=50
            },
            onUpgrade = function(w) w.damage = w.damage + 10; w.critChance = w.critChance + 0.03 end
        },
}

return catalog
