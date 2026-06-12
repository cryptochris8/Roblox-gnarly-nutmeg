--!strict
-- BotAnimationService (SERVER)
-- Plays the standard R15 locomotion animations on BOT rigs. Human characters
-- animate themselves (the default Animate LocalScript), but nothing drives a
-- server-spawned NPC's Animator, so without this the bots glide around frozen.
-- Tracks are loaded and played on the server; the Animator replicates them to
-- every client. Purely cosmetic: attach failures just leave a bot un-animated
-- (e.g. the peg fallback rig, which has no limbs to animate).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BotAnimationService = {}

-- The stock Roblox R15 locomotion set (Roblox-published, free to use).
local ANIM_IDS = {
	idle = "rbxassetid://507766666",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}
local RUN_ANIM_SPEED = 16 -- studs/s the stock run cycle is authored for

type Rig = {
	hum: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	current: string?,
}

local rigs: { [Model]: Rig } = {}

local function play(rig: Rig, name: string, fade: number)
	if rig.current == name then
		return
	end
	local cur = rig.current
	if cur and rig.tracks[cur] then
		rig.tracks[cur]:Stop(fade)
	end
	local track = rig.tracks[name]
	if track then
		track:Play(fade)
	end
	rig.current = name
end

-- Load the locomotion tracks for one bot. Call AFTER the model is in Workspace
-- (the Animator itself must already exist from BEFORE the model replicated).
function BotAnimationService.attach(model: Model)
	local ok = pcall(function()
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not hum or not root or not animator then
			return
		end
		local tracks: { [string]: AnimationTrack } = {}
		for name, id in pairs(ANIM_IDS) do
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Core
			track.Looped = (name ~= "jump")
			tracks[name] = track
		end
		rigs[model] = { hum = hum, root = root, tracks = tracks, current = nil }
		model.Destroying:Connect(function()
			rigs[model] = nil
		end)
	end)
	if not ok then
		warn("[Gnarly Nutmeg] bot animation attach failed (cosmetic only)")
	end
end

-- Roblox-owned emotes (loadable in any game), used for goal celebrations.
local EMOTE_IDS = {
	dance = { "rbxassetid://507771019", "rbxassetid://507776043", "rbxassetid://507777268" },
	cheer = { "rbxassetid://507770677" },
}

