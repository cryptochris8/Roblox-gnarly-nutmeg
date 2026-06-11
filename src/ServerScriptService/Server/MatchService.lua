--!strict
-- MatchService (SERVER)
-- The match orchestrator + state machine. Runs continuous matches:
--   Waiting -> (per half) Countdown -> Playing -> [GoalPause -> Playing]* -> HalfTime
--           -> ... -> Finished -> (short scoreboard) -> repeat.
-- Owns the score and the half clock, repositions everyone at each kickoff, reacts
-- to BallService goals, and broadcasts a MatchState snapshot to all clients.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
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
local AudioService = require(script.Parent.AudioService)

local HALFTIME_SHORT = 4 -- MVP: a brief stoppage between halves
local GOLDEN_SECONDS = 60 -- sudden-death period when the final is tied

local MatchService = {}

local state = "Waiting"
local scores = { Red = 0, Blue = 0 }
local half = 0
local timeRemaining = 0
local resultText = ""
local goldenGoal = false
local goldenWinner: string? = nil
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
	elseif goldenWinner then
		resultText = string.format("GOLDEN GOAL! %s win %d : %d!", goldenWinner, math.max(r, b), math.min(r, b))
	else
		local winner = (r > b) and "Red" or "Blue"
		resultText = string.format("Full time — %s win %d : %d!", winner, math.max(r, b), math.min(r, b))
	end
end

-- Confetti fountain over the goal mouth the ball just went into (cosmetic; the
-- emitter is server-side so everyone sees the same celebration).
local function celebrate(scoreTeam: string)
	local info = TeamService.info(scoreTeam)
	local mouth = TeamService.ownGoalCenter(info.opponent)
	local part = Instance.new("Part")
	part.Name = "GoalConfetti"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(GameConfig.Goal.Width, 1, 2)
	part.CFrame = CFrame.new(mouth + Vector3.new(0, GameConfig.Goal.Height + 2, 0))
	part.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(info.color, Color3.fromRGB(255, 230, 120))
	emitter.LightEmission = 0.7
	emitter.Size = NumberSequence.new(0.8)
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(18, 34)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Acceleration = Vector3.new(0, -28, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(180)
	task.delay(3, function()
		part:Destroy()
	end)
end

-- Reacts to a goal from BallService (fires on the server).
local function onGoal(scoreTeam: string)
	if state ~= "Playing" then
		return
	end
	scores[scoreTeam] = (scores[scoreTeam] or 0) + 1
	-- Credit the goal + name the scorer for the broadcast.
	local scorerUid, scorerTeam = BallService.getLastCarrier()
	local scorerName: string? = nil
	if scorerTeam == scoreTeam then
		if scorerUid ~= 0 then
			local scorer = Players:GetPlayerByUserId(scorerUid)
			if scorer then
				PlayerDataService.addGoal(scorer)
				scorerName = scorer.DisplayName
			end
		else
			scorerName = "a " .. scoreTeam .. " bot"
		end
	end
	if goldenGoal then
		goldenWinner = scoreTeam
		timeRemaining = 0 -- sudden death ends the period immediately
	end
	state = "GoalPause"
	AIService.setActive(false)
	PlayerService.freezeAll(true)
	BallService.stop()
	if goalEvent then
		goalEvent:FireAllClients({ team = scoreTeam, red = scores.Red, blue = scores.Blue, scorer = scorerName })
	end
	AudioService.goal()
	pcall(celebrate, scoreTeam)
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
	AudioService.whistle("short")

	-- Play
	timeRemaining = goldenGoal and GOLDEN_SECONDS or GameConfig.HalfDurationSeconds
	PlayerService.freezeAll(false)
	AIService.setActive(true)
	BallService.kickoff()
	state = "Playing"
	broadcastNow()

	-- The Heartbeat connection drains timeRemaining while state == "Playing".
	-- Goal celebrations flip state to GoalPause, which pauses the clock.
	local stoppageAdded = goldenGoal -- no added time in sudden death
	while true do
		while timeRemaining > 0 do
			task.wait(0.2)
		end
		if stoppageAdded then
			break
		end
		-- authentic drama: random added time, once per half
		stoppageAdded = true
		local extra = math.random(6, 15)
		timeRemaining = extra
		if toastEvent then
			toastEvent:FireAllClients(("+%d seconds of stoppage time!"):format(extra))
		end
		broadcastNow()
	end

	-- Half over
	AudioService.whistle("long")
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
		goldenGoal = false
		goldenWinner = nil
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

		-- A tied final goes to sudden-death GOLDEN GOAL
		if scores.Red == scores.Blue then
			goldenGoal = true
			if toastEvent then
				toastEvent:FireAllClients("⚡ GOLDEN GOAL — first goal wins!")
			end
			task.wait(2)
			playHalf(3)
			goldenGoal = false
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
