# Gnarly Nutmeg — Hytopia → Roblox Conversion Plan

> Source of truth for scope, phases, and the system mapping. Derived from a
> multi-agent feasibility study (2026-06-09) of the original Hytopia soccer game.

## Verdict

**Feasible, and a fun MVP can ship in ~1 week.** The original is ~85% *designed*
but its code is fragile/buggy and engine-specific. We **port the proven design and
tuning numbers, not the code.** The hardest parts of the Hytopia version (player
movement, ball feel, mobile controls) become *easier* on Roblox.

What ports vs what gets rebuilt:

| Bucket | Examples | Plan |
|---|---|---|
| Reuse as data/logic | tuning numbers, AI role table, pass-target heuristic, stamina model, match state machine | Transliterate to Luau ModuleScripts |
| Rebuild on Roblox built-ins | player movement (→ Humanoid), ball (→ real physics), goals (→ Touched), teams (→ Teams), mobile (→ ContextActionService) | Native Roblox |
| Throw away | HTML/CSS UI, SDK glue, the 4,578-line AI monolith, multi-room/tournament layers | Rebuild UI as ScreenGui; skip the rest for MVP |

## Target architecture (mirrors Squishy Smash)

```
src/ReplicatedStorage/Shared/
  GameConfig.lua    pitch dims, goals, timing, ball/shot/pass tunables, team sizes
  Roles.lua         6-role table + pursuit/discipline/spacing AI constants
  Remotes.lua       RemoteEvent names + setupServer()/get()
src/ServerScriptService/Server/
  Main.server.lua   entry: remotes -> services init -> build pitch -> wire events
  WorldService.lua  builds pitch (floor, walls, 2 goals + sensors, center circle, spawns)
  BallService.lua   ball spawn, possession (server CFrame follow), pass/shoot impulse, goal + OOB
  MatchService.lua  state machine (waiting/countdown/playing/goal/half/finished), score, timer, win
  TeamService.lua   team assignment (Teams service), roster, role assignment
  PlayerService.lua player rig spawn, stamina, action cooldowns, respawn-safe
  AIService.lua     lean bot controller: chase / hold role / pass / shoot via Humanoid:MoveTo
  PlayerDataService.lua  DataStore: goals/wins/matches + leaderstats (autosave + BindToClose)
src/StarterPlayer/StarterPlayerScripts/
  ClientController.client.lua  boots UI, routes server msgs, forwards input intents
  InputController.lua          desktop (UIS) + mobile (ContextActionService touch buttons)
  UiTheme.lua                  colors/fonts/builder helpers
  HudUI.lua                    scoreboard, timer, stamina + charge meter, countdown, goal flash
  MenuUI.lua                   team select + start
```

Server-authoritative throughout. Client sends intents (`RequestPass`,
`RequestShoot`, `RequestTackle`, movement is Humanoid) via RemoteEvents; server
validates and broadcasts state (`MatchState`, `ScoreUpdate`, `Countdown`,
`GoalScored`, `StaminaUpdate`, `Possession`).

## Phased plan

### Phase 1 — Smallest fun playable match (LAUNCH TARGET)
- [ ] Project scaffold (Rojo config, rokit, docs, CLAUDE.md)
- [ ] Shared: `GameConfig`, `Roles`, `Remotes`
- [ ] `WorldService`: build pitch — green floor, boundary walls, 2 goals with goal
      sensors, center circle, team spawn points
- [ ] `TeamService` + `PlayerService`: Red/Blue teams, role assignment, rig spawn,
      stamina → WalkSpeed, action cooldowns
- [ ] `BallService`: spawn ball, loose-ball proximity pickup, server-follow
      possession, pass (lead to best teammate), charge-and-shoot impulse, goal
      detection (Touched), out-of-bounds reset to center
- [ ] `AIService`: bots pick {chase ball / return to role spot / shoot if in range
      / pass to best teammate} on a ~0.4s loop using `Humanoid:MoveTo`; one bot per
      team is the keeper (stays on goal line, intercepts)
- [ ] `MatchService`: waiting → countdown(3-2-1) → playing → goal-scored → (timer) →
      finished; score; match timer; win condition; kickoff reset
- [ ] `PlayerDataService`: persist goals/wins/matches + leaderstats
- [ ] Client: `ClientController`, `InputController` (desktop + **mobile** buttons),
      `HudUI`, `MenuUI`, `UiTheme`
- [ ] `Main.server.lua` wiring + Studio smoke test (move/pass/shoot/score/win, mobile)

**Cut-line for launch:** a fun 3v3/4v4 vs bots — move, sprint, pass, charge-shoot,
tackle, bots play soccer, goals count, timer ends the match and shows a winner,
works on mobile. That is shippable for the World Cup.

