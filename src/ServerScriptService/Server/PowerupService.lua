--!strict
-- PowerupService (SERVER)
-- The arcade layer (Phase 3): bobbing neon power-up orbs at six symmetric spots
-- on the pitch. Any footballer — human or bot — collects by running over one.
-- Family-friendly adaptations of the original Hytopia arcade set: ⚡ Speed
-- Boost, 💥 Mega Kick, ❄ Freeze Blast (radial freeze around the collector),
-- 🛡 Shield (tackle/stun immunity with the classic ForceField sparkle).
-- Spots respawn after GameConfig.Arcade.RespawnSeconds. Toggle with
-- GameConfig.Arcade.Enabled. Cosmetic failures never affect the match.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)
local BallService = require(script.Parent.BallService)

local ARCADE = GameConfig.Arcade
local FIELD = GameConfig.Field
local TAG = "Footballer"

local PowerupService = {}

type PowerupType = { id: string, name: string, emoji: string, color: Color3 }
local TYPES: { PowerupType } = {
	{ id = "speed", name = "Speed Boost", emoji = "⚡", color = Color3.fromRGB(255, 220, 60) },
	{ id = "mega", name = "Mega Kick", emoji = "💥", color = Color3.fromRGB(255, 95, 60) },
	{ id = "freeze", name = "Freeze Blast", emoji = "❄", color = Color3.fromRGB(120, 200, 255) },
	{ id = "shield", name = "Shield", emoji = "🛡", color = Color3.fromRGB(140, 255, 160) },
}

local toastEvent: RemoteEvent? = nil
local orbs: { [Part]: boolean } = {} -- live orbs (for the bob/spin loop)
local elapsed = 0

local function displayName(model: Model): string
	local uid = (model:GetAttribute("UserId") :: number?) or 0
	if uid ~= 0 then
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			return plr.DisplayName
		end
	end
	local team = (model:GetAttribute("Team") :: string?) or ""
	return (team ~= "") and ("a " .. team .. " bot") or "a bot"
end

local function toast(text: string)
	if toastEvent then
		toastEvent:FireAllClients(text)
	end
end

local function sparkleBurst(at: Vector3, color: Color3, count: number)
	pcall(function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = CFrame.new(at)
		p.Parent = Workspace
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
		e.LightEmission = 0.8
		e.Lifetime = NumberRange.new(0.4, 0.9)
		e.Speed = NumberRange.new(8, 16)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.7)
		e.Rate = 0
		e.Parent = p
		e:Emit(count)
		task.delay(1.2, function()
			p:Destroy()
		end)
	end)
end

-- a short-lived particle aura attached to a player (speed / mega feedback)
local function aura(model: Model, color: Color3, seconds: number)
	pcall(function()
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local e = Instance.new("ParticleEmitter")
		e.Name = "PowerupAura"
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.7
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(1, 3)
		e.Size = NumberSequence.new(0.45)
		e.Rate = 14
		e.Parent = root
		task.delay(seconds, function()
			e:Destroy()
		end)
	end)
end

-- ---- the four effects --------------------------------------------------------

