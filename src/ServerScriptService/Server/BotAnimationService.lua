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
