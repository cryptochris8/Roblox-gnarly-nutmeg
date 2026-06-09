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
GameConfig.PlayersPerTeam = 3          -- MVP small-sided (includes the goalkeeper)
GameConfig.MaxPlayersPerTeam = 6
GameConfig.FillWithBots = true         -- bots fill the empty slots on both teams
GameConfig.CountdownSeconds = 3        -- 3-2-1-GO before kickoff
GameConfig.HalfDurationSeconds = 120   -- MVP: 2-minute halves
GameConfig.Halves = 2
GameConfig.GoalCelebrationSeconds = 3
GameConfig.MatchEndScoreboardSeconds = 8

-- ---- Pitch geometry (STUDS) -----------------------------------------------
-- Length runs N-S (Z), Width runs E-W (X). Generous so it reads as a real pitch.
local Field = {
	Length = 160,            -- north-south extent (along Z)
	Width = 100,             -- east-west extent (along X)
	CenterX = 0,
	CenterZ = 0,
	GroundY = 0,             -- top surface of the pitch floor
	WallHeight = 20,         -- invisible boundary walls
	FloorThickness = 2,
}
Field.MinX = Field.CenterX - Field.Width / 2
Field.MaxX = Field.CenterX + Field.Width / 2
Field.MinZ = Field.CenterZ - Field.Length / 2
Field.MaxZ = Field.CenterZ + Field.Length / 2
GameConfig.Field = Field

-- Goals sit on the short (N/S) ends, centred on X. Mouth spans X.
GameConfig.Goal = {
	Width = 18,        -- mouth width along X (smaller = harder to score)
	Height = 6,
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
	KeeperReach = 7,         -- goalkeepers claim a ball within this radius (leaves the corners open)
}

-- Realistic dribble: the ball is a real physics body steered to ROLL a few studs
-- ahead of the carrier in their direction of movement (in front, not lagging).
GameConfig.Dribble = {
	Offset = 4,              -- studs ahead of the carrier
	Responsiveness = 12,     -- P-gain steering the ball toward the lead point
	MaxSpeed = 50,           -- cap on dribble steering speed (keeps pace with a sprint)
}

-- ---- Kicking (scaled for the larger pitch; TUNE in playtest) ---------------
GameConfig.Kick = {
	PassSpeed = 95,          -- studs/s for a ground pass
	PassArc = 0.10,
	ShotSpeedMin = 110,      -- studs/s at no charge
	ShotSpeedMax = 200,      -- studs/s at full charge
	ShotArc = 0.18,
	ChargeSeconds = 1.5,     -- hold time from min -> max power
	PassLeadFactor = 0.20,
	AfterKickGraceSeconds = 0.25,
}

-- ---- Tackle / contact ------------------------------------------------------
GameConfig.Tackle = {
	Range = 8,
	KnockbackSpeed = 38,
	StunSeconds = 1.5,
	Cooldown = 1.0,
}

-- ---- Player movement & stamina (faster, to suit the bigger field) ---------
GameConfig.Player = {
	WalkSpeed = 22,
	SprintSpeed = 32,
	LowStaminaSpeed = 14,
	SpawnHeight = 5,
}

GameConfig.Stamina = {
	Max = 100,
	RegenPerSecond = 18,
	DrainPerSecond = 22,
	ShootCost = 8,
	TackleCost = 5,
	PassCost = 2,
	MinToSprint = 5,
}

-- ---- Misc ------------------------------------------------------------------
GameConfig.GoalkeeperRole = "goalkeeper"
GameConfig.OutOfBoundsResetToCenter = true
GameConfig.AiTickSeconds = 0.4

return GameConfig
