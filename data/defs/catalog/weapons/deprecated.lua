local catalog = {
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
}

return catalog
