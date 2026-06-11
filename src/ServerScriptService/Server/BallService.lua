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

local WorldService = require(script.Parent.WorldService)
local TeamService = require(script.Parent.TeamService)
local PlayerService = require(script.Parent.PlayerService)

local FIELD = GameConfig.Field
local BALL = GameConfig.Ball
local KICK = GameConfig.Kick
local TACKLE = GameConfig.Tackle
local GOAL = GameConfig.Goal
local DRIB = GameConfig.Dribble
local NUTMEG = GameConfig.Nutmeg
local VFX = GameConfig.Vfx
local RESTART = GameConfig.Restart

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

local function applyStun(model: Model, seconds: number)
	local uid = (model:GetAttribute("UserId") :: number?) or 0
	local plr = uid ~= 0 and Players:GetPlayerByUserId(uid) or nil
	if plr and plr.Character == model then
		PlayerService.stun(plr, seconds)
	else
		model:SetAttribute("StunUntil", os.clock() + seconds)
	end
end

-- ---- possession ------------------------------------------------------------

local function setPossession(model: Model?)
	carrier = model
	local uid = 0
	if model then
		uid = (model:GetAttribute("UserId") :: number?) or 0
		lastTouchTeam = (model:GetAttribute("Team") :: string?) or lastTouchTeam
		lastCarrierUserId = uid
		lastCarrierTeam = (model:GetAttribute("Team") :: string?) or lastCarrierTeam
		lastKicker = nil -- someone has the ball; clear the post-kick exclusion
		expectedReceiver = nil -- the pass (if any) has been received
	end
	-- The ball is ALWAYS a real physics body now (rolls/bounces); possession just
	-- decides whether carry() steers it. Keep it server-owned for authority.
	if ball then
		ball.CanCollide = true
		ball.Anchored = false
		pcall(function()
			(ball :: any):SetNetworkOwner(nil)
		end)
	end
	if possessionEvent then
		possessionEvent:FireAllClients(uid)
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
function BallService.passFrom(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local team = (fromModel:GetAttribute("Team") :: string?) or ""
	local ballPos = ball.Position
	local useFacing = fromModel:GetAttribute("IsBot") ~= true
	local target = bestTeammate(fromModel, team, ballPos, useFacing)

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
	-- placement: where the facing ray meets the goal line decides the corner
	local halfMouth = math.max(1, GOAL.Width / 2 - GOAL.PostThickness)
	local aimX = goal.X
	local dz = goal.Z - ball.Position.Z
	if math.abs(facing.Z) > 0.05 and (dz / facing.Z) > 0 then
		aimX = ball.Position.X + facing.X * (dz / facing.Z)
	end
	aimX = math.clamp(aimX, goal.X - halfMouth, goal.X + halfMouth)
	aimX = aimX * 0.85 + goal.X * 0.15 -- light assist toward the frame
	local dir = Vector3.new(aimX - ball.Position.X, 0, goal.Z - ball.Position.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or facing

	-- distance shaping (ported intent from the Hytopia original)
	local distToGoal = Vector3.new(goal.X - ball.Position.X, 0, goal.Z - ball.Position.Z).Magnitude
	local power = KICK.ShotSpeedMin + (KICK.ShotSpeedMax - KICK.ShotSpeedMin) * charge
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

	local v = dir * power + Vector3.yAxis * (power * arc)

	setPossession(nil)
	lastKicker = fromModel
	expectedReceiver = nil
	ball.AssemblyLinearVelocity = v
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
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
	if victim then
		local v = victim :: Footballer
		local through = Vector3.new(v.root.Position.X - root.Position.X, 0, v.root.Position.Z - root.Position.Z)
		through = through.Magnitude > 0.1 and through.Unit or fwd
		ball.AssemblyLinearVelocity = through * NUTMEG.PokeSpeed -- flat: stays on the grass, between the legs
		applyStun(v.model, NUTMEG.VictimStumbleSeconds)
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
function BallService.kickoff()
	BallService.placeAtCenter()
	ignorePickupUntil = os.clock() + 0.3
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

-- FIFA rules: over the touchline = throw-in to the other team; over the goal
-- line outside the goal = corner (if the defenders touched it last) or goal kick.
local function checkOutOfBounds()
	if not ball or not enabled or restartActive then
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
	-- Lead the ball in the direction the carrier is MOVING (fall back to facing
	-- when standing still) so it rolls out in front, not behind.
	local dir = hum.MoveDirection
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		local f = root.CFrame.LookVector
		dir = Vector3.new(f.X, 0, f.Z)
	end
	dir = (dir.Magnitude > 0.001) and dir.Unit or Vector3.new(0, 0, 1)

	local radius = BALL.Diameter / 2
	local leadX = root.Position.X + dir.X * DRIB.Offset
	local leadZ = root.Position.Z + dir.Z * DRIB.Offset
	local toLead = Vector3.new(leadX - ball.Position.X, 0, leadZ - ball.Position.Z)
	local hv = toLead * DRIB.Responsiveness
	if hv.Magnitude > DRIB.MaxSpeed then
		hv = hv.Unit * DRIB.MaxSpeed
	end
	local cur = ball.AssemblyLinearVelocity
	ball.AssemblyLinearVelocity = Vector3.new(hv.X, cur.Y, hv.Z)
	-- spin the ball so it visibly rolls while dribbling
	if hv.Magnitude > 1 then
		local axis = Vector3.yAxis:Cross(hv)
		if axis.Magnitude > 0.001 then
			ball.AssemblyAngularVelocity = axis.Unit * (hv.Magnitude / radius)
		end
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
	local nearest: Footballer? = nil
	local nd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		-- only the player who just kicked is briefly blocked from re-grabbing;
		-- everyone else (esp. the keeper) can claim the ball immediately
		if restricted and f.team ~= restricted then
			-- the other team waits out the dead-ball award
		elseif not (graceActive and f.model == lastKicker) and not isStunnedModel(f.model) then
			local isKeeper = f.role == "goalkeeper"
			-- keepers reach further and can claim airborne shots up to the crossbar
			local reach = isKeeper and BALL.KeeperReach or BALL.PickupRadius
			if expectedReceiver == f.model then
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
	if nearest then
		setPossession(nearest.model)
	end
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
