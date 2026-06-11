--!strict
-- Nations
-- The Nutmeg Trophy's 16 playable nations: kit colour + a strength rating that
-- drives simulated fixtures. Country NAMES and generic kit colours only — no
-- federation badges, crests, or competition trademarks.

export type Nation = {
	name: string,
	color: Color3,
	strength: number, -- 70-95; shapes simulated results
}

local Nations = {}

local List: { Nation } = {
	{ name = "BRAZIL", color = Color3.fromRGB(255, 221, 0), strength = 95 },
	{ name = "ARGENTINA", color = Color3.fromRGB(117, 170, 219), strength = 94 },
	{ name = "FRANCE", color = Color3.fromRGB(33, 48, 77), strength = 93 },
	{ name = "ENGLAND", color = Color3.fromRGB(240, 240, 240), strength = 90 },
	{ name = "SPAIN", color = Color3.fromRGB(196, 27, 23), strength = 91 },
	{ name = "GERMANY", color = Color3.fromRGB(225, 225, 225), strength = 89 },
	{ name = "ITALY", color = Color3.fromRGB(0, 102, 170), strength = 88 },
	{ name = "PORTUGAL", color = Color3.fromRGB(150, 16, 30), strength = 90 },
	{ name = "NETHERLANDS", color = Color3.fromRGB(241, 100, 30), strength = 87 },
	{ name = "MEXICO", color = Color3.fromRGB(0, 100, 50), strength = 82 },
	{ name = "USA", color = Color3.fromRGB(230, 230, 235), strength = 80 },
	{ name = "JAPAN", color = Color3.fromRGB(20, 40, 120), strength = 81 },
	{ name = "MOROCCO", color = Color3.fromRGB(170, 30, 40), strength = 83 },
	{ name = "CROATIA", color = Color3.fromRGB(235, 235, 235), strength = 84 },
	{ name = "BELGIUM", color = Color3.fromRGB(190, 25, 35), strength = 85 },
	{ name = "URUGUAY", color = Color3.fromRGB(95, 160, 215), strength = 84 },
}
Nations.List = List

function Nations.byName(name: string): Nation?
	for _, n in ipairs(List) do
		if n.name == name then
			return n
		end
	end
	return nil
end

return Nations
