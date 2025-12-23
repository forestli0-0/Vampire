local catalog = {
        pet_magnet = {
            type = 'pet', name = "Magnet Pup",
            desc = "Periodic MAGNETIC procs (utility). Module: pulse AoE.",
            maxLevel = 1,
            base = {hp = 60, cooldown = 3.0, speed = 200, size = 16}
        },
        pet_corrosive = {
            type = 'pet', name = "Corrosive Slime",
            desc = "Periodic CORROSIVE procs (armor shred). Module: field AoE.",
            maxLevel = 1,
            base = {hp = 70, cooldown = 3.4, speed = 185, size = 17}
        },
        pet_guardian = {
            type = 'pet', name = "Guardian Wisp",
            desc = "Support: heal or brief barrier. Module: barrier i-frames.",
            maxLevel = 1,
            base = {hp = 55, cooldown = 4.0, speed = 215, size = 15}
        },
}

return catalog
