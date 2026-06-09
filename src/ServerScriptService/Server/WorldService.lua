--!strict
-- WorldService (SERVER)
-- Builds the whole pitch from code at runtime, oriented NORTH-SOUTH: the length
-- runs along Z (goals on +Z and -Z ends), the width along X. Grass floor, thick
-- invisible boundary walls, two goals with scoring boxes, full field-line markings
-- (perimeter, halfway, centre circle, penalty + goal boxes, penalty spots), and
-- tiered stadium stands. Returns a `world` table (ball spawn + goal boxes).

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FIELD = GameConfig.Field
local GOAL = GameConfig.Goal

local WorldService = {}

export type GoalBox = {
	scoreTeam: string,
	xMin: number, xMax: number,
	zMin: number, zMax: number,
	yMin: number, yMax: number,
}

export type World = {
	pitch: Folder,
	ballSpawn: Vector3,
	goals: { GoalBox },
}

local LENGTH = FIELD.Length -- along Z (north-south)
local WIDTH = FIELD.Width   -- along X
local CX = FIELD.CenterX
local CZ = FIELD.CenterZ

local COLOR_GRASS = Color3.fromRGB(64, 150, 72)
local COLOR_LINE = Color3.fromRGB(245, 245, 245)
local COLOR_POST = Color3.fromRGB(250, 250, 250)
local WALL_T = 6
local LINE_Y = FIELD.GroundY + 0.06
local LINE_W = 0.6

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function wall(name: string, size: Vector3, position: Vector3, parent: Instance)
	local w = block(name, size, CFrame.new(position), Color3.new(0, 0, 0), parent)
	w.Transparency = 1
	w.CanCollide = true
end

-- ---- field-line helpers (flat white markings on the grass) -----------------

local function lineAlongX(z: number, x1: number, x2: number, parent: Instance)
	local p = block("Line", Vector3.new(math.abs(x2 - x1), 0.12, LINE_W), CFrame.new((x1 + x2) / 2, LINE_Y, z), COLOR_LINE, parent)
	p.CanCollide = false
end

local function lineAlongZ(x: number, z1: number, z2: number, parent: Instance)
	local p = block("Line", Vector3.new(LINE_W, 0.12, math.abs(z2 - z1)), CFrame.new(x, LINE_Y, (z1 + z2) / 2), COLOR_LINE, parent)
	p.CanCollide = false
end

local function spot(x: number, z: number, parent: Instance)
	local p = Instance.new("Part")
	p.Name = "Spot"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.12, 1.4, 1.4)
	p.CFrame = CFrame.new(x, LINE_Y, z) * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.CanCollide = false
	p.Color = COLOR_LINE
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
end

local function circleRing(cx: number, cz: number, radius: number, parent: Instance)
	local segs = 30
	local arc = (2 * math.pi * radius) / segs
	for i = 1, segs do
		local a = (i / segs) * math.pi * 2
		local pos = Vector3.new(cx + math.cos(a) * radius, LINE_Y, cz + math.sin(a) * radius)
		local center = Vector3.new(cx, LINE_Y, cz)
		-- lookAt: local Z faces the centre (radial), local X is the tangent
		local seg = block("CircleSeg", Vector3.new(arc + 0.3, 0.12, LINE_W), CFrame.lookAt(pos, center), COLOR_LINE, parent)
		seg.CanCollide = false
	end
end

local function buildGoalFrame(lineZ: number, inwardDir: number, parent: Instance)
	local frameZ = lineZ + inwardDir * 0.5
	local halfW = GOAL.Width / 2
	local postY = FIELD.GroundY + GOAL.Height / 2
	for _, side in ipairs({ -1, 1 }) do
		block(
			"GoalPost",
			Vector3.new(GOAL.PostThickness, GOAL.Height, GOAL.PostThickness),
			CFrame.new(CX + side * halfW, postY, frameZ),
			COLOR_POST,
			parent
		)
	end
	block(
		"GoalCrossbar",
		Vector3.new(GOAL.Width + GOAL.PostThickness, GOAL.PostThickness, GOAL.PostThickness),
		CFrame.new(CX, FIELD.GroundY + GOAL.Height, frameZ),
		COLOR_POST,
		parent
	)
	local net = block(
		"GoalNet",
		Vector3.new(GOAL.Width, GOAL.Height, GOAL.Depth),
		CFrame.new(CX, FIELD.GroundY + GOAL.Height / 2, lineZ - inwardDir * GOAL.Depth / 2),
		Color3.fromRGB(220, 220, 230),
		parent
	)
	net.Transparency = 0.6
	net.CanCollide = false
	net.Material = Enum.Material.ForceField
