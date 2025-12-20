local defs = {
    enemy = {
        pity = {
            hpThreshold = 0.3,
            energyThreshold = 0.25,
            health = 0.03,
            healthLow = 0.06,
            energy = 0.02,
            energyLow = 0.05
        },
        ammoChance = 0.03,
        explore = {
            elite = {
                healthOrb = 0.20,
                energyOrb = 0.15,
                ammo = 0.12,
                petModule = 0.15,
                modDrop = 0.80,
                bonusRare = 0.5
            },
            normal = {
                modDrop = 0.25
            }
        },
        rooms = {
            elite = {
                healthOrb = 0.20,
                energyOrb = 0.15,
                modDrop = 0.40,
                bonusRare = 0.5
            },
            normal = {
                credit = 0.08,
                modDrop = 0.25
            }
        }
    }
}

return defs
