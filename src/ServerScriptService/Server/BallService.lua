--!strict
-- BallService (SERVER) -- the heart of the game.
-- Owns the single match ball and possession. The ball is ALWAYS a real physics
-- body: while carried it is STEERED to roll a few studs ahead of the carrier
-- (never anchored); a pass/shot/tackle/nutmeg releases it with a set velocity.
-- Also handles loose-ball pickup, goal detection (CENTRE-in-box), and a safety
-- reset.
--
-- Footballers (human characters AND bots) are found via the CollectionService tag
-- "Footballer" + attributes Team/Role/IsBot/UserId, so this service never has to
-- know about AIService directly.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BallCarry = require(Shared:WaitForChild("BallCarry"))

local WorldService = require(script.Parent.WorldService)
local TeamService = require(script.Parent.TeamService)
local PlayerService = require(script.Parent.PlayerService)
local AudioService = require(script.Parent.AudioService)
local DifficultyService = require(script.Parent.DifficultyService)
local BotAnimationService = require(script.Parent.BotAnimationService)
local CosmeticsService = require(script.Parent.CosmeticsService)
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))

local FIELD = GameConfig.Field
local BALL = GameConfig.Ball
local KICK = GameConfig.Kick
local TACKLE = GameConfig.Tackle
local GOAL = GameConfig.Goal
local DRIB = GameConfig.Dribble
local NUTMEG = GameConfig.Nutmeg
local VFX = GameConfig.Vfx
local RESTART = GameConfig.Restart
local HEADER = GameConfig.Header

local TAG = "Footballer"

export type Footballer = {
	model: Model,
	root: BasePart,
	hum: Humanoid,
	team: string,
	role: string,
	isBot: boolean,
	userId: number,
}

local BallService = {}

-- Set by Main: BallService.onGoal(scoreTeam: string)
BallService.onGoal = nil :: (((scoreTeam: string) -> ())?)
-- Set by Main: BallService.onNutmeg(byModel, victimModel) -- a successful meg
BallService.onNutmeg = nil :: (((byModel: Model, victimModel: Model) -> ())?)
-- Set by Main: BallService.onRestart(kind, team) -- "Throw-in"/"Corner kick"/"Goal kick"
BallService.onRestart = nil :: (((kind: string, team: string) -> ())?)
-- Set by Main: a human's pass reached its intended receiver (quest/XP credit)
BallService.onPassComplete = nil :: (((kickerModel: Model, receiverModel: Model) -> ())?)
-- Set by Main: BallService.onHeader(byModel, attacking) -- a ball was headed
BallService.onHeader = nil :: (((byModel: Model, attacking: boolean) -> ())?)

local ball: Part? = nil
local shotTrail: Trail? = nil
local carrier: Model? = nil
local lastTouchTeam: string? = nil
local lastCarrierUserId = 0
local lastCarrierTeam: string? = nil
local enabled = false
local ignorePickupUntil = 0
local lastKicker: Model? = nil
-- dead-ball restart state (throw-ins / corners / goal kicks)
local restartActive = false
local restartToken = 0
local exclusiveTeam: string? = nil
local exclusiveUntil = 0
-- the teammate a pass was aimed at (gets a reception-assist pickup bonus)
local expectedReceiver: Model? = nil
local ballSpawn = Vector3.new(0, 3, 0)
local goals: { WorldService.GoalBox } = {}
local possessionEvent: RemoteEvent

-- ---- footballer registry (shared, via tags) -------------------------------

function BallService.listFootballers(): { Footballer }
	local out: { Footballer } = {}
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		local model = inst :: Model
		if model:IsDescendantOf(Workspace) then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = model:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				out[#out + 1] = {
					model = model,
					root = root,
					hum = hum,
					team = (model:GetAttribute("Team") :: string?) or "",
					role = (model:GetAttribute("Role") :: string?) or "",
					isBot = model:GetAttribute("IsBot") == true,
					userId = (model:GetAttribute("UserId") :: number?) or 0,
				}
			end
		end
	end
	return out
end

local function isStunnedModel(model: Model): boolean
	local uid = (model:GetAttribute("UserId") :: number?) or 0
	if uid ~= 0 then
		local plr = Players:GetPlayerByUserId(uid)
		if plr and plr.Character == model then
			return PlayerService.isStunned(plr)
		end
	end
	return ((model:GetAttribute("StunUntil") :: number?) or 0) > os.clock()
end
BallService.isStunnedModel = isStunnedModel

local function applyStun(model: Model, seconds: number): boolean
	-- a Shield power-up shrugs off stuns, stumbles and freezes
	if ((model:GetAttribute("ShieldUntil") :: number?) or 0) > os.clock() then
		return false
	end
	local uid = (model:GetAttribute("UserId") :: number?) or 0
	local plr = uid ~= 0 and Players:GetPlayerByUserId(uid) or nil
	if plr and plr.Character == model then
		PlayerService.stun(plr, seconds)
	else
		model:SetAttribute("StunUntil", os.clock() + seconds)
	end
	return true
end

-- Public stun (PowerupService's Freeze Blast). Returns false if shielded.
function BallService.stunModel(model: Model, seconds: number): boolean
	return applyStun(model, seconds)
end

-- ---- possession ------------------------------------------------------------

-- a live curling shot: lateral acceleration applied while the ball flies
local shotCurve: { accel: Vector3, expire: number }? = nil
local lastShotAt = 0 -- commentary: a dead ball right after a shot = a near miss

-- contextual ball trail: the streak tells you what kind of ball this is
local function styleTrail(color: Color3, width: number, lifetime: number)
	pcall(function()
		local t = shotTrail
		if t then
			t.Color = ColorSequence.new(color)
			t.WidthScale = NumberSequence.new(width, 0.2)
			t.Lifetime = lifetime
		end
	end)
end

-- a human kicker's EQUIPPED trail recolours the streak (width/lifetime keep
-- their contextual meaning); returns quietly for bots and the classic default
local function applyEquippedTrail(fromModel: Model)
	pcall(function()
		local uid = (fromModel:GetAttribute("UserId") :: number?) or 0
		if uid == 0 then
			return
		end
		local plr = Players:GetPlayerByUserId(uid)
		if not plr then
			return
		end
		local style = Cosmetics.trail(CosmeticsService.getEquipped(plr).trail)
		if not style or style.id == "classic" then
			return
		end
		local t = shotTrail
		if t then
			t.Color = ColorSequence.new(style.c1, style.c2)
		end
	end)
