--!strict
-- Main (SERVER ENTRY POINT)
-- Wires Gnarly Nutmeg together in the right order and kicks off the match loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Skills = require(Shared:WaitForChild("Skills"))

-- 1) Create the RemoteEvents before anything tries to use them.
Remotes.setupServer()

-- 2) Load services (they live next to this script).
local PlayerDataService = require(script.Parent.PlayerDataService)
local TeamService = require(script.Parent.TeamService)
local PlayerService = require(script.Parent.PlayerService)
local WorldService = require(script.Parent.WorldService)
local AudioService = require(script.Parent.AudioService)
local BallService = require(script.Parent.BallService)
local BotAnimationService = require(script.Parent.BotAnimationService)
local AIService = require(script.Parent.AIService)
local RefereeService = require(script.Parent.RefereeService)
local PowerupService = require(script.Parent.PowerupService)
local ProgressionService = require(script.Parent.ProgressionService)
local MatchService = require(script.Parent.MatchService)
local TournamentService = require(script.Parent.TournamentService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local BadgeService = require(script.Parent.BadgeService)
local CosmeticsService = require(script.Parent.CosmeticsService)

-- 3) Initialize, in dependency order.
PlayerDataService.init() -- leaderstats + persistence on join/leave
TeamService.init()       -- create the Red/Blue Teams
PlayerService.init()     -- stamina loop + character hooks

local world = WorldService.build() -- build the pitch from code
AudioService.init()                -- stadium crowd + event sounds
BallService.init(world)            -- spawn the ball + possession loop
BotAnimationService.init()         -- animates bot rigs (humans animate themselves)
AIService.init()                   -- bot decision loop (idle until a match is active)
RefereeService.init()              -- touchline assistant referees (cosmetic)
PowerupService.init()              -- arcade power-up orbs (GameConfig.Arcade)
ProgressionService.init()          -- XP / levels / daily quests / login streak
TournamentService.init()           -- The Nutmeg Trophy (knockout bracket)
LeaderboardService.init()          -- weekly global boards + pitchside display
CosmeticsService.init()            -- the free locker (boots/trails/celebrations)
MatchService.init(world)           -- match state machine + continuous match loop

-- the tournament rides the match loop through these two hooks
MatchService.onMatchSetup = TournamentService.beforeMatch
MatchService.onMatchFinished = TournamentService.afterMatch
-- the stadium jumbotrons mirror every match-state broadcast
MatchService.onSnapshot = WorldService.updateScoreboards

-- 4) Cross-service hooks + client input intents. The server validates everything.
local STA = GameConfig.Stamina
local TACKLE = GameConfig.Tackle
local NUTMEG = GameConfig.Nutmeg

-- Dead-ball restarts: whistle, then tell everyone what it was for.
local toastRemote = Remotes.get(Remotes.Toast)
BallService.onRestart = function(kind, team)
	AudioService.whistle("short")
	toastRemote:FireAllClients(kind .. " — " .. team)
end

-- A successful nutmeg: burst the dribbler past their victim, count the stat,
-- and let every client celebrate it.
local nutmegEvent = Remotes.get(Remotes.Nutmeg)
BallService.onNutmeg = function(byModel, _victimModel)
	local uid = (byModel:GetAttribute("UserId") :: number?) or 0
	local name: string
	if uid ~= 0 then
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			PlayerService.burst(plr, NUTMEG.BurstMultiplier, NUTMEG.BurstSeconds)
			PlayerDataService.addNutmeg(plr)
			BadgeService.nutmeg(plr)
			AudioService.commentary("nutmegCall")
		end
		name = plr and plr.DisplayName or "Someone"
	else
		local team = (byModel:GetAttribute("Team") :: string?) or ""
		name = (team ~= "") and ("A " .. team .. " bot") or "A bot"
	end
	AudioService.ooh() -- the crowd reacts
	if uid ~= 0 then
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			ProgressionService.note(plr, "nutmegs")
		end
	end
	nutmegEvent:FireAllClients({ name = name, byUserId = uid })
end

-- a human's pass finding its intended receiver counts toward quests/XP
BallService.onPassComplete = function(kickerModel, _receiverModel)
	local uid = (kickerModel:GetAttribute("UserId") :: number?) or 0
	if uid ~= 0 then
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			ProgressionService.note(plr, "passes")
		end
	end
end

-- Transient "why didn't that work" cue, throttled so mashing can't spam it —
-- the #1 new-player confusion was tapping Pass/Shoot with no ball and getting
-- dead air. Stays a brief pill; never adds persistent screen clutter.
local lastCue: { [Player]: number } = {}
local function cue(plr: Player, text: string)
	if (lastCue[plr] or 0) + 1.6 > os.clock() then
		return
	end
	lastCue[plr] = os.clock()
	toastRemote:FireClient(plr, text)
