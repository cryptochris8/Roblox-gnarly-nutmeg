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
local Leagues = require(Shared:WaitForChild("Leagues"))

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
local PENALTY_RESULT_HOLD = 4.5 -- the broadcast camera lingers this long after each penalty strike
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
local lastOppTier: { [Player]: number } = {} -- per-human announce of opponent difficulty, on change
local timeRemaining = 0
local resultText = ""
local goldenGoal = false
local goldenWinner: string? = nil
-- penalty shootout state
local shootoutActive = false
local shootoutGoalTeam: string? = nil
local shootoutTally = { Red = 0, Blue = 0 }
local shootoutWinner: string? = nil
local shootoutModeOn = false -- server-wide: when true, every match is a best-of-5 shootout
local casualModeOn = false -- server-wide: when true, all bots are pinned to the easiest league
local preferred: { [Player]: string } = {}

local matchStateEvent: RemoteEvent
local countdownEvent: RemoteEvent
local goalEvent: RemoteEvent
local toastEvent: RemoteEvent
local summaryEvent: RemoteEvent
local penaltyEvent: RemoteEvent
local cornerEvent: RemoteEvent
-- a human's pick-a-corner penalty input, keyed by UserId, consumed by takePenalty
local pendingKick: { [number]: { corner: number, power: number } } = {}
-- a human's pick-a-target corner delivery, keyed by UserId, consumed by startCorner
local pendingCorner: { [number]: { target: string, power: number } } = {}
-- per-human snapshot taken at kickoff so the full-time card can show THIS match's
-- gains (XP, goals, nutmegs) by diffing against lifetime totals
local matchStart: { [Player]: { xp: number, goals: number, nutmegs: number } } = {}

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
		shootoutMode = shootoutModeOn,
		casualMode = casualModeOn,
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
			scorerUserId = scorerUid, -- 0 for a bot; clients match on this, not the non-unique name
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
	local FIELD = GameConfig.Field
	local GOAL = GameConfig.Goal
	-- ONE shared goal for the whole shootout (real-football style): BOTH teams shoot
	-- at the SAME end, so the broadcast camera stays put instead of jumping ends. A
	-- ball that enters it counts for whoever took the kick (see the `scored` check).
	local shootoutAttacker = TeamService.Names[1]
	local goalZ = TeamService.targetGoalCenter(shootoutAttacker).Z
	local goalDir = (goalZ >= FIELD.CenterZ) and 1 or -1 -- +1 if the goal sits at +Z
	local spotZ = goalZ - goalDir * (FIELD.Length * 0.105) -- the spot, on the field side
	local spot = Vector3.new(FIELD.CenterX, FIELD.GroundY + GameConfig.Ball.Diameter / 2, spotZ)
	local goalCenter = Vector3.new(FIELD.CenterX, FIELD.GroundY + GOAL.Height * 0.4, goalZ)

	local shooter, shooterPlayer = pickShooter(shootTeam)
	if not shooter then
		return false
	end
	local shooterUid = ((shooter :: Model):GetAttribute("UserId") :: number?) or 0
	local keeper: Model? = nil
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == oppName and f.role == GameConfig.GoalkeeperRole then
			keeper = f.model
			break
		end
	end

	-- plant the ball dead-still on the spot; stage the taker right behind it
	BallService.placePenaltyBall(shootTeam, spot)
	pcall(function()
		(shooter :: Model):PivotTo(CFrame.lookAt(
			Vector3.new(spot.X, FIELD.GroundY + GameConfig.Player.SpawnHeight, spotZ - goalDir * 2.5),
			Vector3.new(spot.X, FIELD.GroundY + 2, goalZ)
		))
	end)
	if keeper then
		pcall(function()
			(keeper :: Model):PivotTo(CFrame.lookAt(
				Vector3.new(FIELD.CenterX, FIELD.GroundY + GameConfig.Player.SpawnHeight, goalZ - goalDir * 1.5),
				spot
			))
		end)
	end
	-- Clear EVERYONE except the taker and the keeper to the halfway line (where
	-- players wait in a real shootout), spread along X and well behind the camera.
	-- Otherwise, with one shared goal, previous takers and the frozen human pile up
	-- on the spot — blocking the shot AND the view, and the shooting team's own
	-- keeper (whose home is in this goal) would save its own team.
	local clearedZ = FIELD.CenterZ - goalDir * 4
	local waiting = 0
	for _, f in ipairs(BallService.listFootballers()) do
		if f.model ~= shooter and f.model ~= keeper then
			waiting += 1
			local off = (10 + math.floor((waiting - 1) / 2) * 6) * ((waiting % 2 == 0) and 1 or -1)
			local wx = math.clamp(FIELD.CenterX + off, FIELD.MinX + 3, FIELD.MaxX - 3)
			pcall(function()
				(f.model :: Model):PivotTo(CFrame.new(wx, FIELD.GroundY + GameConfig.Player.SpawnHeight, clearedZ))
			end)
		end
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
	pendingKick[shooterUid] = nil
	if penaltyEvent then
		penaltyEvent:FireAllClients({ active = true, shooterUserId = shooterUid, spot = spot, goalCenter = goalCenter })
	end

	-- decide the strike: the human picks a corner + power via the aim UI (or times
	-- out tame); a bot guesses a corner, mostly away from the keeper.
	local cornerOffset = math.min(GOAL.Width / 2 - GOAL.PostThickness - 1, 7)
	local targetX = FIELD.CenterX
	local charge = 0.65
	if shooterPlayer then
		local waitUntil = os.clock() + 8
		while os.clock() < waitUntil and not pendingKick[shooterUid] and shooterPlayer.Parent do
			task.wait(0.1)
		end
		local pk = pendingKick[shooterUid]
		pendingKick[shooterUid] = nil
		if pk then
			-- pk.corner is SCREEN-relative (the left/right the taker sees). The
			-- broadcast camera faces the goal, and its screen-right is +X for the
			-- team shooting at +Z but -X for the team shooting at -Z, so map the
			-- pick to world X by the attack direction or it mirrors for one side.
			targetX = FIELD.CenterX - pk.corner * cornerOffset * goalDir
			charge = pk.power
		else
			targetX = FIELD.CenterX + (math.random() - 0.5) * cornerOffset
			charge = 0.55
		end
	else
		task.wait(1.2) -- a beat of composure so the camera settles
		local side = (math.random() < 0.5) and -1 or 1
		if math.random() < 0.22 then
			side = 0 -- sometimes straight down the middle
		end
		targetX = FIELD.CenterX + side * cornerOffset * (0.82 + math.random() * 0.18)
		charge = 0.6 + math.random() * 0.25
	end
	BallService.penaltyStrike(shootTeam, targetX, goalZ, charge, shooterUid, shooter)
	local strikeAt = os.clock()

	-- The bot keeper GUESSES a third and dives there at the strike — it can't track
	-- a ball that crosses in a blink. Right guess = it gets across to save; wrong
	-- guess = placement beats it (~2 in 3 score). A human keeper dives themselves.
	if keeper and keeperPlayer == nil then
		local shotZone = (targetX > FIELD.CenterX + 2.5) and 1 or ((targetX < FIELD.CenterX - 2.5) and -1 or 0)
		local guess = ({ -1, 0, 1 })[math.random(1, 3)]
		local diveX = (guess == shotZone)
				and math.clamp(targetX, FIELD.CenterX - GameConfig.Goal.Width / 2 + 1, FIELD.CenterX + GameConfig.Goal.Width / 2 - 1)
			or (FIELD.CenterX + guess * cornerOffset)
		pcall(function()
			(keeper :: Model):PivotTo(CFrame.lookAt(
				Vector3.new(diveX, FIELD.GroundY + GameConfig.Player.SpawnHeight, goalZ - goalDir * 1.5),
				Vector3.new(FIELD.CenterX, FIELD.GroundY + 1, spotZ)
			))
		end)
	end

	local deadline = os.clock() + 6
	local scored = false
	while os.clock() < deadline do
		task.wait(0.08)
		if shootoutGoalTeam == shootoutAttacker then
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
			scored = shootoutGoalTeam == shootoutAttacker
			break
		end
	end
	-- Crowd reaction lands HERE, on the close-up, not after the cut.
	if scored then
		AudioService.goal()
	else
		AudioService.ooh()
	end
	-- Hold the broadcast camera on the result before cutting to the wide shot — a
	-- bot's kick resolves in a blink, so otherwise the close-up snaps away at once.
	local heldFor = os.clock() - strikeAt
	if heldFor < PENALTY_RESULT_HOLD then
		task.wait(PENALTY_RESULT_HOLD - heldFor)
	end
	if penaltyEvent then
		penaltyEvent:FireAllClients({ active = false })
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
			end
			if toastEvent then
				toastEvent:FireAllClients(("%s — Shootout: Red %d : %d Blue"):format(
					converted and "GOAL!" or "NO GOAL!", shootoutTally.Red, shootoutTally.Blue))
			end
			task.wait(1.0) -- brief beat between kicks (the result hold is in takePenalty now)
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

	-- Kickoff coaching for our youngest players: at the opening whistle (the highest-
	-- confusion moment) a one-shot nudge to GO — keepers to mind their net — instead
	-- of only the reactive "get the ball first" cue. Half-start only (this path never
	-- runs on an after-goal kickoff), and just the first half so it never nags.
	if h == 1 and toastEvent then
		for _, f in ipairs(BallService.listFootballers()) do
			if not f.isBot then
				local uid = (f.model:GetAttribute("UserId") :: number?) or 0
				local plr = uid ~= 0 and Players:GetPlayerByUserId(uid) or nil
				if plr then
					toastEvent:FireClient(
						plr,
						(f.role == GameConfig.GoalkeeperRole) and "🧤 You're in goal — guard your net!"
							or "🏃 RUN FOR THE BALL!"
					)
				end
			end
		end
	end

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
		-- assign everyone first so per-team difficulty can read their teams
		for _, plr in ipairs(Players:GetPlayers()) do
			ensureAssigned(plr)
		end
		-- PER-TEAM difficulty: a team's bots are competent TEAMMATES (>= PRO) to
		-- their own humans AND OPPONENTS scaled to the humans on the OTHER team.
		-- A solo human thus gets PRO teammates + opponents scaled to their league;
		-- one veteran can no longer force hard bots onto newcomers server-wide.
		local PRO_TIER = 3
		local function strongest(teamName: string): number
			local t = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				local a = TeamService.getAssignment(plr)
				if a and a.team == teamName then
					t = math.max(t, ProgressionService.getLeagueTier(plr))
				end
			end
			return t
		end
		local redH, blueH = strongest("Red"), strongest("Blue")
		local redTier = math.clamp(math.max((redH > 0) and PRO_TIER or 0, blueH), 1, Leagues.MaxTier)
		local blueTier = math.clamp(math.max((blueH > 0) and PRO_TIER or 0, redH), 1, Leagues.MaxTier)
		if casualModeOn then
			redTier, blueTier = 1, 1 -- CASUAL: pin both teams to the easiest league
		end
		DifficultyService.setTiers(redTier, blueTier)
		-- tell each human, only when it changes, what they're now up against
		for _, plr in ipairs(Players:GetPlayers()) do
			local a = TeamService.getAssignment(plr)
			if a and toastEvent then
				local oppLeague = DifficultyService.get(TeamService.info(a.team).opponent)
				if lastOppTier[plr] ~= oppLeague.tier then
					lastOppTier[plr] = oppLeague.tier
					toastEvent:FireClient(plr, ("🏅 Opponents: %s"):format(oppLeague.name))
				end
			end
		end
		AIService.spawnForMatch()
		-- snapshot each human's lifetime tallies so the full-time card can show
		-- THIS match's gains (XP / goals / nutmegs) by diffing at the final whistle
		table.clear(matchStart)
		for _, plr in ipairs(Players:GetPlayers()) do
			local p = PlayerDataService.get(plr) :: any
			matchStart[plr] = {
				xp = ProgressionService.getTotalXP(plr),
				goals = p and (tonumber(p.Goals) or 0) or 0,
				nutmegs = p and (tonumber(p.Nutmegs) or 0) or 0,
			}
		end
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

		-- PENALTY SHOOTOUT MODE: skip the match, go straight to a best-of-5 shootout
		if shootoutModeOn then
			runShootout()
		end
		if not shootoutModeOn then
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
		end -- close 'if not shootoutModeOn'

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
					BadgeService.win(plr, DifficultyService.get(TeamService.info(a.team).opponent).tier)
				end
				if outcome ~= "draw" then
					ProgressionService.noteLeagueResult(plr, outcome == "win")
				end
				-- personal full-time card: THIS match's gains, sent only to this player.
				-- Computed after all XP is granted so it includes the win/match bonuses.
				if summaryEvent then
					local s = matchStart[plr]
					local pp = PlayerDataService.get(plr) :: any
					local curGoals = pp and (tonumber(pp.Goals) or 0) or 0
					local curMegs = pp and (tonumber(pp.Nutmegs) or 0) or 0
					summaryEvent:FireClient(plr, {
						outcome = outcome,
						xpEarned = s and math.max(0, ProgressionService.getTotalXP(plr) - s.xp) or 0,
						level = ProgressionService.getLevel(plr),
						goals = s and math.max(0, curGoals - s.goals) or 0,
						nutmegs = s and math.max(0, curMegs - s.nutmegs) or 0,
						scoreYour = (a.team == "Red") and scores.Red or scores.Blue,
						scoreOpp = (a.team == "Red") and scores.Blue or scores.Red,
					})
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