end

local function buildMarkings(parent: Instance)
	pcall(function()
		local MinX, MaxX, MinZ, MaxZ = FIELD.MinX, FIELD.MaxX, FIELD.MinZ, FIELD.MaxZ
		-- perimeter (inset 1 stud from the boundary)
		lineAlongZ(MinX + 1, MinZ + 1, MaxZ - 1, parent)
		lineAlongZ(MaxX - 1, MinZ + 1, MaxZ - 1, parent)
		lineAlongX(MinZ + 1, MinX + 1, MaxX - 1, parent)
		lineAlongX(MaxZ - 1, MinX + 1, MaxX - 1, parent)
		-- halfway line + centre circle + spot
		lineAlongX(CZ, MinX + 1, MaxX - 1, parent)
		circleRing(CX, CZ, 14, parent)
		spot(CX, CZ, parent)
		-- penalty + goal boxes at each end
		for _, e in ipairs({ { z = MinZ, dir = 1 }, { z = MaxZ, dir = -1 } }) do
			local gz, d = e.z, e.dir
			local pFront = gz + d * 22 -- penalty box depth
			lineAlongX(pFront, -22, 22, parent)
			lineAlongZ(-22, gz + d * 1, pFront, parent)
			lineAlongZ(22, gz + d * 1, pFront, parent)
			local gFront = gz + d * 9 -- goal box depth
			lineAlongX(gFront, -12, 12, parent)
			lineAlongZ(-12, gz + d * 1, gFront, parent)
			lineAlongZ(12, gz + d * 1, gFront, parent)
			spot(CX, gz + d * 14, parent) -- penalty spot
		end
	end)
end

local function buildStands(parent: Instance)
	pcall(function()
		local tiers = 6
		local tierH = 4
		local tierD = 5
		local grey = Color3.fromRGB(95, 100, 115)
		local blue = Color3.fromRGB(50, 80, 170)
		local red = Color3.fromRGB(175, 55, 55)
		local function stand(axis: string, sign: number, color: Color3)
			for i = 0, tiers - 1 do
				local y = FIELD.GroundY + tierH / 2 + i * (tierH * 0.85)
				local outOff = WALL_T + tierD / 2 + i * tierD
				if axis == "x" then
					local x = (sign > 0 and FIELD.MaxX or FIELD.MinX) + sign * outOff
					block("Stand", Vector3.new(tierD, tierH, LENGTH + 2 * (WALL_T + tiers * tierD)), CFrame.new(x, y, CZ), color, parent)
				else
					local z = (sign > 0 and FIELD.MaxZ or FIELD.MinZ) + sign * outOff
					block("Stand", Vector3.new(WIDTH + 2 * (WALL_T + tiers * tierD), tierH, tierD), CFrame.new(CX, y, z), color, parent)
				end
			end
		end
		stand("x", 1, grey)
		stand("x", -1, grey)
		stand("z", 1, red)   -- behind Red's goal (+Z end)
		stand("z", -1, blue) -- behind Blue's goal (-Z end)

		-- floodlight pylons at the four corners
		local pylonH = 64
		local cornerOut = WALL_T + tiers * tierD + 8
		local function pylon(px: number, pz: number)
			block("FloodPole", Vector3.new(2.5, pylonH, 2.5), CFrame.new(px, FIELD.GroundY + pylonH / 2, pz), Color3.fromRGB(55, 60, 70), parent)
			local lamp = block("FloodLamp", Vector3.new(11, 4, 5), CFrame.new(px, FIELD.GroundY + pylonH, pz), Color3.fromRGB(255, 250, 235), parent)
			lamp.Material = Enum.Material.Neon
			lamp.CanCollide = false
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Angle = 130
			light.Range = 140
			light.Brightness = 3
			light.Color = Color3.fromRGB(255, 250, 235)
			light.Parent = lamp
		end
		local px = FIELD.MaxX + cornerOut
		local pz = FIELD.MaxZ + cornerOut
		pylon(px, pz)
		pylon(-px, pz)
		pylon(px, -pz)
		pylon(-px, -pz)
	end)