end
Players.PlayerRemoving:Connect(function(plr)
	lastCue[plr] = nil
end)

-- Getting gassed used to be a silent slow-down; now a one-shot, throttled nudge
-- explains it. Stays a brief pill — no persistent stamina nagging on screen.
PlayerService.onSprintEmpty = function(plr)
	cue(plr, "😮‍💨 Out of breath — ease up to recover!")
end

Remotes.get(Remotes.RequestPass).OnServerEvent:Connect(function(player)
	local char = player.Character
	if not char then
		return
	end
	if not BallService.carrierIsPlayer(player) then
		cue(player, "⚽ Get the ball first!")
		return
	end
	if PlayerService.tryAction(player, "pass", 0.35) then
		PlayerService.spendStamina(player, STA.PassCost)
		BallService.passFrom(char)
	end
end)

Remotes.get(Remotes.RequestShoot).OnServerEvent:Connect(function(player, charge)
	local char = player.Character
	if type(charge) ~= "number" then
		charge = 1
	end
	if not char then
		return
	end
	if not BallService.carrierIsPlayer(player) then
		cue(player, "⚽ Get the ball first!")
		return
	end
	if PlayerService.tryAction(player, "shoot", 0.3) then
		PlayerService.spendStamina(player, STA.ShootCost)
		if BallService.shootFrom(char, charge, GameConfig.Kick.HumanShotSpreadDeg) then
			ProgressionService.note(player, "shots")
		end
	end
end)

Remotes.get(Remotes.RequestTackle).OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and not BallService.carrierIsPlayer(player) and PlayerService.tryAction(player, "tackle", TACKLE.Cooldown) then
		PlayerService.spendStamina(player, STA.TackleCost)
		if BallService.tackleAttempt(char) then
			ProgressionService.note(player, "tackles")
		end
	end
end)

-- Skill moves: validated here (level, possession, cooldown, stamina), executed
-- in BallService. Locked attempts get a teaching toast instead of silence.
Remotes.get(Remotes.RequestSkill).OnServerEvent:Connect(function(player, skillId)
	if type(skillId) ~= "string" then
		return
	end
	local def = Skills.byId(skillId)
	local char = player.Character
	if not def or not char then
		return
	end
	if not BallService.carrierIsPlayer(player) then
		cue(player, "⚽ Get the ball first!")
		return
	end
	if ProgressionService.getLevel(player) < def.unlockLevel then
		toastRemote:FireClient(player, ("🔒 %s unlocks at Level %d"):format(def.name, def.unlockLevel))
		return
	end
	if not PlayerService.tryAction(player, "skill_" .. skillId, def.cooldown) then
		return
	end
	PlayerService.spendStamina(player, def.stamina)
	if skillId == "elastico" then
		if BallService.skillElastico(char) then
			PlayerService.burst(player, 1.4, 0.5)
		end
	elseif skillId == "roulette" then
		BallService.skillRoulette(char)
	elseif skillId == "rainbow" then
		if BallService.skillRainbow(char) then
			AudioService.ooh()
		end
	elseif skillId == "chop" then
		if BallService.skillChop(char) then
			PlayerService.burst(player, 1.3, 0.4)
		end
	elseif skillId == "fakeshot" then
		if BallService.skillFakeShot(char) then
			PlayerService.burst(player, 1.25, 0.45)
		end
	end
end)

Remotes.get(Remotes.RequestNutmeg).OnServerEvent:Connect(function(player)
	local char = player.Character
	if not char then
		return
	end
	if not BallService.carrierIsPlayer(player) then
		cue(player, "⚽ Get the ball first!")
		return
	end
	if PlayerService.tryAction(player, "nutmeg", NUTMEG.Cooldown) then
		PlayerService.spendStamina(player, STA.NutmegCost)
		BallService.nutmegFrom(char)
	end
end)

Remotes.get(Remotes.SetSprint).OnServerEvent:Connect(function(player, on)
	PlayerService.setSprint(player, on == true)
end)

Remotes.get(Remotes.SelectTeam).OnServerEvent:Connect(function(player, teamName)
	if type(teamName) == "string" then
		MatchService.selectTeam(player, teamName)
	end
end)

Remotes.get(Remotes.StartTournament).OnServerEvent:Connect(function(player, nationName)
	if type(nationName) == "string" then
		TournamentService.start(player, nationName)
	end
end)

Remotes.get(Remotes.RequestInitialState).OnServerEvent:Connect(function(player)
	MatchService.sendStateTo(player)
end)

print("[Gnarly Nutmeg] Server ready — kickoff incoming! ⚽")
