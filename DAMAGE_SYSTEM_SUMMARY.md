# 伤害系统与机制（阶段性总结）

> 目标：把当前已实现的“Warframe 风格 Damage 2.0 + 状态异常 + 三层防御”在代码中的实际行为，整理成可讨论、可改动的基线。

## 1. 关键文件/入口

- 武器出伤与数值：`weapons.lua`
  - `weapons.calculateStats(state, weaponKey)`：武器基础 + 被动/Mod 叠加
  - `weapons.spawnProjectile(...)`：生成投射物/范围实例（写入伤害、元素、暴击、触发率等）
  - `weapons.update(state, dt)`：光环类/范围类武器按 CD 命中
- 投射物命中判定：`projectiles.lua`
  - `projectiles.updatePlayerBullets(state, dt)`：子弹与敌人碰撞 → `calculator.applyHit(...)`
- 伤害/异常统一计算：`calculator.lua`
  - `calculator.createInstance(params)`：构建 DamageInstance（拆分 damageByType、元素合成）
  - `calculator.applyHit(state, enemy, paramsOrInstance)`：先上异常，再扣血/盾，并派发 Augment 事件
  - `calculator.applyDamage(...)`：按伤害类型分段结算（克制/穿盾/护甲类型）
- 敌人承伤/持续伤害/护盾回复/敌人出伤：`enemies.lua`
  - `enemies.damageEnemy(...)`：实际扣盾/扣血（含护甲 DR 与 Viral 倍率）
  - `enemies.applyStatus(...)`：异常应用与叠层规则
  - `enemies.update(state, dt)`：DoT tick、护盾回复、敌人子弹、接触伤害
- 数值叠加规则：`stats_rules.lua`
- 武器/Mod/被动配置：`state.lua`（catalog）

## 2. 伤害数据流（一次命中）

1) 生成攻击源
- 武器从 `state.catalog[weaponKey].base` 拿基础 stats。
- `weapons.calculateStats` 应用 passives 与 mods（按 tag 匹配），得到 computedStats。
- `weapons.spawnProjectile` 计算：
  - `finalDmg = floor(wStats.damage * player.stats.might)`
  - 复制/写入：`elements`、`damageBreakdown`、`critChance`、`critMultiplier`、`statusChance`、`pierce` 等

2) 命中判定
- 投射物：`projectiles.updatePlayerBullets` 碰撞后调用 `calculator.applyHit`。
- 光环/范围：`weapons.update` / `projectiles` 内按半径遍历敌人调用 `calculator.applyHit`。

3) `calculator.applyHit`（统一结算顺序）
- 先 `createInstance`（damageByType 拆分 + 元素合成）
- 再 `applyStatus`（按 statusChance 触发异常，可多次 proc）
- 再 `applyDamage`（扣盾/扣血，写 lastDamage，输出伤害数字，派发 Augment 事件）

## 3. 数值叠加与基础公式

### 3.1 武器数值叠加（`stats_rules.lua`）
- `damage/cd/speed/area/...` 默认按“乘法百分比”叠加：
  - `new = base * max(0.1, 1 + mod * level)`
- `critChance/statusChance/critMultiplier/amount/pierce/...` 按“加法”叠加：
  - `new = base + mod * level`

### 3.2 暴击（当前实现）
- `calculator.computeDamage`：单次判定
  - 若 `rand < critChance` → 乘 `critMultiplier`；否则乘 1
- 当前不支持 Warframe 多层暴击（黄/橙/红）；`critChance > 1` 只会变成“必暴”。

### 3.3 元素拆分与复合元素
- `calculator.createInstance` 会把 `damage` 分配到 `damageByType[type]`（整数），分配权重来自 `damageBreakdown`。
- 元素合成（Damage 2.0）：只对**相邻主元素**做合成（如 HEAT+COLD→BLAST）。
- 注意：Mod 的 `addElements` 通过 `pairs()` 迭代，元素插入顺序可能不稳定 → 复合元素结果可能随运行变化。

## 4. 三层防御与克制（当前实现）

敌人字段在 `enemies.ensureStatus` 里标准化为：
- `health/maxHealth`，类型 `healthType`（默认 FLESH）
- `shield/maxShield`，类型 `shieldType`（默认 SHIELD）
- `armor`，类型 `armorType`（默认 FERRITE_ARMOR）

### 4.1 扣盾/扣血顺序（`calculator.applyDamage`）
- 对每个 `damageByType[type]` 单独分段：
  1) 先结算护盾（若不 bypassShield）：
     - `effectiveShieldDamage = remain * typeVsShield * shieldMult`
     - 扣盾后反推消耗量，得到剩余“原始伤害”
  2) 再结算生命：
     - `effectiveHealth = remain * typeVsHealth * typeVsArmorType`
     - `final = floor(effectiveHealth + 0.5)`
     - 再调用 `enemies.damageEnemy` 扣血（含护甲 DR 与 Viral）

