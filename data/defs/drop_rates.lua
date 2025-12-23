local defs = {
    enemy = {
        pity = {
            hpThreshold = 0.3,
            energyThreshold = 0.25,
            health = 0.02,           -- 血球 2% (原3%)
            healthLow = 0.05,        -- 怜悯血球 5% (原6%)
            energy = 0.015,          -- 能量 1.5% (原2%)
            energyLow = 0.04         -- 怜悯能量 4% (原5%)
        },
        ammoChance = 0.12,           -- 弹药 12% (原3%) ⚠️ 大幅提升！
        explore = {
            elite = {
                healthOrb = 0.15,
                energyOrb = 0.12,
                ammo = 0.25,         -- 精英弹药 25% (原12%)
                petModule = 0.15,
                modDrop = 0.20,      -- 精英MOD 20% (原80%) ⚠️ 大幅降低
                bonusRare = 0.5
            },
            normal = {
                ammo = 0.15,         -- 普通怪弹药 15% (新增!)
                modDrop = 0.03       -- 普通MOD 3% (原25%) ⚠️ 大幅降低
            }
        },
        rooms = {
            elite = {
                healthOrb = 0.15,
                energyOrb = 0.12,
                ammo = 0.30,         -- 精英弹药 30% (新增!)
                modDrop = 0.15,      -- 精英MOD 15% (原40%) ⚠️ 大幅降低
                bonusRare = 0.5
            },
            normal = {
                credit = 0.06,
                ammo = 0.18,         -- 普通弹药 18% (新增!)
                modDrop = 0.05       -- 普通MOD 5% (原25%) ⚠️ 大幅降低
            }
        }
    }
}

return defs
