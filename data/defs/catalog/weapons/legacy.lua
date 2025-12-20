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
}

return catalog
