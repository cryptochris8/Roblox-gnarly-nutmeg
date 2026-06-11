--!strict
-- TeamService (SERVER)
-- Owns the two Roblox Teams, assigns humans to a team + role, and provides the
-- pitch geometry on the NORTH-SOUTH field: which way a team attacks (along Z),
-- where each role's home is, and where the goals sit. Bots (AIService) fill the
-- roles humans don't take.

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Roles = require(Shared:WaitForChild("Roles"))

local FIELD = GameConfig.Field
local GOAL = GameConfig.Goal

local TeamService = {}

export type TeamName = string

export type TeamInfo = {
	name: TeamName,
	displayName: string, -- what the scoreboard calls this side ("RED" or a nation)
	ownGoalZ: number,   -- the goal line this team DEFENDS (along Z)
	attackDir: number,  -- +1 attacks toward +Z, -1 toward -Z
	opponent: TeamName,
	color: Color3,
	brick: BrickColor,
}

local DEFAULTS = {
	Blue = { displayName = "BLUE", color = Color3.fromRGB(70, 110, 225) },
	Red = { displayName = "RED", color = Color3.fromRGB(225, 70, 70) },
}

local teamObjects: { [string]: Team } = {}

local INFO: { [string]: TeamInfo } = {
	Blue = {
		name = "Blue", displayName = "BLUE", ownGoalZ = FIELD.MinZ, attackDir = 1, opponent = "Red",
		color = Color3.fromRGB(70, 110, 225), brick = BrickColor.new("Bright blue"),
	},
	Red = {
		name = "Red", displayName = "RED", ownGoalZ = FIELD.MaxZ, attackDir = -1, opponent = "Blue",
		color = Color3.fromRGB(225, 70, 70), brick = BrickColor.new("Bright red"),
	},
}

-- Paint a tournament identity (nation name + kit colour) onto a side. Kits,
-- highlights, and confetti all read INFO.color at spawn/use, so the next
-- kickoff dresses everyone correctly. Pass nil to restore RED/BLUE defaults.
function TeamService.setIdentity(team: TeamName, displayName: string?, color: Color3?)
	local info = INFO[team]
	if not info then
		return
	end
	info.displayName = displayName or DEFAULTS[team].displayName
	info.color = color or DEFAULTS[team].color
	info.brick = BrickColor.new(info.color) -- nearest brick for the Teams chip
	local teamObj = teamObjects[team]
	if teamObj then
		teamObj.TeamColor = info.brick
	end
end

TeamService.Names = { "Blue", "Red" }

type Assignment = { team: TeamName, role: Roles.RoleKey }
local assignments: { [Player]: Assignment } = {}
local takenRoles: { [string]: { [string]: Player } } = { Blue = {}, Red = {} }

function TeamService.teamSize(): number
	return math.clamp(GameConfig.PlayersPerTeam, 1, GameConfig.MaxPlayersPerTeam)
end

function TeamService.info(team: TeamName): TeamInfo
	return INFO[team]
end

local function humanCount(team: TeamName): number
	local n = 0
	for _, a in pairs(assignments) do
		if a.team == team then
			n += 1
		end
	end
	return n
end

-- The point a team attacks toward (the opponent's goal mouth centre).
function TeamService.targetGoalCenter(team: TeamName): Vector3
	local opp = INFO[INFO[team].opponent]
	return Vector3.new(FIELD.CenterX, FIELD.GroundY + GOAL.Height / 2, opp.ownGoalZ)
end

-- The point a team defends (its own goal mouth centre).
function TeamService.ownGoalCenter(team: TeamName): Vector3
	local me = INFO[team]
	return Vector3.new(FIELD.CenterX, FIELD.GroundY + GOAL.Height / 2, me.ownGoalZ)
end

-- Home (formation) position for a team + role.
function TeamService.homePosition(team: TeamName, roleKey: Roles.RoleKey): Vector3
	local def = Roles.get(roleKey)
	local me = INFO[team]
	local y = FIELD.GroundY + GameConfig.Player.SpawnHeight
	return Roles.homePosition(def, me.ownGoalZ, me.attackDir, FIELD.CenterX, y)
end

function TeamService.formation(team: TeamName): { Roles.RoleKey }
	return Roles.formationFor(TeamService.teamSize())
end

function TeamService.humanRoles(team: TeamName): { [string]: boolean }
	local out = {}
	for roleKey, _ in pairs(takenRoles[team]) do
		out[roleKey] = true
	end
	return out
end

function TeamService.assignHuman(player: Player, preferred: TeamName?): (TeamName, Roles.RoleKey)
	local existing = assignments[player]
	if existing then
		return existing.team, existing.role
	end

	local team: TeamName
	if preferred == "Blue" or preferred == "Red" then
		team = preferred
	else
		team = (humanCount("Blue") <= humanCount("Red")) and "Blue" or "Red"
	end

	local formation = TeamService.formation(team)
	local taken = takenRoles[team]
	local role: Roles.RoleKey? = nil
	-- humans get the most ATTACKING open outfield role first (striker > mids > backs)
	for i = #formation, 1, -1 do
		local rk = formation[i]
		if rk ~= GameConfig.GoalkeeperRole and not taken[rk] then
			role = rk
			break
		end
	end
	if not role then
		for _, rk in ipairs(formation) do
			if not taken[rk] then
				role = rk
				break
			end
		end
	end
	role = role or "striker"

	taken[role] = player
	assignments[player] = { team = team, role = role }

	local teamObj = teamObjects[team]
	if teamObj then
		player.Team = teamObj
		player.Neutral = false
	end
	return team, role
end

function TeamService.getAssignment(player: Player): Assignment?
	return assignments[player]
end

function TeamService.unassign(player: Player)
	local a = assignments[player]
	if not a then
		return
	end
	local taken = takenRoles[a.team]
	if taken[a.role] == player then
		taken[a.role] = nil
	end
	assignments[player] = nil
end

function TeamService.init()
	for _, name in ipairs(TeamService.Names) do
		local existing = Teams:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
		local t = Instance.new("Team")
		t.Name = name
		t.TeamColor = INFO[name].brick
		t.AutoAssignable = false
		t.Parent = Teams
		teamObjects[name] = t
	end
end

return TeamService
