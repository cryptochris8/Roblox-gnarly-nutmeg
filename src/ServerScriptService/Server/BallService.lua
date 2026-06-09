--!strict
-- BallService (SERVER) -- the heart of the game.
-- Owns the single match ball and possession. Possession is the proven "attach &
-- follow" model from the original (sidesteps networked physics contests): while a
-- player carries the ball it is anchored just in front of them; a pass/shot/tackle
-- releases it as a real physics body with a set velocity. Also handles loose-ball
-- pickup, goal detection (CENTRE-in-box), and a safety reset.
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

local ball: Part? = nil
local carrier: Model? = nil
local lastTouchTeam: string? = nil
local lastCarrierUserId = 0
local lastCarrierTeam: string? = nil
local enabled = false
local ignorePickupUntil = 0
local lastKicker: Model? = nil
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

-- ---- best-teammate heuristic (ported intent from _findBestPassTarget) ------

local function bestTeammate(fromModel: Model, team: string, ballPos: Vector3): Footballer?
	local goal = TeamService.targetGoalCenter(team)
	local toGoal = Vector3.new(goal.X - ballPos.X, 0, goal.Z - ballPos.Z)
	toGoal = toGoal.Magnitude > 0.1 and toGoal.Unit or Vector3.new(1, 0, 0)

	local best: Footballer? = nil
	local bestScore = -math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == team and f.model ~= fromModel then
			local rel = Vector3.new(f.root.Position.X - ballPos.X, 0, f.root.Position.Z - ballPos.Z)
			local dist = rel.Magnitude
			if dist >= 6 and dist <= 70 then
				local forward = (dist > 0) and toGoal:Dot(rel.Unit) or 0 -- -1..1
				local score = forward * 30 - dist * 0.25
				if not f.isBot then
					score += 8 -- gently prefer passing to humans
				end
				if score > bestScore then
					bestScore = score
					best = f
				end
			end
		end
	end
	return best
end

-- ---- actions (pure mechanics; stamina/cooldown gating happens at the caller) -

-- Pass to the best teammate (or clear toward goal if none). Returns true if kicked.
function BallService.passFrom(fromModel: Model): boolean
	if carrier ~= fromModel or not ball then
		return false
	end
	local team = (fromModel:GetAttribute("Team") :: string?) or ""
	local ballPos = ball.Position
	local target = bestTeammate(fromModel, team, ballPos)

	local dir: Vector3
	if target then
		local lead = target.root.Position + target.root.AssemblyLinearVelocity * KICK.PassLeadFactor
		dir = lead - ballPos
	else
		dir = TeamService.targetGoalCenter(team) - ballPos
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		local fwd = fromModel:FindFirstChild("HumanoidRootPart")
		dir = fwd and (fwd :: BasePart).CFrame.LookVector or Vector3.new(1, 0, 0)
		dir = Vector3.new(dir.X, 0, dir.Z)
	end
	local horiz = dir.Unit
	local v = horiz * KICK.PassSpeed + Vector3.yAxis * (KICK.PassSpeed * KICK.PassArc)

	setPossession(nil)
	lastKicker = fromModel
	ball.AssemblyLinearVelocity = v
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
	return true
end

-- Shoot, charge 0..1, biased toward the goal. Returns true if kicked.
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
	facing = facing.Magnitude > 0.1 and facing.Unit or Vector3.new(1, 0, 0)

	local goal = TeamService.targetGoalCenter(team)
	local toGoal = Vector3.new(goal.X - ball.Position.X, 0, goal.Z - ball.Position.Z)
	toGoal = toGoal.Magnitude > 0.1 and toGoal.Unit or facing

	local dir = (facing * 0.6 + toGoal * 0.4)
	dir = dir.Magnitude > 0.1 and dir.Unit or facing
	-- optional inaccuracy so finishes aren't automatic
	if spreadDeg and spreadDeg > 0 then
		local a = (math.random() - 0.5) * 2 * math.rad(spreadDeg)
		dir = (CFrame.fromAxisAngle(Vector3.yAxis, a) * dir)
	end

	local power = KICK.ShotSpeedMin + (KICK.ShotSpeedMax - KICK.ShotSpeedMin) * charge
	local v = dir * power + Vector3.yAxis * (power * KICK.ShotArc)

	setPossession(nil)
	lastKicker = fromModel
	ball.AssemblyLinearVelocity = v
	ignorePickupUntil = os.clock() + KICK.AfterKickGraceSeconds
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
	b.Parent = Workspace
	ball = b
	pcall(function()
		b:SetNetworkOwner(nil)
	end)
end

function BallService.placeAtCenter()
	setPossession(nil)
	lastKicker = nil
	if ball then
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
	setPossession(nil)
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
	if not ball or carrier or not enabled then
		return
	end
	local graceActive = os.clock() < ignorePickupUntil
	local bp = ball.Position
	local nearest: Footballer? = nil
	local nd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		-- only the player who just kicked is briefly blocked from re-grabbing;
		-- everyone else (esp. the keeper) can claim the ball immediately
		if not (graceActive and f.model == lastKicker) and not isStunnedModel(f.model) then
			local isKeeper = f.role == "goalkeeper"
			-- keepers reach further and can claim airborne shots up to the crossbar
			local reach = isKeeper and BALL.KeeperReach or BALL.PickupRadius
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
	local margin = 8
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
		else
			tryPickup()
			applyLooseDrag(dt)
		end
		checkGoal()
		checkSafety()
	end)
end

return BallService
