--!strict
-- AIService (SERVER)
-- Spawns placeholder bot rigs to fill the roles humans don't take, and drives them
-- with a lean decision loop (re-deciding every GameConfig.AiTickSeconds) using the
-- ported Roles data. Deliberately NOT a port of the original 4,578-line AI monolith
-- -- it's a small state machine on top of Humanoid:MoveTo:
--   keeper        -> guard the goal line, track the ball's Z, rush a close loose ball
--   has the ball  -> shoot if near the goal, pass if pressured, else dribble at goal
--   opp has ball  -> the closest teammate presses & tackles; others hold a defensive home
--   loose ball    -> the closest teammate chases
--   teammate ball -> push up to a forward support position

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Roles = require(Shared:WaitForChild("Roles"))

local TeamService = require(script.Parent.TeamService)
local BallService = require(script.Parent.BallService)
local BotAnimationService = require(script.Parent.BotAnimationService)

local TAG = "Footballer"
local SHOOT_RANGE = 55

local AIService = {}

type BotEntry = { model: Model, team: string, role: Roles.RoleKey }
local bots: { BotEntry } = {}
local active = false
local accum = 0
local keeperAccum = 0

local function lighten(c: Color3, amt: number): Color3
	return Color3.new(math.min(1, c.R + amt), math.min(1, c.G + amt), math.min(1, c.B + amt))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function hdist(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

-- ---- bot rig: a real R15 avatar dressed in the team kit -------------------

local function dressInKit(model: Model, info)
	local jersey = info.color
	local shorts = Color3.fromRGB(245, 245, 245)
	local function paint(name: string, c: Color3)
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = c
			p.Material = Enum.Material.SmoothPlastic
		end
	end
	-- R15 limbs
	paint("UpperTorso", jersey)
	paint("LowerTorso", jersey)
	paint("LeftUpperArm", jersey)
	paint("RightUpperArm", jersey)
	paint("LeftLowerArm", jersey)
	paint("RightLowerArm", jersey)
	paint("LeftUpperLeg", shorts)
	paint("RightUpperLeg", shorts)
	paint("LeftLowerLeg", jersey) -- socks
	paint("RightLowerLeg", jersey)
	paint("Head", Color3.fromRGB(255, 204, 153)) -- skin tone so heads aren't dark
	-- R6 fallback names
	paint("Torso", jersey)
	paint("Left Arm", jersey)
	paint("Right Arm", jersey)
	paint("Left Leg", shorts)
	paint("Right Leg", shorts)
	-- a thin team-coloured outline for at-a-glance team identity
	local hl = model:FindFirstChild("KitOutline") :: Highlight?
	if not hl then
		hl = Instance.new("Highlight")
		hl.Name = "KitOutline"
	end
	hl.FillTransparency = 1
	hl.OutlineColor = jersey
	hl.OutlineTransparency = 0
	hl.Parent = model
end

local function makeBot(team: string, role: Roles.RoleKey): Model
	local info = TeamService.info(team)
	local def = Roles.get(role)

	-- A real R15 avatar (proper player body + limbs). Falls back to a simple peg
	-- if avatar creation fails, so a match always runs.
	local model: Model? = nil
	local ok = pcall(function()
		model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		local m = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 5, 2)
		root.Color = info.color
		root.Anchored = false
		root.CanCollide = true
		root.Parent = m
		m.PrimaryPart = root
		local h = Instance.new("Humanoid")
		h.RigType = Enum.HumanoidRigType.R15
		h.HipHeight = 2.5
		h.AutoRotate = true
		h.Parent = m
		model = m
	end
	local bot = model :: Model
	bot.Name = "Bot_" .. team .. "_" .. role

	local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		bot.PrimaryPart = root
	end

	local hum = bot:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = def.isKeeper and (GameConfig.Player.WalkSpeed + 4) or GameConfig.Player.WalkSpeed
		hum.AutoRotate = true
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- no floating name tags
		-- the Animator must exist BEFORE the model replicates for server-played
		-- animation tracks to show on clients (BotAnimationService drives it)
		if not hum:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = hum
		end
	end
	-- the bundled Animate LocalScript never runs for an NPC; drop it so nothing
	-- ever fights our server-side animation driver
	local animate = bot:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	dressInKit(bot, info)

	bot:SetAttribute("Team", team)
	bot:SetAttribute("Role", role)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("UserId", 0)
	bot:SetAttribute("StunUntil", 0)
	CollectionService:AddTag(bot, TAG)

	bot.Parent = Workspace
	if root then
		pcall(function()
			(root :: any):SetNetworkOwner(nil)
		end)
	end
	BotAnimationService.attach(bot)
	return bot
end

-- Closest OUTFIELD teammate to the ball (keepers excluded; they have their own job).
local function closestOutfieldToBall(team: string, ballPos: Vector3): Model?
	local best: Model? = nil
	local bd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == team and f.role ~= GameConfig.GoalkeeperRole then
			local d = hdist(f.root.Position, ballPos)
			if d < bd then
				bd = d
				best = f.model
			end
		end
	end
	return best
end

-- ---- per-bot decision ------------------------------------------------------

local function decideBot(entry: BotEntry)
	local model = entry.model
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return
	end
	if BallService.isStunnedModel(model) then
		hum:Move(Vector3.zero)
		return
	end

	local team = entry.team
	local role = entry.role
	local def = Roles.get(role)
	local info = TeamService.info(team)
	local myPos = root.Position
	local ballPos = BallService.getBallPosition()
	local carrier = BallService.getCarrier()
	local home = TeamService.homePosition(team, role)
	local targetGoal = TeamService.targetGoalCenter(team)
	local ownGoal = TeamService.ownGoalCenter(team)

	-- GOALKEEPER
	if role == GameConfig.GoalkeeperRole then
		if carrier == model then
			BallService.passFrom(model) -- clear it upfield
			return
		end
		local halfMouth = GameConfig.Goal.Width / 2
		-- advance off the line to narrow the angle as the ball gets closer
		local ballToGoal = hdist(ballPos, ownGoal)
		local advance = math.clamp(45 - ballToGoal, 0, 16)
		local guardZ = ownGoal.Z + info.attackDir * (3 + advance)
		-- hold a central position (where shots aim), only shading toward the ball's side
		local mouthX = math.clamp(ballPos.X * 0.5, ownGoal.X - halfMouth, ownGoal.X + halfMouth)
		local target = Vector3.new(mouthX, myPos.Y, guardZ)
		-- rush out to smother a loose ball threatening close in
		if BallService.isLoose() and ballToGoal < 24 and hdist(myPos, ballPos) < 18 then
			target = Vector3.new(ballPos.X, myPos.Y, ballPos.Z)
		end
		hum:MoveTo(target)
		return
	end

	-- I HAVE THE BALL
	if carrier == model then
		local dGoal = hdist(myPos, targetGoal)
		if dGoal < SHOOT_RANGE then
			BallService.shootFrom(model, math.clamp(dGoal / 55, 0.5, 1), 7)
			return
		end
		local pressured = false
		for _, f in ipairs(BallService.listFootballers()) do
			if f.team ~= team and hdist(f.root.Position, myPos) < 7 then
				pressured = true
				break
			end
		end
		if pressured then
			-- a flash of skill: sometimes meg the defender instead of passing
			if math.random() < 0.2 and BallService.nutmegFrom(model) then
				return
			end
			if math.random() < 0.7 and BallService.passFrom(model) then
				return
			end
		end
		hum:MoveTo(Vector3.new(targetGoal.X, myPos.Y, targetGoal.Z))
		return
	end

	local closest = closestOutfieldToBall(team, ballPos)
	local amClosest = (closest == model)

	-- OPPONENT HAS THE BALL
	if carrier and carrier:GetAttribute("Team") ~= team then
		local cRoot = carrier:FindFirstChild("HumanoidRootPart") :: BasePart?
		if amClosest and cRoot and hdist(myPos, cRoot.Position) < def.pursuitDistance + 8 then
			hum:MoveTo(Vector3.new(cRoot.Position.X, myPos.Y, cRoot.Position.Z))
			if hdist(myPos, cRoot.Position) < GameConfig.Tackle.Range then
				BallService.tackleAttempt(model)
			end
			return
		end
		local defendZ = (home.Z + ownGoal.Z) / 2 -- drop a bit toward our own goal
		hum:MoveTo(Vector3.new(home.X, myPos.Y, defendZ))
		return
	end

	-- LOOSE BALL
	if BallService.isLoose() then
		if amClosest and hdist(myPos, ballPos) < def.pursuitDistance + 10 then
			hum:MoveTo(Vector3.new(ballPos.X, myPos.Y, ballPos.Z))
			return
		end
	end

	-- TEAMMATE HAS THE BALL / not chasing -> push to a forward support spot
	local supportZ = home.Z + info.attackDir * 8
	hum:MoveTo(Vector3.new(home.X, myPos.Y, supportZ))
end

-- ---- public API ------------------------------------------------------------

-- Spawn bots for every formation role not held by a human, on both teams.
function AIService.spawnForMatch()
	AIService.clear()
	for _, team in ipairs(TeamService.Names) do
		local formation = TeamService.formation(team)
		local humanRoles = TeamService.humanRoles(team)
		for _, roleKey in ipairs(formation) do
			if not humanRoles[roleKey] then
				local model = makeBot(team, roleKey)
				local home = TeamService.homePosition(team, roleKey)
				pcall(function()
					model:PivotTo(CFrame.new(home))
				end)
				bots[#bots + 1] = { model = model, team = team, role = roleKey }
			end
		end
	end
end

function AIService.repositionAll()
	for _, e in ipairs(bots) do
		local home = TeamService.homePosition(e.team, e.role)
		local hum = e.model:FindFirstChildOfClass("Humanoid")
		e.model:SetAttribute("StunUntil", 0)
		pcall(function()
			e.model:PivotTo(CFrame.new(home))
		end)
		if hum then
			hum:Move(Vector3.zero)
		end
	end
end

function AIService.setActive(isActive: boolean)
	active = isActive
	if not isActive then
		for _, e in ipairs(bots) do
			local hum = e.model:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:Move(Vector3.zero)
			end
		end
	end
end

function AIService.clear()
	for _, e in ipairs(bots) do
		e.model:Destroy()
	end
	table.clear(bots)
end

-- Despawn the bot holding a given role (used when a human takes that role).
function AIService.removeBotByRole(team: string, role: string)
	for i = #bots, 1, -1 do
		local e = bots[i]
		if e.team == team and e.role == role then
			e.model:Destroy()
			table.remove(bots, i)
		end
	end
end

function AIService.init()
	RunService.Heartbeat:Connect(function(dt)
		if not active then
			return
		end
		accum += dt
		keeperAccum += dt
		local runOutfield = accum >= GameConfig.AiTickSeconds
		local runKeeper = keeperAccum >= 0.12 -- keepers react ~3x faster than outfielders
		if runOutfield then
			accum = 0
		end
		if runKeeper then
			keeperAccum = 0
		end
		if not (runOutfield or runKeeper) then
			return
		end
		for _, entry in ipairs(bots) do
			if entry.model.Parent then
				local isKeeper = entry.role == GameConfig.GoalkeeperRole
				if (isKeeper and runKeeper) or (not isKeeper and runOutfield) then
					local ok, err = pcall(decideBot, entry)
					if not ok then
						warn("[Gnarly Nutmeg] AI error: " .. tostring(err))
					end
				end
			end
		end
	end)
end

return AIService
