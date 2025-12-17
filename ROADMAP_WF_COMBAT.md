# Warframe-Style Combat System Roadmap

> 把 WF 的局外养成压缩到单局 roguelike

---

## 当前状态 (已完成)

### Phase 0-2: 基础职业系统 ✅
- [x] 手动攻击 (按住射击, Shift 瞄准)
- [x] 三职业 (Warrior/Mage/Beastmaster)
- [x] Q 职业技能
- [x] 职业权重系统 (升级选项偏好)
- [x] 开局保底 (前 2 次升级保证职业物品)
- [x] 自动扳机道具 (T 键切换)

---

## 待实现: WF 风格改造

### Phase A: 武器系统重构 ✅ [COMPLETED]

```
武器类别 (weaponCategory):
┌─────────────────────────────────────────────────────┐
│ Primary (主武器) - 键1                               │
│  ├─ rifle    : Braton, Boltor                       │
│  ├─ shotgun  : Hek, Strun                           │
│  ├─ sniper   : Vectis, Lanka                        │
│  ├─ bow      : Dread, Paris                         │
│  └─ energy   : Ignis, Amprex, Synapse (legacy)      │
├─────────────────────────────────────────────────────┤
│ Secondary (副武器) - 键2切换                         │
│  ├─ pistol   : Lato, Lex                            │
│  └─ energy   : Atomos                               │
├─────────────────────────────────────────────────────┤
│ Melee (近战) - 键2                                   │
│  └─ melee    : Skana, Fragor, Dual Zoren            │
└─────────────────────────────────────────────────────┘

Legacy (彩蛋武器):
- wand, holy_wand, fire_wand, static_orb (→ Amprex)
- heavy_hammer (→ Fragor), hellfire (→ Ignis), thunder_loop (→ Synapse)

Deprecated (已移除):
- garlic, ice_ring, soul_eater (光环类)
- axe, death_spiral (VS投射物)
- dagger, thousand_edge (飞刀类)
- absolute_zero, earthquake (将作为技能重做)
```

已实现:
- [x] state.lua 武器结构改为 ranged/melee 槽位
- [x] 武器定义添加 `weaponCategory` 字段
- [x] 武器切换逻辑 (1=ranged, 2=melee)
- [x] 新增 14 种 WF 风格武器
- [x] SHOOT_SPREAD 霰弹枪行为
- [ ] Arsenal 按类别分组显示 (TODO)
- [ ] HUD 显示当前武器类别 (TODO)

---

### Phase B: 弹药系统 [HIGH]

```
武器类型与弹药:
┌─────────────────────────────────────────────────────┐
│ 远程武器 (Ranged)                                    │
│  ├─ 消耗弹药 (magazine + reserve)                   │
│  ├─ 需要换弹 (reloadTime)                           │
│  └─ 备弹有上限                                       │
├─────────────────────────────────────────────────────┤
│ 近战武器 (Melee)                                     │
│  ├─ 无弹药消耗                                       │
│  └─ 可能有"能量/体力"系统 (轻击免费, 重击消耗)      │
└─────────────────────────────────────────────────────┘

补给来源:
- 箱子掉落 (仅远程弹药)
- 敌人掉落 (概率)
- 商店购买
```

> 当前状态: 部分武器已有 `magazine/reserve/reloadTime` 字段定义 (wand, dagger, hellfire 等)，
> 但实际换弹逻辑和弹药消耗尚未实现。

实现内容:
- [x] 武器定义添加 ammo/maxAmmo/reloadTime (部分完成)
- [ ] 实际弹药消耗逻辑 (weapons.lua)
- [ ] 换弹动画/逻辑 (R键)
- [ ] 弹药 HUD 显示
- [ ] 弹药掉落物

---

### Phase C: 近战动画化 [MEDIUM]

```
轻击: 点击, 快速, 低伤害
重击: 长按释放, 慢, 高伤害
连段: 轻x3 → 重 (combo finisher)
```

实现内容:
- [ ] 近战 behavior 独立
- [ ] 轻击/重击状态机
- [ ] 攻击动画帧
- [ ] 闪避取消 (Hades 风格)

---

### Phase D: 敌人攻击系统 [MEDIUM]

```
| 敌人类型 | 攻击方式  | 预警        |
|----------|-----------|-------------|
| 近战     | 挥砍      | 红光 0.3s   |
| 远程     | 弹幕发射  | 瞄准线      |
| 精英     | 技能组合  | 特效提示    |
| Boss     | 阶段技能  | 语音/动画   |
```

实现内容:
- [ ] 敌人攻击状态机 (预警→挥动→后摇)
- [ ] 弹幕发射系统
- [ ] 弹幕使用 calculator.lua 伤害
- [ ] 近战反弹弹幕 (进阶)

---

### Phase E: 4 技能系统 [MEDIUM]

```
| 键 | 名称       | 特点              |
|----|------------|-------------------|
| 1  | Ability 1  | 低能量, 快 CD     |
| 2  | Ability 2  | 中等              |
| 3  | Ability 3  | 高能量            |
| 4  | Ultimate   | 最强, 长 CD       |
```

消耗能量, 能量掉落补给

实现内容:
- [ ] 能量值 + HUD
- [ ] 4 技能槽定义
- [ ] 技能键位绑定
- [ ] 能量掉落物

---

### Phase F: 任务类型 [LOW]

```
| 类型        | 目标       | 奖励         |
|-------------|------------|--------------|
| Exterminate | 清除敌人   | 标准         |
| Defense     | 守护 X 波  | MOD + 资源   |
| Survival    | 存活 X 秒  | 大量资源     |
```

实现内容:
- [ ] 防御目标物 + 血条
- [ ] 生存计时器 + 生命支援
- [ ] 房间选择 UI (分支)

---

### Phase G: MOD 8 槽位 [LOW]

```
每把武器:
- 8 个 MOD 槽
- 容量限制 (类似 WF)
- MOD 等级 0-5

局内获取:
- 房间奖励
- 精英/Boss 掉落
- 商店购买
```

---

## 键位规划

```
| 键        | 功能              |
|-----------|-------------------|
| WASD      | 移动              |
| 鼠标左/J  | 攻击              |
| Space     | 闪避              |
| 1         | 切换远程武器      |
| 2         | 切换近战武器      |
| Q         | 职业技能          |
| R         | 换弹 (仅远程)     |
| Tab       | 任务信息          |
```

---

## 文件结构提示

现有关键文件:
- `state.lua` - 游戏状态, 职业定义, catalog
- `weapons.lua` - 武器发射逻辑
- `calculator.lua` - 伤害计算
- `player.lua` - 玩家逻辑, 闪避, 技能
- `enemies.lua` - 敌人 AI
- `draw.lua` - 渲染/HUD
- `rooms.lua` - 房间系统
- `arsenal.lua` - 开局配置
