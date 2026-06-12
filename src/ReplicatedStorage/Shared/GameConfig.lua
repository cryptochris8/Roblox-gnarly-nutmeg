--!strict
-- GameConfig
-- Every Gnarly Nutmeg tunable in one place.
--
-- ORIENTATION: the pitch runs NORTH-SOUTH. The LENGTH axis is Z (goals at min/max
-- Z); the WIDTH axis is X. Everything derives from Field.Length/Width/Center, so
-- resizing the pitch is a one-line change here.
--
-- The original Hytopia tuning (role zones, ball feel) informed these values, but
-- they're now Roblox-native and sized for this engine (gravity 196.2). Force/speed
-- numbers are starting points to refine in playtest.

local GameConfig = {}

-- ---- Teams & match flow ----------------------------------------------------
GameConfig.PlayersPerTeam = 6          -- full 6v6 (includes the goalkeeper); 1-6 all work
GameConfig.MaxPlayersPerTeam = 6
GameConfig.FillWithBots = true         -- bots fill the empty slots on both teams
GameConfig.CountdownSeconds = 3        -- 3-2-1-GO before kickoff
GameConfig.HalfDurationSeconds = 120   -- 2-minute halves
GameConfig.Halves = 2
GameConfig.GoalCelebrationSeconds = 6 -- room for the full 4.6s replay dolly + a beat
GameConfig.MatchEndScoreboardSeconds = 8

-- ---- Pitch geometry (STUDS) -----------------------------------------------
-- Length runs N-S (Z), Width runs E-W (X). FIFA-proportioned (105m x 68m is
-- ~1.54:1) and sized for 6v6 spacing. EVERYTHING derives from these two numbers
-- (markings, AI formation spots, boxes, circle), so rescaling the pitch really
-- is a one-line change — push Length toward 300 for full character-scale FIFA.
local Field = {
	Length = 240,            -- north-south extent (along Z) — the LEGAL pitch, line to line
	Width = 150,             -- east-west extent (along X)
	Runoff = 14,             -- grass apron beyond the lines (throw-ins/corners happen here)
	CenterX = 0,
	CenterZ = 0,
	GroundY = 0,             -- top surface of the pitch floor
	WallHeight = 20,         -- invisible boundary walls (out at the apron edge)
	FloorThickness = 2,
}
Field.MinX = Field.CenterX - Field.Width / 2
Field.MaxX = Field.CenterX + Field.Width / 2
Field.MinZ = Field.CenterZ - Field.Length / 2
Field.MaxZ = Field.CenterZ + Field.Length / 2
GameConfig.Field = Field

-- Goals sit on the short (N/S) ends, centred on X. Mouth spans X.
GameConfig.Goal = {
	Width = 20,        -- mouth width along X (smaller = harder to score)
	Height = 7,        -- with the crossbar near real 7.32m x 2.44m proportions
	Depth = 6,         -- how far the net box extends behind the line
	PostThickness = 1,
}

-- ---- Ball ------------------------------------------------------------------
GameConfig.Ball = {
	Diameter = 2.5,          -- studs (placeholder sphere)
	Density = 0.6,
	Elasticity = 0.5,        -- realistic soccer-ball bounce
	Friction = 0.4,          -- grips the grass and rolls naturally
	LooseDragPerSecond = 0.25, -- rolling / air resistance applied to a loose ball
	SpawnHeight = 3,         -- studs above GroundY at kickoff
	PickupRadius = 6,        -- a loose ball within this many studs auto-attaches
	KeeperReach = 6,         -- goalkeepers claim a ball within this radius (leaves the corners open)
	                         -- (was 7 on the 3v3 pitch; 6v6 + the wider goal plays best near 6)
	MaxClaimSpeed = 40,      -- outfielders can only trap a ball slower than this
	                         -- (the intended pass receiver and keepers are exempt —
	                         -- ported from the Hytopia possession design; stops
	                         -- defenders vacuum-catching driven passes mid-flight)
}

-- Realistic dribble: the ball is a real physics body steered to ROLL a few studs
-- ahead of the carrier in their direction of movement (in front, not lagging).
GameConfig.Dribble = {
	Offset = 4,              -- studs ahead of the carrier
	Responsiveness = 12,     -- P-gain steering the ball toward the lead point
	MaxSpeed = 50,           -- cap on dribble steering speed (keeps pace with a sprint)
	LeashRadius = 14,        -- server force-looses a human-steered ball that strays this far
	SprintKnockOn = 2.5,     -- extra lead at full sprint: faster carry, easier to nick
}

