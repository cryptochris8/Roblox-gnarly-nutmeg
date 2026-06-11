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

local LENGTH = FIELD.Length -- along Z (north-south), line to line
local WIDTH = FIELD.Width   -- along X, line to line
local RUNOFF = FIELD.Runoff -- grass apron beyond the lines
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
		-- FIFA-proportioned marking sizes derived from the pitch (ratios of the
		-- 105m x 68m laws-of-the-game pitch) so ANY Field size keeps a true layout
		local boxHalfW = WIDTH * 0.295   -- penalty box: 40.3m wide
		local boxDepth = LENGTH * 0.16   -- 16.5m deep
		local gboxHalfW = WIDTH * 0.135  -- goal box: 18.3m wide
		local gboxDepth = LENGTH * 0.052 -- 5.5m deep
		local spotDist = LENGTH * 0.105  -- penalty spot: 11m out
		local circleR = WIDTH * 0.135    -- centre circle: 9.15m radius
		-- perimeter at the EXACT legal bounds (the apron lies beyond the lines)
		lineAlongZ(MinX, MinZ, MaxZ, parent)
		lineAlongZ(MaxX, MinZ, MaxZ, parent)
		lineAlongX(MinZ, MinX, MaxX, parent)
		lineAlongX(MaxZ, MinX, MaxX, parent)
		-- halfway line + centre circle + spot
		lineAlongX(CZ, MinX, MaxX, parent)
		circleRing(CX, CZ, circleR, parent)
		spot(CX, CZ, parent)
		-- penalty + goal boxes at each end
		for _, e in ipairs({ { z = MinZ, dir = 1 }, { z = MaxZ, dir = -1 } }) do
			local gz, d = e.z, e.dir
			local pFront = gz + d * boxDepth
			lineAlongX(pFront, CX - boxHalfW, CX + boxHalfW, parent)
			lineAlongZ(CX - boxHalfW, gz + d * 1, pFront, parent)
			lineAlongZ(CX + boxHalfW, gz + d * 1, pFront, parent)
			local gFront = gz + d * gboxDepth
			lineAlongX(gFront, CX - gboxHalfW, CX + gboxHalfW, parent)
			lineAlongZ(CX - gboxHalfW, gz + d * 1, gFront, parent)
			lineAlongZ(CX + gboxHalfW, gz + d * 1, gFront, parent)
			spot(CX, gz + d * spotDist, parent)
		end
	end)
end

