--!strict
-- Skills
-- The unlockable skill moves: shared data so the server validates and the
-- client shows the right keys/levels. Effects live in BallService.

export type Skill = {
	id: string,
	name: string,
	unlockLevel: number,
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
	cooldown: number,
	stamina: number,
	blurb: string,
}

local Skills = {}

local List: { Skill } = {
	{
		id = "elastico",
		name = "Elastico Dash",
		unlockLevel = 3,
		key = Enum.KeyCode.R,
		pad = Enum.KeyCode.DPadLeft,
		cooldown = 5,
		stamina = 8,
		blurb = "Explosive touch — dash with the ball glued to your feet.",
	},
	{
		id = "roulette",
		name = "Roulette",
		unlockLevel = 6,
		key = Enum.KeyCode.T,
		pad = Enum.KeyCode.DPadUp,
		cooldown = 6,
		stamina = 9,
		blurb = "Spin off the defender — untackleable while you turn.",
	},
	{
		id = "rainbow",
		name = "Rainbow Flick",
		unlockLevel = 10,
		key = Enum.KeyCode.G,
		pad = Enum.KeyCode.DPadRight,
		cooldown = 6,
		stamina = 10,
		blurb = "Flick the ball over their heads and run onto it.",
	},
	{
		id = "chop",
		name = "Chop Cut",
		unlockLevel = 14,
		key = Enum.KeyCode.C,
		pad = Enum.KeyCode.DPadDown,
		cooldown = 5,
		stamina = 8,
		blurb = "Plant and cut the ball 90° — the lunge flies past you.",
	},
	{
		id = "fakeshot",
		name = "Fake Shot",
		unlockLevel = 18,
		key = Enum.KeyCode.V,
		pad = Enum.KeyCode.ButtonR3,
		cooldown = 6,
		stamina = 8,
		blurb = "Sell the strike — the nearest defender bites and freezes.",
	},
}
Skills.List = List

function Skills.byId(id: string): Skill?
	for _, s in ipairs(List) do
		if s.id == id then
			return s
		end
	end
	return nil
end

return Skills
