# 暴击系统重构计划 (Critical Hit System Refactor)

## 目标
引入类似 Warframe 的暴击机制，为后续的 Build 系统打下数值基础。
这是从 "Roguelike" 转向 "RPG/Warframe" 数值体系的第一步。

核心逻辑：
- 每次造成伤害时，根据武器的 `critChance` 进行判定。
- 如果暴击，伤害乘以 `critMultiplier`。
- 暴击时，伤害数字显示为**黄色**且字号变大，提供视觉反馈。

## 涉及文件
1.  `state.lua`: 定义武器的基础暴击属性。
2.  `weapons.lua`: 在属性计算中包含暴击属性。
3.  `enemies.lua`: 执行伤害时进行暴击判定，并处理飘字颜色。
4.  `projectiles.lua`: 确保子弹携带武器的暴击属性。

## 详细步骤

### 步骤 1: 数据层 (`state.lua`)
为 `catalog` 中的武器添加基础暴击参数。
- **默认标准**: `critChance = 0.05` (5%), `critMultiplier = 1.5` (150%)。
- **Dagger (飞刀)**: 高暴击武器，设为 `critChance = 0.20`, `critMultiplier = 2.0`。
- **Wand (魔杖)**: 标准暴击。
- **Axe (斧头)**: 高爆伤，设为 `critChance = 0.10`, `critMultiplier = 2.5`。

### 步骤 2: 计算层 (`weapons.lua`)
修改 `cloneStats` 和 `calculateStats` 函数。
- 在 `cloneStats` 中，增加 `critChance` 和 `critMultiplier` 的复制。
- 确保这些属性最终能传递给生成的子弹 (Projectile)。

### 步骤 3: 逻辑层 (`enemies.lua`)
修改 `enemies.damageEnemy(state, enemy, damage, isCrit)` 函数。
- 增加 `isCrit` 参数。
- 如果 `isCrit` 为 true：
    - 飘字颜色改为黄色 `{1, 1, 0}`。
    - 飘字大小/缩放增加。
- 如果 `isCrit` 为 false：
    - 保持原有的白色 `{1, 1, 1}`。

### 步骤 4: 触发层 (`projectiles.lua` & `weapons.lua`)
- 在 `weapons.spawnProjectile` 中，确保生成的 `bullet` 对象拥有 `critChance` 和 `critMultiplier` 属性。
- 在 `projectiles.lua` 的碰撞检测逻辑中：
    - 当子弹击中敌人时，执行 `math.random() < bullet.critChance` 判定。
    - 计算最终伤害：`finalDamage = bullet.damage * (isCrit ? bullet.critMultiplier : 1)`。
    - 调用 `enemies.damageEnemy(state, enemy, finalDamage, isCrit)`。

## 验证计划
1.  启动游戏，选择 `Dagger` (如果可选) 或观察默认 `Wand`。
2.  攻击敌人，观察飘出的伤害数字。
3.  确认是否偶尔出现**黄色**的数字，且数值明显高于普通白色数字。
