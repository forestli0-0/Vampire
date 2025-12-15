# 军械库 UI 设计文档 (Arsenal UI Design)

## 1. 目标
重构 `arsenal.lua`，将其从简单的列表菜单升级为可视化的 **Mod 配置工作台**。
核心参考：Warframe 的武器配装界面。

## 2. 界面布局 (Layout)

### 2.1 左侧：武器概览 (Stats Panel)
* **武器选择器**: 顶部下拉或左右切换当前要配置的武器 (Wand / Axe / etc.)。
* **属性面板**: 显示当前武器的实时属性。
    * 基础伤害 (Base Dmg)
    * 暴击几率 / 倍率 (Crit)
    * 触发几率 (Status)
    * 元素伤害分布 (Impact/Slash/Heat/etc.) - **重点**：不同元素用不同颜色显示。
    * 攻速 / 范围 (Fire Rate / Range)

### 2.2 右侧：Mod 配置区 (Modding Grid)
* **容量条 (Capacity Bar)**: 显示 `已用容量 / 总容量`（例如 12 / 30）。
    * 如果超出容量，阻止装备。
* **8个插槽**: 2行4列的网格。每个格子代表一个 Mod 位。
* **Mod 库 (Mod Inventory)**: 底部显示玩家拥有的所有 Mod（可滚动）。
    * 支持拖拽（Drag & Drop）或者 点击选中->点击插槽。

## 3. 交互逻辑 (Interaction Logic)

1.  **装备/卸下**:
    * 点击底部库存里的 Mod -> 点击上方插槽 -> 装备。
    * 右键点击插槽 -> 卸下。
2.  **冲突检测**:
    * 同名 Mod 只能装一个（例如不能装两个 `Serration`）。
3.  **排序**:
    * `state.profile.weaponMods[weaponKey].modOrder` 需要严格对应插槽的顺序（1-8），因为元素组合顺序很重要（火+电=辐射，电+火=辐射，但火+冰+电 可能变成 爆炸+电）。

## 4. 数据结构调整 (State Changes)

在 `state.lua` 的 `catalog` 中，为每个 Mod 添加 `cost` (容量消耗) 属性。
* `mod_serration`: cost = 6
* `mod_split_chamber`: cost = 10
* `mod_cryogenic_rounds`: cost = 4
* ...

## 5. 视觉风格 (Visual Style)
* Mod 卡牌化：画成矩形卡片，左上角显示名字，右上角显示消耗，中间显示图标/缩写，下方显示等级圆点。
* 背景：暗色科技感网格。