# Render Pipeline Implementation Checklist (LOVE2D)
Project: Vampire
Version: v0.1
Owner: Tech Art / Rendering
Date: 2025-12-21

Purpose: Define the systems required to support the target neon look and specify the exact asset data those systems require.

---

## 0) Key Principle
The rendering system defines what assets must provide. Art production follows the system spec (layers, masks, naming, and limits).

---

## 1) Minimum Visual Systems (Phase A: Core Neon Look)
Goal: Achieve strong glow + contrast with minimal risk.

Systems:
- Emissive layer per sprite (optional, but supported everywhere)
- Bloom post-process with clamp
- VFX additive blending
- Camera feedback (shake + punch + flash)
- Parallax background (4 layers)

Asset requirements:
- Base color PNG
- Emissive PNG for neon parts (black if none)
- VFX sprites with glow cores

Acceptance:
- Emissive glow visible in most gameplay frames
- Bloom never blows out the full screen

---

## 2) Extended Visual Systems (Phase B: Depth and Material)
Goal: Add depth and volume without losing readability.

Systems:
- Normal-mapped 2D lighting for selected sprites
- Light mask composition (soft falloff)
- Optional AO or mask channel support

Asset requirements:
- Normal maps for key sprites (player, bosses, large props)
- Optional packed material map (see Section 5)

Acceptance:
- Light direction is readable on key assets
- Lights do not flatten silhouettes

---

## 3) Render Pass Breakdown (LOVE2D)
Pass order:
1) Background layers (parallax)
2) Scene base (all sprites)
3) Emissive mask (emissive sprites only)
4) Light mask (dynamic lights, optional normals)
5) Bloom (emissive -> downsample -> blur -> upsample)
6) Composite (base + lighting + bloom)
7) Post (tone map + LUT + vignette + grain + chromatic)
8) UI

Canvas sizes:
- Scene: full resolution
- Emissive: full resolution
- Light mask: half resolution
- Bloom chain: 1/2 -> 1/4 -> 1/8

Blend modes:
- Base: alpha
- Emissive: add
- Light mask: add (soft)
- Bloom: add (clamped)

---

## 4) Asset Naming and Lookup Rules
Rule: Same folder, same base name, optional suffixes.

Examples:
- assets/characters/player/move_1.png
- assets/characters/player/move_1_emit.png
- assets/characters/player/move_1_nrm.png

Fallback rules:
- If emissive missing, use black (0,0,0).
- If normal missing, use flat normal (0.5,0.5,1.0).

---

## 5) Material Map Options
Option A (separate files):
- *_emit.png
- *_nrm.png

Option B (packed single file):
- *_mat.png
- R: emissive mask
- G: ambient occlusion
- B: light mask or roughness proxy
- A: height (optional)

Pick one option and enforce consistently.

---

## 6) Data Required Per Asset (Checklist)
Per-asset metadata:
- Pixel size (w x h)
- Pivot (x, y)
- Animation FPS
- Emissive intensity target (0.0 - 3.0)
- Light response: none / low / high

Per-asset files:
- Base (required)
- Emissive (recommended)
- Normal (optional)
- Material map (optional, if using packed maps)

---

## 7) Lighting System Requirements
Light parameters:
- Position (x, y)
- Radius
- Color
- Intensity
- Type: point / cone / area

Limits:
- Typical lights on screen: 8-12
- Hard cap: 16
- Cull by distance and priority

---

## 8) Post-Processing Targets
Bloom:
- Threshold: 0.7-0.8
- Intensity: 1.0-1.4 (normal), 2.0 clamp (burst)

Tone mapping:
- ACES or filmic curve
- Avoid crushed blacks or washed highlights

Grading:
- LUT for final color shaping
- Vignette strength: 0.15-0.25
- Grain: 0.05-0.10
- Chromatic: subtle, 0.002-0.006

---

## 9) Debug and QA Views (Mandatory)
- Base color only
- Emissive only
- Light mask only
- Bloom only
- Final composite

Acceptance checks:
- Emissive areas <= 25% of screen
- Average luminance 0.12-0.20 (linear)
- No full-screen blowout during heavy combat

---

## 10) Implementation Checklist (LOVE2D)
- [ ] Create canvases for base, emissive, light, bloom chain
- [ ] Add sprite loader that resolves _emit/_nrm variants
- [ ] Implement emissive draw pass (additive)
- [ ] Implement bloom chain (downsample/blur/upsample)
- [ ] Implement composite shader (base + light + bloom)
- [ ] Add optional tone map + LUT pass
- [ ] Add debug view toggles
- [ ] Add light budget culling
- [ ] Add QA counters (lights, particles, bloom intensity)

---

## 11) What Art Must Deliver (System-Driven)
Characters:
- Base + emissive for all frames
- Normal for hero and bosses

Weapons:
- Base + emissive
- Impact sprites with strong emissive cores

VFX:
- Additive-friendly sprites (core + glow)
- Short lifespan with clear peak frame

Environment:
- Neon signage and props with emissive
- Optional normals for large props

UI:
- Glow layer for key highlights