### Phase 2 — AI quality + soccer polish
Pursuit coordination (cap chasers), formation spacing/repulsion, stop-and-pass
timing, better keeper, throw-in / corner / goal kick restarts, halftime + 2 halves,
stoppage time, dribble "nutmeg" dodge, crowd/announcer/music (reuse original audio).

### Phase 3 — Arcade mode (optional)
Mode toggle + 3–4 highest-impact power-ups (Speed Boost, Mega Kick, Freeze Blast,
Shield) as field pickups (Part + ProximityPrompt).

### Phase 4 — Post-launch
Penalty shootout, overtime, spectator camera, tournament brackets (multi-room →
one match per server or TeleportService reserved servers).

### Phase 5 — Real assets
Replace placeholder Parts with Creator Store / Toolbox meshes (see
`reference_roblox_free_assets`): ball, goal nets, stadium, kits, goal VFX/celebrations.

## Hytopia → Roblox system mapping (soccer specifics)

| System | Hytopia (original) | Roblox (this build) |
|---|---|---|
| Player movement | hand-rolled proportional-impulse controller | **Humanoid** (WalkSpeed/MoveDirection) — free desktop+mobile+gamepad |
| Ball | DYNAMIC rigidbody + "attach & set position each tick" possession | unanchored Ball Part w/ server **network ownership**; possession = server CFrame-follow 0.7 studs ahead |
| Pass/Shoot | `applyImpulse` along camera dir, charged power meter | `:ApplyImpulse` / set `AssemblyLinearVelocity`; charge timer on client → server validates |
| Goal detection | `isSensor` collider in goal mouth | thin `CanCollide=false` Part in the goal, `.Touched` |
| Out of bounds | sideline throw-in / goal-line corner/goal-kick | MVP: reset to center; restarts deferred to Phase 2 |
| Teams | manual `TeamManagementService` | **Teams** service (Red/Blue, team spawns) |
| AI movement | manual per-tick velocity, custom A* | `Humanoid:MoveTo` (+ `PathfindingService` if needed) |
| AI brain | 4,578-line monolith (don't copy) | lean state machine driven by `Roles.lua` data |
| Stamina | 0–100 → speed multiplier | same model → drives `Humanoid.WalkSpeed` |
| Input/mobile | HTML buttons (often broken) | `UserInputService` + `ContextActionService` touch buttons (strict upgrade) |
| UI | HTML/CSS overlay | ScreenGui modules (layout intent ported, markup rebuilt) |
| Audio | Hytopia Audio API | `Sound`/`SoundService` (reuse original audio files later) |
| Persistence | Hytopia PersistenceManager | `DataStoreService` (+ leaderstats) |

## Reused tuning (ported from the Hytopia source — real values)

From `Gnarley/state/gameConfig.ts`:
- Pitch bounds X **−37→52**, Z **−33→26** (≈89×59), center ≈ (7, −3); goal lines:
  Blue goal at X=**−37**, Red goal at X=**52**; goal width **10**, height **4**.
- Half **3 min**, 2 halves, halftime **2 min** (MVP may use one short half).
- `PASS_FORCE` 3.5, `SHOT_FORCE` 4.0, `TACKLE_KNOCKBACK_FORCE` 12, `STUN` 1.5s,
  ball friction 0.35, linear damping 0.2.

From `Gnarley/entities/ai/AIRoleDefinitions.ts`:
- 6 roles (goalkeeper, left-back, right-back, central-midfielder-1/2, striker) with
  `preferredArea` min/max X/Z, defensive/offensive 0–10, pursuit tendency, support &
  intercept distances; plus role pursuit distances/probabilities, position
  discipline, repulsion distance 14 / strength 1.2, shot arc 0.08 / pass arc 0.03.

> **Units note:** these are now **studs**; Roblox gravity 196.2 (vs 32) means the
> force constants (`SHOT_FORCE`, impulses, jump) need a playtest tuning pass.
> Geometry (bounds/goals/role areas) is kept 1:1 to preserve the proven layout.

## Risks & mitigations

1. **AI feel is the product.** Start at 3v3/4v4, port the role tuning table, ship
   "good enough" bots, iterate. (Biggest risk.)
2. **Ball feel under networking.** Keep server-owned ball + CFrame-follow possession
   (sidesteps networked physics contests); tune impulse constants in playtest.
3. **Scope creep.** Defer tournaments/multi-room/full arcade/penalties/spectator.
4. **UI time.** HUD + team-select only for launch.
5. **Tuning iteration.** All tunables live in `GameConfig`/`Roles` so tuning is a
   data edit, not a code change.
