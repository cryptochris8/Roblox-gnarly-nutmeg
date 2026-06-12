--!strict
-- BotAnimationService (SERVER)
-- Plays the standard R15 locomotion animations on BOT rigs. Human characters
-- animate themselves (the default Animate LocalScript), but nothing drives a
-- server-spawned NPC's Animator, so without this the bots glide around frozen.
-- Tracks are loaded and played on the server; the Animator replicates them to
-- every client. Purely cosmetic: attach failures just leave a bot un-animated
-- (e.g. the peg fallback rig, which has no limbs to animate).

local RunService = game:GetService("RunService")

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
-- Kicks, slide tackles and keeper dives are CODE-BUILT KeyframeSequences,
-- registered at runtime (KeyframeSequenceProvider:RegisterKeyframeSequence
-- issues a local id — real animations with ZERO uploaded assets and zero
-- moderation surface). This is the only approach that works on every rig in
-- the game: our bots are next-gen AnimationConstraint rigs with NO Motor6Ds
-- (verified live — a C0-tween approach silently no-ops on them), while human
-- characters are classic Motor6D rigs; the Animator drives both identically.
-- "AnimActionUntil" stops overlapping actions fighting on one rig.

local function actionBusy(model: Model, seconds: number): boolean
	if ((model:GetAttribute("AnimActionUntil") :: number?) or 0) > os.clock() then
		return true
	end
	model:SetAttribute("AnimActionUntil", os.clock() + seconds)
	return false
end

-- A pose tree following the R15 joint hierarchy. Only named joints get
-- weight 1; ancestors pass through at weight 0.
type PoseSpec = { [string]: CFrame }

local function buildKeyframe(t: number, spec: PoseSpec): Keyframe
	local kf = Instance.new("Keyframe")
	kf.Time = t
	local CHAIN = {
		{ "HumanoidRootPart", "LowerTorso", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
		{ "HumanoidRootPart", "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
		{ "HumanoidRootPart", "LowerTorso", "UpperTorso", "RightUpperArm", "RightLowerArm" },
		{ "HumanoidRootPart", "LowerTorso", "UpperTorso", "LeftUpperArm", "LeftLowerArm" },
	}
	local made: { [string]: Pose } = {}
	local function poseFor(name: string): Pose
		local p = made[name]
		if not p then
			p = Instance.new("Pose")
			p.Name = name
			p.CFrame = spec[name] or CFrame.identity
			p.Weight = spec[name] and 1 or 0
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.Out
			made[name] = p
		end
		return p
	end
	for _, chain in ipairs(CHAIN) do
		for i = 2, #chain do
			local parent = poseFor(chain[i - 1])
			local child = poseFor(chain[i])
			if child.Parent ~= parent and not (child :: any):IsDescendantOf(kf) then
				parent:AddSubPose(child)
			end
		end
	end
	kf:AddPose(made.HumanoidRootPart)
	return kf
end

local function buildSequence(frames: { { t: number, spec: PoseSpec } }): string
	local ks = Instance.new("KeyframeSequence")
	ks.Loop = false
	ks.Priority = Enum.AnimationPriority.Action
	for _, f in ipairs(frames) do
		buildKeyframe(f.t, f.spec).Parent = ks
	end
	return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(ks)
end

local actionAnims: { [string]: Animation } = {}

local function ensureActionAnims()
	if actionAnims.kick then
		return
	end
	local deg = math.rad
	-- the leg swing: wind the right thigh back, lash through, recover
	local kickId = buildSequence({
		{ t = 0, spec = {} },
		{ t = 0.1, spec = { RightUpperLeg = CFrame.Angles(deg(38), 0, 0), RightLowerLeg = CFrame.Angles(deg(-55), 0, 0) } },
		{ t = 0.24, spec = { RightUpperLeg = CFrame.Angles(deg(-78), 0, 0), RightLowerLeg = CFrame.Angles(deg(15), 0, 0) } },
		{ t = 0.55, spec = {} },
	})
	-- the slide: lean way back and sink while momentum carries them through
	local slideId = buildSequence({
		{ t = 0, spec = {} },
		{ t = 0.15, spec = { LowerTorso = CFrame.new(0, -0.85, 0) * CFrame.Angles(deg(-48), 0, 0) } },
		{ t = 0.55, spec = { LowerTorso = CFrame.new(0, -0.85, 0) * CFrame.Angles(deg(-48), 0, 0) } },
		{ t = 0.8, spec = {} },
	})
	-- keeper dives, one per side: roll toward the ball, top arm thrown up
	local function diveId(s: number): string
		local arm = (s > 0) and "RightUpperArm" or "LeftUpperArm"
		local dove: PoseSpec = {
			LowerTorso = CFrame.new(s * 0.6, -0.6, 0) * CFrame.Angles(0, 0, deg(-s * 62)),
			[arm] = CFrame.Angles(0, 0, deg(s * 150)),
		}
		return buildSequence({
			{ t = 0, spec = {} },
			{ t = 0.16, spec = dove },
			{ t = 0.6, spec = dove },
			{ t = 0.85, spec = {} },
		})
	end
	local function anim(id: string): Animation
		local a = Instance.new("Animation")
		a.AnimationId = id
		return a
	end
	actionAnims.kick = anim(kickId)
	actionAnims.slide = anim(slideId)
	actionAnims.diveR = anim(diveId(1))
	actionAnims.diveL = anim(diveId(-1))
end

local function playAction(model: Model, name: string, lifetime: number)
	pcall(function()
		if actionBusy(model, lifetime) then
			return
		end
		ensureActionAnims()
		local hum = model:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		local a = actionAnims[name]
		if not animator or not a then
			return
		end
		local track = (animator :: Animator):LoadAnimation(a)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		track:Play(0.05)
		task.delay(lifetime + 0.4, function()
			track:Stop(0.1)
			track:Destroy()
		end)
	end)
end

-- A proper leg swing on any rig (bots and humans alike).
function BotAnimationService.kick(model: Model)
	playAction(model, "kick", 0.55)
end

-- The clean slide for a won tackle.
function BotAnimationService.slideTackle(model: Model)
	playAction(model, "slide", 0.8)
end

-- Keeper dive toward the ball side.
function BotAnimationService.keeperDive(model: Model, side: number)
	playAction(model, (side >= 0) and "diveR" or "diveL", 0.85)
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
