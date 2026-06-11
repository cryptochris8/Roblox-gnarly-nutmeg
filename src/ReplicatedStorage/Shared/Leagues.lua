--!strict
-- Leagues
-- The bot-difficulty ladder. Promotion at PromoteWins wins in a tier,
-- relegation at RelegateLosses losses. Each tier tunes how the bots actually
-- play: how fast they re-decide, how fast they run, how accurately they shoot,
-- and how far the keeper can reach.

export type League = {
	tier: number,
	name: string,
	color: Color3,
	aiTick: number,        -- seconds between outfield bot decisions
	walkMult: number,      -- bot WalkSpeed multiplier
	botShotSpread: number, -- degrees of bot shot inaccuracy
	keeperReachMult: number,
}

local Leagues = {}

Leagues.PromoteWins = 3
Leagues.RelegateLosses = 3

local List: { League } = {
	{ tier = 1, name = "AMATEUR", color = Color3.fromRGB(150, 200, 150), aiTick = 0.55, walkMult = 0.88, botShotSpread = 8, keeperReachMult = 0.8 },
	{ tier = 2, name = "SEMI-PRO", color = Color3.fromRGB(120, 190, 220), aiTick = 0.45, walkMult = 0.94, botShotSpread = 6.5, keeperReachMult = 0.9 },
	{ tier = 3, name = "PRO", color = Color3.fromRGB(245, 196, 60), aiTick = 0.4, walkMult = 1.0, botShotSpread = 5, keeperReachMult = 1.0 },
	{ tier = 4, name = "ELITE", color = Color3.fromRGB(245, 130, 60), aiTick = 0.33, walkMult = 1.05, botShotSpread = 4, keeperReachMult = 1.1 },
	{ tier = 5, name = "LEGEND", color = Color3.fromRGB(235, 80, 200), aiTick = 0.26, walkMult = 1.1, botShotSpread = 3, keeperReachMult = 1.2 },
}
Leagues.List = List

function Leagues.get(tier: number): League
	return List[math.clamp(tier, 1, #List)]
end

Leagues.MaxTier = #List

return Leagues
