# Vampire x Warframe Project Context

## 1. 项目简介 (Project Overview)
这是一个基于 **Löve2D (Lua)** 引擎开发的类《吸血鬼幸存者》(Vampire Survivors) 游戏。
目前项目已经具备了基础的幸存者游戏框架，包括：
- **核心循环**: 敌人生成、自动攻击、经验拾取、升级选择。
- **战斗系统**: 多种武器（匕首、斧头、魔杖等）、投射物逻辑。
- **已实现的进阶机制**: 
    - **状态异常 (Status Effects)**: 流血(Bleed)、燃烧(Fire)、冰冻(Freeze)、油(Oil)、静电(Static)。
    - **暴击系统 (Critical)**: 仿 Warframe 的暴击层级（黄色、橙色、红色暴击）。
    - **多重射击 (Multishot)**: 投射物数量加成。
    - **性能测试**: `benchmark.lua` 用于压力测试。

## 2. 核心愿景：Vampire x Warframe (The Vision)
**目标**: 将《Warframe》复杂的伤害与防御机制（Damage 2.0）引入到《吸血鬼幸存者》的极简操作中，创造更有深度的配装(Build)体验。

### 2.1 防御类型 (Defense Types)
敌人不再只有单一的 "HP"，而是由三种防御层组成：
1.  **生命 (Health/Flesh)**: 红色血条。最基础的生命值。
2.  **护盾 (Shield)**: 蓝色血条。受到伤害后若一段时间未受击，会自动回复。
3.  **护甲 (Armor)**: 黄色血条。提供伤害减免 (DR)。
    *   公式参考: `DR = Armor / (Armor + 300)` (示例)。

### 2.2 元素与异常状态 (Elements & Status Effects)
我们需要重构伤害计算逻辑，引入 Warframe 风格的元素克制与异常状态：

*   **物理 (Physical)**:
    *   **切葛 (Slash)** -> **流血 (Bleed)**: 造成真实伤害（无视护甲）的 DoT。
    *   **穿刺 (Puncture)** -> **虚弱 (Weakened)**: 减少敌人造成的伤害。
    *   **冲击 (Impact)** -> **击退/失衡 (Stagger)**: 提高处决阈值（如果有）。

*   **单元素 (Primary Elements)**:
    *   **火焰 (Heat)**: DoT 伤害 + 暂时削减 50% 护甲。
    *   **冰冻 (Cold)**: 减速 + 承受暴击伤害增加。
    *   **电击 (Electricity)**: 连锁闪电伤害 + 眩晕。
    *   **毒素 (Toxin)**: **直接无视护盾**，对生命造成 DoT 伤害。

*   **复合元素 (Secondary Elements)**:
    *   **爆炸 (Blast)** (火+冰): AoE 击倒/降低命中率。
    *   **腐蚀 (Corrosive)** (电+毒): **永久** 剥离敌人护甲。
    *   **毒气 (Gas)** (火+毒): 制造持续伤害的毒云。
    *   **磁力 (Magnetic)** (冰+电): 对护盾造成额外伤害 + 阻止护盾回复。
    *   **辐射 (Radiation)** (火+电): 混乱（敌人互相攻击）+ 禁用光环效果。
    *   **病毒 (Viral)** (冰+毒): **生命值伤害增幅** (对生命造成的伤害提高 100%~325%)。

## 3. 当前进度与下一步计划 (Roadmap)

### 当前状态 (Current Status)
- 基础的状态异常（流血、燃烧等）已经硬编码在 `enemies.lua` 和 `projectiles.lua` 中。
- 刚刚完成了 `benchmark.lua` 工具，用于在重构前记录性能基准（FPS），以确保复杂的伤害计算不会拖垮游戏。

### 下一步任务 (Next Steps for New Session)
1.  **架构重构 (Refactor)**:
    - 创建 `calculator.lua` 模块。
    - 将分散在 `enemies.lua` (受击逻辑) 和 `projectiles.lua` (伤害逻辑) 中的代码解耦。
    - 建立统一的 `DamageInstance` 结构，包含：基础伤害、暴击层级、触发几率、元素类型列表。

2.  **实现 Damage 2.0**:
    - 修改 `Enemy` 类，使其拥有 `health`, `shield`, `armor` 属性。
    - 在 `calculator.lua` 中实现上述的元素克制逻辑（例如：毒素伤害跳过护盾计算）。

3.  **UI 更新**:
    - 绘制不同颜色的血条（红/蓝/黄）。
    - 伤害数字颜色区分（暴击颜色已实现，需加入护盾伤害显示）。

## 4. 给 AI 的指令 (Instructions for AI)
在新的会话中，请读取此文件。
你的首要任务是**不要破坏现有的游戏循环**。
请先从 **重构 (Refactor)** 开始，建立 `calculator.lua`，把现有的简单伤害逻辑迁移进去，确保游戏能正常运行，然后再逐步添加护盾、护甲和复杂的元素反应。
