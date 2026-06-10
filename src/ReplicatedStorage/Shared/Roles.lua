--!strict
-- Roles
-- The six soccer positions + AI behaviour constants (ported from the original
-- AIRoleDefinitions.ts). With the NORTH-SOUTH pitch, `offsetLongFrac` is the
-- FRACTION of the pitch length from the team's OWN goal line toward the opponent
-- (along Z) and `laneCrossFrac` is the FRACTION of the pitch width across the
-- lane (X, relative to centre) — so the formation keeps true FIFA spacing at ANY
-- Field size in GameConfig. Pursuit/discipline are ported and drive AIService.

export type RoleKey =
	"goalkeeper"
	| "left-back"
	| "right-back"
	| "central-midfielder-1"
	| "central-midfielder-2"
	| "striker"

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

export type RoleDef = {
	key: RoleKey,
	name: string,
	isKeeper: boolean,
	offsetLongFrac: number,     -- fraction of pitch LENGTH from OWN goal line toward the opponent
	laneCrossFrac: number,      -- fraction of pitch WIDTH across the lane, relative to centre
	defensive: number,          -- 0-10
	offensive: number,          -- 0-10
	pursuitDistance: number,    -- studs (local pressing range; deliberately absolute)
	pursuitProbability: number,
	discipline: number,
}

local Roles = {}

local Definitions: { [string]: RoleDef } = {
	["goalkeeper"] = {
		key = "goalkeeper", name = "Goalkeeper", isKeeper = true,
		offsetLongFrac = 0.035, laneCrossFrac = 0, defensive = 10, offensive = 1,
		pursuitDistance = 8.0, pursuitProbability = 0.12, discipline = 0.95,
	},
	["left-back"] = {
		key = "left-back", name = "Left Back", isKeeper = false,
		offsetLongFrac = 0.15, laneCrossFrac = -0.26, defensive = 8, offensive = 5,
		pursuitDistance = 16.0, pursuitProbability = 0.28, discipline = 0.82,
	},
	["right-back"] = {
		key = "right-back", name = "Right Back", isKeeper = false,
		offsetLongFrac = 0.15, laneCrossFrac = 0.26, defensive = 8, offensive = 5,
		pursuitDistance = 16.0, pursuitProbability = 0.28, discipline = 0.82,
	},
	["central-midfielder-1"] = {
		key = "central-midfielder-1", name = "Left Central Midfielder", isKeeper = false,
		offsetLongFrac = 0.36, laneCrossFrac = -0.15, defensive = 6, offensive = 7,
		pursuitDistance = 22.0, pursuitProbability = 0.38, discipline = 0.72,
	},
	["central-midfielder-2"] = {
		key = "central-midfielder-2", name = "Right Central Midfielder", isKeeper = false,
		offsetLongFrac = 0.36, laneCrossFrac = 0.15, defensive = 6, offensive = 7,
		pursuitDistance = 22.0, pursuitProbability = 0.38, discipline = 0.72,
	},
	["striker"] = {
		key = "striker", name = "Striker", isKeeper = false,
		offsetLongFrac = 0.46, laneCrossFrac = 0, defensive = 3, offensive = 10,
		pursuitDistance = 26.0, pursuitProbability = 0.42, discipline = 0.62,
	},
}
Roles.Definitions = Definitions

local Formations: { [number]: { RoleKey } } = {
	[1] = { "goalkeeper" },
	[2] = { "goalkeeper", "striker" },
	[3] = { "goalkeeper", "central-midfielder-1", "striker" },
	[4] = { "goalkeeper", "left-back", "central-midfielder-1", "striker" },
	[5] = { "goalkeeper", "left-back", "right-back", "central-midfielder-1", "striker" },
	[6] = { "goalkeeper", "left-back", "right-back", "central-midfielder-1", "central-midfielder-2", "striker" },
}
Roles.Formations = Formations

-- Global AI behaviour constants (ported, scaled up for the larger pitch).
Roles.TeammateRepulsionDistance = 18.0
Roles.TeammateRepulsionStrength = 1.2
Roles.CenterAvoidanceRadius = 16.0
Roles.ShotArcFactor = 0.08
Roles.PassArcFactor = 0.03

function Roles.get(key: RoleKey): RoleDef
	return Definitions[key]
end

function Roles.formationFor(teamSize: number): { RoleKey }
	local f = Formations[teamSize]
	if f then
		return f
	end
	return Formations[6]
end

-- Home position on the north-south pitch: along the length (Z) from the team's own
-- goal line toward the opponent, in a lane across the width (X). attackDir is +1 if
-- the team attacks toward +Z, -1 toward -Z. Fractions x the live Field size keep
-- the same formation shape on any pitch.
function Roles.homePosition(def: RoleDef, ownGoalZ: number, attackDir: number, centerX: number, y: number): Vector3
	local FIELD = GameConfig.Field
	return Vector3.new(
		centerX + def.laneCrossFrac * FIELD.Width,
		y,
		ownGoalZ + attackDir * def.offsetLongFrac * FIELD.Length
	)
end

return Roles
