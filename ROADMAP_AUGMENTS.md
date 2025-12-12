# 机制升级（Augment）路线图

## 目标
- 解决“局内增幅几乎全是数值”的致命缺陷：让升级选择能改变打法、走位与决策，而不仅是让数字变大。
- 保持现有数值体系（武器/被动/mod）不推倒重来：机制层以“可插拔、数据驱动、可扩展”为核心。

## 设计原则
- **机制优先**：Augment 以“新增规则/触发/资源循环/弹道变化”为主；可带少量数值但不是主角。
- **低耦合**：通过事件钩子接入（onShoot/onHit/onKill…），避免到处写 if-else。
- **易加新内容**：新增一个 Augment 只需“填数据 + 写一段 handler”，不需要改核心结算逻辑。
- **可控复杂度**：每局可获得 Augment 数量有限（例如 3–6 个），减少信息过载。

## 数据结构（建议）
- `state.catalog` 新增条目：`type='augment'`
  - `maxLevel`：建议先做 `1`（一次性机制），后续再扩展可叠层。
  - `tags`/`targetTags`：可选（全局或指定武器标签生效）。
  - `handler`：可选（或者在 `augments.lua` 内按 key 分发）。
- `state.inventory.augments = { [augmentKey] = level }`

## 事件钩子层（核心）
新增 `augments.lua`（建议），提供：
- `augments.dispatch(state, eventName, ctx)`

建议的事件列表（先实现最常用的几类）：
- `onShoot`：一次开火（ctx: weaponKey, weaponStats, target, x,y）
- `onProjectileSpawned`：生成投射物（ctx: bullet）
- `onHit`：命中结算后（ctx: enemy, result{damage,isCrit,appliedEffects}, instance）
- `onProc`：触发异常后（ctx: enemy, effectType）
- `onKill`：击杀（ctx: enemy, sourceInstance）
- `onPickup`：拾取（ctx: kind, amount）
- `onHurt`：玩家受伤（ctx: amount）

## 接入点（改动位置）
- `weapons.spawnProjectile`：触发 `onShoot` / `onProjectileSpawned`
- `calculator.applyHit`：在命中结算后触发 `onHit` / `onProc`
- `enemies.damageEnemy`：在死亡判定处触发 `onKill`
- `pickups.lua`：拾取处触发 `onPickup`
- `player.hurt`：受伤处触发 `onHurt`

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
- Debug 菜单支持：直接添加/移除某个 Augment，快速验证机制手感。

## 里程碑
1) **脚手架**：`augments.lua` + 事件接入点打通 + 2 个示例 Augment
2) **内容扩充**：达到 8–12 个可用 Augment，形成明显分支流派
3) **进阶**（可选）：决定 Augment 的“局外收集/解锁池”还是“纯局内随机”

## 开放问题（等你拍板）
- Augment 的定位：纯局内随机？还是局外解锁后进入局内池？
- Augment 是全局生效还是按武器生效（或两套并存）？
- 每局 Augment 上限、出现频率、是否保底给机制选项？

