# Gnarly Nutmeg — Roadmap (what's left to build)

Status audit against `00_CONVERSION_PLAN.md` + the 2026-06-11 competitive/
presentation research. Updated 2026-06-11.

## Where the original plan stands

| Phase | Status |
|---|---|
| **1 — Playable match (launch target)** | ✅ **Done & exceeded** (6v6, not 3v3; published privately, v9) |
| **2 — AI quality + soccer polish** | ✅ Done — restarts, stoppage, nutmeg, keeper, pass timing, crowd audio. *Missing: announcer + music.* |
| **3 — Arcade mode (power-ups)** | ❌ Not started (deliberately deferred) |
| **4 — Post-launch** | ✅ Penalties, golden goal, tournament (single-server). *Missing: spectator camera; multi-room brackets not needed yet.* |
| **5 — Real assets** | ❌ Mostly placeholder-styled (deliberate clean look). Meshy pipeline doc ready (`20_MESHY_PIPELINE.md`). |

## Remaining — original plan

1. **Arcade mode (Phase 3):** mode toggle + 3–4 power-ups as field pickups
   (Speed Boost, Mega Kick, Freeze Blast, Shield — full Hytopia list + numbers
   are in the design-mining notes). Biggest remaining *gameplay* feature.
2. **Spectator camera** (Phase 4) — watch the bots when eliminated/waiting.
3. **Real assets (Phase 5):** Meshy trophy mesh + mascot + stadium props
   (NOT player models — see `20_MESHY_PIPELINE.md`), Creator Store goal nets,
   kit textures, grass texture pass.
4. **Announcer + music** (Phase 2 leftover): FIFA-style text ticker first
   (~25 template strings + one MatchEvent remote), then client-side TTS
   name-reads (`AudioTextToSpeech` is client-only); gentle menu/halftime music
   from the Roblox audio library.

## Remaining — retention roadmap (2026-06 research, ranked)

1. **Daily quests + login streak** (~8h) — the #1 D7-retention tool; quests
   double as a tutorial ("complete 5 passes", "nutmeg a defender").
2. **XP / levels → unlockable skill moves** (~12h) — elastico, roulette,
   rainbow flick; the proven "one more match" loop, no gacha.
3. **Bot difficulty leagues** (~6h) — Amateur/Pro/Legend tuning ladders with
   promotion; replaces PvP ranked anxiety with PvE mastery.
4. Promo codes (~3h) — free marketing via the codes-site ecosystem.
5. Post-match ratings + Man of the Match (~5h).
6. Practice lobby (~5h) — open goal + cone course while waiting.
7. Coin shop cosmetics: kits, ball trails, celebrations (~12h, monetization path).
8. Power shot on cooldown (~5h) — pairs with arcade mode.
9. Co-op: friends join your team vs bots (~10h) — the social loop.
10. Weekly leaderboards (OrderedDataStore) (~5h).
11. Panna cage 1v1 ("Nutmeg Streets") (~10h) — identity play.

## Small polish backlog

- Bot kick/tackle animations (bots still don't swing a leg on kicks).
- Finesse/curve second shot type (low-driven vs placed).
- Trophy ceremony: visually verify (needs 3 straight wins); consider a
  celebration camera orbit; bump `GoalCelebrationSeconds` 3 → 5.
- Crowd volume swell when the ball enters the final third.
- Halftime stats screen (possession %, shots, tackles).
- Kickoff lineup card over the flyover.
- Ghost replay system (weekend project — ring buffer + client ghosts).

## Portfolio level (beyond this game)

Next Hytopia conversions per the migration ranking: **Penalty Kicks**
(~80% done in `Sports-game-generator`, 3–5 days, ideal companion app),
Basketball 3-Point, Golf, Ark-Rush, GhostSprint.
