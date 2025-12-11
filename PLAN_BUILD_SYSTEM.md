# Build 系统重构与扩展计划

## 目标
解决当前 Build 系统深度不足、进化路线单一、缺乏“割草”快感的问题。通过引入新的通用被动道具和更多超武进化，增强玩家的策略选择和后期爽感。

## 阶段一：核心属性扩展 (New Passives)
当前被动只有 3 个（菠菜、空书、靴子）。我们需要引入影响核心机制的被动道具，特别是“投射物数量”和“范围”。

### 新增被动道具
1.  **Duplicator (复制器)**
    *   **效果**: 每级增加武器的投射物数量 (`amount` +1)。
    *   **爽点**: 弹幕流的核心，配合飞刀、魔杖效果爆炸。
2.  **Candelabrador (烛台)**
    *   **效果**: 增加攻击范围 (`area` +10%)。
    *   **爽点**: 让大蒜、斧头变大，视觉冲击力强。
3.  **Spellbinder (缚咒者)**
    *   **效果**: 增加武器持续时间 (`duration` +10%)。
    *   **爽点**: 延长冰冻、油污、静电的存在时间，强化控制流。
4.  **Attractorb (吸引器)**
    *   **效果**: 增加拾取范围 (`pickupRange`)。
    *   **爽点**: 站桩输出必备，减少跑图捡经验的麻烦。

## 阶段二：补全进化路线 (New Evolutions)
目前只有 2 个进化。目标是让所有基础武器都有对应的进化形态。

### 进化配方规划
| 基础武器 | 需求被动 | 进化武器 | 描述 |
| :--- | :--- | :--- | :--- |
| **Garlic (大蒜)** | Pummarola (番茄/红心) *[需新增]* | **Soul Eater (噬魂者)** | 范围极大，且吸取敌人生命值。 |
| **Dagger (飞刀)** | Bracer (护腕) *[需新增]* | **Thousand Edge (千刃)** | 无CD连发飞刀，像机枪一样扫射。 |
| **Fire Wand (火杖)** | Candelabrador (烛台) | **Hellfire (地狱火)** | 发射巨大的火球，能够穿透所有敌人。 |
| **Ice Ring (冰戒)** | Spellbinder (缚咒者) | **Absolute Zero (绝对零度)** | 持续存在的暴风雪区域，进入的敌人被永久减速/冻结。 |
| **Static Orb (静电球)** | Duplicator (复制器) | **Thunder Loop (雷环)** | 投射物数量翻倍，且在两点间形成电流网。 |
| **Heavy Hammer (重锤)** | Armor (护甲) *[需新增]* | **Earthquake (地震)** | 攻击变为全屏震动，眩晕所有地面敌人。 |

*(注：Oil Bottle 作为辅助武器，暂时可以不进化，或者设计为与 Fire Wand 的特殊连携)*

## 阶段三：系统逻辑升级 (System Upgrades)

### 1. 支持 `Amount` (数量) 属性
*   **现状**: `weapons.lua` 中大部分武器写死了发射数量（如 `wand` 发1个，`axe` 发1个）。
*   **修改**: 修改 `weapons.spawnProjectile` 和各武器逻辑，使其读取 `stats.amount` 属性。
    *   `Wand`: 连发次数 = 1 + amount。
    *   `Axe`: 同时扇形发射数量 = 1 + amount。
    *   `Dagger`: 连发或扇形 = 1 + amount。

### 2. 优化元素交互 (Status Scaling)
*   让状态效果（流血伤害、燃烧伤害）能受到 `Might` (攻击力) 的加成，避免后期元素流刮痧。

## 执行步骤 (Action Plan)

1.  **创建新被动**: 在 `state.lua` 的 `catalog` 中添加 `duplicator`, `candelabrador`, `spellbinder` 等定义。
2.  **修改武器逻辑**: 更新 `weapons.lua`，在计算属性时应用新的被动效果（特别是 `amount` 和 `duration`）。
3.  **实现新进化**:
    *   定义进化后的武器数据 (`state.lua`)。
    *   实现进化后的攻击逻辑 (`weapons.lua`)。
4.  **测试**: 验证新被动是否生效，进化是否正常触发。

---
*此文档作为后续开发的指导大纲。*