local function buildStands(parent: Instance)
	pcall(function()
		local tiers = 6
		local tierH = 4
		local tierD = 5
		local standBase = RUNOFF + WALL_T -- stands begin past the apron + wall
		local grey = Color3.fromRGB(95, 100, 115)
		local blue = Color3.fromRGB(50, 80, 170)
		local red = Color3.fromRGB(175, 55, 55)
		local function stand(axis: string, sign: number, color: Color3)
			for i = 0, tiers - 1 do
				local y = FIELD.GroundY + tierH / 2 + i * (tierH * 0.85)
				local outOff = standBase + tierD / 2 + i * tierD
				if axis == "x" then
					local x = (sign > 0 and FIELD.MaxX or FIELD.MinX) + sign * outOff
					block("Stand", Vector3.new(tierD, tierH, LENGTH + 2 * (standBase + tiers * tierD)), CFrame.new(x, y, CZ), color, parent)
				else
					local z = (sign > 0 and FIELD.MaxZ or FIELD.MinZ) + sign * outOff
					block("Stand", Vector3.new(WIDTH + 2 * (standBase + tiers * tierD), tierH, tierD), CFrame.new(CX, y, z), color, parent)
				end
			end
		end
		stand("x", 1, grey)
		stand("x", -1, grey)
		stand("z", 1, red)   -- behind Red's goal (+Z end)
		stand("z", -1, blue) -- behind Blue's goal (-Z end)

		-- floodlight pylons at the four corners
		local pylonH = 64
		local cornerOut = RUNOFF + WALL_T + tiers * tierD + 8
		local function pylon(px: number, pz: number)
			block("FloodPole", Vector3.new(2.5, pylonH, 2.5), CFrame.new(px, FIELD.GroundY + pylonH / 2, pz), Color3.fromRGB(55, 60, 70), parent)
			local lamp = block("FloodLamp", Vector3.new(11, 4, 5), CFrame.new(px, FIELD.GroundY + pylonH, pz), Color3.fromRGB(255, 250, 235), parent)
			lamp.Material = Enum.Material.Neon
			lamp.CanCollide = false
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Angle = 130
			light.Range = math.max(140, LENGTH * 0.75)
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

local function buildCornerFlags(parent: Instance)
	pcall(function()
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local x = CX + sx * WIDTH / 2
				local z = CZ + sz * LENGTH / 2
				local pole = block("CornerFlagPole", Vector3.new(0.35, 5, 0.35), CFrame.new(x, FIELD.GroundY + 2.5, z), Color3.fromRGB(250, 220, 60), parent)
				pole.CanCollide = false
				pole.Material = Enum.Material.SmoothPlastic
				local flag = block("CornerFlag", Vector3.new(1.8, 1.1, 0.12), CFrame.new(x - sx * 0.9, FIELD.GroundY + 4.6, z), Color3.fromRGB(235, 90, 40), parent)
				flag.CanCollide = false
				flag.Material = Enum.Material.SmoothPlastic
			end
		end
	end)
end

-- Pitch-side advertising hoardings in the runoff (low boards facing the pitch).
local function buildHoardings(parent: Instance)
	pcall(function()
		local texts = { "GNARLY NUTMEG", "ATHLETE DOMAINS", "WORLD CUP 2026", "⚽ NUTMEG!" }
		local navy = Color3.fromRGB(18, 24, 48)
		local boardH = 1.6
		local function board(pos: Vector3, faceToward: Vector3, segLen: number, textIndex: number)
			local b = block("AdBoard", Vector3.new(segLen, boardH, 0.5), CFrame.lookAt(pos, faceToward), navy, parent)
			b.Material = Enum.Material.SmoothPlastic
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 28
			gui.Parent = b
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, 1, 0)
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.Text = texts[(textIndex - 1) % #texts + 1]
			label.Parent = gui
		end
		local segLen = 26
		local gap = 3
		local inset = 5 -- boards sit this far into the runoff, past the line
		local n = 0
		-- along both touchlines
		local count = math.floor((LENGTH - 10) / (segLen + gap))
		for _, sx in ipairs({ -1, 1 }) do
			local x = CX + sx * (WIDTH / 2 + inset)
			for i = 1, count do
				local z = CZ - ((count - 1) / 2) * (segLen + gap) + (i - 1) * (segLen + gap)
				n += 1
				board(Vector3.new(x, FIELD.GroundY + boardH / 2, z), Vector3.new(CX, FIELD.GroundY + boardH / 2, z), segLen, n)
			end
		end
		-- behind both goal lines (leave the goal mouth area open)
		local endCount = math.floor((WIDTH - GOAL.Width - 20) / 2 / (segLen + gap))
		for _, sz in ipairs({ -1, 1 }) do
			local z = CZ + sz * (LENGTH / 2 + inset)
			for _, side in ipairs({ -1, 1 }) do
				for i = 1, math.max(1, endCount) do
					local x0 = side * (GOAL.Width / 2 + 12)
					local x = CX + x0 + side * (i - 1) * (segLen + gap) + side * segLen / 2
					n += 1
					board(Vector3.new(x, FIELD.GroundY + boardH / 2, z), Vector3.new(x, FIELD.GroundY + boardH / 2, CZ), segLen, n)
				end
			end
		end
	end)
end

local function tuneLighting()
	pcall(function()
		-- The template ships a broken/black skybox: with environment lighting on,
		-- it renders the grass near-black. A FRESH default Sky = the standard
		-- bright blue Roblox sky, which lights the pitch correctly.
		for _, inst in ipairs(Lighting:GetChildren()) do
			if inst:IsA("Sky") or inst:IsA("Atmosphere") then
				inst:Destroy()
			end
		end
		local sky = Instance.new("Sky")
		sky.Parent = Lighting
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.3
		atmo.Offset = 0.25
		atmo.Color = Color3.fromRGB(199, 211, 222)
		atmo.Decay = Color3.fromRGB(106, 112, 125)
		atmo.Glare = 0.2
		atmo.Haze = 1.2
		atmo.Parent = Lighting
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

	-- The template's Baseplate top sits at exactly Y=0 and z-fights our grass
	-- invisible; its SpawnLocation fights ours. Remove template leftovers.
	pcall(function()
		local bp = Workspace:FindFirstChild("Baseplate")
		if bp then
			bp:Destroy()
		end
		for _, inst in ipairs(Workspace:GetChildren()) do
			if inst:IsA("SpawnLocation") then
				inst:Destroy()
			end
		end
	end)

	local pitch = Instance.new("Folder")
	pitch.Name = "Pitch"
	pitch.Parent = Workspace

	-- Floor: legal pitch + the runoff apron all around
	-- NOTE: Material.Grass renders near-BLACK at distance in this lighting setup
	-- (verified in playtest) — SmoothPlastic + two-tone mow stripes reads better
	-- and is predictable on every device.
	local floor = block(
		"Ground",
		Vector3.new(WIDTH + 2 * RUNOFF, FIELD.FloorThickness, LENGTH + 2 * RUNOFF),
		CFrame.new(CX, FIELD.GroundY - FIELD.FloorThickness / 2, CZ),
		COLOR_GRASS,
		pitch
	)
	floor.Material = Enum.Material.SmoothPlastic

	-- Mowed-grass stripes across the legal pitch (alternating bands, pure looks)
	pcall(function()
		local bands = 12
		local bandLen = LENGTH / bands
		local light = Color3.fromRGB(74, 164, 82)
		for i = 0, bands - 1 do
			if i % 2 == 0 then
				local z = FIELD.MinZ + (i + 0.5) * bandLen
				local s = block("GrassStripe", Vector3.new(WIDTH, 0.04, bandLen), CFrame.new(CX, FIELD.GroundY + 0.02, z), light, pitch)
				s.Material = Enum.Material.SmoothPlastic
				s.CanCollide = false
			end
		end
	end)

	-- Boundary walls at the APRON edge (closed box; thick so a hard shot can't
	-- tunnel). Play is whistled dead at the lines well before the ball gets here.
	local wallY = FIELD.GroundY + FIELD.WallHeight / 2
	local wx = WIDTH / 2 + RUNOFF
	local wz = LENGTH / 2 + RUNOFF
	wall("WallXMin", Vector3.new(WALL_T, FIELD.WallHeight, 2 * wz + 2 * WALL_T), Vector3.new(CX - wx - WALL_T / 2, wallY, CZ), pitch)
	wall("WallXMax", Vector3.new(WALL_T, FIELD.WallHeight, 2 * wz + 2 * WALL_T), Vector3.new(CX + wx + WALL_T / 2, wallY, CZ), pitch)
	wall("WallZMin", Vector3.new(2 * wx + 2 * WALL_T, FIELD.WallHeight, WALL_T), Vector3.new(CX, wallY, CZ - wz - WALL_T / 2), pitch)
	wall("WallZMax", Vector3.new(2 * wx + 2 * WALL_T, FIELD.WallHeight, WALL_T), Vector3.new(CX, wallY, CZ + wz + WALL_T / 2), pitch)

	buildGoalFrame(FIELD.MinZ, 1, pitch)  -- Blue defends the -Z end
	buildGoalFrame(FIELD.MaxZ, -1, pitch) -- Red defends the +Z end

	buildMarkings(pitch)
	buildStands(pitch)
	buildCornerFlags(pitch)
	buildHoardings(pitch)
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
