--!strict
-- RefereeService (SERVER)
-- Two assistant referees in black kits who run the touchlines tracking the
-- ball, flag in hand. They live in the runoff OUTSIDE the lines so they can
-- never interfere with play (an on-pitch centre ref would collide with the
-- ball). Purely cosmetic: pcall-guarded; the match runs fine without them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local BallService = require(script.Parent.BallService)
local BotAnimationService = require(script.Parent.BotAnimationService)

local FIELD = GameConfig.Field

local RefereeService = {}

local linesmen: { Model } = {}
local accum = 0

local function dressInBlack(model: Model)
	local black = Color3.fromRGB(30, 30, 34)
	local skin = Color3.fromRGB(222, 170, 120)
	for _, name in ipairs({
		"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
		"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot",
		"LeftHand", "RightHand", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
	}) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = black
			p.Material = Enum.Material.SmoothPlastic
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.Color = skin
		head.Material = Enum.Material.SmoothPlastic
		if not head:FindFirstChildOfClass("Decal") then
			local face = Instance.new("Decal")
			face.Name = "face"
			face.Face = Enum.NormalId.Front
			face.Texture = "rbxasset://textures/face.png"
			face.Parent = head
		end
	end
	-- the assistant's flag: a bright orange square on a short stick
	pcall(function()
		local hand = model:FindFirstChild("RightHand") :: BasePart?
		if hand then
			local stick = Instance.new("Part")
			stick.Name = "FlagStick"
			stick.Size = Vector3.new(0.2, 1.6, 0.2)
			stick.Color = Color3.fromRGB(220, 220, 220)
			stick.Material = Enum.Material.SmoothPlastic
			stick.CanCollide = false
			stick.Massless = true
			stick.CFrame = hand.CFrame * CFrame.new(0, 0.8, 0)
			stick.Parent = model
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = stick
			weld.Parent = stick
			local flag = Instance.new("Part")
			flag.Name = "Flag"
			flag.Size = Vector3.new(0.1, 0.7, 0.9)
			flag.Color = Color3.fromRGB(245, 130, 40)
			flag.Material = Enum.Material.SmoothPlastic
			flag.CanCollide = false
			flag.Massless = true
			flag.CFrame = stick.CFrame * CFrame.new(0, 0.7, 0.45)
			flag.Parent = model
			local weld2 = Instance.new("WeldConstraint")
			weld2.Part0 = stick
			weld2.Part1 = flag
			weld2.Parent = flag
		end
	end)
end

local function makeLinesman(sideX: number): Model?
	local model: Model? = nil
	pcall(function()
		model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not model then
		return nil
	end
	local ref = model :: Model
	ref.Name = "AssistantReferee"
	local hum = ref:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = GameConfig.Player.WalkSpeed + 2
		hum.AutoRotate = true
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		if not hum:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = hum
		end
	end
	local animate = ref:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	dressInBlack(ref)
	pcall(function()
		ref:PivotTo(CFrame.new(sideX, FIELD.GroundY + GameConfig.Player.SpawnHeight, 0))
	end)
	ref.Parent = Workspace
	local root = ref:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			(root :: any):SetNetworkOwner(nil)
		end)
	end
	BotAnimationService.attach(ref)
	return ref
end

function RefereeService.init()
	pcall(function()
		local lineOffset = FIELD.Runoff - 4 -- in the runoff, clear of the hoardings
		for _, sx in ipairs({ -1, 1 }) do
			local x = (sx > 0 and FIELD.MaxX or FIELD.MinX) + sx * lineOffset
			local ref = makeLinesman(x)
			if ref then
				linesmen[#linesmen + 1] = ref
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.25 then
			return
		end
		accum = 0
		pcall(function()
			local ballZ = BallService.getBallPosition().Z
			local targetZ = math.clamp(ballZ, FIELD.MinZ + 4, FIELD.MaxZ - 4)
			for _, ref in ipairs(linesmen) do
				local hum = ref:FindFirstChildOfClass("Humanoid")
				local root = ref:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hum and root then
					hum:MoveTo(Vector3.new(root.Position.X, root.Position.Y, targetZ))
				end
			end
		end)
	end)
end

return RefereeService