-- ---- Kicking (scaled for the larger pitch; TUNE in playtest) ---------------
GameConfig.Kick = {
	PassSpeedMin = 70,       -- soft short pass (speed scales with distance)
	PassSpeedMax = 130,      -- driven long ball
	PassArc = 0.10,
	PassMaxRange = 110,      -- furthest teammate considered for a pass (long balls)
	PassLeadDamping = 0.9,   -- fraction of the physically-perfect lead to apply
	ReceptionAssist = 1.6,   -- pickup-reach multiplier for the intended receiver
	ShotSpeedMin = 110,      -- studs/s at no charge
	ShotSpeedMax = 200,      -- studs/s at full charge
	ShotArc = 0.18,
	HumanShotSpreadDeg = 2,  -- slight human inaccuracy (bots use ~7)
	ChargeSeconds = 1.5,     -- hold time from min -> max power
	AfterKickGraceSeconds = 0.25,
	-- Curling finesse: a PLACED shot (sweet-spot charge, room to work) sets off
	-- outside the aim line and bends back in around the keeper; blasted shots
	-- (past CurlMaxCharge) fly straight and true. ELITE+ bots curl theirs too.
	CurlDeg = 9,             -- outward set-off angle the curl bends back through
	CurlMinCharge = 0.2,     -- below this it's a toe-poke - no shape on it
	CurlMaxCharge = 0.7,     -- above this it's driven - straight
	CurlMinDist = 14,        -- inside this there's no room to bend one
	CurlBotTier = 4,         -- bot leagues from this tier curl their corner picks
	StrikeShapePush = 7,     -- studs of placement drag from cutting across the ball
}

-- ---- Dead-ball restarts (throw-ins / corners / goal kicks) ------------------
GameConfig.Restart = {
	FreezeSeconds = 1.5,     -- whistle pause with the ball held on the spot
	ExclusiveSeconds = 3.5,  -- only the awarded team may take the ball (long
	                         -- enough for a far bot to actually walk to the spot)
}

-- ---- Tackle / contact ------------------------------------------------------
GameConfig.Tackle = {
	Range = 8,
	KnockbackSpeed = 38,
	StunSeconds = 1.5,
	Cooldown = 1.0,
}

-- ---- Nutmeg (the signature skill move) --------------------------------------
-- Poke the ball low THROUGH a close defender's legs: they stumble, you burst
-- past and re-collect. With nobody in front it's a simple knock-and-run touch.
GameConfig.Nutmeg = {
	Range = 7,               -- a defender this close (and ahead) can be megged
	FrontDot = 0.45,         -- how directly ahead the defender must be (cosine)
	PokeSpeed = 70,          -- low, fast poke through the legs
	KnockOnSpeed = 45,       -- knock-and-run touch when nobody is in front
	VictimStumbleSeconds = 0.9,
	BurstMultiplier = 1.35,  -- the winner's speed burst...
	BurstSeconds = 1.1,      -- ...and how long it lasts
	Cooldown = 2.5,
}

-- ---- Cosmetics ---------------------------------------------------------------
GameConfig.Vfx = {
	ShotTrailMinSpeed = 100, -- a loose ball faster than this leaves a streak (shots, not passes)
}

-- ---- Arcade power-ups (Phase 3) ----------------------------------------------
-- Floating pickups on the pitch — run over one to grab it. Family-friendly
-- adaptations of the Hytopia arcade set (no damage; clean sports effects only).
GameConfig.Arcade = {
	Enabled = true,          -- flip false for a pure-FIFA pitch
	RespawnSeconds = 15,     -- per spawn spot, after a pickup
	SpeedMultiplier = 1.4,   -- ⚡ Speed Boost…
	SpeedSeconds = 6,
	MegaKickMultiplier = 1.5, -- 💥 Mega Kick: shot power while active
	MegaKickSeconds = 8,
	FreezeRadius = 24,       -- ❄ Freeze Blast: opponents this close are frozen
	FreezeSeconds = 2.5,
	ShieldSeconds = 8,       -- 🛡 Shield: immune to tackles, stuns and freezes
}

-- ---- Player movement & stamina (faster, to suit the bigger field) ---------
GameConfig.Player = {
	WalkSpeed = 22,
	SprintSpeed = 32,
	LowStaminaSpeed = 14,
	SpawnHeight = 5,
}

GameConfig.Stamina = {
	Max = 120,               -- a little deeper tank for the bigger pitch
	RegenPerSecond = 18,
	DrainPerSecond = 22,
	ShootCost = 8,
	TackleCost = 5,
	PassCost = 2,
	NutmegCost = 10,
	MinToSprint = 5,
}

-- ---- Misc ------------------------------------------------------------------
GameConfig.GoalkeeperRole = "goalkeeper"
GameConfig.OutOfBoundsResetToCenter = true
GameConfig.AiTickSeconds = 0.4

return GameConfig
