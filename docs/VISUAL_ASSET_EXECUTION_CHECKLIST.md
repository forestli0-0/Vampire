# Visual Asset Execution Checklist (Neon Abyss 80% Target)
Project: Vampire
Version: v0.1
Owner: Art Lead
Date: 2025-12-21

Purpose: This document defines per-asset deliverables and completion criteria to reach the target visual quality.

---

## 0) How to Use
- Use this checklist for each asset before integration.
- Mark items complete only when the asset is live in-game and validated against the style guide.
- If a requirement is not applicable, mark as N/A and explain in the asset notes.

---

## 1) Project Asset Paths (Current Project)
Characters (frame sequences):
- Pattern: assets/characters/<name>/move_<frame>.png
- Examples: assets/characters/player/move_1.PNG, assets/characters/skeleton/move_1.PNG, assets/characters/plant/move_1.PNG, assets/characters/bat/move_1.PNG
- Note: Existing character frames use .PNG (uppercase). Prefer lowercase .png for new assets to avoid case-sensitive issues.

Weapons:
- Pattern: assets/weapons/<weapon>.png
- Examples: assets/weapons/wand.png, assets/weapons/axe.png, assets/weapons/dagger.png, assets/weapons/bullet.png
- Placeholders to replace: assets/weapons/absolute_zero.txt, assets/weapons/earthquake.txt, assets/weapons/hellfire.txt, assets/weapons/soul_eater.txt, assets/weapons/thousand_edge.txt, assets/weapons/thunder_loop.txt

Enemy bullets:
- assets/enemies/plant_bullet.png

Effects (status):
- Pattern: assets/effects/<effect>/<frame>.png
- Examples: assets/effects/freeze/1.png, assets/effects/fire/1.png, assets/effects/bleed/1.png, assets/effects/static/1.png, assets/effects/oil/1.png

Pickups:
- Pattern: assets/pickups/<name>.png
- Examples: assets/pickups/chest.png, assets/pickups/gem.png, assets/pickups/chicken.png, assets/pickups/magnet.png, assets/pickups/bomb.png

Tiles:
- assets/tiles/grass.png

Optional/reserved:
- assets/sprites/player_sheet.png (atlas-style sheet, currently unused in code)

---

## 2) Common Deliverables (All Assets)
Files:
- Base color PNG
- Emissive PNG (if emissive exists)
- Normal PNG (optional, only if used)

Naming:
- Follow the folder patterns in Section 1.
- Add emissive and normal variants in the same folder:
  - {base}_emit.png
  - {base}_nrm.png
  - Example: assets/characters/player/move_1_emit.png

Metadata to record:
- Pixel size (w x h)
- FPS
- Pivot (x, y)
- Palette colors used
- Emissive intensity (target range)

Common checks:
- [ ] Silhouette reads at 1.0x and 2.0x
- [ ] Emissive areas are limited and intentional
- [ ] No stray pixels or transparency noise
- [ ] Palette compliance (base + neon + danger)
- [ ] Pivot set to spec
- [ ] Animation FPS documented

---

## 3) Player Character
Required actions:
- idle (6-8 frames)
- run (8-12 frames)
- jump/fall (6-8 frames)
- dash (4-6 frames)
- attack/cast (6-10 frames)
- hit (3-5 frames)
- death (8-12 frames)

Checks:
- [ ] Run cycle has no foot sliding
- [ ] Dash has 1-2 frame anticipation and 1 frame overshoot
- [ ] Hit reaction is readable within 120 ms
- [ ] Emissive accents on gear/eyes/weapon only
- [ ] Flash/outline test passes on dark backgrounds

Completion criteria:
- All actions implemented in-game with correct timings
- At least 2 idle variants or subtle breathing loop
- Dash and attack have distinct silhouettes

---

## 4) Enemies (Standard)
Required actions:
- idle/move (6-10 frames)
- attack (6-12 frames)
- hit (3-5 frames)
- death (6-10 frames)

Checks:
- [ ] Attack telegraph is visible 0.25-0.50s before impact
- [ ] Elite variant adds emissive highlights and color shift
- [ ] Hit reaction does not hide the silhouette

Completion criteria:
- Move/attack/hit/death are readable at 1.0x scale
- Elite variant is distinct at a glance

---

## 5) Bosses
Required actions:
- idle/move (8-12 frames)
- 2-3 attack cycles (each 8-16 frames)
- charge/telegraph (6-10 frames)
- hit (4-6 frames)
- phase transition (8-16 frames)
- death (12-20 frames)

Checks:
- [ ] Telegraphed areas are readable with color + shape
- [ ] Emissive is stronger than standard enemies but below bloom clamp
- [ ] Phase change includes VFX and audio cue

Completion criteria:
- Two distinct phases with different VFX signatures
- Attacks are readable with no overlapping clutter

---

## 6) Weapons and Projectiles
Weapons (player):
- muzzle flash or cast flash
- unique trail or arc
- impact effect

Projectiles:
- base sprite
- trail (2-3 frames)
- impact (4-8 frames)
- status overlay (if elemental)

Checks:
- [ ] Weapon silhouette is unique among the set
- [ ] Projectile reads at 0.5x scale
- [ ] Emissive is focused on the core, not the entire sprite

Completion criteria:
- Weapon loop and impact feel distinct from other weapons
- At least one signature VFX per weapon

---

## 7) Pickups and Drops
Required:
- idle loop (4-8 frames)
- glow layer
- spawn effect (2-4 frames)
- collect effect (4-8 frames)

Checks:
- [ ] Readable at a glance during combat
- [ ] Glow does not exceed 0.6 alpha

Completion criteria:
- Idle loop is smooth with no popping
- Collect effect is clearly visible within 0.20s

---

## 8) Environment and Props
Background:
- 4 parallax layers minimum
- 2-3 animated elements per biome

Props:
- static prop (1 frame)
- emissive accents (if neon)
- optional small loop (4-6 frames)

Checks:
- [ ] Foreground and midground do not obscure combat readability
- [ ] Parallax strength: far 0.2x, mid 0.5x, near 0.8x

Completion criteria:
- Biome reads clearly with at least 3 depth cues
- Lighting anchors space (signs, lamps, vents)

---

## 9) VFX Pack
Required categories:
- hit (light/heavy)
- explosion (small/large)
- trail (dash/projectile)
- status (burn/freeze/electric)
- environment (ambient glows)

Checks:
- [ ] Each VFX has clear start, peak, and end
- [ ] Additive used only for neon and sparks
- [ ] Lifetime within spec

Completion criteria:
- 30+ reusable VFX presets
- At least 3 variants per category

---

## 10) UI and Icons
UI states:
- default / hover / pressed / disabled
- focus glow (keyboard)

Icons:
- 1px outline
- 2-3 color max
- consistent lighting direction

Checks:
- [ ] All UI states animate within 0.08-0.18s
- [ ] Icons readable at 24 px
- [ ] Glow never exceeds 0.8 intensity

Completion criteria:
- Full HUD + menu set in target style
- Buttons feel responsive in combat

---

## 11) Final Acceptance (Per Asset)
Pass if ALL are true:
- [ ] Meets visual targets from style guide
- [ ] In-game readability confirmed on dark and bright backgrounds
- [ ] Emissive obeys bloom clamp
- [ ] No performance regression beyond budget
- [ ] Reviewed and signed off by art + VFX + design

---

## 12) Asset Tracking Template (Copy Per Asset)
Asset name:
Role:
Size (px):
Frames:
FPS:
Pivot:
Palette:
Emissive intensity:
Notes:
Checklist status: PASS / FAIL / N/A
