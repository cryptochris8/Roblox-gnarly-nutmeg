--!strict
-- Cosmetics
-- The free unlock track: boots, ball trails, and goal celebrations, earned by
-- level. Shared data so the server validates equips and the client renders the
-- locker. No purchases anywhere — you earn your look by playing.

export type Boot = { id: string, name: string, color: Color3, unlockLevel: number }
export type TrailStyle = { id: string, name: string, c1: Color3, c2: Color3, unlockLevel: number }
export type Celebration = { id: string, name: string, animId: number, unlockLevel: number }

local Cosmetics = {}

Cosmetics.Boots = {
	{ id = "classic", name = "Classic Black", color = Color3.fromRGB(30, 32, 38), unlockLevel = 1 },
	{ id = "white", name = "Pro Whites", color = Color3.fromRGB(240, 240, 245), unlockLevel = 3 },
	{ id = "crimson", name = "Crimson Strikers", color = Color3.fromRGB(200, 45, 55), unlockLevel = 6 },
	{ id = "volt", name = "Volt Rush", color = Color3.fromRGB(190, 255, 60), unlockLevel = 9 },
	{ id = "ocean", name = "Ocean Blues", color = Color3.fromRGB(45, 120, 230), unlockLevel = 12 },
	{ id = "royal", name = "Royal Purple", color = Color3.fromRGB(140, 70, 220), unlockLevel = 15 },
	{ id = "pink", name = "Hot Pink Heat", color = Color3.fromRGB(255, 95, 180), unlockLevel = 18 },
	{ id = "gold", name = "Golden Boots", color = Color3.fromRGB(245, 196, 60), unlockLevel = 22 },
} :: { Boot }

Cosmetics.Trails = {
	{ id = "classic", name = "Classic White", c1 = Color3.fromRGB(245, 245, 245), c2 = Color3.fromRGB(245, 245, 245), unlockLevel = 1 },
	{ id = "ice", name = "Ice Cold", c1 = Color3.fromRGB(150, 225, 255), c2 = Color3.fromRGB(235, 250, 255), unlockLevel = 8 },
	{ id = "rainbow", name = "Rainbow Curl", c1 = Color3.fromRGB(255, 80, 80), c2 = Color3.fromRGB(90, 120, 255), unlockLevel = 12 },
	{ id = "fire", name = "On Fire", c1 = Color3.fromRGB(255, 130, 30), c2 = Color3.fromRGB(255, 220, 90), unlockLevel = 16 },
	{ id = "shadow", name = "Shadow Strike", c1 = Color3.fromRGB(60, 60, 80), c2 = Color3.fromRGB(160, 160, 190), unlockLevel = 20 },
} :: { TrailStyle }

-- the three Roblox-owned dances already used by celebrations
Cosmetics.Celebrations = {
	{ id = "groove", name = "The Groove", animId = 507771019, unlockLevel = 1 },
	{ id = "shuffle", name = "Side Shuffle", animId = 507776043, unlockLevel = 5 },
	{ id = "bounce", name = "Big Bounce", animId = 507777268, unlockLevel = 9 },
} :: { Celebration }

local function findIn<T>(list: { T & { id: string } }, id: string?): (T & { id: string })?
	for _, item in ipairs(list) do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Cosmetics.boot(id: string?): Boot?
	return findIn(Cosmetics.Boots, id)
end

function Cosmetics.trail(id: string?): TrailStyle?
	return findIn(Cosmetics.Trails, id)
end

function Cosmetics.celebration(id: string?): Celebration?
	return findIn(Cosmetics.Celebrations, id)
end

return Cosmetics