### 4.2 护甲 DR（`enemies.damageEnemy`）
- `DR = armor / (armor + 300)`
- `healthAfterDR = remaining * (1 - DR)`

### 4.3 特例：毒素穿盾
- 直接伤害：`TOXIN` 在 `calculator.applyDamage` 中强制 `bypassShield=true`。
- DoT：toxin tick 也以 `bypassShield=true` 方式结算。

## 5. 异常与机制（已实现行为）

异常应用入口：`calculator.applyStatus` → `enemies.applyStatus`。
- `statusChance` 可大于 1：
  - `floor(statusChance)` 作为必定 proc 次数，小数部分作为额外一次概率。
  - 每次 proc 按 `damageByType` 作为权重抽取元素。

### 5.1 主要异常效果摘要
- `COLD/FREEZE`：冷却叠层减速；10 层冻结（speed=0），到时恢复。
- `HEAT/FIRE`：Heat DoT；Heat 期间敌方护甲临时减半（`getEffectiveArmor`）。油火联动会触发额外燃烧计时。
- `SLASH/BLEED`：DoT tick 时 `bypassShield=true` 且 `ignoreArmor=true`（相当于真实伤害）。
- `ELECTRIC/STATIC`：DoT + 短眩晕（带 lockout 防永久控）；tick 可向周围溅射电伤（有 cd 节流）。
- `MAGNETIC`：提高对护盾的伤害倍率并锁盾回（`shieldLocked=true`）。
- `VIRAL`：叠层提高对生命伤害倍率（上限 10 层）。
- `CORROSIVE`：永久剥甲（以 baseArmor 为基准按层数重算）。
- `PUNCTURE`：降低敌人造成的伤害（子弹/接触伤害都会被乘减益系数，最低 25%）。
- `BLAST`：降低敌人射击精度（子弹角度增加随机散布）。
- `GAS`：穿盾 DoT，并可对周围敌人溅射（有 cd 节流）。
- `RADIATION`：敌人会转而追击/射击其他敌人。

### 5.2 额外：STATIC 即时链电（Volt-like）
- 若一次命中 proc 出 `STATIC`，`calculator.applyHit` 会立即 `spawnVoltStaticChain`：
  - 在范围内跳跃若干目标，造成一定比例电伤并附带 STATIC。

## 6. 命中频率/穿透/多段

- 子弹对同一敌人：通过 `b.hitTargets[enemy]=true` 限制“一颗子弹只命中该敌人一次”。
- 穿透：`pierce` 命中一次减 1，归零消失。
- 回旋/二段：若子弹进入返程，会清空 `hitTargets` 允许返程再命中。
- 范围类（蒜、冰环、绝对零度、地震）：每次触发都会遍历范围敌人 → 天然多段（通常不做 per-target 冷却）。

## 7. 敌人护盾回复

- `SHIELD_REGEN_DELAY = 2.5s` 后开始回复。
- `SHIELD_REGEN_RATE = 0.25 * maxShield / s`。
- 若被 `shieldLocked`（如 MAGNETIC）则不回复。

## 8. 玩家受伤机制（敌人 → 玩家）

- 敌人子弹：`projectiles.updateEnemyBullets` → `player.hurt(state, damage)`。
- 敌人接触伤害：`enemies.update` 距离过近 → `player.hurt(state, 10 * dmgMult)`。
- 玩家减伤：平直护甲 `applied = floor(dmg - player.stats.armor)`，并有 `0.5s` 无敌帧。

## 9. Augment 事件钩子（扩展点）

- 命中链路：`preHit → onHit/onProc → postHit`（以及 `onDamageDealt/onShieldBroken/...`）
- 发射/子弹：`onShoot`、`onProjectileSpawned`、`onProjectileHit`
- 受伤链路：`preHurt → onHurt → postHurt`

## 10. 已知缺口/潜在问题（便于后续讨论）

- 多层暴击未实现（当前为单层判定）。
- 复合元素依赖元素顺序；而 Mod 加元素顺序可能不稳定 → 合成结果可能不稳定。
- “碎冰”（HEAVY 对冻结）额外伤害是直接 `enemies.damageEnemy`，不走类型克制表，也不吃暴击。

## 11. 下一步建议的讨论问题清单（你提问时可直接引用）

1) 你希望“复合元素”的规则更像 Warframe（按总元素集合合成）还是保留“相邻合成”？
2) 多层暴击要不要上？若上，想要：暴击颜色/倍率/溢出层数的具体规则？
3) `damageByType` 的分配与四舍五入是否符合预期（尤其低伤害武器）？
4) DoT 是否应该继承暴击/克制/元素占比？现在 tick 走 `applyDamage`，但 crit=0。
5) 你想优先平衡哪条 build：油火、冰锤碎冰、匕首流血、静电链电、毒素穿盾？
