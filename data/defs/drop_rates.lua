local defs = {
    enemy = {
        pity = {
            hpThreshold = 0.3,
            energyThreshold = 0.25,
            health = 0,              -- 血球 0% (禁用)
            healthLow = 0,           -- 怜悯血球 0% (禁用)
            energy = 0,              -- 能量 0% (禁用)
            energyLow = 0            -- 怜悯能量 0% (禁用)
        },
        ammoChance = 0.12,           -- 弹药 12%
        explore = {
            elite = {
                healthOrb = 0,       -- 精英血球 0% (禁用)
                energyOrb = 0,       -- 精英能量球 0% (禁用)
                ammo = 0.25,         -- 精英弹药 25%
                petModule = 0.15,
                modDrop = 0.20,      -- 精英MOD 20%
                bonusRare = 0.5
            },
            normal = {
                ammo = 0.15,         -- 普通怪弹药 15%
                modDrop = 0.03       -- 普通MOD 3%
            }
        },
        rooms = {
            elite = {
                healthOrb = 0,       -- 精英血球 0% (禁用)
                energyOrb = 0,       -- 精英能量球 0% (禁用)
                ammo = 0.30,         -- 精英弹药 30%
                modDrop = 0.15,      -- 精英MOD 15%
                bonusRare = 0.5
            },
            normal = {
                credit = 0.06,
                ammo = 0.18,         -- 普通弹药 18%
                modDrop = 0.05       -- 普通MOD 5%
            }
        }
    }
}

return defs