-- A human's pick-a-corner penalty: corner -1/0/1 (left/centre/right), power 0..1.
-- Stored for takePenalty to consume; only meaningful while it's their kick.
function MatchService.submitPenaltyKick(player: Player, corner: number, power: number)
	if type(corner) ~= "number" or type(power) ~= "number" then
		return
	end
	pendingKick[player.UserId] = {
		corner = math.clamp(math.floor(corner + 0.5), -1, 1),
		power = math.clamp(power, 0, 1),
	}
end

-- Server-wide PENALTY SHOOTOUT MODE: when on, every match is a best-of-5 shootout
-- instead of a full game (great for a quick game and for testing). Any player can
-- flip it from the menu; we abort the current match so the switch takes effect now.
function MatchService.toggleShootoutMode(_player: Player)
	shootoutModeOn = not shootoutModeOn
	abortRequested = true -- end the current match/shootout; the loop applies the new mode next
	timeRemaining = 0 -- ...and run the half clock out NOW so the switch is near-instant
	if toastEvent then
		toastEvent:FireAllClients(
			shootoutModeOn and "⚡ PENALTY SHOOTOUT mode — straight to the spot!"
				or "⚽ Back to FULL MATCHES"
		)
	end
	broadcastNow() -- push the new mode to clients (updates the button)
