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
local Roles = require(Shared:WaitForChild("Roles"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local WorldService = require(script.Parent.WorldService)
local TeamService = require(script.Parent.TeamService)
local PlayerService = require(script.Parent.PlayerService)
local BallService = require(script.Parent.BallService)
local AIService = require(script.Parent.AIService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local AudioService = require(script.Parent.AudioService)
local BotAnimationService = require(script.Parent.BotAnimationService)
local ProgressionService = require(script.Parent.ProgressionService)
local DifficultyService = require(script.Parent.DifficultyService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local BadgeService = require(script.Parent.BadgeService)

local HALFTIME_SHORT = 4 -- MVP: a brief stoppage between halves
local GOLDEN_SECONDS = 60 -- sudden-death period when the final is tied

local MatchService = {}

-- Set by Main: called during new-match setup (the tournament paints nation
-- identities here) and once per finished match with the winning team name.
MatchService.onMatchSetup = nil :: (() -> ())?
MatchService.onMatchFinished = nil :: ((winnerTeam: string?) -> ())?
MatchService.onSnapshot = nil :: ((snap: any) -> ())? -- stadium big screens
-- Tournament presentation, broadcast in every snapshot when set.
MatchService.roundLabel = nil :: string?
MatchService.board = nil :: { string }?

local state = "Waiting"
local abortRequested = false
local scores = { Red = 0, Blue = 0 }
local half = 0
local scorerTally: { [string]: number } = {} -- goals per scorer this match (commentary "on fire")
local timeRemaining = 0
local resultText = ""
local goldenGoal = false
local goldenWinner: string? = nil
-- penalty shootout state
local shootoutActive = false
local shootoutGoalTeam: string? = nil
local shootoutTally = { Red = 0, Blue = 0 }
local shootoutWinner: string? = nil
local preferred: { [Player]: string } = {}

local matchStateEvent: RemoteEvent
local countdownEvent: RemoteEvent
local goalEvent: RemoteEvent
local toastEvent: RemoteEvent

local function snapshot()
	local redInfo = TeamService.info("Red")
	local blueInfo = TeamService.info("Blue")
	local snap = {
		phase = state,
		red = scores.Red,
		blue = scores.Blue,
		redName = redInfo.displayName,
		blueName = blueInfo.displayName,
		redColor = redInfo.color,
		blueColor = blueInfo.color,
		half = half,
		halves = GameConfig.Halves,
		timeLeft = math.ceil(timeRemaining),
		playersPerTeam = TeamService.teamSize(),
		result = (state == "Finished") and resultText or nil,
		roundLabel = MatchService.roundLabel,
		board = MatchService.board,
	}
	return snap
end

local function broadcastNow()
	local snap = snapshot()
	if matchStateEvent then
		matchStateEvent:FireAllClients(snap)
	end
	-- the stadium's own big screens ride the same snapshot (wired in Main)
	local hook = MatchService.onSnapshot
	if hook then
		pcall(hook, snap)
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
	if r == b and shootoutWinner then
		resultText = string.format(
			"%s win it ON PENALTIES! Shootout %d : %d",
			TeamService.info(shootoutWinner :: string).displayName,
			math.max(shootoutTally.Red, shootoutTally.Blue),
			math.min(shootoutTally.Red, shootoutTally.Blue)
		)
	elseif r == b then
		resultText = string.format("Full time — %d : %d. It's a draw!", r, b)
	elseif goldenWinner then
		resultText = string.format("GOLDEN GOAL! %s win %d : %d!", TeamService.info(goldenWinner :: string).displayName, math.max(r, b), math.min(r, b))
	else
		local winner = (r > b) and "Red" or "Blue"
		resultText = string.format("Full time — %s win %d : %d!", TeamService.info(winner).displayName, math.max(r, b), math.min(r, b))
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
	-- the crowd's camera flashes pop around the bowl
	local pitch = Workspace:FindFirstChild("Pitch")
	if pitch then
		for _, inst in ipairs(pitch:GetChildren()) do
			if inst.Name == "CrowdFlash" then
				local e = inst:FindFirstChildOfClass("ParticleEmitter")
				if e then
					task.delay(math.random() * 1.6, function()
						e:Emit(math.random(1, 3))
					end)
				end
			end
		end
	end
	-- the scorer dances; nearby teammates join in — and everyone TURNS to face
	-- the pitch first, because the replay dolly films from the centre side and
	-- a scorer who just ran at the net would otherwise show the camera his back
	local scorerModel = BallService.getLastKickerModel()
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == scoreTeam then
			local isScorer = f.model == scorerModel
			local nearParty = scorerModel
				and (f.root.Position - (scorerModel :: Model):GetPivot().Position).Magnitude < 32
			if isScorer or nearParty then
				pcall(function()
					local p = f.root.Position
					local look = Vector3.new(GameConfig.Field.CenterX - p.X, 0, GameConfig.Field.CenterZ - p.Z)
					if look.Magnitude > 1 then
						f.root.CFrame = CFrame.lookAt(p, p + look.Unit)
					end
				end)
				BotAnimationService.celebrate(f.model, isScorer and "dance" or "cheer")
			end
		end
	end
end

-- Reacts to a goal from BallService (fires on the server).
local function onGoal(scoreTeam: string)
	if shootoutActive then
		-- shootout goals are tallied by the shootout runner, not the match
		shootoutGoalTeam = scoreTeam
		BallService.stop()
		return
	end
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
				LeaderboardService.addGoal(scorer)
				ProgressionService.note(scorer, "goals")
				scorerName = scorer.DisplayName
			end
		else
			scorerName = "a " .. scoreTeam .. " bot"
		end
	end
	-- streaks only for NAMED humans: every bot on a team shares one scorer
	-- name, so pooling them would call two different bots "on fire"
	local streak = 0
	if scorerName and scorerUid ~= 0 then
		scorerTally[scorerName] = (scorerTally[scorerName] or 0) + 1
		streak = scorerTally[scorerName]
		local scorerPlr = Players:GetPlayerByUserId(scorerUid)
		if scorerPlr then
			BadgeService.goalStreak(scorerPlr, streak)
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
		goalEvent:FireAllClients({
			team = scoreTeam,
			teamName = TeamService.info(scoreTeam).displayName,
			red = scores.Red,
			blue = scores.Blue,
			scorer = scorerName,
		})
	end
	AudioService.goal(streak)
	WorldService.goalLightShow(TeamService.info(scoreTeam).color)
	pcall(celebrate, scoreTeam)
	broadcastNow()

	-- Celebrate, then resume from a fresh kickoff (unless the half just ended).
	task.delay(GameConfig.GoalCelebrationSeconds, function()
		if timeRemaining > 0 then
			repositionEveryone()
			PlayerService.freezeAll(false)
			AIService.setActive(true)
			-- real football: the team that CONCEDED takes the kickoff
			BallService.kickoff(TeamService.info(scoreTeam).opponent)
			state = "Playing"
			broadcastNow()
		end
	end)
end

-- ---- penalty shootout --------------------------------------------------------

-- The kicker: a human on the team if one's alive, else the most attacking bot.
local function pickShooter(team: string): (Model?, Player?)
	for _, plr in ipairs(Players:GetPlayers()) do
		local a = TeamService.getAssignment(plr)
		local char = plr.Character
		if a and a.team == team and char and char.Parent then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				return char, plr
			end
		end
	end
	local best: Model? = nil
	local bestOff = -1
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == team and f.isBot and f.role ~= GameConfig.GoalkeeperRole then
			local def = Roles.Definitions[f.role]
			if def and def.offensive > bestOff then
				bestOff = def.offensive
				best = f.model
			end
		end
	end
	return best, nil
end

-- One penalty kick for `shootTeam`. Returns true if it went in.
local function takePenalty(shootTeam: string): boolean
	local oppName = TeamService.info(shootTeam).opponent
	local oppInfo = TeamService.info(oppName)
	local FIELD = GameConfig.Field
	local spotZ = oppInfo.ownGoalZ + oppInfo.attackDir * (FIELD.Length * 0.105)
	local spot = Vector3.new(FIELD.CenterX, FIELD.GroundY + GameConfig.Ball.Diameter / 2, spotZ)

	local shooter, shooterPlayer = pickShooter(shootTeam)
	if not shooter then
		return false
	end
	local keeper: Model? = nil
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == oppName and f.role == GameConfig.GoalkeeperRole then
			keeper = f.model
			break
		end
	end

	-- stage the kick: shooter behind the spot facing goal, keeper on his line
	pcall(function()
		(shooter :: Model):PivotTo(CFrame.lookAt(
			Vector3.new(spot.X, FIELD.GroundY + GameConfig.Player.SpawnHeight, spotZ + oppInfo.attackDir * 8),
			Vector3.new(spot.X, FIELD.GroundY + 2, oppInfo.ownGoalZ)
		))
	end)
	if keeper then
		pcall(function()
			(keeper :: Model):PivotTo(CFrame.lookAt(
				Vector3.new(FIELD.CenterX, FIELD.GroundY + GameConfig.Player.SpawnHeight, oppInfo.ownGoalZ + oppInfo.attackDir * 1.5),
				spot
			))
		end)
	end
	-- a human keeper defends their own net (unfrozen for the kick)
	local keeperPlayer: Player? = nil
	if keeper and (keeper :: Model):GetAttribute("IsBot") ~= true then
		local uid = ((keeper :: Model):GetAttribute("UserId") :: number?) or 0
		keeperPlayer = uid ~= 0 and Players:GetPlayerByUserId(uid) or nil
		if keeperPlayer then
			PlayerService.setFrozen(keeperPlayer, false)
		end
	end

	shootoutGoalTeam = nil
	local who = shooterPlayer and shooterPlayer.DisplayName or ("a " .. shootTeam .. " bot")
	if toastEvent then
		toastEvent:FireAllClients(("Penalty: %s steps up…"):format(who))
	end
	BallService.penaltyRestart(shootTeam, spot)
	if shooterPlayer then
		PlayerService.setFrozen(shooterPlayer, false) -- the human takes their own kick
	end

	local deadline = os.clock() + 10
	local kicked = false
	local scored = false
	while os.clock() < deadline do
		task.wait(0.1)
		-- keeper mini-AI (the main bot loop is off): shadow the ball on his line
		if keeper and keeperPlayer == nil then
			local hum = (keeper :: Model):FindFirstChildOfClass("Humanoid")
			local root = (keeper :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root then
				local bx = BallService.getBallPosition().X
				local gx = math.clamp(bx, FIELD.CenterX - GameConfig.Goal.Width / 2 + 1, FIELD.CenterX + GameConfig.Goal.Width / 2 - 1)
				hum:MoveTo(Vector3.new(gx, root.Position.Y, oppInfo.ownGoalZ + oppInfo.attackDir * 1.5))
			end
		end
		-- bot shooter: walk on, collect, pick a corner and strike
		if not shooterPlayer then
			local hum = (shooter :: Model):FindFirstChildOfClass("Humanoid")
			if hum then
				if BallService.getCarrier() ~= shooter then
					hum:MoveTo(spot)
				elseif not kicked then
					kicked = true
					task.wait(0.3) -- a beat of composure
					BallService.shootFrom(shooter :: Model, 0.6 + math.random() * 0.18, 4)
				end
			end
		end
		if shootoutGoalTeam == shootTeam then
			scored = true
			AudioService.commentary("shootoutScore", true)
			break
		end
		if keeper and BallService.getCarrier() == keeper then
			AudioService.commentary("shootoutSave", true)
			break -- SAVED
		end
		local bp = BallService.getBallPosition()
		if math.abs(bp.Z - FIELD.CenterZ) > FIELD.Length / 2 + 1.5 then
			task.wait(0.35) -- give goal detection one last beat
			scored = shootoutGoalTeam == shootTeam
			break
		end
	end
	if shooterPlayer then
		PlayerService.setFrozen(shooterPlayer, true)
	end
	if keeperPlayer then
		PlayerService.setFrozen(keeperPlayer, true)
	end
	BallService.stop()
	return scored
end

-- Best-of-5 alternating kicks, then sudden-death pairs. Returns the winner.
local function runShootout(): string
	shootoutActive = true
	shootoutTally = { Red = 0, Blue = 0 }
	state = "Shootout"
	AudioService.commentary("shootoutIntro", true)
	AIService.setActive(false)
	PlayerService.freezeAll(true)
	BallService.stop()
	BallService.setShootoutMode(true)
	repositionEveryone()
	if toastEvent then
		toastEvent:FireAllClients("⚽ PENALTY SHOOTOUT — best of 5!")
	end
	broadcastNow()
	task.wait(2.5)

	local taken = { Red = 0, Blue = 0 }
	-- pick a stadium mood for the drama (replicates to every client)
	pcall(function()
		local Lighting = game:GetService("Lighting")
		Lighting.ClockTime = 18.2 -- shootouts happen under the lights
		Lighting.Brightness = 1.6
	end)

	local function decided(): string?
		if taken.Red < 5 or taken.Blue < 5 then
			local remR = math.max(0, 5 - taken.Red)
			local remB = math.max(0, 5 - taken.Blue)
			if shootoutTally.Red > shootoutTally.Blue + remB then
				return "Red"
			end
			if shootoutTally.Blue > shootoutTally.Red + remR then
				return "Blue"
			end
		elseif taken.Red == taken.Blue and shootoutTally.Red ~= shootoutTally.Blue then
			return (shootoutTally.Red > shootoutTally.Blue) and "Red" or "Blue"
		end
		return nil
	end

	local winner: string? = nil
	while not winner do
		for _, team in ipairs({ "Red", "Blue" }) do
			local converted = takePenalty(team)
			taken[team] += 1
			if converted then
				shootoutTally[team] += 1
				AudioService.goal()
			else
				AudioService.ooh()
			end
			if toastEvent then
				toastEvent:FireAllClients(("%s — Shootout: Red %d : %d Blue"):format(
					converted and "GOAL!" or "NO GOAL!", shootoutTally.Red, shootoutTally.Blue))
			end
			task.wait(1.8)
			winner = decided()
			if winner then
				break
			end
		end
	end

	BallService.setShootoutMode(false)
	shootoutActive = false
	shootoutWinner = winner
	-- belt and braces: every human refrozen no matter which kick path unfroze
	-- them (a keeper who left/respawned mid-kick can otherwise slip the net)
	PlayerService.freezeAll(true)
	return winner :: string
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
	if goldenGoal then
		AudioService.commentary("goldenGoal", true)
	elseif h == 1 then
		AudioService.commentary("kickoff")
	end

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
			-- the crowd leans in over the last 30 seconds of a half
			AudioService.tension(timeRemaining < 30 and (1 - timeRemaining / 30) or 0)
			AudioService.maybeBanter() -- the booth riffs through quiet spells
		end
		if stoppageAdded or abortRequested then
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
		abortRequested = false
		scores.Red, scores.Blue = 0, 0
		half = 0
		table.clear(scorerTally)
		timeRemaining = 0
		resultText = ""
		goldenGoal = false
		goldenWinner = nil
		shootoutWinner = nil
		shootoutTally = { Red = 0, Blue = 0 }
		local setupHook = MatchService.onMatchSetup
		if setupHook then
			pcall(setupHook) -- tournament paints nation identities before kits spawn
		end
		-- bot difficulty: the highest-league human present sets the bar
		local tier = 1
		for _, plr in ipairs(Players:GetPlayers()) do
			tier = math.max(tier, ProgressionService.getLeagueTier(plr))
		end
		if DifficultyService.setTier(tier) and toastEvent then
			toastEvent:FireAllClients(("🏅 Bot difficulty: %s"):format(DifficultyService.get().name))
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			ensureAssigned(plr)
		end
		AIService.spawnForMatch()
		-- stadium mood for this match: midday, late sun, or under the lights
		pcall(function()
			local Lighting = game:GetService("Lighting")
			local variant = math.random(1, 3)
			if variant == 1 then
				Lighting.ClockTime = 14
				Lighting.Brightness = 2.5
			elseif variant == 2 then
				Lighting.ClockTime = 17.2
				Lighting.Brightness = 2.1
			else
				Lighting.ClockTime = 19.2 -- evening kickoff, floodlights doing the work
				Lighting.Brightness = 1.4
			end
		end)
		broadcastNow()
		task.wait(1.5)

		for h = 1, GameConfig.Halves do
			playHalf(h)
			if abortRequested then
				break
			end
			if h < GameConfig.Halves then
				state = "HalfTime"
				AudioService.commentary("halftime", true)
				broadcastNow()
				if toastEvent then
					toastEvent:FireAllClients("Half time")
				end
				task.wait(HALFTIME_SHORT)
			end
		end

		-- A tied final goes to sudden-death GOLDEN GOAL…
		if scores.Red == scores.Blue and not abortRequested then
			goldenGoal = true
			if toastEvent then
				toastEvent:FireAllClients("⚡ GOLDEN GOAL — first goal wins!")
			end
			task.wait(2)
			playHalf(3)
			goldenGoal = false
		end

		-- …and if STILL tied, the drama everyone came for: penalties.
		if scores.Red == scores.Blue and not abortRequested then
			runShootout()
		end

		-- Full time
		AudioService.commentary("fullTime", true)
		computeResult()
		for _, plr in ipairs(Players:GetPlayers()) do
			local a = TeamService.getAssignment(plr)
			if a then
				local outcome = "draw"
				if scores.Red ~= scores.Blue then
					local winner = (scores.Red > scores.Blue) and "Red" or "Blue"
					outcome = (a.team == winner) and "win" or "loss"
				elseif shootoutWinner then
					outcome = (a.team == shootoutWinner) and "win" or "loss"
				end
				PlayerDataService.recordResult(plr, outcome)
				ProgressionService.note(plr, "matches")
				if outcome == "win" then
					ProgressionService.note(plr, "wins")
					LeaderboardService.addWin(plr)
					BadgeService.win(plr, DifficultyService.get().tier)
				end
				if outcome ~= "draw" then
					ProgressionService.noteLeagueResult(plr, outcome == "win")
				end
			end
		end
		-- MVP spotlight: the match's top human scorer gets a glow and a call
		pcall(function()
			local bestName, bestGoals = nil, 0
			for name, n in pairs(scorerTally) do
				if n > bestGoals then
					bestName, bestGoals = name, n
				end
			end
			if bestName and bestGoals >= 1 and toastEvent then
				toastEvent:FireAllClients(("⭐ MVP: %s — %d goal%s!"):format(bestName, bestGoals, bestGoals == 1 and "" or "s"))
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr.DisplayName == bestName and plr.Character then
						local glow = Instance.new("Highlight")
						glow.FillTransparency = 1
						glow.OutlineColor = Color3.fromRGB(245, 196, 60)
						glow.Parent = plr.Character
						task.delay(7, function()
							glow:Destroy()
						end)
					end
				end
			end
		end)
		state = "Finished"
		broadcastNow()
		if toastEvent then
			toastEvent:FireAllClients(resultText)
		end
		-- hand the result to the tournament (if one is running)
		local finishedHook = MatchService.onMatchFinished
		if finishedHook then
			local winner: string? = nil
			if scores.Red ~= scores.Blue then
				winner = (scores.Red > scores.Blue) and "Red" or "Blue"
			elseif shootoutWinner then
				winner = shootoutWinner
			end
			pcall(finishedHook, winner)
			broadcastNow() -- the hook may have updated the board
		end
		task.wait(GameConfig.MatchEndScoreboardSeconds)
		AIService.clear()
	end
end

-- Wrap up the current exhibition quickly (used when a tournament starts so the
-- bracket isn't stuck behind a full match). No effect on tournament matches.
function MatchService.abortMatch()
	abortRequested = true
	timeRemaining = 0
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
