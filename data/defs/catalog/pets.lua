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
        -- Pet Modules (in-run relic-like, non-replaceable once installed)
        pet_module_pulse = {
            type = 'pet_module', name = "Pulse Core",
            desc = "Magnet Pup: ability becomes a short-range pulse that hits multiple enemies.",
            maxLevel = 1,
            requiresPetKey = 'pet_magnet',
            moduleId = 'pulse'
        },
        pet_module_field = {
            type = 'pet_module', name = "Field Core",
            desc = "Corrosive Slime: ability becomes a corrosive field around it.",
            maxLevel = 1,
            requiresPetKey = 'pet_corrosive',
            moduleId = 'field'
        },
        pet_module_barrier = {
            type = 'pet_module', name = "Barrier Core",
            desc = "Guardian Wisp: ability grants a brief barrier instead of healing.",
            maxLevel = 1,
            requiresPetKey = 'pet_guardian',
            moduleId = 'barrier'
        },

        -- Pet Upgrades (in-run growth, stackable)
        pet_upgrade_power = {
            type = 'pet_upgrade', name = "Pet Power",
            desc = "Pet ability deals more damage.",
            maxLevel = 5
        },
        pet_upgrade_overclock = {
            type = 'pet_upgrade', name = "Pet Overclock",
            desc = "Pet ability cooldown reduced.",
            maxLevel = 5
        },
        pet_upgrade_status = {
            type = 'pet_upgrade', name = "Pet Catalyst",
            desc = "Pet applies more status procs per ability.",
            maxLevel = 4
        },
        pet_upgrade_vitality = {
            type = 'pet_upgrade', name = "Pet Vitality",
            desc = "Pet max HP increased.",
            maxLevel = 5
        },
}

return catalog