end

-- Server-wide CASUAL MODE: pin every bot to the easiest league so our youngest
-- players get gentle, beatable opponents (and teammates that won't overshadow
-- them). Unlike shootout this needs no abort — turning it ON eases the LIVE match
-- immediately (DifficultyService is read per-tick by the AI), and every later
-- match respects the flag at setup. Turning OFF restores normal difficulty from
-- the next match (the current one rides out easy, which never hurts).
function MatchService.toggleCasualMode(_player: Player)
	casualModeOn = not casualModeOn
	if casualModeOn then
		DifficultyService.setTiers(1, 1) -- ease the bots already on the pitch right now
	end
	if toastEvent then
		toastEvent:FireAllClients(
			casualModeOn and "🧸 CASUAL MODE — easy bots for everyone!"
				or "💪 Normal difficulty from the next match"
		)
	end
	broadcastNow() -- push the new mode to clients (updates the button)
end

-- A corner SET-PIECE (fired from BallService.onCorner; the ball is already held at
-- the flag). Pause the bots so positions stick, send the attackers into the box
-- (near post / pen spot / far post) and the keeper to his line. If the NEAREST
-- attacker is a human, they step up: their camera swings behind the flag and a
-- pick-a-target aimer (NEAR / FAR / SPOT / SHORT + hold-to-power) goes up; otherwise
-- a bot auto-delivers. Either way the taker whips a lofted cross to a danger zone
-- and the HEADER mechanic + live play resolve the scramble.
local cornerActive = false
function MatchService.startCorner(team: string, spot: Vector3)
	if cornerActive then
		return
	end
	cornerActive = true
	local FIELD = GameConfig.Field
	local GOAL = GameConfig.Goal
	local oppName = TeamService.info(team).opponent
	local goalZ = TeamService.info(oppName).ownGoalZ
	local intoField = (goalZ >= FIELD.CenterZ) and -1 or 1 -- from the goal line toward the pitch
	local cornerSide = (spot.X >= FIELD.CenterX) and 1 or -1
	local headY = FIELD.GroundY + 4.5
	-- the four pickable delivery targets (head height for the posts/spot; a lower,
	-- nearer ball for the short option)
	local nearPost = Vector3.new(FIELD.CenterX + cornerSide * (GOAL.Width / 2 - 1), headY, goalZ + intoField * 4)
	local penSpot = Vector3.new(FIELD.CenterX, headY, goalZ + intoField * 14)
	local farPost = Vector3.new(FIELD.CenterX - cornerSide * (GOAL.Width / 2 - 1), headY, goalZ + intoField * 7)
	local shortBall = Vector3.new(FIELD.CenterX + cornerSide * 8, FIELD.GroundY + 2.5, goalZ + intoField * 13)
	local targetByName = { near = nearPost, far = farPost, spot = penSpot, short = shortBall }

	AIService.setActive(false)
	if toastEvent then
		toastEvent:FireAllClients("⛳ Corner — " .. TeamService.info(team).displayName)
	end

	-- the attacking team's players; nearest to the flag takes it, the rest crash the box
	local attackers = {}
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == team then
			attackers[#attackers + 1] = f
		end
	end
	table.sort(attackers, function(a, b)
		return (a.root.Position - spot).Magnitude < (b.root.Position - spot).Magnitude
	end)
	local taker = attackers[1]
	local boxAim = Vector3.new(FIELD.CenterX, FIELD.GroundY + 1, goalZ + intoField * 8)
	if taker then
		pcall(function()
			(taker.model :: Model):PivotTo(CFrame.lookAt(
				Vector3.new(spot.X, FIELD.GroundY + GameConfig.Player.SpawnHeight, spot.Z) + (spot - boxAim).Unit * 2.5,
				boxAim
			))
		end)
	end
	local runs = { nearPost, penSpot, farPost }
	for i = 2, math.min(#attackers, 4) do
		local p = runs[i - 1] or penSpot
		pcall(function()
			(attackers[i].model :: Model):PivotTo(CFrame.new(p.X, FIELD.GroundY + GameConfig.Player.SpawnHeight, p.Z))
		end)
	end
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == oppName and f.role == GameConfig.GoalkeeperRole then
			pcall(function()
				(f.model :: Model):PivotTo(CFrame.new(FIELD.CenterX, FIELD.GroundY + GameConfig.Player.SpawnHeight, goalZ + intoField * 1.5))
			end)
		end
	end

	local takerModel = taker and taker.model or nil
	local takerUid = takerModel and ((takerModel:GetAttribute("UserId") :: number?) or 0) or 0
	local takerPlayer = (takerModel and takerModel:GetAttribute("IsBot") ~= true and takerUid ~= 0)
			and Players:GetPlayerByUserId(takerUid)
		or nil

	local target: Vector3
	local power: number
	if takerPlayer then
		-- a HUMAN steps up: freeze them on the spot, swing their camera behind the
		-- flag, raise the pick-a-target aimer, then resolve on their pick (or a tame
		-- timeout so the set-piece can never stall).
		PlayerService.setFrozen(takerPlayer, true)
		local goalCenter = Vector3.new(FIELD.CenterX, FIELD.GroundY + GOAL.Height / 2, goalZ)
		pendingCorner[takerUid] = nil
		if cornerEvent then
			cornerEvent:FireClient(takerPlayer, {
				active = true,
				takerUserId = takerUid,
				spot = spot,
				goalCenter = goalCenter,
				side = cornerSide,
			})
		end
		local waitUntil = os.clock() + 7
		while os.clock() < waitUntil and not pendingCorner[takerUid] and takerPlayer.Parent do
			task.wait(0.1)
		end
		local pc = pendingCorner[takerUid]
		pendingCorner[takerUid] = nil
		target = (pc and targetByName[pc.target]) or penSpot
		power = (pc and pc.power) or 0.5
	else
		task.wait(1.3) -- a beat for everyone to set
		target = ({ nearPost, penSpot, farPost })[math.random(1, 3)]
		power = 0.55 + math.random() * 0.25
	end

	BallService.deliverCross(team, target, power, takerUid, takerModel)

	if takerPlayer then
		task.wait(0.7) -- let the camera trail the cross a beat before handing it back
		if cornerEvent then
			cornerEvent:FireClient(takerPlayer, { active = false })
		end
		PlayerService.setFrozen(takerPlayer, false) -- live again: chase the rebound
	end
	AIService.setActive(true) -- live again: the box reacts and the headers fly

	task.wait(0.6)
	cornerActive = false
end

-- A human taker's pick-a-target corner input (validated; consumed by startCorner).
function MatchService.submitCornerKick(player: Player, target: string, power: number)
	if type(target) ~= "string" or type(power) ~= "number" then
		return
	end
	if target ~= "near" and target ~= "far" and target ~= "spot" and target ~= "short" then
		return -- only the four legal zones; never trust the client
	end
	pendingCorner[player.UserId] = { target = target, power = math.clamp(power, 0, 1) }
end

function MatchService.init(_world: WorldService.World)
	matchStateEvent = Remotes.get(Remotes.MatchState)
	countdownEvent = Remotes.get(Remotes.Countdown)
	goalEvent = Remotes.get(Remotes.GoalScored)
	toastEvent = Remotes.get(Remotes.Toast)
	summaryEvent = Remotes.get(Remotes.MatchSummary)
	penaltyEvent = Remotes.get(Remotes.Penalty)
	cornerEvent = Remotes.get(Remotes.Corner)

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
		-- Don't hot-swap a bot out mid-SHOOTOUT — pulling the staged keeper or
		-- shooter would disrupt the kicks. The team is still assigned (so the result
		-- counts for them); the next match setup slots them onto the pitch properly.
		if shootoutActive then
			return
		end
		AIService.removeBotByRole(team, role)
		if player.Character then
			PlayerService.registerFootballer(player)
			PlayerService.positionAtHome(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		TeamService.unassign(player)
		preferred[player] = nil
		lastOppTier[player] = nil
		matchStart[player] = nil
		pendingKick[player.UserId] = nil
	end)

	-- Periodic state broadcast: a sync safety-net for late/altered clients. Its only
	-- time-sensitive field is the match clock (whole seconds), and every real event
	-- (goal, possession, restart) already forces its own broadcast — so 1Hz is plenty
	-- and halves this per-client traffic vs the old 2.5Hz (a mobile bandwidth win).
	task.spawn(function()
		while true do
			task.wait(1.0)
			broadcastNow()
		end
	end)

	-- Run matches forever.
	task.spawn(runMatchLoop)
end

return MatchService