end

local function setPossession(model: Model?)
	carrier = model
	shotCurve = nil -- whatever the ball was doing in the air is over
	local uid = 0
	if model then
		uid = (model:GetAttribute("UserId") :: number?) or 0
		lastTouchTeam = (model:GetAttribute("Team") :: string?) or lastTouchTeam
		lastCarrierUserId = uid
		lastCarrierTeam = (model:GetAttribute("Team") :: string?) or lastCarrierTeam
		lastKicker = nil -- someone has the ball; clear the post-kick exclusion
		expectedReceiver = nil -- the pass (if any) has been received
		model:SetAttribute("CarrySince", os.clock()) -- AI uses this for its dribble budget
	end
	-- The ball is ALWAYS a real physics body (rolls/bounces); possession decides
	-- who SIMULATES it. A human carrier's own client network-owns the ball and
	-- steers it locally (CarryController + Shared/BallCarry) — a server-steered
	-- ball renders in the past on the carrier's screen and visibly drags BEHIND
	-- them. Bot-carried and loose balls are server-owned. The server still owns
	-- possession, every kick, and the carry() leash; every release path
	-- (pass/shot/nutmeg/tackle/restart/reset) re-enters here, reclaiming
	-- ownership BEFORE its release velocity is applied.
	if ball then
		ball.CanCollide = true
		ball.Anchored = false
		local owner: Player? = nil
		if model and uid ~= 0 then
			local plr = Players:GetPlayerByUserId(uid)
			if plr and plr.Character == model then
				owner = plr
			end
		end
		pcall(function()
			(ball :: any):SetNetworkOwner(owner)
		end)
	end
	if possessionEvent then
		-- team rides along so HUDs can say WHO has it (nil = loose ball)
		possessionEvent:FireAllClients(uid, model and (model:GetAttribute("Team") :: string?) or nil)
	end
end

function BallService.getCarrier(): Model?
	return carrier
end

function BallService.getCarrierTeam(): string?
	return carrier and ((carrier:GetAttribute("Team") :: string?)) or nil
end

-- The last footballer to possess the ball (for crediting goals). userId 0 = a bot.
function BallService.getLastCarrier(): (number, string?)
	return lastCarrierUserId, lastCarrierTeam
end

-- The model that struck the last kick (a goal's ball is always loose, so on a
-- goal this IS the scorer — used to aim the celebration at the right player).
function BallService.getLastKickerModel(): Model?
	return lastKicker
end

function BallService.isLoose(): boolean
	return carrier == nil
end

function BallService.getBallPosition(): Vector3
	return ball and ball.Position or ballSpawn
end

function BallService.getBall(): Part?
	return ball
end

function BallService.carrierIsPlayer(player: Player): boolean
	return carrier ~= nil and player.Character == carrier
end

-- ---- best-teammate heuristic (FIFA-style assisted passing) ------------------
-- A pass picks a PLAYER, not a direction: score teammates by forward progress,
-- how open they are, and (for humans) how close they are to where the passer is
-- FACING, so you aim a pass by looking at its target.

