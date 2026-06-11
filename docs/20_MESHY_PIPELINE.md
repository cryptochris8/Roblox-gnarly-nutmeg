# Meshy → Roblox pipeline for Gnarly Nutmeg

Research summary (web-verified 2026-06-11) on using **Meshy AI** (meshy.ai) to
generate 3D assets for this game, and what it should — and should not — be
used for.

## The headline: NOT for player models

Meshy's auto-rig produces generic humanoid skeletons, **not Roblox R15 rigs**.
The two ways to get a Meshy humanoid into Roblox both lose:

1. **Avatar Auto-Setup** (Roblox's mesh→R15 converter) has strict input rules a
   raw Meshy sculpt fails: body ≤ 10,742 tris (head 4,000), upright A/T-pose,
   and the head must contain **five separate sub-meshes (2 eyes, upper teeth,
   lower teeth, tongue)** — Meshy outputs one welded mesh, so every character
   needs Blender surgery first.
2. **Custom skinned mesh + AnimationController** imports fine but abandons the
   whole R15 ecosystem: no default locomotion, no catalog animations, every
   run/kick/dive becomes custom animation work.

Our bots are stock R15 avatars in code-colored kits with free Roblox
locomotion — that is the right call. **Keep it.**

## What Meshy IS great for here (ranked)

1. **Trophy / World Cup-style cup** — hero prop for a post-match ceremony.
2. **Stadium dressing** — mascot statue outside the ground, camera gantries,
   team bus, food stalls, floodlight heads.
3. **Decorative goal frames + nets** — visual mesh only; keep the invisible
   Part colliders so ball physics stay exactly as tuned.
4. **Rigid accessories for R15 players** — cleats, headbands, keeper gloves
   (rigid accessories avoid all skinning pain).
5. *(stretch)* One mascot NPC via Avatar Auto-Setup, budgeting Blender time
   for the eye/teeth surgery.

## The working pipeline (props)

1. **Generate** in Meshy — Image-to-3D from a reference render beats
   text-to-3D for consistency. Use **Low Poly mode**, or **Remesh** down to
   ≤ 8–10k tris before export. Export **FBX** (or GLB).
2. **Blender sanity pass** (often skippable): apply transforms, one material /
   **single 1024² texture atlas** (Roblox = one material per MeshPart).
   The Blender MCP is available for this — see the home-dir memory.
3. **Import** via Studio's 3D Importer (Avatar tab). Hard ceiling: **20k tris
   per mesh** — budget under 10k. Set CollisionFidelity = Box on decorative
   meshes; real collisions stay as invisible Parts.
4. Texture via SurfaceAppearance if Meshy's PBR set is worth keeping.

Meshy also markets a one-click **"Roblox Bridge"** (OAuth → sends GLB to
Creator Hub). Verify it in-app; fall back to manual FBX download.

## Account notes

- **Free tier:** 100 credits/month, 1 queued task, and **outputs are public
  under CC BY 4.0** (attribution required — fine for placeholders, wrong for
  shipped IP).
- **Pro (~$20/mo):** ~1,000 credits, **private assets**, API access. If we
  adopt Meshy for real assets, Pro is the floor. The REST API (text-to-3D,
  image-to-3D, rigging) makes batch prop generation scriptable.

## Asset upload automation

For uploading finished meshes/images at scale, reuse the proven Open Cloud
pipeline from Squishy Smash (`tools/card_art/` in the Roblox-squishy repo):
.NET multipart upload (curl/Python TLS fail on this machine), and remember
the Decal-id → Image-id resolution gotcha documented there.
