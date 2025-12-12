# 机制升级（Augment）路线图

## 目标
- 解决“局内增幅几乎全是数值”的致命缺陷：让升级选择能改变打法、走位与决策，而不仅是让数字变大。
- 保持现有数值体系（武器/被动/mod）不推倒重来：机制层以“可插拔、数据驱动、可扩展”为核心。

## 设计原则
- **机制优先**：Augment 以“新增规则/触发/资源循环/弹道变化”为主；可带少量数值但不是主角。
- **低耦合**：通过事件钩子接入（onShoot/onHit/onKill…），避免到处写 if-else。
- **易加新内容**：新增一个 Augment 只需“填数据 + 写一段 handler”，不需要改核心结算逻辑。
- **可控复杂度**：每局可获得 Augment 数量有限（例如 3–6 个），减少信息过载。
- **支持离散 + 持续触发**：既能处理“命中/击杀/拾取”等离散事件，也能支持“移动充能/站桩蓄力/每秒触发”等持续类被动。

## 数据结构（建议）
- `state.catalog` 新增条目：`type='augment'`
  - `maxLevel`：建议先做 `1`（一次性机制），后续再扩展可叠层。
  - `tags`/`targetTags`：可选（全局或指定武器标签生效）。
  - `handler`：可选（或者在 `augments.lua` 内按 key 分发）。
- `state.inventory.augments = { [augmentKey] = level }`
- `state.augmentState = { [augmentKey] = {cooldowns={}, counters={}, stacks={}, charge=0, data={}} }`
  - 用于：移动距离累计、站立计时、充能条、内部冷却、临时层数等“技能自身状态”。

## 事件钩子层（核心）
新增 `augments.lua`（建议），提供两层能力：
- **事件分发**：`augments.dispatch(state, eventName, ctx)`（命中/击杀/拾取/受伤等离散事件）
- **持续更新**：`augments.update(state, dt)`（用于移动充能、周期触发、内部冷却衰减等）

建议的事件列表（先实现最常用的几类）：
- `tick`：每帧（ctx: dt, t, player, movedDist, isMoving）
- `onShoot`：一次开火（ctx: weaponKey, weaponStats, target, x,y）
- `onProjectileSpawned`：生成投射物（ctx: bullet）
- `onProjectileHit`：投射物命中（ctx: bullet, enemy, result）
- `preHit`：命中结算前（可改 instance / 可 cancel）
- `onHit`：命中结算后（ctx: enemy, result{damage,isCrit,appliedEffects}, instance）
- `onProc`：触发异常后（ctx: enemy, effectType）
- `postHit`：命中+异常分发完毕后
- `onDamageDealt`：一次伤害结算后（ctx: damage, shieldDamage, healthDamage）
- `onShieldDamaged`：本次伤害有护盾伤害时
- `onShieldBroken`：本次伤害击破护盾时
- `onHealthDamaged`：本次伤害有生命伤害时
- `onKill`：击杀（ctx: enemy, sourceInstance）
- `onPickup`：拾取（ctx: kind, amount）
- `postPickup`：拾取生效后（用于“拾取后触发”）
- `pickupCancelled`：拾取被取消（ctx.cancel=true）
- `preHurt`：玩家受伤前（可改 amount / 可 cancel）
- `onHurt`：玩家受伤（ctx: amount）
- `postHurt`：玩家受伤后
- `hurtCancelled`：受伤被取消（ctx.cancel=true）
- `onEnemySpawned`：敌人生成
- `onLevelUp`：玩家升级
- `onUpgradeQueued`：升级界面入队（宝箱/升级）
- `onUpgradeOptions`：三选一生成后（可改 options）
- `onUpgradeChosen`：选择升级后

> 事件 ctx 是可变表：`preHurt/preHit/onShoot/onPickup` 这类“前置事件”里可以通过修改 ctx 来影响后续流程；设置 `ctx.cancel=true` 可取消本次动作。

## 触发条件系统（关键：支持“移动充能”等乱七八糟被动）
不建议把所有逻辑都写成“事件里塞 if-else”，而是让 Augment 用可组合的触发条件描述自己：
- **触发器（Trigger）**：绑定一个事件名 + 条件 + 冷却/计数器 + 动作
- **条件（Condition）**：可选过滤器，用于表达“移动中/站立中/血量阈值/元素命中/暴击/击杀类型”等
- **动作（Action）**：执行效果（生成投射物、附加状态、改变下一次攻击、掉落资源、临时buff…）

建议第一版就支持这些通用字段（足够覆盖多数 Build 游戏套路）：
- `cooldown`：触发后进入冷却（每个 Augment 独立）
- `chance`：概率触发
- `maxPerSecond`：限频（防止 tick 类技能爆炸）
- `requires`：条件集合（例如 `isMoving=true`、`enemyHasShield=true`、`isCrit=true`、`proc='ELECTRIC'`）
- `counter`：累计器（例如移动距离、站立时间、击杀数、命中数）
  - 示例：`counter='moveDist'`, `threshold=300` 表示“累计移动 300 距离触发一次并扣除阈值”

