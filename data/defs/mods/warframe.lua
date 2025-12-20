local catalog = {
    vitality = {
        name = "生命力", desc = "生命值",
        stat = 'maxHp', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    steel_fiber = {
        name = "钢铁纤维", desc = "护甲值",
        stat = 'armor', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    redirection = {
        name = "重定向", desc = "护盾值",
        stat = 'maxShield', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    flow = {
        name = "流线型", desc = "能量上限",
        stat = 'maxEnergy', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.25,0.50,0.75,1.00,1.25,1.50}
    },
    streamline = {
        name = "精简", desc = "技能效率",
        stat = 'abilityEfficiency', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    intensify = {
        name = "强化", desc = "技能强度",
        stat = 'abilityStrength', type = 'add',
        cost = {6,7,8,9,10,11}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    rush = {
        name = "冲刺", desc = "移动速度",
        stat = 'moveSpeed', type = 'mult',
        cost = {3,4,5,6,7,8}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    quick_thinking = {
        name = "快速思维", desc = "能量回复",
        stat = 'energyRegen', type = 'mult',
        cost = {5,6,7,8,9,10}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    continuity = {
        name = "持续", desc = "技能持续时间",
        stat = 'abilityDuration', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    stretch = {
        name = "伸展", desc = "技能范围",
        stat = 'abilityRange', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.07,0.14,0.21,0.28,0.35,0.42}
    },
    blind_rage = {
        name = "盲怒", desc = "技能强度↑ 技能效率↓",
        stat = 'abilityStrength', type = 'add',
        cost = {6,7,8,9,10,11}, value = {0.08,0.16,0.24,0.32,0.40,0.48},
        stats = {
            {stat = 'abilityStrength', type = 'add', value = {0.08,0.16,0.24,0.32,0.40,0.48}},
            {stat = 'abilityEfficiency', type = 'add', value = {-0.04,-0.08,-0.12,-0.16,-0.20,-0.24}}
        }
    },
    fleeting_expertise = {
        name = "迅敏专精", desc = "技能效率↑ 技能持续↓",
        stat = 'abilityEfficiency', type = 'add',
        cost = {6,7,8,9,10,11}, value = {0.06,0.12,0.18,0.24,0.30,0.36},
        stats = {
            {stat = 'abilityEfficiency', type = 'add', value = {0.06,0.12,0.18,0.24,0.30,0.36}},
            {stat = 'abilityDuration', type = 'add', value = {-0.06,-0.12,-0.18,-0.24,-0.30,-0.36}}
        }
    },
    narrow_minded = {
        name = "狭域专注", desc = "技能持续↑ 技能范围↓",
        stat = 'abilityDuration', type = 'add',
        cost = {6,7,8,9,10,11}, value = {0.08,0.16,0.24,0.32,0.40,0.48},
        stats = {
            {stat = 'abilityDuration', type = 'add', value = {0.08,0.16,0.24,0.32,0.40,0.48}},
            {stat = 'abilityRange', type = 'add', value = {-0.05,-0.10,-0.15,-0.20,-0.25,-0.30}}
        }
    },
    tactical_dodge = {
        name = "战术闪避", desc = "闪避冷却",
        stat = 'dashCooldown', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {-0.06,-0.12,-0.18,-0.24,-0.30,-0.36}
    },
    momentum = {
        name = "动能驱动", desc = "闪避距离",
        stat = 'dashDistance', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.08,0.16,0.24,0.32,0.40,0.48}
    }
}

return catalog
