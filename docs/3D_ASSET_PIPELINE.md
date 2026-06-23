# 3D Asset Pipeline — concept → 3D model → in‑game Roblox

How we turn an idea (a 2D picture or a text description) into a real, good‑looking
3D model inside a Roblox game. This is the process behind the Gnarly Nutmeg stadium
props (trophy, TV camera, **Gnarls** the squirrel mascot) and the Squishy Smash
buddy models. Reusable for any future character or prop.

## The chain (one picture)

```
  2D art  ──┐
            ├──►  Meshy AI  ──►  .fbx + thumbnail  ──►  VISUAL QC  ──►  Roblox
  prompt  ──┘   (gen 3D)        (local files)         (eyeball it)     Open Cloud
                                                                       upload
                                                                          │
                                                                          ▼
                                                                    MeshPart in
                                                                    the game world
```

Tooling: **Meshy.ai** (AI 3D generation) → **Roblox Open Cloud Assets API** (upload)
→ a `MeshPart` placed by code (`WorldService.placeProp`). Everything is scripted in
PowerShell under `tools/mesh_pipeline/`. **No Blender / no Studio modelling required.**

---

## Two routes into Meshy — pick the right one

### Route A — IMAGE‑to‑3D  *(best for canon characters; "looks great" because it matches the art)*
Feed Meshy a **2D picture** (the character's hero art) and it builds a 3D model
faithful to that image. This is how **Squishy Smash** made every buddy — each one is
generated from its card art, so the 3D matches the 2D canon.
- Endpoint: `POST https://api.meshy.ai/openapi/v1/image-to-3d`
- Input: the PNG as a base64 **data URI** in `image_url` (no public hosting needed).
- Single stage: it returns geometry **and** texture together.
- Script: `tools/mesh_pipeline/meshy_batch.ps1` (lives in Squishy; reads `crops/<id>.png`).
- **Use this when you have a reference image and want consistency.** A clean, well‑lit,
  front‑ish hero crop on a plain background gives the best result.

### Route B — TEXT‑to‑3D  *(when you have no art yet)*
Describe it in words; Meshy invents the look. This is how Gnarly Nutmeg's props +
Gnarls' poses were made. Quick, but it **re‑rolls the look every time** — which is why
Gnarls' cheer/acorn/kick poses drift slightly from his original statue.
- Endpoint: `POST https://api.meshy.ai/openapi/v2/text-to-3d`
- **Two stages:** `mode=preview` (geometry) → wait → `mode=refine` (texture).
- Script: `tools/mesh_pipeline/meshy_props.ps1` (a `$props` table of name → prompt).
- **Tip for consistency:** once you have ONE good text‑to‑3D render of a character,
  switch to Route A (image‑to‑3D from that render) for all his other poses so they
  share a look. *(This is the upgrade for future Gnarls poses.)*

Common Meshy request knobs (both routes): `enable_pbr = false` (Roblox wants simple
materials), `should_remesh = true`, `topology = 'triangle'`, `target_polycount`
~9k–12k (low enough to be cheap in‑engine, high enough to look smooth).

---

## Step by step

**1. Source.** Either a 2D hero image (Route A) or a one‑sentence prompt (Route B).
Good prompt shape: *"a cheerful orange cartoon squirrel mascot cheering, arms raised,
soccer jersey, **full body, no base**, family friendly, game asset."* (Say "no base/
pedestal" unless you want a statue plinth.)

**2. Generate (Meshy).** Run the script. It POSTs the task, polls every ~20s until
`SUCCEEDED`, then downloads `output/<name>.fbx` + `output/<name>_thumb.png`. The
**MESHY_API_KEY** is read from `HKCU:\Environment` (registry) — never printed, never
committed. Cost is in **Meshy credits** (the batch prints `consumed_credits` + remaining
balance). Manifests (`manifest.json`) make every run resumable.

**3. VISUAL QC — house rule.** *Look at the thumbnail before doing anything with it.*
This came after a 2026‑06‑10 moderation false‑positive: nothing goes near Roblox until a
human (or me, via Read) has eyeballed it for quality + anything brand‑risky (e.g. a stray
swoosh/logo Meshy sometimes stamps on a kit — regenerate clean if so).

**4. Upload to Roblox (Open Cloud).** `tools/mesh_pipeline/upload_props.ps1`
(Squishy: `upload_meshes.ps1`). It POSTs the `.fbx` as `assetType = 'Model'` to
`https://apis.roblox.com/assets/v1/assets` with `x-api-key = $env:ROBLOX_OPEN_CLOUD_KEY`,
polls the operation for the `assetId`, then polls `moderationResult`.
- **Account‑safety discipline (non‑negotiable):** ONE asset per **8 minutes**
  (`gapSeconds = 480`), **stop the whole run on any rejection** (exit 2), resumable via
  `props_uploaded.json`. The account has taken false‑positive strikes before — keep it a
  trickle, never a burst, and never upload un‑QC'd art.
- Out comes a **mesh asset id** (a number). That's what the game references.

**5. Place it in‑game.** Reference the id in a `PROP_IDS` table and spawn it as a
`MeshPart`. In Gnarly Nutmeg that's `WorldService.placeProp(id, targetHeight, cf, parent,
tilt, snapToGround)` → `loadProp` builds the MeshPart scaled to a target height. **Three
gotchas that make or break how it looks:**
- **Facing:** Meshy meshes face **−Z** → flip 180° so the prop faces where you aim it
  (`cf * CFrame.Angles(0, rad(180), 0)`).
- **Up‑axis:** the FBX exports **Z‑up** → most props need a **+90° pitch** tilt
  (`CFrame.Angles(rad(90), 0, 0)`) to stand upright. Verify live — Gnarls' was found
  empirically.
- **Grounding:** scale to a real‑world `targetHeight`, then snap to the floor using the
  model's bounding box (don't trust the pivot).

---

## Gotchas & tips for "looks great"

- **Image‑to‑3D > text‑to‑3D for anything that must stay on‑model.** Consistency is the
  whole reason Squishy's buddies look canon.
- **Strong source art = strong model.** Clean background, good lighting, character
  filling the frame, a clear silhouette.
- **`enable_pbr = false`** for Roblox — PBR maps mostly fight Roblox's lighting.
- **Polycount 9k–12k** is the sweet spot (smooth but light). Higher just costs more.
- **Always QC the thumbnail; regenerate brand‑risky textures** (logos/wordmarks) before
  upload — public storefront + a strike‑history account = zero tolerance.
- **Trickle uploads** (1/8 min, stop on reject). Same rule as the audio pipeline.
- **Orientation is the #1 "why does my prop look broken" bug** — −Z facing + Z‑up export.
  Bake the 180° flip + 90° tilt into your placement helper once and reuse it.
- **Free alternative:** for generic props you don't need bespoke, the Roblox Creator
  Store / toolbox has free meshes — see Squishy's `docs/10_FREE_ASSET_SOURCES.md`.

## Reference — files & keys

| Thing | Where |
|---|---|
| Text‑to‑3D generator | `tools/mesh_pipeline/meshy_props.ps1` (Gnarly) |
| Image‑to‑3D generator | `tools/mesh_pipeline/meshy_batch.ps1` (Squishy) |
| Roblox uploader | `tools/mesh_pipeline/upload_props.ps1` (Gnarly) / `upload_meshes.ps1` (Squishy) |
| Meshy key | `HKCU:\Environment\MESHY_API_KEY` (registry, never committed) |
| Roblox upload key | `$env:ROBLOX_OPEN_CLOUD_KEY` (Open Cloud, Asset write scope) |
| Generated models | `tools/mesh_pipeline/output/<name>.fbx` + `_thumb.png` |
| In‑game placement | `WorldService.placeProp` + a `PROP_IDS` id table |

**Current Gnarly Nutmeg mesh assets:** trophy `71905579050165`, tv_camera
`127716077350497`, mascotStatue (Gnarls) `102627059380175`. New Gnarls poses
(cheer/acorn/kick) are generated locally; upload only with an explicit per‑asset OK.