当前 `requires` 已支持（可继续扩展）：
- `isMoving / minMovedDist`
- `isCrit / proc`
- `playerHpPctBelow / playerHpPctAbove`
- `enemyHasShield / enemyShieldPctBelow / enemyShieldPctAbove`
- `enemyHasArmor / enemyHpPctBelow / enemyHpPctAbove`
- `enemyIsElite / enemyIsBoss / enemyKind / enemyFrozen`
- `weaponTag / weaponKey`
- `pickupKind`
- `minDamage / maxDamage`

当前 `counter` 已支持（按事件累计）：
- `tick`: `moveDist / moveTime / idleTime / time`
- `onHit`: `hits / damageDealt / crits`
- `onDamageDealt`: `damageDealt / shieldDamageDealt / healthDamageDealt`
- `onShoot`: `shots`
- `onProjectileSpawned`: `projectiles`
- `onProc`: `procs`
- `onKill`: `kills`
- `onPickup`: `pickups / pickupAmount`
- `onHurt`: `hitsTaken / damageTaken`
- `onLevelUp`: `levelUps`
- `onUpgradeChosen`: `upgrades`
- `onEnemySpawned`: `spawns`

> 这样“移动充能/站桩蓄力/每 N 秒一次/每 N 次命中一次/连杀触发”等都可以用同一套机制表达。

## 接入点（改动位置）
- `weapons.spawnProjectile`：触发 `onShoot` / `onProjectileSpawned`
- `calculator.applyHit`：在命中结算后触发 `onHit` / `onProc`
- `enemies.damageEnemy`：在死亡判定处触发 `onKill`
- `pickups.lua`：拾取处触发 `onPickup`
- `player.hurt`：受伤处触发 `onHurt`
- `player.updateMovement` 或主循环：在更新移动后，触发 `tick` 并提供 `movedDist/isMoving`

## 升级系统接入（Augment 如何出现在三选一里）
- `upgrades.generateUpgradeOptions`：把 `type='augment'` 加入 pool
  - 去重：同一个 Augment 不重复出现
  - 限制：到达“本局可拿 Augment 上限”后不再进入池
  - 保底：可做“每 N 次升级至少给 1 个机制选项”

## 第一批内容（建议先做 8–12 个）
要求：每个 Augment 都能显著改变打法；尽量少依赖 UI。

示例方向（占坑，不等于最终定案）：
- 弹道类：回旋/反弹一次/穿墙一次/命中后分裂
- 触发类：暴击追加弹/击杀爆炸/破盾震荡波/受伤反击
- 状态类：异常扩散/同元素叠层触发额外效果/元素协同奖励
- 资源类：击杀掉落临时能量球（拾取后下一次攻击强化）

## UI / 调试支持
- 左侧面板展示“本局已获得 Augment 列表”（可只显示名字+1行描述）。
- Debug 菜单支持：直接添加/移除某个 Augment，快速验证机制手感（F3 打开 → Tab 切到 `augment` 模式 → Right/Enter 添加 → Left/Backspace 移除）。

## 里程碑
1) **脚手架**：`augments.lua` + 事件接入点打通 + 2 个示例 Augment
2) **内容扩充**：达到 8–12 个可用 Augment，形成明显分支流派
3) **进阶**（可选）：决定 Augment 的“局外收集/解锁池”还是“纯局内随机”

## 当前实现（已落地）
- **事件系统**：已接入 `preHit/preHurt/onProjectileHit/onShieldBroken/onUpgradeOptions...` 等（见上方事件列表）。
- **机制型 Augment（现有）**
  - `aug_kinetic_discharge`：移动距离充能放电。
  - `aug_blood_burst`：击杀爆炸。
  - `aug_combo_arc`：连击阈值触发链电。
  - `aug_evasive_momentum`：移动中周期闪避一次受击（带短暂无敌帧）。
  - **弹道变化包（最有感）**
    - `aug_forked_trajectory`：投射物分叉。
    - `aug_homing_protocol`：投射物追踪。
    - `aug_ricochet_matrix`：投射物弹射找下一个目标。
    - `aug_boomerang_return`：投射物回旋返回（当前：回程未命中会在玩家附近转圈直至寿命结束）。
    - `aug_shatter_shards`：命中后碎裂成小弹片。

## 下一步（计划）
- **平衡与约束**：处理“分叉×碎裂×弹射”等组合上限、触发频率、性能压力。
- **机制保底**：升级三选一增加“机制选项保底/出现节奏”，让局内路线更开放。
- **反馈增强**：给弹道变化做更清晰的视觉反馈（例如弹片颜色/特效/轨迹）。

## 开放问题（等你拍板）
- Augment 的定位：纯局内随机？还是局外解锁后进入局内池？
- Augment 是全局生效还是按武器生效（或两套并存）？
- 每局 Augment 上限、出现频率、是否保底给机制选项？
