--!strict
-- ProgressionService (SERVER)
-- XP, levels, three rotating daily quests, and the login streak — the reasons
-- to come back tomorrow. XP flows in from match events (Main/MatchService call
-- `note`), quests auto-claim on completion, the streak pays out on the first
-- join of each UTC day, and everything persists inside the PlayerDataService
-- profile. Pushes a ProgressionSync snapshot to the owning client on change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Skills = require(Shared:WaitForChild("Skills"))
local Leagues = require(Shared:WaitForChild("Leagues"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local ProgressionService = {}

-- XP for each tracked event
local XP_FOR: { [string]: number } = {
	goals = 25,
	nutmegs = 15,
	tackles = 8,
	passes = 3,
	shots = 2,
	wins = 30,
	matches = 20,
}

-- the daily quest pool; 3 are drawn per UTC day (same draw for everyone)
type QuestDef = { id: string, text: string, stat: string, target: number, xp: number }
local QUEST_POOL: { QuestDef } = {
	{ id = "goals2", text = "Score 2 goals", stat = "goals", target = 2, xp = 60 },
	{ id = "win1", text = "Win a match", stat = "wins", target = 1, xp = 80 },
	{ id = "megs2", text = "Nutmeg 2 defenders", stat = "nutmegs", target = 2, xp = 70 },
	{ id = "pass8", text = "Complete 8 passes", stat = "passes", target = 8, xp = 50 },
	{ id = "tackle5", text = "Win 5 tackles", stat = "tackles", target = 5, xp = 50 },
	{ id = "match3", text = "Finish 3 matches", stat = "matches", target = 3, xp = 60 },
	{ id = "shot6", text = "Take 6 shots", stat = "shots", target = 6, xp = 40 },
}

local LEVEL_CAP = 50

local syncEvent: RemoteEvent? = nil
local toastEvent: RemoteEvent? = nil
local xpGainEvent: RemoteEvent? = nil
local syncQueued: { [Player]: boolean } = {}

local function utcDay(): number
	return math.floor(os.time() / 86400)
end

-- XP needed to go from `level` to `level + 1` (fast early levels)
local function xpToNext(level: number): number
	return 100 + (level - 1) * 60
end

local function levelFromTotalXP(total: number): (number, number, number)
	local level = 1
	local rem = total
	while level < LEVEL_CAP and rem >= xpToNext(level) do
		rem -= xpToNext(level)
		level += 1
	end
	return level, rem, xpToNext(level)
end

local function todaysQuests(): { QuestDef }
	-- deterministic per-day draw, same for every player
	local rng = Random.new(utcDay())
	local pool = table.clone(QUEST_POOL)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	return { pool[1], pool[2], pool[3] }
end

local function toastTo(player: Player, text: string)
	if toastEvent then
		toastEvent:FireClient(player, text)
	end
end

-- profile.Progression = { XP, Quests = { day, progress = {id->n}, claimed = {id->true} }, Streak = { lastDay, count } }
local function progression(player: Player): any?
	local p = PlayerDataService.get(player) :: any
	if not p then
		return nil
	end
	if type(p.Progression) ~= "table" then
		p.Progression = { XP = 0, Quests = { day = 0, progress = {}, claimed = {} }, Streak = { lastDay = 0, count = 0 } }
	end
	local prog = p.Progression
	prog.XP = tonumber(prog.XP) or 0
	if type(prog.Quests) ~= "table" then
		prog.Quests = { day = 0, progress = {}, claimed = {} }
	end
	if type(prog.Streak) ~= "table" then
		prog.Streak = { lastDay = 0, count = 0 }
	end
	if type(prog.League) ~= "table" then
		prog.League = { tier = 1, wins = 0, losses = 0 }
	end
	-- a new day resets quest progress
	if prog.Quests.day ~= utcDay() then
		prog.Quests = { day = utcDay(), progress = {}, claimed = {} }
	end
	return prog
end

local function refreshLevelStat(player: Player, level: number)
	local stats = player:FindFirstChild("leaderstats")
	local lv = stats and stats:FindFirstChild("Level")
	if lv and lv:IsA("IntValue") then
		lv.Value = level
	end
end

function ProgressionService.getLevel(player: Player): number
	local prog = progression(player)
	if not prog then
		return 1
	end
	local level = levelFromTotalXP(prog.XP)
	return level
end

-- Lifetime XP total — the post-match card diffs this across a match.
function ProgressionService.getTotalXP(player: Player): number
	local prog = progression(player)
	return prog and (tonumber(prog.XP) or 0) or 0
end

function ProgressionService.getLeagueTier(player: Player): number
	local prog = progression(player)
	if not prog then
		return 1
	end
	return math.clamp(tonumber(prog.League.tier) or 1, 1, Leagues.MaxTier)
end

-- A match result on the ladder: 3 wins climbs a league, 3 losses drops one.
function ProgressionService.noteLeagueResult(player: Player, won: boolean)
	local prog = progression(player)
	if not prog then
		return
	end
	local lg = prog.League
	-- wins and losses CANCEL so the ladder tracks a NET record (no yo-yo where
	-- a win fails to pay down accumulated losses)
	if won then
		lg.losses = math.max(0, (tonumber(lg.losses) or 0) - 1)
		lg.wins = (tonumber(lg.wins) or 0) + 1
		if lg.wins >= Leagues.PromoteWins and lg.tier < Leagues.MaxTier then
			lg.tier += 1
			lg.wins = 0
			lg.losses = 0
			toastTo(player, ("🏅 PROMOTED! Welcome to the %s league!"):format(Leagues.get(lg.tier).name))
			ProgressionService.addXP(player, 100, "promotion")
		end
	else
		lg.wins = math.max(0, (tonumber(lg.wins) or 0) - 1)
		lg.losses = (tonumber(lg.losses) or 0) + 1
		if lg.losses >= Leagues.RelegateLosses and lg.tier > 1 then
			lg.tier -= 1
			lg.wins = 0
			lg.losses = 0
			toastTo(player, ("Moved down to %s — go win it back!"):format(Leagues.get(lg.tier).name))
		end
	end
	ProgressionService.sync(player)
end

-- Queue a sync to the owning client (coalesces bursts).
function ProgressionService.sync(player: Player)
	if syncQueued[player] then
		return
	end
	syncQueued[player] = true
	task.delay(0.4, function()
		syncQueued[player] = nil
		if player.Parent == nil then
			return
		end
		local prog = progression(player)
		if not prog or not syncEvent then
			return
		end
		local level, into, need = levelFromTotalXP(prog.XP)
		local quests = {}
		for _, q in ipairs(todaysQuests()) do
			quests[#quests + 1] = {
				id = q.id,
				text = q.text,
				xp = q.xp,
				target = q.target,
				progress = math.min(tonumber(prog.Quests.progress[q.id]) or 0, q.target),
				done = prog.Quests.claimed[q.id] == true,
			}
		end
		local tier = math.clamp(tonumber(prog.League.tier) or 1, 1, Leagues.MaxTier)
		-- the equipped cosmetics ride along (blob owned by CosmeticsService;
		-- read directly to avoid a module cycle)
		local cosmetics = nil
		do
			local p2 = PlayerDataService.get(player)
			local c = p2 and (p2 :: any).Cosmetics
			if type(c) == "table" and type(c.equipped) == "table" then
				cosmetics = c.equipped
			end
		end
		-- career totals ride along so the client can show the trophy cabinet
		local career = nil
		local p = PlayerDataService.get(player)
		if p then
			career = {
				goals = p.Goals,
				wins = p.Wins,
				draws = p.Draws,
				losses = p.Losses,
				matches = p.Matches,
				nutmegs = p.Nutmegs,
				trophies = p.Trophies,
			}
		end
		;(syncEvent :: RemoteEvent):FireClient(player, {
			xp = prog.XP,
			level = level,
			xpInto = into,
			xpNeed = need,
			quests = quests,
			streak = prog.Streak.count,
			career = career,
			cosmetics = cosmetics,
			league = {
				tier = tier,
				name = Leagues.get(tier).name,
				wins = tonumber(prog.League.wins) or 0,
				losses = tonumber(prog.League.losses) or 0,
				promoteAt = Leagues.PromoteWins,
				relegateAt = Leagues.RelegateLosses,
			},
		})
		refreshLevelStat(player, level)
	end)
end

-- A floating "+N REASON" reward chip fires only for the BIG moments. The frequent
-- pass/shot/tackle/match XP is deliberately absent: chipping every touch would
-- clutter the play screen — worst of all on mobile, where the brief is to keep it
-- clear for the game. Those still grant XP; they just don't pop a chip.
local CHIP_REASON: { [string]: string } = {
	goals = "GOAL!",
	wins = "WIN!",
	nutmegs = "NUTMEG!",
	promotion = "PROMOTED!",
	streak = "DAILY STREAK!",
}

-- Grant XP (level-ups + unlock announcements ride the sync/toasts).
function ProgressionService.addXP(player: Player, amount: number, reason: string?)
	local prog = progression(player)
	if not prog or amount <= 0 then
		return
	end
	local beforeLevel = levelFromTotalXP(prog.XP)
	prog.XP += amount
	local afterLevel = levelFromTotalXP(prog.XP)
	if afterLevel > beforeLevel then
		toastTo(player, ("⬆ LEVEL %d!"):format(afterLevel))
		for _, s in ipairs(Skills.List) do
			if s.unlockLevel > beforeLevel and s.unlockLevel <= afterLevel then
				toastTo(player, ("🔓 %s unlocked — press %s!"):format(s.name, s.key.Name))
			end
		end
	end
	local label = reason and CHIP_REASON[reason]
	if label and xpGainEvent then
		(xpGainEvent :: RemoteEvent):FireClient(player, amount, label)
	end
	ProgressionService.sync(player)
end

-- Record a tracked event: base XP + daily-quest progress (auto-claim).
function ProgressionService.note(player: Player, stat: string, n: number?)
	local count = n or 1
	local prog = progression(player)
	if not prog then
		return
	end
	local base = (XP_FOR[stat] or 0) * count
	for _, q in ipairs(todaysQuests()) do
		if q.stat == stat and not prog.Quests.claimed[q.id] then
			local cur = (tonumber(prog.Quests.progress[q.id]) or 0) + count
			prog.Quests.progress[q.id] = cur
			if cur >= q.target then
				prog.Quests.claimed[q.id] = true
				base += q.xp
				toastTo(player, ("✅ Quest complete: %s  (+%d XP)"):format(q.text, q.xp))
			end
		end
	end
	if base > 0 then
		ProgressionService.addXP(player, base, stat)
	else
		ProgressionService.sync(player)
	end
end

-- First join of the day: advance/reset the streak and pay it out.
local function handleStreak(player: Player)
	local prog = progression(player)
	if not prog then
		return
	end
	local today = utcDay()
	local s = prog.Streak
	if s.lastDay == today then
		return -- already counted today
	end
	if s.lastDay == today - 1 then
		s.count = (tonumber(s.count) or 0) + 1
	else
		-- the streak resets, but coming back after days away is WELCOMED,
		-- not punished — a soft landing so returning never feels bad
		if (tonumber(s.lastDay) or 0) > 0 and today - s.lastDay >= 3 then
			toastTo(player, "👋 Welcome back! We saved your boots — here's +75 XP")
			ProgressionService.addXP(player, 75, "welcome back")
		end
		s.count = 1
	end
	s.lastDay = today
	local reward = 25 + 15 * math.min(s.count, 7)
	if s.count > 0 and s.count % 7 == 0 then
		reward += 150
		toastTo(player, ("🔥 %d-day streak — milestone bonus!"):format(s.count))
	end
	toastTo(player, ("🔥 Day %d login streak: +%d XP"):format(s.count, reward))
	ProgressionService.addXP(player, reward, "streak")
end

function ProgressionService.init()
	syncEvent = Remotes.get(Remotes.ProgressionSync)
	toastEvent = Remotes.get(Remotes.Toast)
	xpGainEvent = Remotes.get(Remotes.XpGain)

	local function onJoin(player: Player)
		task.spawn(function()
			-- wait for the profile (PlayerDataService loads it async)
			local deadline = os.clock() + 30
			while PlayerDataService.get(player) == nil and player.Parent ~= nil and os.clock() < deadline do
				task.wait(0.5)
			end
			if player.Parent == nil then
				return
			end
			-- a Level leaderstat next to Goals/Wins/Nutmegs/Trophies
			pcall(function()
				local stats = player:WaitForChild("leaderstats", 10)
				if stats and not stats:FindFirstChild("Level") then
					local lv = Instance.new("IntValue")
					lv.Name = "Level"
					lv.Value = ProgressionService.getLevel(player)
					lv.Parent = stats
				end
			end)
			handleStreak(player)
			ProgressionService.sync(player)
		end)
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in ipairs(Players:GetPlayers()) do
		onJoin(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		syncQueued[player] = nil
	end)
end

return ProgressionService
