# Gnarly Nutmeg ⚽ (Roblox)

A small-sided arcade soccer game for Roblox — the first of the Athlete Domains
Hytopia → Roblox conversions. Built to ride the 2026 World Cup window.

This is a **redesign**, not a literal port: it reuses the proven *design and tuning
numbers* from the original Hytopia "soccer" game (`C:\Users\chris\Hytopia-games\Gnarley`)
but is rebuilt natively on Roblox (Luau + Rojo) using Roblox's free built-ins
(Humanoid movement, real physics, Teams, native mobile controls).

## Run it

1. Install [Rokit](https://github.com/rojo-rbx/rokit) and run `rokit install` (gets Rojo 7.6.1).
2. From this folder: `rojo serve`
3. In Roblox Studio (Edit mode), connect the **Rojo** plugin, then Play.

## MVP scope (Phase 1)

A 3v3 / 4v4 match vs bots: move, sprint, pass, charge-and-shoot, tackle, a simple
goalkeeper, a scoreboard + timer + win condition, and mobile-friendly controls.
See `docs/00_CONVERSION_PLAN.md` for the full phased plan and the Hytopia→Roblox
system mapping.

## Architecture

Mirrors the proven **Squishy Smash** template (`C:\Users\chris\Roblox-squishy`):

- `src/ReplicatedStorage/Shared/` — data tables, `GameConfig`, `Roles`, `Remotes` (ModuleScripts)
- `src/ServerScriptService/Server/` — server-authoritative services + `Main.server.lua`
- `src/StarterPlayer/StarterPlayerScripts/` — client controller + ScreenGui UI modules

Server is authoritative; client sends input intents over RemoteEvents.