end

local function tuneLighting()
	pcall(function()
		Lighting.ClockTime = 14
		Lighting.Brightness = 2.5
		Lighting.GlobalShadows = true
		Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	end)
end

function WorldService.build(): World
	local existing = Workspace:FindFirstChild("Pitch")
	if existing then
		existing:Destroy()
	end

	local pitch = Instance.new("Folder")
	pitch.Name = "Pitch"
	pitch.Parent = Workspace

	-- Floor
	local floor = block(
		"Ground",
		Vector3.new(WIDTH, FIELD.FloorThickness, LENGTH),
		CFrame.new(CX, FIELD.GroundY - FIELD.FloorThickness / 2, CZ),
		COLOR_GRASS,
		pitch
	)
	floor.Material = Enum.Material.Grass

	-- Boundary walls (closed box; thick so a hard shot can't tunnel through)
	local wallY = FIELD.GroundY + FIELD.WallHeight / 2
	wall("WallXMin", Vector3.new(WALL_T, FIELD.WallHeight, LENGTH + 2 * WALL_T), Vector3.new(FIELD.MinX - WALL_T / 2, wallY, CZ), pitch)
	wall("WallXMax", Vector3.new(WALL_T, FIELD.WallHeight, LENGTH + 2 * WALL_T), Vector3.new(FIELD.MaxX + WALL_T / 2, wallY, CZ), pitch)
	wall("WallZMin", Vector3.new(WIDTH + 2 * WALL_T, FIELD.WallHeight, WALL_T), Vector3.new(CX, wallY, FIELD.MinZ - WALL_T / 2), pitch)
	wall("WallZMax", Vector3.new(WIDTH + 2 * WALL_T, FIELD.WallHeight, WALL_T), Vector3.new(CX, wallY, FIELD.MaxZ + WALL_T / 2), pitch)

	buildGoalFrame(FIELD.MinZ, 1, pitch)  -- Blue defends the -Z end
	buildGoalFrame(FIELD.MaxZ, -1, pitch) -- Red defends the +Z end

	buildMarkings(pitch)
	buildStands(pitch)
	tuneLighting()

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "CentreSpawn"
	spawnPad.Size = Vector3.new(6, 1, 6)
	spawnPad.CFrame = CFrame.new(CX, FIELD.GroundY + 0.5, CZ)
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.Parent = pitch

	-- Scoring boxes just inside each goal mouth (ball CENTRE inside => a goal).
	local halfW = GOAL.Width / 2
	local xMin = CX - halfW
	local xMax = CX + halfW
	local yMin = FIELD.GroundY - 1
	local yMax = FIELD.GroundY + GOAL.Height + 0.5

	local goals: { GoalBox } = {
		{ scoreTeam = "Red", xMin = xMin, xMax = xMax, zMin = FIELD.MinZ - 5, zMax = FIELD.MinZ + 3, yMin = yMin, yMax = yMax },
		{ scoreTeam = "Blue", xMin = xMin, xMax = xMax, zMin = FIELD.MaxZ - 3, zMax = FIELD.MaxZ + 5, yMin = yMin, yMax = yMax },
	}

	return {
		pitch = pitch,
		ballSpawn = Vector3.new(CX, FIELD.GroundY + GameConfig.Ball.SpawnHeight, CZ),
		goals = goals,
	}
end

function WorldService.pointInGoal(pos: Vector3, box: GoalBox): boolean
	return pos.X >= box.xMin and pos.X <= box.xMax
		and pos.Z >= box.zMin and pos.Z <= box.zMax
		and pos.Y >= box.yMin and pos.Y <= box.yMax
end

return WorldService
