--!strict
-- DifficultyService (SERVER)
-- Holds the match's active bot-difficulty league. MatchService sets it at each
-- match setup (the highest-league human present sets the bar — everyone fights
-- up); AIService and BallService read the live knobs from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Leagues = require(Shared:WaitForChild("Leagues"))

local DifficultyService = {}

local current: Leagues.League = Leagues.get(1)

-- Returns true if the tier actually changed (callers may announce it).
function DifficultyService.setTier(tier: number): boolean
	local league = Leagues.get(tier)
	if league.tier == current.tier then
		return false
	end
	current = league
	return true
end

function DifficultyService.get(): Leagues.League
	return current
end

return DifficultyService
