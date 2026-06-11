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
local DifficultyService = require(script.Parent.DifficultyService)

local TAG = "Footballer"
local SHOOT_RANGE = 48 -- bots work it closer before shooting (6v6 keepers eat 55-out efforts)

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

local SKIN_TONES = {
	Color3.fromRGB(255, 213, 170),
	Color3.fromRGB(234, 184, 130),
	Color3.fromRGB(196, 142, 102),
	Color3.fromRGB(150, 103, 71),
	Color3.fromRGB(106, 70, 48),
}
local KEEPER_JERSEY = Color3.fromRGB(252, 200, 38) -- classic bright keeper kit

local function dressInKit(model: Model, info, def: Roles.RoleDef)
	-- keepers wear the classic bright jersey; team identity stays on the outline
	local jersey = def.isKeeper and KEEPER_JERSEY or info.color
	local shorts = def.isKeeper and Color3.fromRGB(35, 38, 46) or Color3.fromRGB(245, 245, 245)
	local skin = SKIN_TONES[math.random(1, #SKIN_TONES)]
	local boots = Color3.fromRGB(28, 28, 30)
	local function paint(name: string, c: Color3)
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = c
			p.Material = Enum.Material.SmoothPlastic
		end
	end
	-- short-sleeved jersey + shorts + team socks + boots, varied skin tones
	paint("UpperTorso", jersey)
	paint("LowerTorso", shorts)
	paint("LeftUpperArm", jersey)
	paint("RightUpperArm", jersey)
	paint("LeftLowerArm", skin)
	paint("RightLowerArm", skin)
	paint("LeftHand", skin)
	paint("RightHand", skin)
	paint("LeftUpperLeg", shorts)
	paint("RightUpperLeg", shorts)
	paint("LeftLowerLeg", jersey) -- socks
	paint("RightLowerLeg", jersey)
	paint("LeftFoot", boots)
	paint("RightFoot", boots)
	paint("Head", skin)
	-- R6 fallback names
	paint("Torso", jersey)
	paint("Left Arm", jersey)
	paint("Right Arm", jersey)
	paint("Left Leg", shorts)
	paint("Right Leg", shorts)
	-- the classic face (built-in texture, always available)
	pcall(function()
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") and not head:FindFirstChildOfClass("Decal") then
			local face = Instance.new("Decal")
			face.Name = "face"
			face.Face = Enum.NormalId.Front
			face.Texture = "rbxasset://textures/face.png"
			face.Parent = head
		end
	end)
	-- shirt number on the back
	pcall(function()
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "ShirtNumber"
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 64
			gui.Parent = torso
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, 1, 0)
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeColor3 = Color3.fromRGB(20, 20, 24)
			label.TextStrokeTransparency = 0.2
			label.Text = tostring(def.number)
			label.Parent = gui
		end
	end)
	-- a thin team-coloured outline for at-a-glance team identity
	local hl = model:FindFirstChild("KitOutline") :: Highlight?
	if not hl then
		hl = Instance.new("Highlight")
		hl.Name = "KitOutline"
	end
	hl.FillTransparency = 1
	hl.OutlineColor = info.color
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
		local base = def.isKeeper and (GameConfig.Player.WalkSpeed + 4) or GameConfig.Player.WalkSpeed
		hum.WalkSpeed = base * DifficultyService.get().walkMult
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

	dressInKit(bot, info, def)

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

-- Bot pass with a short follow-through "plant" so passes read like kicks, not
-- teleports (the Hytopia original used a 300ms stop-and-plant).
local function botPass(model: Model): boolean
	if BallService.passFrom(model) then
		model:SetAttribute("PlantUntil", os.clock() + 0.3)
		return true
	end
	return false
end

-- Closest outfield BOT on a team to the ball. Humans are deliberately ignored:
-- a bot must never defer the chase to a human who may be standing AFK (this
-- exact bug let the other team score on every kickoff while a human idled).
local function closestOutfieldToBall(team: string, ballPos: Vector3): Model?
	local best: Model? = nil
	local bd = math.huge
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team == team and f.isBot and f.role ~= GameConfig.GoalkeeperRole then
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
	if ((model:GetAttribute("PlantUntil") :: number?) or 0) > os.clock() then
		hum:Move(Vector3.zero) -- follow-through after a pass
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
			botPass(model) -- clear it upfield
			return
		end
		local halfMouth = GameConfig.Goal.Width / 2
		-- advance off the line to narrow the angle as the ball gets closer
		local ballToGoal = hdist(ballPos, ownGoal)
		local advance = math.clamp(45 - ballToGoal, 0, 10)
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
		-- corner-kick / byline flavour: from deep and wide, cross it into the box
		local nearByline = math.abs(myPos.Z - targetGoal.Z) < 14
			and math.abs(myPos.X - GameConfig.Field.CenterX) > GameConfig.Field.Width / 2 - 16
		if nearByline and botPass(model) then
			return
		end
		local dGoal = hdist(myPos, targetGoal)
		if dGoal < SHOOT_RANGE then
			-- cap at the sweet spot: bots don't balloon overcharged shots
			BallService.shootFrom(model, math.clamp(dGoal / 55, 0.5, 0.8), DifficultyService.get().botShotSpread)
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
			if math.random() < 0.7 and botPass(model) then
				return
			end
		end

		-- POSSESSION FOOTBALL: pass-first, dribble second. Even unpressured,
		-- give it to a teammate who's clearly better placed (15+ studs more
		-- advanced and unmarked), and never carry past the role's dribble
		-- budget — backs circulate quickly, the striker drives longest.
		local carrySince = (model:GetAttribute("CarrySince") :: number?) or 0
		local carryTime = os.clock() - carrySince
		if carryTime > 0.6 then
			for _, f in ipairs(BallService.listFootballers()) do
				if f.team == team and f.model ~= model and f.role ~= GameConfig.GoalkeeperRole
					and hdist(f.root.Position, targetGoal) < dGoal - 15 then
					local open = true
					for _, o in ipairs(BallService.listFootballers()) do
						if o.team ~= team and hdist(o.root.Position, f.root.Position) < 8 then
							open = false
							break
						end
					end
					if open and botPass(model) then
						return
					end
				end
			end
		end
		local dribbleBudget = 1.0 + def.offensive * 0.18 -- ~1.5s backs, ~2.8s striker
		if carryTime > dribbleBudget and botPass(model) then
			return
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
		local restricted = BallService.getRestrictedTeam()
		if restricted and restricted ~= team then
			-- dead ball awarded against us: hold shape instead of mobbing the spot
			hum:MoveTo(Vector3.new(home.X, myPos.Y, (home.Z + ownGoal.Z) / 2))
			return
		end
		-- the closest teammate ALWAYS goes to a loose ball, from any distance —
		-- with no walls, a ball near a line would otherwise sit outside every
		-- pursuit radius and freeze the match (frozen-throw-in bug, 2026-06-11)
		if amClosest then
			hum:MoveTo(Vector3.new(ballPos.X, myPos.Y, ballPos.Z))
			return
		end
	end

	-- TEAMMATE HAS THE BALL / not chasing -> make yourself a passing option.
	-- Attackers push AHEAD of the ball into their lane (real support runs);
	-- disciplined roles stay tied to their home position.
	local supportZ
	if carrier and (carrier:GetAttribute("Team") :: string?) == team then
		local aheadZ = ballPos.Z + info.attackDir * (10 + def.offensive * 2.2)
		local pull = def.discipline * 0.45 -- backs anchored, striker free
		supportZ = aheadZ * (1 - pull) + home.Z * pull
		supportZ = math.clamp(supportZ, GameConfig.Field.MinZ + 6, GameConfig.Field.MaxZ - 6)
	else
		supportZ = home.Z + info.attackDir * 8
	end
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
		local runOutfield = accum >= DifficultyService.get().aiTick
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
