# Shader 替换计划（VFX 美术表现）

适用引擎：LÖVE2D（Lua + GLSL Shader）

## 目标
- 在“素材仍是占位符”的前提下，用程序化 shader 提升特效质感。
- 统一视觉标准：像当前“毒气圈 / 闪电链”一样清晰、有层次、不过曝。
- 控制 Bloom：Bloom 只服务“亮点/细线”，不把“大面积范围圈”洗白。

## 现状（已完成）
- 已有后处理 Bloom：`bloom.lua`（`B` 键切换）。
- 已有程序化 VFX 模块：`vfx.lua`（`V` 键切换），并已接入：
  - 毒气圈：`vfx.drawGas`（enemy gas 状态）
  - 静电光晕：`vfx.drawElectricAura`（enemy static 状态）
  - 闪电链：`vfx.drawLightningSegment`（`state.chainLinks`）
  - 地震冲击波：`vfx.drawExplosion`（`state.quakeEffects`）
- 已对“大面积圈”做过曝压制：`garlic/soul_eater`、`ice_ring`、`absolute_zero` 不再使用 add 叠加。

## 设计原则（强制）
1. **范围圈默认 alpha 混合**：禁止用 `add` 做大面积底色（避免 Bloom 提亮成白）。
2. **只有“细线/亮点”允许 add**：例如闪电链、边缘 sparkle、小火花。
3. **VFX 与 Bloom 解耦**：
   - 范围圈：低亮度、低 alpha、软边、噪声细节即可；
   - 亮点：才让 Bloom 发挥“柔和光晕”的优势。
4. **Draw 调用层只见 API**：`draw.lua` 只调用 `vfx.*`，不直接写 shader/混合模式逻辑。

## 需要替换/统一的效果清单

### P0：范围圈（统一为“柔和体积场/软边”标准）
| 效果 | 当前数据源 | 当前绘制点 | 目标 shader 方案 | 混合 | Bloom 贡献 |
|---|---|---|---|---|---|
| Garlic / Soul Eater 圈 | `weapons.calculateStats` 半径 | `draw.lua` “大蒜圈”段 | 软边 + 低频噪声 + 轻微脉冲；Soul Eater 颜色偏紫 | alpha | 低 |
| Ice Ring 提示圈 | `weapons.calculateStats('ice_ring')` | `draw.lua` “冰环提示”段 | 冷色软边 + 细碎冰晶噪声（可选） | alpha | 低 |
| Absolute Zero 大范围圈 | bullet `radius/size` | `draw.lua` bullets 分支 | 冷雾场（与 gas 同框架） | alpha | 低 |
| Earthquake 冲击波 | `state.quakeEffects` | `draw.lua` “地震特效”段 | 冲击环 + 微粒/碎屑噪声（已做基础） | alpha | 中（仅边缘点） |

### P0：链/线（维持“闪电链标准”并增强）
| 效果 | 数据源 | 绘制点 | 目标 shader 方案 | 混合 | Bloom 贡献 |
|---|---|---|---|---|---|
| Chain lightning | `state.chainLinks` | `draw.lua` chainLinks 段 | 主干(core)+外辉(glow)+抖动(offset)+闪烁(flicker)；可选分叉 | add | 高 |

### P1：地面覆盖/云雾（做成通用“Area Field”）
| 效果 | 数据源 | 绘制点 | 目标 shader 方案 | 混合 | Bloom 贡献 |
|---|---|---|---|---|---|
| Gas（已实现） | enemy `status.gasTimer/gasRadius` | `draw.lua` enemies 段 | 流场噪声 + 密度阈值 + 软边 | alpha | 低 |
| Oil（可扩） | enemy `status.oiled` 或地面效果 | 待确认 | 同框架：颜色/密度/流速参数化 | alpha | 低 |
| Freeze field（可扩） | `ice_ring` 或冰状态场 | 待确认 | 同框架：加冰晶纹理噪声（程序化） | alpha | 低 |

### P2：命中/小粒子（给 Bloom 提供“高质量亮点”）
| 效果 | 数据源 | 绘制点 | 目标 shader 方案 | 混合 | Bloom 贡献 |
|---|---|---|---|---|---|
| Electric sparks | 命中/静电跳点 | `hitEffects` 或新事件 | 小尺寸 sprite shader：尖锐亮点 + 抖动 | add | 高 |
| Fire sparks / embers | burn/heat tick | `hitEffects` 或新事件 | 小尺寸火花 + 余烬漂浮（可选） | add/alpha | 中 |
| Ice crack | frozen/heavy 破碎 | `hitEffects` | 冰裂纹闪烁 + 少量碎片点 | alpha + 少量 add | 中 |

## 统一 VFX API（建议落地到 `vfx.lua`）

### 必需接口（稳定）
- `vfx.drawAreaField(kind, x, y, radius, intensity, opts)`
  - `kind`: `gas|ice|soul|garlic|absolute_zero|quake|oil|...`
  - `opts`: `{ time, progress, edge, seed, alphaCap, bloomPolicy }`
- `vfx.drawLightningSegment(x1, y1, x2, y2, width, alpha)`（已实现，可增强）
- `vfx.drawElectricAura(x, y, radius, alpha)`（已实现，可调参）

### Bloom 策略（接口层约束）
- `bloomPolicy = 'none'|'low'|'high'`
  - `none/low`：强制 alpha 混合 + 限制输出亮度
  - `high`：允许 add（仅限细线/亮点）

## Shader 实现规范（所有 shader 通用）
- 输入：`time`（必需）、`alpha`（必需）、`progress`（可选 0..1）
- 输出：
  - 范围场：`vec4(col * a, a)`，并对 `a` 做上限钳制（避免过曝）
  - 亮点/细线：允许更高强度，但仍需限制覆盖面积
- 噪声：优先使用 1~2 层 value noise（已在 `vfx.lua` 有实现），避免高成本 FBM。

## 分阶段落地（执行顺序）
1. **P0 范围圈统一**：把所有范围圈都迁移到 `vfx.drawAreaField`（先做 garlic/soul/ice/absolute_zero）。
2. **P0 闪电增强**：在不改变数据结构的情况下，增强 `drawLightningSegment` 的层次（core+glow+flicker）。
3. **P1 Area Field 扩展**：把 oil/freeze 等也复用同一框架（只换参数）。
4. **P2 小粒子**：补齐 sparks/crack 等“给 Bloom 喂亮点”的细节。
5. **Bloom 收口（可选强化）**：如果仍有泛白风险，再做“亮通道分离”：Bloom 只处理亮通道 canvas。

## 验收标准（明确）
- 打开 Bloom（`B`）且开启 VFX（`V`）时：
  - 闪电链有明显光晕与抖动层次；
  - 毒气/范围圈“有质感但不洗白”，边缘柔和，中心不发白。
- 关闭 Bloom 时仍然好看（不会只剩一团灰）。
- Benchmark 场景下帧率不出现明显劣化；必要时降低噪声频率/层数。

## 复现与调试
- Bloom：自动高亮提取 + 模糊叠加（常驻，无开关）
- `V`：切换 VFX
- 静电触发：使用 `static_orb` / `thunder_loop`，命中敌人概率触发 `STATIC` 状态。
