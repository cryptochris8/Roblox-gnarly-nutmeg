--!strict
-- DifficultyService (SERVER)
-- Holds the bot-difficulty league PER TEAM. MatchService sets both at each match
-- setup; AIService and BallService read the live knobs for a given team. Per-team
-- so a team's bots can be competent teammates to their own humans AND opponents
-- scaled to the humans on the other side — one veteran can no longer force hard
-- bots onto newcomers server-wide.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Leagues = require(Shared:WaitForChild("Leagues"))

local DifficultyService = {}

local current: { [string]: Leagues.League } = {
	Red = Leagues.get(1),
	Blue = Leagues.get(1),
}

-- Set both teams' tiers. Returns true if either changed (callers may announce).
function DifficultyService.setTiers(redTier: number, blueTier: number): boolean
	local r, b = Leagues.get(redTier), Leagues.get(blueTier)
	local changed = (r.tier ~= current.Red.tier) or (b.tier ~= current.Blue.tier)
	current.Red, current.Blue = r, b
	return changed
end

-- The league for a team's bots. With no team it returns the HARDER of the two,
-- used by the shared AI tick gate (which simply runs at the faster rate).
function DifficultyService.get(team: string?): Leagues.League
	if team == "Red" then
		return current.Red
	elseif team == "Blue" then
		return current.Blue
	end
	return (current.Red.tier >= current.Blue.tier) and current.Red or current.Blue
end

return DifficultyService
