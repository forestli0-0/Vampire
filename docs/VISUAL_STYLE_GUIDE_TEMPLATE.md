# Visual Style Guide (Neon Abyss 80% Target, LOVE2D)
Project: Vampire
Owner: Art Lead
Version: v0.1
Date: 2025-12-21

Purpose: This document defines the visual targets, technical budgets, and art rules required to reach a Neon Abyss-style look at ~80% fidelity.

---

## 0) Visual Goals
- Target vibe: Neon dungeon, arcade chaos, high contrast with controlled glow.
- Top 3 reference titles:
  - Neon Abyss: https://store.steampowered.com/app/788100/Neon_Abyss/
  - Enter the Gungeon: https://store.steampowered.com/app/311690/Enter_the_Gungeon/
  - Katana ZERO: https://store.steampowered.com/app/460950/Katana_ZERO/
- What "80% match" means:
  - 4-layer parallax background plus dynamic lights on the gameplay layer.
  - Emissive elements visible in most frames; bloom halo radius 8-16 px.
  - Average scene luminance <= 0.20 (linear), accents 18-22% of screen area.
  - Hit feedback uses flash + punch + trails in most combat moments.

---

## 1) Technical Targets and Budgets
| Item | Target |
| --- | --- |
| FPS | 60 |
| Internal resolution | 1280x720 |
| Render scale | 1.0 (output scale 1.5 for 1080p) |
| Max dynamic lights per screen | 12 (hard cap 16) |
| Max particles on screen | 600 typical, 1200 burst |
| Max bloom intensity | 1.4 normal, 2.0 burst clamp |
| Post chain | bloom -> tone map -> LUT -> vignette -> grain -> chromatic |

Performance notes:
- Target hardware: i5-8400 or Ryzen 5 2600 + GTX 1050 / UHD 620 class iGPU.
- Quality tiers: low/med/high with toggles for bloom, chromatic, grain, and dynamic lights.

---

## 2) Render Pipeline (LOVE2D)
Pass order:
1) Scene base color
2) Emissive mask
3) Light mask
4) Bloom (downsample -> blur -> upsample)
5) Composite (base + light + bloom)
6) UI

Canvas sizes:
- Scene canvas: full internal resolution
- Emissive mask: full internal resolution
- Light mask: half resolution
- Bloom chain: 1/2 -> 1/4 -> 1/8

Shader toggles:
- bloom
- tone_map_aces
- lut_2d
- vignette
- grain
- chromatic_aberration

Debug views:
- base
- emissive
- lighting
- bloom
- final

---

## 3) Color System
Base palette (dark): #07080F #0B0F1A #101624 #1A2236 #222C3F
Neon palette (accent): #00E5FF #FF3EA5 #7CFF6B #FFD23F #5B7CFF
Danger palette (warning): #FF3B3B #FF8A00 #FF2D6F
Accent usage ratio: 18-22%

Rules:
- Dark background must stay darker than 0.18 luminance (linear).
- Neon accents should be limited to 20% screen area (hard cap 25%).
- Avoid full-screen saturation spikes; keep average saturation <= 0.60.

---

## 4) Lighting and Materials
Sprite layers:
- Base color
- Emissive
- Normal (optional, tangent space)

Channel packing (if used):
- R: emissive
- G: ao
- B: mask
- A: height

Light rules:
- Light types: point, cone, area
- Typical radius: 120-220 px (player), 80-140 px (bullets), 200-320 px (boss)
- Falloff: smoothstep with soft clamp for compositing

---

## 5) Sprite Specs
Pixel density:
- Units per tile: 32 px
- Character height: 28-36 px (boss 64-96 px)

Outline:
- Thickness: 1 px
- Color: #0A0D14

Anchors:
- Characters: center-bottom
- Props: center

Naming:
- {entity}_{action}_{frame}.png
- Example: player_run_01.png

Export:
- Format: PNG, sRGB
- No premultiply, no transparency noise, no subpixel blur
- Use nearest filtering in engine

---

## 6) Animation Specs
Global FPS:
- Characters: 12-16
- Effects: 20-30

Timing:
- Attack windup: 4-6 frames
- Active frames: 2-4 frames
- Recovery: 4-8 frames
- Hitstop: 60-90 ms light, 90-140 ms heavy

Motion rules:
- No feet sliding at 1.0x speed
- Strong anticipation on heavy attacks
- 1-2 px overshoot on fast actions for snap

---

## 7) VFX System
Effect categories:
- hit
- explosion
- trail
- status
- environment

Blend modes:
- Additive for neon and sparks
- Alpha for bodies and smoke

Lifetime targets:
- Hit: 0.08-0.20s
- Explosion: 0.30-0.60s
- Status: 0.80-1.60s

DoD for each VFX:
- Uses palette colors only
- Has core + glow layers
- Does not exceed particle budget
- Readable at 1.0x scale
- Includes a clear start and end pose

---

## 8) UI Style
Fonts:
- Primary: Oxanium Bold (or closest geometric)
- Secondary: Noto Sans CJK SC (for Chinese) or similar

Sizes:
- Title: 28-36 px
- Body: 14-16 px
- Numbers: 18-24 px

Panels:
- Base color: #0D1424 (alpha 0.85)
- Border: #00E5FF
- Glow: #00E5FF, intensity 0.8

Motion:
- Hover duration: 0.12s
- Click flash: 0.08s
- Panel open: 0.18s

---

## 9) Camera and Feedback
Screenshake:
- Light: 2-4 px / 0.10-0.14s
- Heavy: 8-12 px / 0.18-0.24s

Zoom punch:
- Scale: 1.03-1.05
- Duration: 0.10-0.14s

Flash:
- Color: #BFF6FF or #FFFFFF
- Alpha: 0.15-0.25
- Duration: 40-90 ms

---

## 10) Asset Intake Checklist
- [ ] Naming matches spec
- [ ] Pivot set correctly
- [ ] Base/emissive present
- [ ] Normal map optional and correct
- [ ] Palette compliance
- [ ] Animation fps recorded
- [ ] Emissive intensity set and reviewed

---

## 11) Visual QA Checklist
- [ ] Silhouette readable against background
- [ ] Bloom not blowing out full screen
- [ ] Emissive limited to intended areas
- [ ] Average brightness within target range (0.12-0.20 linear)
- [ ] 60 fps on target hardware

---

## 12) Per-Asset Specification (fill for each asset)
Asset name: player_run
- Role: player
- Size (px): 32 x 32
- Frames: 8
- FPS: 14
- Palette: #00E5FF #FF3EA5 #7CFF6B
- Emissive intensity: 2.5
- Notes: 2-frame anticipation, 1-frame overshoot, no foot sliding
