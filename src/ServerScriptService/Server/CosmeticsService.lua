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

local DEFAULTS = { boots = "classic", trail = "classic", celebration = "groove" }

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

function CosmeticsService.getEquipped(player: Player): { boots: string, trail: string, celebration: string }
	local c = blob(player)
	local e = c and c.equipped or {}
	return {
		boots = (type(e.boots) == "string") and e.boots or DEFAULTS.boots,
		trail = (type(e.trail) == "string") and e.trail or DEFAULTS.trail,
		celebration = (type(e.celebration) == "string") and e.celebration or DEFAULTS.celebration,
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
			end)
		end)
	end)
end

return CosmeticsService
