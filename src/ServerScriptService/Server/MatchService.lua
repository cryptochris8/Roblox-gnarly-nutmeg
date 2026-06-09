--!strict
-- MatchService (SERVER)
-- The match orchestrator + state machine. Runs continuous matches:
--   Waiting -> (per half) Countdown -> Playing -> [GoalPause -> Playing]* -> HalfTime
--           -> ... -> Finished -> (short scoreboard) -> repeat.
-- Owns the score and the half clock, repositions everyone at each kickoff, reacts
-- to BallService goals, and broadcasts a MatchState snapshot to all clients.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local WorldService = require(script.Parent.WorldService)
local TeamService = require(script.Parent.TeamService)
local PlayerService = require(script.Parent.PlayerService)
local BallService = require(script.Parent.BallService)
local AIService = require(script.Parent.AIService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local HALFTIME_SHORT = 4 -- MVP: a brief stoppage between halves

local MatchService = {}

local state = "Waiting"
local scores = { Red = 0, Blue = 0 }
local half = 0
local timeRemaining = 0
local resultText = ""
local preferred: { [Player]: string } = {}

local matchStateEvent: RemoteEvent
local countdownEvent: RemoteEvent
local goalEvent: RemoteEvent
local toastEvent: RemoteEvent

local function snapshot()
	local snap = {
		phase = state,
		red = scores.Red,
		blue = scores.Blue,
		half = half,
		halves = GameConfig.Halves,
		timeLeft = math.ceil(timeRemaining),
		playersPerTeam = TeamService.teamSize(),
		result = (state == "Finished") and resultText or nil,
	}
	return snap
end

local function broadcastNow()
	if matchStateEvent then
		matchStateEvent:FireAllClients(snapshot())
	end
end

function MatchService.sendStateTo(player: Player)
	if matchStateEvent then
		matchStateEvent:FireClient(player, snapshot())
	end
end

-- Make sure a present player has a team + role + footballer tag.
local function ensureAssigned(player: Player)
	if not TeamService.getAssignment(player) then
		TeamService.assignHuman(player, preferred[player])
	end
	PlayerService.registerFootballer(player)
end

local function repositionEveryone()
	AIService.repositionAll()
	for _, plr in ipairs(Players:GetPlayers()) do
		if TeamService.getAssignment(plr) then
			PlayerService.positionAtHome(plr)
		end
	end
end

local function computeResult()
	local r, b = scores.Red, scores.Blue
	if r == b then
		resultText = string.format("Full time — %d : %d. It's a draw!", r, b)
	else
		local winner = (r > b) and "Red" or "Blue"
		resultText = string.format("Full time — %s win %d : %d!", winner, math.max(r, b), math.min(r, b))
	end
end

-- Reacts to a goal from BallService (fires on the server).
local function onGoal(scoreTeam: string)
	if state ~= "Playing" then
		return
	end
	scores[scoreTeam] = (scores[scoreTeam] or 0) + 1
	-- Credit the goal to the last human to touch the ball (if on the scoring team).
	local scorerUid, scorerTeam = BallService.getLastCarrier()
	if scorerTeam == scoreTeam and scorerUid ~= 0 then
		local scorer = Players:GetPlayerByUserId(scorerUid)
		if scorer then
			PlayerDataService.addGoal(scorer)
		end
	end
	state = "GoalPause"
	AIService.setActive(false)
	PlayerService.freezeAll(true)
	BallService.stop()
	if goalEvent then
		goalEvent:FireAllClients({ team = scoreTeam, red = scores.Red, blue = scores.Blue })
	end
	broadcastNow()

	-- Celebrate, then resume from a fresh kickoff (unless the half just ended).
	task.delay(GameConfig.GoalCelebrationSeconds, function()
		if timeRemaining > 0 then
			repositionEveryone()
			PlayerService.freezeAll(false)
			AIService.setActive(true)
			BallService.kickoff()
			state = "Playing"
			broadcastNow()
		end
	end)
end

local function playHalf(h: number)
	half = h

	-- Kickoff setup
	repositionEveryone()
	AIService.setActive(false)
	PlayerService.freezeAll(true)
	BallService.placeAtCenter()
	state = "Countdown"
	broadcastNow()
	for n = GameConfig.CountdownSeconds, 1, -1 do
		if countdownEvent then
			countdownEvent:FireAllClients(n)
		end
		task.wait(1)
	end
	if countdownEvent then
		countdownEvent:FireAllClients(0) -- GO!
	end

	-- Play
	timeRemaining = GameConfig.HalfDurationSeconds
	PlayerService.freezeAll(false)
	AIService.setActive(true)
	BallService.kickoff()
	state = "Playing"
	broadcastNow()

	-- The Heartbeat connection drains timeRemaining while state == "Playing".
	-- Goal celebrations flip state to GoalPause, which pauses the clock.
	while timeRemaining > 0 do
		task.wait(0.2)
	end

	-- Half over
	AIService.setActive(false)
	PlayerService.freezeAll(true)
	BallService.stop()
end

local function runMatchLoop()
	while true do
		-- New match setup
		state = "Waiting"
		scores.Red, scores.Blue = 0, 0
		half = 0
		timeRemaining = 0
		resultText = ""
		for _, plr in ipairs(Players:GetPlayers()) do
			ensureAssigned(plr)
		end
		AIService.spawnForMatch()
		broadcastNow()
		task.wait(1.5)

		for h = 1, GameConfig.Halves do
			playHalf(h)
			if h < GameConfig.Halves then
				state = "HalfTime"
				broadcastNow()
				if toastEvent then
					toastEvent:FireAllClients("Half time")
				end
				task.wait(HALFTIME_SHORT)
			end
		end

		-- Full time
		computeResult()
		for _, plr in ipairs(Players:GetPlayers()) do
			local a = TeamService.getAssignment(plr)
			if a then
				local outcome = "draw"
				if scores.Red ~= scores.Blue then
					local winner = (scores.Red > scores.Blue) and "Red" or "Blue"
					outcome = (a.team == winner) and "win" or "loss"
				end
				PlayerDataService.recordResult(plr, outcome)
			end
		end
		state = "Finished"
		broadcastNow()
		if toastEvent then
			toastEvent:FireAllClients(resultText)
		end
		task.wait(GameConfig.MatchEndScoreboardSeconds)
		AIService.clear()
	end
end

-- A human chooses a team (applied immediately only between matches).
function MatchService.selectTeam(player: Player, teamName: string)
	if teamName ~= "Red" and teamName ~= "Blue" then
		return
	end
	preferred[player] = teamName
	if state == "Waiting" or state == "Finished" then
		TeamService.unassign(player)
		local team, role = TeamService.assignHuman(player, teamName)
		AIService.removeBotByRole(team, role)
		PlayerService.registerFootballer(player)
		PlayerService.positionAtHome(player)
	end
end

function MatchService.getPhase(): string
	return state
end

function MatchService.getScore(): { Red: number, Blue: number }
	return { Red = scores.Red, Blue = scores.Blue }
end

function MatchService.init(_world: WorldService.World)
	matchStateEvent = Remotes.get(Remotes.MatchState)
	countdownEvent = Remotes.get(Remotes.Countdown)
	goalEvent = Remotes.get(Remotes.GoalScored)
	toastEvent = Remotes.get(Remotes.Toast)

	BallService.onGoal = onGoal

	-- Half clock
	RunService.Heartbeat:Connect(function(dt)
		if state == "Playing" then
			timeRemaining = math.max(0, timeRemaining - dt)
		end
	end)

	-- A human who joins mid-match is slotted in (replacing a bot in that role).
	Players.PlayerAdded:Connect(function(player)
		local team, role = TeamService.assignHuman(player, preferred[player])
		AIService.removeBotByRole(team, role)
		if player.Character then
			PlayerService.registerFootballer(player)
			PlayerService.positionAtHome(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		TeamService.unassign(player)
		preferred[player] = nil
	end)

	-- Periodic state broadcast (cheap; keeps late/altered clients in sync).
	task.spawn(function()
		while true do
			task.wait(0.4)
			broadcastNow()
		end
	end)

	-- Run matches forever.
	task.spawn(runMatchLoop)
end

return MatchService
