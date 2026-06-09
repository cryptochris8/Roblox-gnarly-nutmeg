# Gnarly Nutmeg — Claude Code Master Instructions

You are helping build **Gnarly Nutmeg**, a small-sided arcade **soccer** game on
Roblox (Rojo + Roblox Studio + local files). It is the first conversion in the
Athlete Domains **Hytopia → Roblox** migration.

## What this is (and isn't)

This is a **ground-up Roblox rebuild** that reuses the *design and tuning* of the
original Hytopia soccer game. It is **NOT** a line-by-line port.

- **Design + tuning reference (read, don't copy code):**
  `C:\Users\chris\Hytopia-games\Gnarley` — especially `state/gameConfig.ts`
  (field/goal/timing/ball numbers) and `entities/ai/AIRoleDefinitions.ts`
  (the 6-role table + pursuit/discipline constants). The original code is buggy
  (a self-review found 96 issues) and engine-specific — **port the proven numbers
  and behaviour specs, not the implementation.**
- **Architecture template:** the Squishy Smash project at
  `C:\Users\chris\Roblox-squishy` (and its `CLAUDE.md`). Match its conventions.
- **Full plan:** `docs/00_CONVERSION_PLAN.md` is the source of truth for scope,
  phases, and the Hytopia→Roblox system mapping.

## First MVP goal (Phase 1)

A playable **3v3 or 4v4** match vs bots: move, sprint, pass, charge-and-shoot,
tackle, a simple goalkeeper, bots that play recognizable soccer, a scoreboard +
match timer + win condition, basic HUD, and **mobile-friendly controls**.
Placeholder art only (colored Parts). No tournaments / multi-room / full arcade
power-up set / penalties / spectator yet — those are later phases.

## Architecture (mirror Squishy Smash)

- `src/ReplicatedStorage/Shared/` — ModuleScripts: `GameConfig` (tunables),
  `Roles` (AI role table + constants), `Remotes` (RemoteEvent names + setup/get).
  Data tables are the single source of truth; both server and client `require()` them.
- `src/ServerScriptService/Server/` — **server-authoritative** service modules,
  one per feature, plus `Main.server.lua` (the only `Script`) that creates remotes
  first, requires + `init()`s services, builds the pitch, then wires events.
- `src/StarterPlayer/StarterPlayerScripts/` — client controller + ScreenGui UI
  modules, written respawn-safe. A `ClientController` boots UI and routes server
  messages + forwards input intents.

## Conventions (non-negotiable)

- `--!strict` at the top of every **server** module. Services are plain tables:
  `local Service = {}` … `function Service.init() … end` … `return Service`.
  No OOP/metatables.
- Services never `init()` each other — `Main.server.lua` is the only orchestrator.
  Cross-service hooks are callbacks set on the module table (e.g.
  `MatchService.onGoal = function(...) end`), to avoid circular requires.
- Always `Shared:WaitForChild("Module")` on requires (Shared streams in via Rojo).
- Intra-Server requires use `script.Parent.ServiceName`.
- All RemoteEvent names live in `Remotes.lua`; the server creates the folder and
  parents it **last**. The server validates every request — never trust the client.
- `pcall`-wrap all DataStore calls and any cosmetic world-build step; a cosmetic
  failure must never crash the server.
- Per-object state goes on the instance via `:SetAttribute`/`:GetAttribute`
  (cleaned up automatically when the instance is destroyed), not global tables.
- **Placeholder-first:** primitive Parts now; MeshParts/real models later.

## Input & mobile

Input is read on the **client** (`UserInputService` for desktop, plus
`ContextActionService` with `createTouchButton = true` for mobile Pass/Shoot/Tackle)
and forwarded to the server as intents via RemoteEvents. Movement uses the built-in
`Humanoid` controller (free desktop + mobile + gamepad support). Mobile must work —
it was the #1 pain point in the Hytopia original and is a strict upgrade on Roblox.

## Units note

Ported constants from the Hytopia source are now treated as **studs** (Roblox).
Roblox gravity is **196.2** (vs Hytopia's 32), so any ball/jump/shot **force**
constants will need a tuning pass during playtest. Field/goal **geometry** ported
1:1 preserves the relative layout and the AI role areas — keep it intact.

## Terminology (player-facing)

Standard soccer: Goal, Kickoff, Half, Possession, Tackle, Save, Striker,
Goalkeeper, Nutmeg (skill move). Family-friendly / Athlete Domains brand —
no violence beyond clean sports contact.

## Workflow

`rojo serve` from the repo root, connect the Rojo plugin in Studio (Edit mode),
then Play. World geometry is built from code in `WorldService` at runtime — there
is no pre-placed Studio geometry to lose on sync. DataStore is unavailable in
unpublished places (the persistence service guards for this and falls back to an
in-memory session).