-- One-shot celebration on ANY humanoid rig (bots, humans, even the linesmen).
-- Action priority sits above the locomotion tracks, so no state juggling.
function BotAnimationService.celebrate(model: Model, kind: string)
	pcall(function()
		local hum = model:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		local pool = EMOTE_IDS[kind] or EMOTE_IDS.cheer
		local anim = Instance.new("Animation")
		anim.AnimationId = pool[math.random(1, #pool)]
		local track = (animator :: Animator):LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.15)
		task.delay(2.6, function()
			track:Stop(0.3)
			track:Destroy()
		end)
	end)
end

-- ---- procedural action overlays ---------------------------------------------
-- Kicks, slide tackles and keeper dives are SERVER-TWEENED Motor6D.C0 offsets.
-- C0 is a replicated property (unlike .Transform, which every client's own
-- Animator overwrites locally), and the animator's pose COMPOSES with it — so
-- one tween here reads correctly on every client, over any running animation,
-- for bots AND humans, with zero uploaded animation assets. Each action
-- captures the joint's rest C0 and restores it; "AnimActionUntil" stops
-- overlapping actions from fighting on the same rig.

local function motorOf(model: Model, partName: string, motorName: string): Motor6D?
	local part = model:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(motorName)
	if motor and motor:IsA("Motor6D") then
		return motor
	end
	return nil
end

local function actionBusy(model: Model, seconds: number): boolean
	if ((model:GetAttribute("AnimActionUntil") :: number?) or 0) > os.clock() then
		return true
	end
	model:SetAttribute("AnimActionUntil", os.clock() + seconds)
	return false
end

local function tweenC0(motor: Motor6D, c0: CFrame, t: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(
		motor,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		{ C0 = c0 }
	):Play()
end

-- A proper leg swing: wind the right thigh back, lash it through, recover.
function BotAnimationService.kick(model: Model)
	pcall(function()
		if actionBusy(model, 0.55) then
			return
		end
		local hip = motorOf(model, "RightUpperLeg", "RightHip")
		local knee = motorOf(model, "RightLowerLeg", "RightKnee")
		if not hip then
			return
		end
		local hipRest = hip.C0
		local kneeRest = knee and knee.C0
		tweenC0(hip, hipRest * CFrame.Angles(math.rad(38), 0, 0), 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if knee and kneeRest then
			tweenC0(knee, kneeRest * CFrame.Angles(math.rad(-55), 0, 0), 0.1)
		end
		task.delay(0.11, function()
			tweenC0(hip, hipRest * CFrame.Angles(math.rad(-78), 0, 0), 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if knee and kneeRest then
				tweenC0(knee, kneeRest * CFrame.Angles(math.rad(15), 0, 0), 0.14)
			end
		end)
		task.delay(0.3, function()
			tweenC0(hip, hipRest, 0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			if knee and kneeRest then
				tweenC0(knee, kneeRest, 0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			end
		end)
	end)
end

-- The clean slide: lean way back and sink while momentum carries them through.
function BotAnimationService.slideTackle(model: Model)
	pcall(function()
		if actionBusy(model, 0.8) then
			return
		end
		local rootM = motorOf(model, "LowerTorso", "Root")
		if not rootM then
			return
		end
		local rest = rootM.C0
		local slid = rest * CFrame.new(0, -0.85, 0) * CFrame.Angles(math.rad(-48), 0, 0)
		tweenC0(rootM, slid, 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.45, function()
			tweenC0(rootM, rest, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end)
	end)
end

-- Keeper dive: roll the torso toward the ball side and throw the arms up.
function BotAnimationService.keeperDive(model: Model, side: number)
	pcall(function()
		if actionBusy(model, 0.85) then
			return
		end
		local rootM = motorOf(model, "LowerTorso", "Root")
		if not rootM then
			return
		end
		local s = (side >= 0) and 1 or -1
		local rest = rootM.C0
		local dove = rest * CFrame.new(s * 0.6, -0.6, 0) * CFrame.Angles(0, 0, math.rad(-s * 62))
		tweenC0(rootM, dove, 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local shoulder = motorOf(model, s > 0 and "RightUpperArm" or "LeftUpperArm", s > 0 and "RightShoulder" or "LeftShoulder")
		local shoulderRest = shoulder and shoulder.C0
		if shoulder and shoulderRest then
			tweenC0(shoulder, shoulderRest * CFrame.Angles(0, 0, math.rad(s * 150)), 0.16)
		end
		task.delay(0.5, function()
			tweenC0(rootM, rest, 0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			if shoulder and shoulderRest then
				tweenC0(shoulder, shoulderRest, 0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			end
		end)
	end)
end

local function step()
	for model, rig in pairs(rigs) do
		if not model:IsDescendantOf(game) or rig.hum.Health <= 0 then
			rigs[model] = nil
		else
			local state = rig.hum:GetState()
			if state == Enum.HumanoidStateType.Jumping then
				play(rig, "jump", 0.1)
			elseif state == Enum.HumanoidStateType.Freefall then
				play(rig, "fall", 0.2)
			else
				local v = rig.root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				if speed > 1.5 then
					play(rig, "run", 0.15)
					rig.tracks.run:AdjustSpeed(math.clamp(speed / RUN_ANIM_SPEED, 0.5, 2.2))
				else
					play(rig, "idle", 0.2)
				end
			end
		end
	end
end

function BotAnimationService.init()
	RunService.Heartbeat:Connect(function()
		pcall(step)
	end)
end

return BotAnimationService