local function bestTeammate(fromModel: Model, team: string, ballPos: Vector3, useFacing: boolean): Footballer?
	local goal = TeamService.targetGoalCenter(team)
	local toGoal = Vector3.new(goal.X - ballPos.X, 0, goal.Z - ballPos.Z)
	toGoal = toGoal.Magnitude > 0.1 and toGoal.Unit or Vector3.new(1, 0, 0)

	local facing: Vector3? = nil
	if useFacing then
		local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local f = root.CFrame.LookVector
			f = Vector3.new(f.X, 0, f.Z)
			facing = f.Magnitude > 0.1 and f.Unit or nil
		end
	end

	local mates: { Footballer } = {}
	local opps: { Footballer } = {}
	for _, f in ipairs(BallService.listFootballers()) do
		if f.model == fromModel then
			-- self
		elseif f.team == team then
			mates[#mates + 1] = f
		else
			opps[#opps + 1] = f
		end
	end

	local best: Footballer? = nil
	local bestScore = -math.huge
	for _, f in ipairs(mates) do
		local rel = Vector3.new(f.root.Position.X - ballPos.X, 0, f.root.Position.Z - ballPos.Z)
		local dist = rel.Magnitude
		if dist >= 6 and dist <= KICK.PassMaxRange then
			local dir = rel.Unit
			local score = toGoal:Dot(dir) * 18 - dist * 0.22
			if facing then
				score += facing:Dot(dir) * 26 -- the pass goes where you're looking
			end
			-- openness: how far the nearest opponent is from the receiver
			local nearestOpp = math.huge
			for _, o in ipairs(opps) do
				local od = Vector3.new(o.root.Position.X - f.root.Position.X, 0, o.root.Position.Z - f.root.Position.Z).Magnitude
				if od < nearestOpp then
					nearestOpp = od
				end
			end
			score += math.min(nearestOpp, 14) * 0.9
			if not f.isBot then
				score += 6 -- gently prefer passing to humans
			end
			if score > bestScore then
				bestScore = score
				best = f
			end
		end
	end
	return best
end

-- ---- actions (pure mechanics; stamina/cooldown gating happens at the caller) -

-- Pass to the best teammate (or clear toward goal if none). Power scales with
-- distance, the ball is led to where the receiver WILL be, and the receiver
-- gets a reception-assist pickup bonus so passes stick. Returns true if kicked.
function BallService.passFrom(fromModel: Model, forcedReceiver: Model?): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local team = (fromModel:GetAttribute("Team") :: string?) or ""
	local ballPos = ball.Position
	local useFacing = fromModel:GetAttribute("IsBot") ~= true
	-- a forced receiver (the give-and-go return) skips the teammate heuristic
	local target: Footballer? = nil
	if forcedReceiver then
		for _, f in ipairs(BallService.listFootballers()) do
			if f.model == forcedReceiver and f.team == team then
				local rel = Vector3.new(f.root.Position.X - ballPos.X, 0, f.root.Position.Z - ballPos.Z)
				if rel.Magnitude >= 6 and rel.Magnitude <= KICK.PassMaxRange then
					target = f
				end
				break
			end
		end
	end
	target = target or bestTeammate(fromModel, team, ballPos, useFacing)

	local dir: Vector3
	local speed: number
	local receiver: Model? = nil
	if target then
		local rel = Vector3.new(target.root.Position.X - ballPos.X, 0, target.root.Position.Z - ballPos.Z)
		local dist = rel.Magnitude
		speed = math.clamp(dist * 1.3, KICK.PassSpeedMin, KICK.PassSpeedMax)
		-- physically-correct lead: aim where the receiver will be on arrival
		local t = dist / speed
		local vel = target.root.AssemblyLinearVelocity
		local lead = target.root.Position + Vector3.new(vel.X, 0, vel.Z) * (t * KICK.PassLeadDamping)
		-- never lead a pass over a line: receivers sprinting the wing used to
		-- get throw-in ping-pong instead of a ball they could keep in
		lead = Vector3.new(
			math.clamp(lead.X, FIELD.MinX + 2, FIELD.MaxX - 2),
			lead.Y,
			math.clamp(lead.Z, FIELD.MinZ + 2, FIELD.MaxZ - 2)
		)
		dir = lead - ballPos
		receiver = target.model
	else
		dir = TeamService.targetGoalCenter(team) - ballPos
		speed = KICK.PassSpeedMax * 0.85
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		local fwd = fromModel:FindFirstChild("HumanoidRootPart")
		dir = fwd and (fwd :: BasePart).CFrame.LookVector or Vector3.new(1, 0, 0)
		dir = Vector3.new(dir.X, 0, dir.Z)
	end
	local horiz = dir.Unit
	local v = horiz * speed + Vector3.yAxis * (speed * KICK.PassArc)

	setPossession(nil)
	lastKicker = fromModel
	expectedReceiver = receiver
	ball.AssemblyLinearVelocity = v
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
	AudioService.kick(speed / KICK.PassSpeedMax * 0.7)
	BotAnimationService.kick(fromModel)
	styleTrail(Color3.fromRGB(245, 245, 245), 0.7, 0.16) -- thin white pass streak
	applyEquippedTrail(fromModel)
	return true
end

-- Shoot, charge 0..1, with FIFA-style placement: the shot aims where your
-- FACING ray crosses the goal line (clamped inside the posts, lightly assisted
-- toward the frame), distance shapes the strike (close = finesse with extra
-- loft, long = driven and flatter), and OVERCHARGING past the sweet spot
-- balloons it. Returns true if kicked.
function BallService.shootFrom(fromModel: Model, charge: number, spreadDeg: number?): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	charge = math.clamp(charge, 0, 1)
	local team = (fromModel:GetAttribute("Team") :: string?) or ""
	local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local facing = root.CFrame.LookVector
	facing = Vector3.new(facing.X, 0, facing.Z)
	facing = facing.Magnitude > 0.1 and facing.Unit or Vector3.new(0, 0, 1)

	local goal = TeamService.targetGoalCenter(team)
	local halfMouth = math.max(1, GOAL.Width / 2 - GOAL.PostThickness)
	local aimX = goal.X
	local strikeAcross = 0 -- how hard the shooter is cutting across the strike
	if fromModel:GetAttribute("IsBot") == true then
		-- bots run straight at goal, so facing can't place their shots — they
		-- pick a corner instead, biased to the FAR post (away from where they
		-- are), which is how you actually beat a keeper who shades your side
		local side = (ball.Position.X > goal.X) and -1 or 1
		if math.random() < 0.3 then
			side = -side -- sometimes go near post to stay honest
		end
		aimX = goal.X + side * halfMouth * (0.55 + math.random() * 0.4)
	else
		-- humans place shots by FACING: where your aim ray crosses the goal
		-- line is where the shot goes (clamped inside the posts, light assist)
		local dz = goal.Z - ball.Position.Z
		if math.abs(facing.Z) > 0.05 and (dz / facing.Z) > 0 then
			aimX = ball.Position.X + facing.X * (dz / facing.Z)
		end
		aimX = math.clamp(aimX, goal.X - halfMouth, goal.X + halfMouth)
		aimX = aimX * 0.9 + goal.X * 0.1
		-- STRIKE NUANCE: momentum shapes the strike — cutting across the ball
		-- at contact drags the placement with the run and adds bend below
		local hum = fromModel:FindFirstChildOfClass("Humanoid")
		if hum then
			local mv = hum.MoveDirection
			strikeAcross = Vector3.new(mv.X, 0, mv.Z):Dot(Vector3.new(-facing.Z, 0, facing.X))
			aimX = math.clamp(aimX + strikeAcross * KICK.StrikeShapePush, goal.X - halfMouth, goal.X + halfMouth)
		end
	end
	local dir = Vector3.new(aimX - ball.Position.X, 0, goal.Z - ball.Position.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or facing

	-- distance shaping (ported intent from the Hytopia original)
	local distToGoal = Vector3.new(goal.X - ball.Position.X, 0, goal.Z - ball.Position.Z).Magnitude
	local power = KICK.ShotSpeedMin + (KICK.ShotSpeedMax - KICK.ShotSpeedMin) * charge
	-- 💥 Mega Kick power-up: rockets while it lasts
	if ((fromModel:GetAttribute("MegaKickUntil") :: number?) or 0) > os.clock() then
		power *= GameConfig.Arcade.MegaKickMultiplier
	end
	local arc = KICK.ShotArc
	if distToGoal < 20 then
		power *= 1.1 -- close-range finesse pops
		arc *= 1.25
	elseif distToGoal > 70 then
		power *= 0.9 -- long efforts stay controlled
		arc *= 0.7
	end
	-- overcharge: past the sweet spot the shot balloons (watch the meter!)
	local extraSpread = 0
	if charge > 0.85 then
		local over = (charge - 0.85) / 0.15
		arc *= 1 + 0.8 * over
		extraSpread = 6 * over
	end
	local totalSpread = (spreadDeg or 0) + extraSpread
	if totalSpread > 0 then
		local a = (math.random() - 0.5) * 2 * math.rad(totalSpread)
		dir = (CFrame.fromAxisAngle(Vector3.yAxis, a) * dir)
	end

	setPossession(nil)

	-- Curling finesse: a placed shot sets off OUTSIDE the aim line and a
	-- lateral pull bends it back onto the aim point as it arrives — the
	-- banana around the keeper. Blasted shots stay straight.
	local wantsCurl: boolean
	if fromModel:GetAttribute("IsBot") == true then
		wantsCurl = DifficultyService.get(team).tier >= KICK.CurlBotTier and math.random() < 0.6
	else
		wantsCurl = charge >= KICK.CurlMinCharge and charge <= KICK.CurlMaxCharge
	end
	if wantsCurl and distToGoal >= KICK.CurlMinDist then
		local lateral = Vector3.new(-dir.Z, 0, dir.X) -- horizontal perpendicular
		local cornerOffset = aimX - goal.X
		local s: number
		if math.abs(cornerOffset) < 0.5 then
			s = (math.random() < 0.5) and 1 or -1 -- dead-centre aim: pick a side
		else
			s = (lateral.X * cornerOffset >= 0) and 1 or -1 -- outward = past the corner
		end
		local outward = lateral * s
		-- cutting across the ball whips MORE bend onto a finesse strike
		local theta = math.rad(KICK.CurlDeg * (1 + math.min(math.abs(strikeAcross), 1) * 0.5))
		dir = (dir * math.cos(theta) + outward * math.sin(theta)).Unit
		-- lateral kinematics: a*t^2/2 cancels v*sin(theta)*t over the flight,
		-- so the shot re-converges on the aim point right as it gets there
		local pull = 2 * power * power * math.sin(theta) / math.max(distToGoal, 8)
		shotCurve = {
			accel = -outward * pull,
			expire = os.clock() + math.min(distToGoal / power + 0.4, 2.5),
		}
	end

	local v = dir * power + Vector3.yAxis * (power * arc)
	lastKicker = fromModel
	lastShotAt = os.clock()
	expectedReceiver = nil
	ball.AssemblyLinearVelocity = v
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
	AudioService.kick(charge)
	BotAnimationService.kick(fromModel)
	-- the streak sells the strike: team colour by power, fiery when mega-kicked
	if ((fromModel:GetAttribute("MegaKickUntil") :: number?) or 0) > os.clock() then
		styleTrail(Color3.fromRGB(255, 120, 40), 1.7, 0.42)
	else
		styleTrail(TeamService.info(team).color, 0.9 + charge * 0.9, 0.22 + charge * 0.18)
		applyEquippedTrail(fromModel)
	end
	if fromModel:GetAttribute("IsBot") ~= true and charge >= 0.8 then
		AudioService.commentary("bigShot") -- the call rides the flight of a thunderbolt
	end
	return true
end

-- The signature move: poke the ball low THROUGH the closest defender ahead (a
-- "nutmeg") -- they stumble briefly and can't instantly reclaim it, and Main
-- rewards the dribbler with a speed burst to run round and re-collect. With no
-- defender in front it degrades to a simple knock-and-run touch.
-- Returns true if the ball was released.
function BallService.nutmegFrom(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local team = (fromModel:GetAttribute("Team") :: string?) or ""
	local fwd = root.CFrame.LookVector
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	fwd = fwd.Magnitude > 0.1 and fwd.Unit or Vector3.new(0, 0, 1)

	-- the closest opponent ahead of us within megging range
	local victim: Footballer? = nil
	local vd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team ~= team and f.model ~= fromModel then
			local rel = Vector3.new(f.root.Position.X - root.Position.X, 0, f.root.Position.Z - root.Position.Z)
			local d = rel.Magnitude
			if d <= NUTMEG.Range and d > 0.1 and fwd:Dot(rel.Unit) >= NUTMEG.FrontDot and d < vd then
				vd = d
				victim = f
			end
		end
	end

	setPossession(nil)
	lastKicker = fromModel
	expectedReceiver = nil
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
	BotAnimationService.kick(fromModel)
	if victim then
		local v = victim :: Footballer
		local through = Vector3.new(v.root.Position.X - root.Position.X, 0, v.root.Position.Z - root.Position.Z)
		through = through.Magnitude > 0.1 and through.Unit or fwd
		ball.AssemblyLinearVelocity = through * NUTMEG.PokeSpeed -- flat: stays on the grass, between the legs
		applyStun(v.model, NUTMEG.VictimStumbleSeconds)
		AudioService.kick(0.3)
		local cb = BallService.onNutmeg
		if cb then
			task.spawn(cb, fromModel, v.model)
		end
	else
		ball.AssemblyLinearVelocity = fwd * NUTMEG.KnockOnSpeed
	end
	return true
end

-- Attempt a steal: must face an opposing carrier within range. Returns true on win.
function BallService.tackleAttempt(byModel: Model): boolean
	if not ball or not carrier or carrier == byModel then
		return false
	end
	local byTeam = byModel:GetAttribute("Team") :: string?
	local carrierTeam = carrier:GetAttribute("Team") :: string?
	if byTeam == carrierTeam then
		return false
	end
	-- a spinning (roulette) or shielded (power-up) carrier can't be tackled
	if ((carrier:GetAttribute("SpinImmuneUntil") :: number?) or 0) > os.clock()
		or ((carrier:GetAttribute("ShieldUntil") :: number?) or 0) > os.clock() then
		return false
	end
	local byRoot = byModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cRoot = carrier:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not byRoot or not cRoot then
		return false
	end
	local rel = cRoot.Position - byRoot.Position
	local flat = Vector3.new(rel.X, 0, rel.Z)
	if flat.Magnitude > TACKLE.Range then
		return false
	end
	local fwd = byRoot.CFrame.LookVector
	if flat.Magnitude > 0.1 and fwd:Dot(flat.Unit) < 0.2 then
		return false -- not facing the carrier
	end

	local victim = carrier
	setPossession(byModel) -- tackler wins the ball
	BotAnimationService.slideTackle(byModel)
	applyStun(victim, TACKLE.StunSeconds)
	local knock = flat.Magnitude > 0.1 and flat.Unit or fwd
	local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	if vRoot then
		vRoot.AssemblyLinearVelocity = knock * TACKLE.KnockbackSpeed + Vector3.yAxis * 8
	end
	return true
end

-- ---- ball lifecycle --------------------------------------------------------

local function spawnBall()
	if ball then
		ball:Destroy()
	end
	local b = Instance.new("Part")
	b.Name = "MatchBall"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(BALL.Diameter, BALL.Diameter, BALL.Diameter)
	b.Color = Color3.fromRGB(245, 245, 245)
	b.Material = Enum.Material.SmoothPlastic
	b.CustomPhysicalProperties = PhysicalProperties.new(BALL.Density, BALL.Friction, BALL.Elasticity, 1, 1)
	b.Anchored = false
	b.CanCollide = true
	b.CFrame = CFrame.new(ballSpawn)
	-- Classic soccer-ball look: pentagon decals on all six faces of the Ball part
	-- (Roblox legacy catalog textures). Keeps perfect sphere rolling physics.
	local faceTex = {
		[Enum.NormalId.Top] = "rbxassetid://26517924",
		[Enum.NormalId.Bottom] = "rbxassetid://26517924",
		[Enum.NormalId.Front] = "rbxassetid://26517926",
		[Enum.NormalId.Back] = "rbxassetid://26517926",
		[Enum.NormalId.Left] = "rbxassetid://26517926",
		[Enum.NormalId.Right] = "rbxassetid://26517926",
	}
	for face, tex in pairs(faceTex) do
		local d = Instance.new("Decal")
		d.Face = face
		d.Texture = tex
		d.Parent = b
	end
	-- a streak that lights up while the ball really flies (cosmetic only)
	shotTrail = nil
	pcall(function()
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, BALL.Diameter * 0.3, 0)
		a0.Parent = b
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -BALL.Diameter * 0.3, 0)
		a1.Parent = b
		local trail = Instance.new("Trail")
		trail.Name = "ShotTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Lifetime = 0.25
		trail.WidthScale = NumberSequence.new(1, 0.3)
		trail.FaceCamera = true
		trail.LightEmission = 0.6
		trail.Enabled = false
		trail.Parent = b
		shotTrail = trail
	end)
	b.Parent = Workspace
	ball = b
	pcall(function()
		b:SetNetworkOwner(nil)
	end)
end

function BallService.placeAtCenter()
	restartToken += 1 -- cancel any pending dead-ball release
	restartActive = false
	exclusiveTeam = nil
	exclusiveUntil = 0
	expectedReceiver = nil
	setPossession(nil)
	lastKicker = nil
	if ball then
		ball.Anchored = false
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CFrame = CFrame.new(ballSpawn)
	end
end

-- Reset to centre and (re)start play -- called by MatchService at each kickoff.
-- forTeam (real-football kickoffs): after a goal the CONCEDING team restarts,
-- so they get the same exclusive first-touch window a throw-in gives.
function BallService.kickoff(forTeam: string?)
	BallService.placeAtCenter()
	ignorePickupUntil = os.clock() + 0.3
	if forTeam then
		exclusiveTeam = forTeam
		exclusiveUntil = os.clock() + RESTART.ExclusiveSeconds
	end
	enabled = true
end

function BallService.stop()
	enabled = false
	restartToken += 1
	restartActive = false
	exclusiveTeam = nil
	exclusiveUntil = 0
	expectedReceiver = nil
	if ball then
		ball.Anchored = false
	end
	setPossession(nil)
end

-- ---- dead-ball restarts (throw-ins / corners / goal kicks) -------------------

-- While a restart is pending (or its exclusive window runs), only this team may
-- take the ball. AI uses it to hold shape instead of crowding the spot.
function BallService.getRestrictedTeam(): string?
	if restartActive then
		return exclusiveTeam
	end
	if exclusiveTeam and os.clock() < exclusiveUntil then
		return exclusiveTeam
	end
	return nil
end

local function beginRestart(kind: string, team: string, spot: Vector3)
	restartActive = true
	restartToken += 1
	local token = restartToken
	setPossession(nil)
	lastKicker = nil
	expectedReceiver = nil
	exclusiveTeam = team
	if ball then
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CFrame = CFrame.new(spot)
		ball.Anchored = true -- held on the spot until the whistle releases it
	end
	local cb = BallService.onRestart
	if cb then
		task.spawn(cb, kind, team)
	end
	task.delay(RESTART.FreezeSeconds, function()
		if restartToken ~= token then
			return -- a kickoff/stop superseded this restart
		end
		restartActive = false
		exclusiveUntil = os.clock() + RESTART.ExclusiveSeconds
		if ball then
			ball.Anchored = false
		end
	end)
end

-- During a penalty shootout the shootout runner owns the ball's fate; normal
-- out-of-bounds whistles are suspended.
local shootoutMode = false

function BallService.setShootoutMode(on: boolean)
	shootoutMode = on and true or false
end

-- Place the ball on a penalty spot for `team` (whistle + exclusive take).
function BallService.penaltyRestart(team: string, spot: Vector3)
	enabled = true
	beginRestart("Penalty", team, spot)
end

-- PENALTY (FIFA): the ball is planted DEAD-STILL on the spot and must be struck
-- once — no dribble, no second touch. placePenaltyBall anchors it and suspends
-- auto-pickup/drag (restartActive) until penaltyStrike launches it.
function BallService.placePenaltyBall(team: string, spot: Vector3)
	enabled = true
	setPossession(nil)   -- loose + server-owned; clears any carrier
	restartActive = true -- freeze: Heartbeat skips pickup/drag while we hold it
	restartToken += 1    -- cancel any pending beginRestart auto-release
	exclusiveTeam = team
	exclusiveUntil = 0
	lastKicker = nil
	expectedReceiver = nil
	if ball then
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CFrame = CFrame.new(spot)
		ball.Anchored = true -- stays put until the strike
	end
end

-- Strike the planted ball toward (`targetX`, `goalZ`) — the shootout goal, which
-- both teams share, so it's passed in rather than read from the taker's normal
-- attacking goal. `charge` (0..1) is power. One touch; credited to the taker.
function BallService.penaltyStrike(team: string, targetX: number, goalZ: number, charge: number, shooterUid: number?, shooterModel: Model?): boolean
	if not ball then
		return false
	end
	charge = math.clamp(charge, 0, 1)
	local from = ball.Position
	setPossession(nil)    -- un-anchors + server-owns the now-live loose ball
	restartActive = false -- live: the keeper may claim it (a save), drag applies
	local dir = Vector3.new(targetX - from.X, 0, goalZ - from.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, (goalZ >= from.Z) and 1 or -1)
	local power = KICK.ShotSpeedMin + (KICK.ShotSpeedMax - KICK.ShotSpeedMin) * charge
	local v = dir * power + Vector3.yAxis * (power * KICK.ShotArc)
	ball.Anchored = false
	ball.AssemblyLinearVelocity = v
	lastTouchTeam = team
	lastCarrierTeam = team
	lastCarrierUserId = shooterUid or 0
	lastKicker = shooterModel
	lastShotAt = os.clock()
	expectedReceiver = nil
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
	AudioService.kick(charge)
	if shooterModel then
		BotAnimationService.kick(shooterModel)
	end
	return true
end

-- FIFA rules: over the touchline = throw-in to the other team; over the goal
-- line outside the goal = corner (if the defenders touched it last) or goal kick.
local function checkOutOfBounds()
	if not ball or not enabled or restartActive or shootoutMode then
		return
	end
	local p = ball.Position
	local rOut = BALL.Diameter / 2 + 0.1 -- the WHOLE ball must cross the line
	local outX = (p.X < FIELD.MinX - rOut and -1) or (p.X > FIELD.MaxX + rOut and 1) or nil
	local outZ = (p.Z < FIELD.MinZ - rOut and -1) or (p.Z > FIELD.MaxZ + rOut and 1) or nil
	if not outX and not outZ then
		return
	end
	-- a ball in/above the net region is checkGoal's business, never a corner
	if outZ then
		for _, box in ipairs(goals) do
			if p.X >= box.xMin and p.X <= box.xMax and p.Z >= box.zMin and p.Z <= box.zMax and p.Y <= box.yMax then
				return
			end
		end
	end
	local y = FIELD.GroundY + BALL.Diameter / 2
	local lt = lastTouchTeam

	if outX then
		local awarded: string
		if lt and TeamService.info(lt) then
			awarded = TeamService.info(lt).opponent
		else
			awarded = TeamService.Names[math.random(1, #TeamService.Names)]
		end
		local sideX = (outX == 1) and (FIELD.MaxX - 1.5) or (FIELD.MinX + 1.5)
		local spot = Vector3.new(sideX, y, math.clamp(p.Z, FIELD.MinZ + 4, FIELD.MaxZ - 4))
		beginRestart("Throw-in", awarded, spot)
		return
	end

	local endZ = (outZ == 1) and FIELD.MaxZ or FIELD.MinZ
	local defender = TeamService.Names[1]
	for _, name in ipairs(TeamService.Names) do
		if math.abs(TeamService.info(name).ownGoalZ - endZ) < 1 then
			defender = name
		end
	end
	local attacker = TeamService.info(defender).opponent
	if lt == defender then
		-- corner for the attack, at the corner flag nearest where it went out
		local sx = (p.X >= FIELD.CenterX) and 1 or -1
		local spot = Vector3.new(FIELD.CenterX + sx * (FIELD.Width / 2 - 2), y, endZ - (outZ :: number) * 2)
		beginRestart("Corner kick", attacker, spot)
	else
		-- goal kick from the front of the goal box
		if os.clock() - lastShotAt < 2.5 then
			AudioService.commentary("nearMiss") -- a shot just sailed wide/over
		end
		local spot = Vector3.new(FIELD.CenterX, y, endZ - (outZ :: number) * (FIELD.Length * 0.052 + 2))
		beginRestart("Goal kick", defender, spot)
	end
end

-- ---- per-frame -------------------------------------------------------------

local function carry()
	if not (carrier and ball) then
		return
	end
	local c = carrier :: Model
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not root or not c:IsDescendantOf(Workspace) or not hum or hum.Health <= 0 then
		setPossession(nil)
		return
	end
	local b = ball :: Part
	if ((c:GetAttribute("UserId") :: number?) or 0) ~= 0 then
		-- a HUMAN carrier's own client steers the ball (it network-owns the
		-- assembly — see setPossession); the server just keeps it honest: if
		-- the ball strays past the leash (tampering, or a physics blow-up),
		-- it is simply loose again and normal pickup rules apply
		local d = b.Position - root.Position
		if Vector3.new(d.X, 0, d.Z).Magnitude > DRIB.LeashRadius or math.abs(d.Y) > 12 then
			setPossession(nil)
		end
		return
	end
	-- BOT carriers simulate here on the server: steer directly
	local hv = BallCarry.steer(DRIB, {
		ballPos = b.Position,
		rootPos = root.Position,
		moveDir = hum.MoveDirection,
		lookDir = root.CFrame.LookVector,
		carrierVel = root.AssemblyLinearVelocity,
	})
	local cur = b.AssemblyLinearVelocity
	b.AssemblyLinearVelocity = Vector3.new(hv.X, cur.Y, hv.Z)
	-- spin the ball so it visibly rolls while dribbling
	local spin = BallCarry.rollSpin(hv, BALL.Diameter / 2)
	if spin then
		b.AssemblyAngularVelocity = spin
	end
end

-- A loose ball above head height gets HEADED by the nearest OUTFIELDER who has
-- risen to it (a jump lifts their head into range; standing reaches a head-high
-- ball). The winner nods it toward their attacking goal — in the box it drives
-- down at the net, deep it's a high clearance away. Keepers still CATCH aerial
-- balls (tryPickup). Runs before tryPickup, so airborne = header, low = trap.
local function tryHeader()
	if not ball or carrier or not enabled or restartActive or shootoutMode then
		return
	end
	local bp = ball.Position
	if bp.Y < FIELD.GroundY + HEADER.MinBallHeight then
		return
	end
	local graceActive = os.clock() < ignorePickupUntil
	local best: Footballer? = nil
	local bestD = HEADER.Reach
	for _, f in ipairs(BallService.listFootballers()) do
		if f.role ~= "goalkeeper"
			and not (graceActive and f.model == lastKicker)
			and not isStunnedModel(f.model) then
			local head = f.root.Position + Vector3.new(0, HEADER.HeadOffset, 0)
			local d = (head - bp).Magnitude
			if d <= bestD then
				bestD = d
				best = f
			end
		end
	end
	if not best then
		return
	end
	local team = best.team
	local goal = TeamService.targetGoalCenter(team)
	local flat = Vector3.new(goal.X - bp.X, 0, goal.Z - bp.Z)
	local dist = flat.Magnitude
	local dir = dist > 0.1 and flat.Unit or Vector3.new(0, 0, (goal.Z >= bp.Z) and 1 or -1)
	local attacking = dist < HEADER.AttackDist
	local arc = attacking and HEADER.AttackArc or HEADER.ClearArc
	shotCurve = nil
	setPossession(nil)
	ball.AssemblyLinearVelocity = dir * HEADER.Power + Vector3.yAxis * (HEADER.Power * arc)
	lastKicker = best.model
	lastShotAt = os.clock()
	lastTouchTeam = team
	lastCarrierTeam = team
	lastCarrierUserId = best.userId
	expectedReceiver = nil
	ignorePickupUntil = os.clock() + HEADER.GraceSeconds
	AudioService.kick(0.5)
	local cb = BallService.onHeader
	if cb then
		task.spawn(cb, best.model, attacking)
	end
end

local function tryPickup()
	if not ball or carrier or not enabled or restartActive then
		return
	end
	local graceActive = os.clock() < ignorePickupUntil
	-- after a dead ball, only the awarded team may take it for a short window
	local restricted = (os.clock() < exclusiveUntil) and exclusiveTeam or nil
	local bp = ball.Position
	local bv = ball.AssemblyLinearVelocity
	local ballSpeed = Vector3.new(bv.X, 0, bv.Z).Magnitude
	local nearest: Footballer? = nil
	local nd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		-- only the player who just kicked is briefly blocked from re-grabbing;
		-- everyone else (esp. the keeper) can claim the ball immediately
		if restricted and f.team ~= restricted then
			-- the other team waits out the dead-ball award
		elseif not (graceActive and f.model == lastKicker) and not isStunnedModel(f.model) then
			local isKeeper = f.role == "goalkeeper"
			local isReceiver = expectedReceiver == f.model
			-- a fast ball can only be trapped by its intended receiver or a
			-- keeper — bystanders can't vacuum-catch a driven pass mid-flight
			if isKeeper or isReceiver or ballSpeed <= BALL.MaxClaimSpeed then
				-- keepers reach further and claim airborne shots up to the crossbar
				-- (reach scales with the difficulty league — only for BOT keepers)
				local reach = isKeeper and BALL.KeeperReach or BALL.PickupRadius
				-- the difficulty reach-boost is suspended during a shootout: at full
				-- strength it spans the whole goal mouth and saves every penalty. A
				-- penalty keeper guesses a side instead (see MatchService.takePenalty),
				-- so corner placement can beat it.
				if isKeeper and f.isBot and not shootoutMode then
					reach *= DifficultyService.get(f.team).keeperReachMult
				end
				if isReceiver then
					reach *= KICK.ReceptionAssist -- the pass sticks to its target
				end
				local maxY = FIELD.GroundY + (isKeeper and (GOAL.Height + 1) or 5)
				if bp.Y <= maxY then
					local d = Vector3.new(f.root.Position.X - bp.X, 0, f.root.Position.Z - bp.Z).Magnitude
					if d <= reach and d < nd then
						nd = d
						nearest = f
					end
				end
			end
		end
	end
	if nearest then
		-- a completed pass = the intended receiver collecting it (capture before
		-- setPossession clears the bookkeeping)
		local completedBy: Model? = nil
		if nearest.model == expectedReceiver and lastKicker and lastKicker ~= nearest.model then
			completedBy = lastKicker
		end
		-- a keeper smothering a genuinely fast ball is a SAVE worth calling
		if nearest.role == "goalkeeper" and ballSpeed > 45 then
			AudioService.commentary("save")
			local rel = bp - nearest.root.Position
			BotAnimationService.keeperDive(nearest.model, rel:Dot(nearest.root.CFrame.RightVector))
		end
		setPossession(nearest.model)
		if completedBy then
			-- a HUMAN finding a BOT arms the GIVE-AND-GO: for a beat the bot
			-- looks to play it first-time back into the passer's run (AIService)
			if nearest.isBot then
				local uid = (completedBy:GetAttribute("UserId") :: number?) or 0
				if uid ~= 0 then
					nearest.model:SetAttribute("ReturnToUserId", uid)
					nearest.model:SetAttribute("ReturnUntil", os.clock() + 3)
				end
			end
			local cb = BallService.onPassComplete
			if cb then
				task.spawn(cb, completedBy :: Model, nearest.model)
			end
		end
	end
end

-- ---- unlockable skill moves (validated by Main: level/cooldown/stamina) -----

-- Elastico dash: a sharp burst in your movement direction with the ball glued.
function BallService.skillElastico(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = fromModel:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return false
	end
	local dir = hum.MoveDirection
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		local f = root.CFrame.LookVector
		dir = Vector3.new(f.X, 0, f.Z)
	end
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(0, 0, 1)
	root.CFrame = root.CFrame + dir * 6 -- the dash; carry() snaps the ball along
	fromModel:SetAttribute("SkillFlashUntil", os.clock() + 0.4)
	return true
end

-- Roulette: brief tackle immunity while you turn (the spin itself is played by
-- the owning client, which owns its character's physics).
function BallService.skillRoulette(fromModel: Model): boolean
	if carrier ~= fromModel then
		return false
	end
	fromModel:SetAttribute("SpinImmuneUntil", os.clock() + 0.8)
	return true
end

-- Rainbow flick: pop the ball up and over — only YOU (reception assist) or a
-- keeper can touch it in flight, thanks to the claim-speed gate.
function BallService.skillRainbow(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local f = root.CFrame.LookVector
	local dir = Vector3.new(f.X, 0, f.Z)
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(0, 0, 1)
	setPossession(nil)
	lastKicker = fromModel
	expectedReceiver = fromModel -- run onto your own flick
	ball.AssemblyLinearVelocity = dir * 26 + Vector3.yAxis * 52
	ignorePickupUntil = os.clock() + 0.45 -- can't instantly re-grab; chase it down
	AudioService.kick(0.45)
	return true
end

-- Chop Cut: plant and cut the ball 90° to your steering side — your momentum
-- resets on the new line while the defender's lunge carries them past.
function BallService.skillChop(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = fromModel:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return false
	end
	local fwd = root.CFrame.LookVector
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	fwd = fwd.Magnitude > 0.1 and fwd.Unit or Vector3.new(0, 0, 1)
	local lateral = Vector3.new(-fwd.Z, 0, fwd.X)
	local mv = hum.MoveDirection
	local side = (Vector3.new(mv.X, 0, mv.Z):Dot(lateral) < 0) and -1 or 1
	local newDir = lateral * side
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + newDir) + newDir * 2.5 -- the cut
	root.AssemblyLinearVelocity = newDir * 30
	ball.AssemblyLinearVelocity = newDir * 26 -- the touch goes with you
	fromModel:SetAttribute("SpinImmuneUntil", os.clock() + 0.4) -- the cut beats the lunge
	fromModel:SetAttribute("SkillFlashUntil", os.clock() + 0.4)
	AudioService.kick(0.25)
	return true
end

-- Fake Shot: sell the full strike (real kick animation), the nearest defender
-- ahead bites and freezes for a beat. Clean family jukes only.
function BallService.skillFakeShot(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local root = fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	BotAnimationService.kick(fromModel) -- the sell
	local fwd = root.CFrame.LookVector
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	fwd = fwd.Magnitude > 0.1 and fwd.Unit or Vector3.new(0, 0, 1)
	local team = (fromModel:GetAttribute("Team") :: string?) or ""
	local bit: Footballer? = nil
	local bd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team ~= team and f.model ~= fromModel then
			local rel = Vector3.new(f.root.Position.X - root.Position.X, 0, f.root.Position.Z - root.Position.Z)
			local d = rel.Magnitude
			if d < 10 and d > 0.1 and fwd:Dot(rel.Unit) > 0.2 and d < bd then
				bd = d
				bit = f
			end
		end
	end
	if bit then
		applyStun((bit :: Footballer).model, 0.55) -- bought the dummy
	end
	return true
end

local function applyLooseDrag(dt: number)
	if not ball then
		return
	end
	local v = ball.AssemblyLinearVelocity
	local factor = math.max(0, 1 - BALL.LooseDragPerSecond * dt)
	ball.AssemblyLinearVelocity = Vector3.new(v.X * factor, v.Y, v.Z * factor)
end

local function checkGoal()
	if not ball or not enabled then
		return
	end
	if carrier then
		return -- only a loose / in-flight ball can score (prevents keeper own-goals)
	end
	local pos = ball.Position
	for _, box in ipairs(goals) do
		if WorldService.pointInGoal(pos, box) then
			enabled = false
			setPossession(nil)
			local cb = BallService.onGoal
			if cb then
				task.spawn(cb, box.scoreTeam)
			end
			return
		end
	end
end

local function checkSafety()
	if not ball then
		return
	end
	local p = ball.Position
	local m = p.Magnitude
	local margin = FIELD.Runoff + 8 -- the apron is legal ground for dead balls
	if m ~= m
		or p.Y < FIELD.GroundY - 30 or p.Y > 150
		or p.X < FIELD.MinX - margin or p.X > FIELD.MaxX + margin
		or p.Z < FIELD.MinZ - margin or p.Z > FIELD.MaxZ + margin then
		BallService.placeAtCenter()
	end
end

function BallService.init(world: WorldService.World)
	possessionEvent = Remotes.get(Remotes.PossessionChanged)
	ballSpawn = world.ballSpawn
	goals = world.goals
	spawnBall()

	RunService.Heartbeat:Connect(function(dt)
		if carrier then
			carry()
		elseif not restartActive then
			local curve = shotCurve
			if curve then
				if os.clock() > curve.expire then
					shotCurve = nil
				elseif ball then
					ball.AssemblyLinearVelocity += curve.accel * dt
				end
			end
			tryHeader()
			tryPickup()
			applyLooseDrag(dt)
		end
		checkGoal()
		checkOutOfBounds()
		checkSafety()
		local trail = shotTrail
		if trail and ball then
			local v = ball.AssemblyLinearVelocity
			trail.Enabled = carrier == nil and Vector3.new(v.X, 0, v.Z).Magnitude > VFX.ShotTrailMinSpeed
		end
	end)
end

return BallService
