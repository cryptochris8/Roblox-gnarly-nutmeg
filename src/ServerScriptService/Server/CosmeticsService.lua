--!strict
-- CosmeticsService (SERVER)
-- The free locker: validates equips against the player's level and keeps the
-- equipped set in the persisted profile (Cosmetics blob, saved alongside
-- Progression). Boots recolor the character's feet; BallService reads the
-- equipped trail at kick time; clients play their own equipped celebration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)

local CosmeticsService = {}

local toastEvent: RemoteEvent? = nil

local DEFAULTS = { boots = "classic", trail = "classic", celebration = "groove", costume = "none" }

local function blob(player: Player): any?
	local p = PlayerDataService.get(player)
	if not p then
		return nil
	end
	local c = (p :: any).Cosmetics
	if type(c) ~= "table" or type(c.equipped) ~= "table" then
		c = { equipped = { boots = DEFAULTS.boots, trail = DEFAULTS.trail, celebration = DEFAULTS.celebration } }
		;(p :: any).Cosmetics = c
	end
	return c
end

function CosmeticsService.getEquipped(player: Player): { boots: string, trail: string, celebration: string, costume: string }
	local c = blob(player)
	local e = c and c.equipped or {}
	return {
		boots = (type(e.boots) == "string") and e.boots or DEFAULTS.boots,
		trail = (type(e.trail) == "string") and e.trail or DEFAULTS.trail,
		celebration = (type(e.celebration) == "string") and e.celebration or DEFAULTS.celebration,
		costume = (type(e.costume) == "string") and e.costume or DEFAULTS.costume,
	}
end

-- Paint the equipped boots onto the character's feet (called after the kit
-- pass repaints the body, after equips, and shortly after each spawn).
function CosmeticsService.applyBoots(player: Player)
	pcall(function()
		local boot = Cosmetics.boot(CosmeticsService.getEquipped(player).boots)
		local char = player.Character
		if not (boot and char) then
			return
		end
		for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
			local foot = char:FindFirstChild(name)
			if foot and foot:IsA("BasePart") then
				foot.Color = boot.color
			end
		end
	end)
end

-- Layer the GNARLS squirrel costume (ears + a fat fluffy tail) over the player's
-- kit when equipped, or strip it off. Every piece is massless, non-colliding and
-- raycast-invisible so it never touches ball physics or tackles. Called after the
-- kit pass on spawn and on equip; "none" just removes it.
function CosmeticsService.applyCostume(player: Player)
	pcall(function()
		local char = player.Character
		if not char then
			return
		end
		local existing = char:FindFirstChild("GnarlsCostume")
		if existing then
			existing:Destroy()
		end
		if CosmeticsService.getEquipped(player).costume ~= "gnarls" then
			return
		end
		local head = char:FindFirstChild("Head")
		if not (head and head:IsA("BasePart")) then
			return
		end
		local torso = char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
		if not (torso and torso:IsA("BasePart")) then
			return
		end
		local fur = Color3.fromRGB(196, 110, 48)
		local cream = Color3.fromRGB(247, 236, 214)
		local folder = Instance.new("Folder")
		folder.Name = "GnarlsCostume"
		local function piece(size: Vector3, cf: CFrame, color: Color3, weldTo: BasePart, shape: Enum.PartType?): Part
			local p = Instance.new("Part")
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = Enum.Material.SmoothPlastic
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Massless = true
			if shape then
				p.Shape = shape
			end
			p.Parent = folder
			local w = Instance.new("WeldConstraint")
			w.Part0 = p
			w.Part1 = weldTo
			w.Parent = p
			return p
		end
		-- ears: two rounded orange ears with a cream inner, atop the head
		local hy = head.Size.Y / 2
		for _, sgn in ipairs({ -1, 1 }) do
			local earCf = head.CFrame * CFrame.new(sgn * 0.42, hy + 0.28, 0.05) * CFrame.Angles(0, 0, sgn * math.rad(16))
			piece(Vector3.new(0.55, 0.85, 0.28), earCf, fur, head, Enum.PartType.Ball)
			piece(Vector3.new(0.32, 0.5, 0.18), earCf * CFrame.new(0, 0.02, 0.1), cream, head, Enum.PartType.Ball)
		end
		-- tail: a fat curl of balls rising up behind the torso, cream at the tip
		local segs = {
			{ off = Vector3.new(0, -0.5, 0.9), s = 1.6 },
			{ off = Vector3.new(0, 0.3, 1.35), s = 1.9 },
			{ off = Vector3.new(0, 1.2, 1.5), s = 2.0 },
			{ off = Vector3.new(0, 2.1, 1.25), s = 1.8 },
			{ off = Vector3.new(0, 2.8, 0.7), s = 1.4 },
		}
		for i, seg in ipairs(segs) do
			local color = (i >= #segs - 1) and cream or fur
			piece(Vector3.new(seg.s, seg.s, seg.s), torso.CFrame * CFrame.new(seg.off), color, torso, Enum.PartType.Ball)
		end
		folder.Parent = char
	end)
end

local SLOTS: { [string]: (string) -> any } = {
	boots = function(id)
		return Cosmetics.boot(id)
	end,
	trail = function(id)
		return Cosmetics.trail(id)
	end,
	celebration = function(id)
		return Cosmetics.celebration(id)
	end,
	costume = function(id)
		return Cosmetics.costume(id)
	end,
}

local function onEquip(player: Player, slot: any, id: any)
	if type(slot) ~= "string" or type(id) ~= "string" then
		return
	end
	local find = SLOTS[slot]
	if not find then
		return
	end
	local item = find(id)
	if not item then
		return
	end
	if ProgressionService.getLevel(player) < item.unlockLevel then
		if toastEvent then
			toastEvent:FireClient(player, ("🔒 %s unlocks at Level %d — keep playing!"):format(item.name, item.unlockLevel))
		end
		return
	end
	local c = blob(player)
	if not c then
		return
	end
	c.equipped[slot] = id
	if slot == "boots" then
		CosmeticsService.applyBoots(player)
	end
	if slot == "costume" then
		CosmeticsService.applyCostume(player)
	end
	if toastEvent then
		toastEvent:FireClient(player, ("✨ Equipped: %s"):format(item.name))
	end
	ProgressionService.sync(player) -- the equipped set rides ProgressionSync
end

function CosmeticsService.init()
	toastEvent = Remotes.get(Remotes.Toast)
	Remotes.get(Remotes.RequestEquip).OnServerEvent:Connect(onEquip)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.delay(1.5, function()
				CosmeticsService.applyBoots(player)
				CosmeticsService.applyCostume(player)
			end)
		end)
	end)
end

return CosmeticsService
