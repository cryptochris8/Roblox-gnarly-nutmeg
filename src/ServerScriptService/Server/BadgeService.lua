--!strict
-- BadgeService (SERVER)
-- Awards the five achievement badges. Ids come from Creator Hub (Chris);
-- an id of 0 means "not created yet" and that badge silently no-ops.
-- Every call is fire-and-forget and pcall-guarded; awarding never
-- touches the match flow.

local RobloxBadgeService = game:GetService("BadgeService")

local BadgeService = {}

local IDS = {
	FirstGoal = 0,
	HatTrick = 0,
	FirstNutmeg = 386665015462925,
	CupWinner = 1224844358661312,
	LegendSlayer = 0,
}

local function award(player: Player, key: string)
	local id = IDS[key]
	if not id or id == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			if not RobloxBadgeService:UserHasBadgeAsync(player.UserId, id) then
				RobloxBadgeService:AwardBadgeAsync(player.UserId, id)
			end
		end)
	end)
end

function BadgeService.firstGoal(player: Player)
	award(player, "FirstGoal")
end

-- streak = that scorer's goals this match (3+ = the hat-trick moment)
function BadgeService.goalStreak(player: Player, streak: number)
	award(player, "FirstGoal")
	if streak >= 3 then
		award(player, "HatTrick")
	end
end

function BadgeService.nutmeg(player: Player)
	award(player, "FirstNutmeg")
end

function BadgeService.cupWin(player: Player)
	award(player, "CupWinner")
end

-- a full-time win against tier-5 bots
function BadgeService.win(player: Player, botTier: number)
	if botTier >= 5 then
		award(player, "LegendSlayer")
	end
end

return BadgeService