local function applySpeed(model: Model)
	local uid = (model:GetAttribute("UserId") :: number?) or 0
	local plr = uid ~= 0 and Players:GetPlayerByUserId(uid) or nil
	if plr then
		PlayerService.burst(plr, ARCADE.SpeedMultiplier, ARCADE.SpeedSeconds)
	else
		-- bots: guarded WalkSpeed bump (don't stack restores)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and ((model:GetAttribute("SpeedBoostUntil") :: number?) or 0) < os.clock() then
			local base = hum.WalkSpeed
			hum.WalkSpeed = base * ARCADE.SpeedMultiplier
			task.delay(ARCADE.SpeedSeconds, function()
				if hum.Parent then
					hum.WalkSpeed = base
				end
			end)
		end
	end
	model:SetAttribute("SpeedBoostUntil", os.clock() + ARCADE.SpeedSeconds)
	aura(model, Color3.fromRGB(255, 220, 60), ARCADE.SpeedSeconds)
end

local function applyMega(model: Model)
	model:SetAttribute("MegaKickUntil", os.clock() + ARCADE.MegaKickSeconds)
	aura(model, Color3.fromRGB(255, 95, 60), ARCADE.MegaKickSeconds)
end

local function applyFreeze(byModel: Model)
	local byTeam = (byModel:GetAttribute("Team") :: string?) or ""
	local root = byModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local frozen = 0
	for _, f in ipairs(BallService.listFootballers()) do
		if f.team ~= byTeam then
			local d = (f.root.Position - root.Position).Magnitude
			if d <= ARCADE.FreezeRadius then
				if BallService.stunModel(f.model, ARCADE.FreezeSeconds) then
					frozen += 1
					sparkleBurst(f.root.Position, Color3.fromRGB(150, 220, 255), 14)
				end
			end
		end
	end
	if frozen > 0 then
		toast(("❄ %d opponent%s frozen!"):format(frozen, frozen == 1 and "" or "s"))
	end
end

local function applyShield(model: Model)
	model:SetAttribute("ShieldUntil", os.clock() + ARCADE.ShieldSeconds)
	pcall(function()
		local ff = Instance.new("ForceField") -- the classic sparkle bubble
		ff.Name = "PowerupShield"
		ff.Parent = model
		task.delay(ARCADE.ShieldSeconds, function()
			ff:Destroy()
		end)
	end)
end

local APPLY: { [string]: (Model) -> () } = {
	speed = applySpeed,
	mega = applyMega,
	freeze = applyFreeze,
	shield = applyShield,
}

-- ---- orbs ---------------------------------------------------------------------

local function spawnSpots(): { Vector3 }
	local y = FIELD.GroundY + 3
	local wx = FIELD.Width * 0.3
	local lz = FIELD.Length * 0.28
	return {
		Vector3.new(FIELD.CenterX - wx, y, FIELD.CenterZ),
		Vector3.new(FIELD.CenterX + wx, y, FIELD.CenterZ),
		Vector3.new(FIELD.CenterX - wx, y, FIELD.CenterZ - lz),
		Vector3.new(FIELD.CenterX + wx, y, FIELD.CenterZ - lz),
		Vector3.new(FIELD.CenterX - wx, y, FIELD.CenterZ + lz),
		Vector3.new(FIELD.CenterX + wx, y, FIELD.CenterZ + lz),
	}
end

local function spawnOrb(spot: Vector3)
	local ptype = TYPES[math.random(1, #TYPES)]
	local orb = Instance.new("Part")
	orb.Name = "PowerupOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.4, 2.4, 2.4)
	orb.Color = ptype.color
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CFrame = CFrame.new(spot)
	orb:SetAttribute("PowerupId", ptype.id)
	orb:SetAttribute("BaseY", spot.Y)
	local light = Instance.new("PointLight")
	light.Color = ptype.color
	light.Range = 10
	light.Brightness = 1.4
	light.Parent = orb
	local taken = false
	orb.Touched:Connect(function(hit)
		if taken then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model or not CollectionService:HasTag(model, TAG) then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end
		taken = true
		orbs[orb] = nil
		pcall(function()
			local fn = APPLY[ptype.id]
			if fn then
				fn(model)
			end
			toast(("%s %s — %s!"):format(ptype.emoji, ptype.name, displayName(model)))
			sparkleBurst(orb.Position, ptype.color, 22)
		end)
		orb:Destroy()
		task.delay(ARCADE.RespawnSeconds, function()
			spawnOrb(spot)
		end)
	end)
	orb.Parent = Workspace
	orbs[orb] = true
end

function PowerupService.init()
	if not ARCADE.Enabled then
		return
	end
	toastEvent = Remotes.get(Remotes.Toast)
	for _, spot in ipairs(spawnSpots()) do
		spawnOrb(spot)
	end
	-- one loop bobs and spins every live orb
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		for orb in pairs(orbs) do
			if orb.Parent then
				local baseY = (orb:GetAttribute("BaseY") :: number?) or 3
				local p = orb.Position
				orb.CFrame = CFrame.new(p.X, baseY + math.sin(elapsed * 2.2) * 0.6, p.Z)
					* CFrame.Angles(0, elapsed * 1.8, 0)
			else
				orbs[orb] = nil
			end
		end
	end)
end

return PowerupService
