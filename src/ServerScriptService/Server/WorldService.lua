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
	-- BOX NET: invisible dead-bounce collider panels (a scored shot billows in
	-- and drops instead of flying through) wrapped in a white string lattice
	-- that reads as a real net from every angle. ~60 thin anchored strands per
	-- goal, no shadows, no collisions - negligible cost.
	local netDepth = GOAL.Depth
	local backZ = lineZ - inwardDir * netDepth
	local topY = FIELD.GroundY + GOAL.Height
	local midY = FIELD.GroundY + GOAL.Height / 2
	local midZ = lineZ - inwardDir * netDepth / 2
	local deadNet = PhysicalProperties.new(0.7, 0.8, 0.05, 1, 1)
	local function catchPanel(name: string, size: Vector3, cf: CFrame)
		local p = block(name, size, cf, COLOR_POST, parent)
		p.Transparency = 1
		p.CanCollide = true
		p.CustomPhysicalProperties = deadNet
	end
	catchPanel("NetCatchBack", Vector3.new(GOAL.Width, GOAL.Height, 0.4), CFrame.new(CX, midY, backZ))
	catchPanel("NetCatchTop", Vector3.new(GOAL.Width, 0.4, netDepth), CFrame.new(CX, topY + 0.2, midZ))
	catchPanel("NetCatchSideL", Vector3.new(0.4, GOAL.Height, netDepth), CFrame.new(CX - halfW - 0.2, midY, midZ))
	catchPanel("NetCatchSideR", Vector3.new(0.4, GOAL.Height, netDepth), CFrame.new(CX + halfW + 0.2, midY, midZ))

	local stringColor = Color3.fromRGB(246, 246, 250)
	local function strand(size: Vector3, cf: CFrame)
		local s = block("NetStrand", size, cf, stringColor, parent)
		s.CanCollide = false
		s.CastShadow = false
		s.Transparency = 0.08
	end
	local t = 0.12
	local nx = math.max(6, math.floor(GOAL.Width / 1.4))
	local ny = math.max(3, math.floor(GOAL.Height / 1.4))
	local nz = math.max(2, math.floor(netDepth / 1.5))
	-- back panel
	for i = 0, nx do
		strand(Vector3.new(t, GOAL.Height, t), CFrame.new(CX - halfW + i * (GOAL.Width / nx), midY, backZ))
	end
	for j = 0, ny do
		strand(Vector3.new(GOAL.Width, t, t), CFrame.new(CX, FIELD.GroundY + j * (GOAL.Height / ny), backZ))
	end
	-- roof panel
	for i = 0, nx do
		strand(Vector3.new(t, t, netDepth), CFrame.new(CX - halfW + i * (GOAL.Width / nx), topY, midZ))
	end
	for k = 0, nz do
		strand(Vector3.new(GOAL.Width, t, t), CFrame.new(CX, topY, lineZ - inwardDir * k * (netDepth / nz)))
	end
	-- side panels
	for _, side in ipairs({ -1, 1 }) do
		local x = CX + side * halfW
		for k = 0, nz do
			strand(Vector3.new(t, GOAL.Height, t), CFrame.new(x, midY, lineZ - inwardDir * k * (netDepth / nz)))
		end
		for j = 0, ny do
			strand(Vector3.new(t, t, netDepth), CFrame.new(x, FIELD.GroundY + j * (GOAL.Height / ny), midZ))
		end
	end
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

-- Blocky fans filling the stand tiers: torso + head per fan, anchored, no
-- shadows. End stands wear the home team's colours; the sides are a mix.
local function buildCrowd(parent: Instance)
	pcall(function()
		local tiers = 6
		local tierH = 4
		local tierD = 5
		local standBase = RUNOFF + WALL_T
		local sideMix = {
			Color3.fromRGB(235, 235, 235), Color3.fromRGB(70, 110, 225), Color3.fromRGB(225, 70, 70),
			Color3.fromRGB(80, 190, 120), Color3.fromRGB(250, 200, 60), Color3.fromRGB(150, 90, 200),
			Color3.fromRGB(40, 44, 60), Color3.fromRGB(245, 130, 60),
		}
		local redMix = { Color3.fromRGB(225, 70, 70), Color3.fromRGB(180, 45, 45), Color3.fromRGB(245, 245, 245), Color3.fromRGB(120, 30, 30) }
		local blueMix = { Color3.fromRGB(70, 110, 225), Color3.fromRGB(45, 70, 180), Color3.fromRGB(245, 245, 245), Color3.fromRGB(25, 40, 120) }
		local skins = {
			Color3.fromRGB(255, 213, 170), Color3.fromRGB(234, 184, 130),
			Color3.fromRGB(196, 142, 102), Color3.fromRGB(150, 103, 71), Color3.fromRGB(106, 70, 48),
		}
		local rng = Random.new(7)
		local function fan(x: number, y: number, z: number, palette: { Color3 })
			local body = Instance.new("Part")
			body.Anchored = true
			body.CanCollide = false
			body.CanQuery = false -- invisible to raycasts/overlaps (ball logic safety)
			body.CanTouch = false
			body.CastShadow = false
			body.Material = Enum.Material.SmoothPlastic
			body.Color = palette[rng:NextInteger(1, #palette)]
			body.Size = Vector3.new(1.3, 1.7, 0.7)
			body.CFrame = CFrame.new(x, y + 0.85, z) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
			body.Name = "Fan"
			body.Parent = parent
			local head = Instance.new("Part")
			head.Shape = Enum.PartType.Ball
			head.Anchored = true
			head.CanCollide = false
			head.CanQuery = false
			head.CanTouch = false
			head.CastShadow = false
			head.Material = Enum.Material.SmoothPlastic
			head.Color = skins[rng:NextInteger(1, #skins)]
			head.Size = Vector3.new(0.9, 0.9, 0.9)
			head.CFrame = CFrame.new(x, y + 2.1, z)
			head.Name = "FanHead"
			head.Parent = parent
		end
		-- a few camera-flash emitters scattered through the bowl (fired on goals)
		local function flashSpot(x: number, y: number, z: number)
			local p = Instance.new("Part")
			p.Name = "CrowdFlash"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			p.Size = Vector3.new(6, 2, 6)
			p.CFrame = CFrame.new(x, y + 2, z)
			p.Parent = parent
			local e = Instance.new("ParticleEmitter")
			e.Rate = 0
			e.Lifetime = NumberRange.new(0.08, 0.18)
			e.Speed = NumberRange.new(0, 1)
			e.Size = NumberSequence.new(1.6)
			e.LightEmission = 1
			e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			e.Transparency = NumberSequence.new(0, 1)
			e.Parent = p
		end
		local step = 4.5
		local occupancy = 0.45
		for i = 0, tiers - 1 do
			local tierTopY = FIELD.GroundY + tierH / 2 + i * (tierH * 0.85) + tierH / 2
			local outOff = standBase + tierD / 2 + i * tierD
			-- side stands (mixed colours)
			local sideLen = LENGTH + 2 * (standBase + tiers * tierD) - 8
			for _, sx in ipairs({ -1, 1 }) do
				local x = (sx > 0 and FIELD.MaxX or FIELD.MinX) + sx * outOff
				local n = math.floor(sideLen / step)
				for k = 0, n do
					if rng:NextNumber() < occupancy then
						fan(x, tierTopY, CZ - sideLen / 2 + k * step + rng:NextNumber(-0.8, 0.8), sideMix)
					end
				end
			end
			-- end stands (team colours)
			local endLen = WIDTH + 2 * (standBase + tiers * tierD) - 8
			for _, sz in ipairs({ -1, 1 }) do
				local z = (sz > 0 and FIELD.MaxZ or FIELD.MinZ) + sz * outOff
				local palette = (sz > 0) and redMix or blueMix
				local n = math.floor(endLen / step)
				for k = 0, n do
					if rng:NextNumber() < occupancy then
						fan(CX - endLen / 2 + k * step + rng:NextNumber(-0.8, 0.8), tierTopY, z, palette)
					end
				end
			end
			-- camera flashes on the middle tiers
			if i == 2 or i == 4 then
				local x = FIELD.MaxX + outOff
				for fz = -LENGTH / 2, LENGTH / 2, 40 do
					flashSpot(x, tierTopY, fz)
					flashSpot(-x, tierTopY, fz)
				end
				local z = FIELD.MaxZ + outOff
				for fx = -WIDTH / 2, WIDTH / 2, 40 do
					flashSpot(fx, tierTopY, z)
					flashSpot(fx, tierTopY, -z)
				end
			end
		end
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
		-- (no FIFA/"World Cup" trademarks on anything player-facing)
		local texts = { "GNARLY NUTMEG", "ATHLETE DOMAINS", "THE NUTMEG TROPHY", "⚽ NUTMEG!" }
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

-- Live big-screens behind each end. MatchService feeds these via the
-- onSnapshot hook (wired in Main) every broadcast, so the stadium itself
-- shows the score, the clock and the competition line.
type Jumbo = { score: TextLabel, clock: TextLabel, ticker: TextLabel }
local jumbos: { Jumbo } = {}

local function buildJumbotrons(parent: Instance)
	table.clear(jumbos)
	pcall(function()
		local tiers, tierD = 6, 5
		local standBase = RUNOFF + WALL_T
		local behind = standBase + tiers * tierD + 10
		local y = FIELD.GroundY + 32
		for _, ez in ipairs({ FIELD.MaxZ + behind, FIELD.MinZ - behind }) do
			local pos = Vector3.new(CX, y, ez)
			local cf = CFrame.lookAt(pos, Vector3.new(CX, y - 5, CZ))
			local frame = block("JumboFrame", Vector3.new(32, 16, 1.6), cf, Color3.fromRGB(24, 27, 34), parent)
			frame.Material = Enum.Material.Metal
			for _, lx in ipairs({ -13, 13 }) do
				block("JumboLeg", Vector3.new(1.6, y - FIELD.GroundY, 1.6),
					CFrame.new(CX + lx, FIELD.GroundY + (y - FIELD.GroundY) / 2, ez), Color3.fromRGB(45, 49, 58), parent)
			end
			local screen = block("JumboScreen", Vector3.new(29, 13.4, 0.5), cf * CFrame.new(0, 0.4, -0.9), Color3.fromRGB(8, 10, 14), parent)
			screen.Material = Enum.Material.SmoothPlastic
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.CanvasSize = Vector2.new(1160, 540)
			gui.LightInfluence = 0
			gui.Brightness = 2
			gui.Parent = screen
			local function label(yFrac: number, hFrac: number, size: number, color: Color3): TextLabel
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.Position = UDim2.fromScale(0.02, yFrac)
				l.Size = UDim2.fromScale(0.96, hFrac)
				l.Font = Enum.Font.GothamBlack
				l.TextScaled = true
				l.TextColor3 = color
				l.RichText = true
				l.Text = ""
				local cap = Instance.new("UITextSizeConstraint")
				cap.MaxTextSize = size
				cap.Parent = l
				l.Parent = gui
				return l
			end
			jumbos[#jumbos + 1] = {
				score = label(0.03, 0.5, 190, Color3.fromRGB(255, 255, 255)),
				clock = label(0.55, 0.26, 100, Color3.fromRGB(120, 235, 130)),
				ticker = label(0.82, 0.16, 64, Color3.fromRGB(245, 196, 60)),
			}
		end
	end)
end

local function hex(c: Color3?): string
	if not c then
		return "FFFFFF"
	end
	return string.format("%02X%02X%02X",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

function WorldService.updateScoreboards(snap: any)
	pcall(function()
		local scoreText = string.format(
			'<font color="#%s">%s</font>  %d - %d  <font color="#%s">%s</font>',
			hex(snap.redColor), tostring(snap.redName or "RED"), tonumber(snap.red) or 0,
			tonumber(snap.blue) or 0, hex(snap.blueColor), tostring(snap.blueName or "BLUE"))
		local phase = tostring(snap.phase or "Waiting")
		local clockText: string
		if phase == "Playing" or phase == "Countdown" then
			local half = tonumber(snap.half) or 1
			local halfLabel = (half >= 3 and "GOLDEN GOAL") or (half == 2 and "2ND HALF") or "1ST HALF"
			local t = math.max(0, tonumber(snap.timeLeft) or 0)
			clockText = string.format("%s   %d:%02d", halfLabel, math.floor(t / 60), t % 60)
		elseif phase == "HalfTime" then
			clockText = "HALF TIME"
		elseif phase == "Finished" then
			clockText = tostring(snap.result or "FULL TIME")
		else
			clockText = "NEXT MATCH COMING UP"
		end
		local tickerText = tostring(snap.roundLabel or "GNARLY NUTMEG  •  ATHLETE DOMAINS ARENA")
		for _, j in ipairs(jumbos) do
			j.score.Text = scoreText
			j.clock.Text = clockText
			j.ticker.Text = tickerText
		end
	end)
end

-- Two roofed dugouts flanking halfway on the west touchline, each with a
-- row of seated subs in team colours (same imposter style as the crowd).
local function buildDugouts(parent: Instance)
	pcall(function()
		local x = FIELD.MinX - RUNOFF * 0.55
		local benches = {
			{ z = CZ - 17, color = Color3.fromRGB(175, 55, 55) },
			{ z = CZ + 17, color = Color3.fromRGB(50, 80, 170) },
		}
		for _, b in ipairs(benches) do
			block("DugoutBack", Vector3.new(0.8, 5.4, 15), CFrame.new(x - 2.4, FIELD.GroundY + 2.7, b.z), Color3.fromRGB(38, 42, 52), parent)
			block("DugoutSideA", Vector3.new(4.6, 5.4, 0.8), CFrame.new(x - 0.3, FIELD.GroundY + 2.7, b.z - 7.5), Color3.fromRGB(38, 42, 52), parent)
			block("DugoutSideB", Vector3.new(4.6, 5.4, 0.8), CFrame.new(x - 0.3, FIELD.GroundY + 2.7, b.z + 7.5), Color3.fromRGB(38, 42, 52), parent)
			local roof = block("DugoutRoof", Vector3.new(5.4, 0.35, 16), CFrame.new(x - 0.2, FIELD.GroundY + 5.6, b.z), Color3.fromRGB(190, 215, 240), parent)
			roof.Material = Enum.Material.Glass
			roof.Transparency = 0.35
			local seat = block("DugoutBench", Vector3.new(2.0, 1.0, 13), CFrame.new(x - 1.2, FIELD.GroundY + 0.9, b.z), Color3.fromRGB(70, 75, 88), parent)
			seat.Material = Enum.Material.SmoothPlastic
			for i = 1, 4 do
				local sz = b.z - 4.5 + (i - 1) * 3
				local torso = block("SubTorso", Vector3.new(1.5, 1.7, 1.0), CFrame.new(x - 1.2, FIELD.GroundY + 2.3, sz), b.color, parent)
				torso.CanCollide = false
				torso.CastShadow = false
				local head = block("SubHead", Vector3.new(0.9, 0.9, 0.9), CFrame.new(x - 1.2, FIELD.GroundY + 3.6, sz), Color3.fromRGB(232, 190, 152), parent)
				head.CanCollide = false
				head.CastShadow = false
			end
		end
	end)
end

-- ---- Meshy hero props ---------------------------------------------------------
-- Generated stadium dressing (tools/mesh_pipeline; ids in props_uploaded.json).
-- Loaded by id at boot, normalised to a target height, anchored, decorative
-- only. id = 0 means not uploaded yet — silently skipped. Raw Meshy meshes
-- face -Z, so aiming uses lookAt * 180° yaw (the facing contract from Squishy).
-- (an entrance-arch prop was generated twice and failed visual QC twice —
-- dropped; the plaza is the mascot's. A parts-built gate can come later.)
local PROP_IDS = {
	tvCamera = 127716077350497,
	mascotStatue = 102627059380175,
}

local function loadProp(id: number, targetHeight: number): Model?
	if id == 0 then
		return nil
	end
	local model: Model? = nil
	pcall(function()
		local InsertService = game:GetService("InsertService")
		local container = InsertService:LoadAsset(id)
		local m = container:FindFirstChildOfClass("Model") or container
		local first = m:FindFirstChildWhichIsA("BasePart", true)
		if not first then
			return
		end
		if not m.PrimaryPart then
			(m :: Model).PrimaryPart = first
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CastShadow = false
			end
		end
		local extents = (m :: Model):GetExtentsSize()
		if extents.Y > 0.01 then
			(m :: Model):ScaleTo(targetHeight / extents.Y)
		end
		m.Parent = nil
		model = m :: Model
	end)
	return model
end

-- tilt: per-prop axis correction (some Meshy FBX exports arrive Z-up — the
-- mascot needed a +90° pitch, found empirically in the live place).
-- snapToGround: drop the model so its bounding box sits on the grass.
local function placeProp(id: number, targetHeight: number, cf: CFrame, parent: Instance, tilt: CFrame?, snapToGround: boolean?)
	pcall(function()
		local m = loadProp(id, targetHeight)
		if not m then
			return
		end
		-- Meshy meshes face -Z: flip so the prop's face follows the lookAt
		m:PivotTo(cf * CFrame.Angles(0, math.rad(180), 0) * (tilt or CFrame.identity))
		m.Parent = parent
		if snapToGround then
			local ext = m:GetExtentsSize()
			local bb = m:GetBoundingBox()
			local bottomY = bb.Position.Y - ext.Y / 2
			m:PivotTo(m:GetPivot() + Vector3.new(0, FIELD.GroundY - bottomY, 0))
		end
	end)
end

local function buildHeroProps(parent: Instance)
	pcall(function()
		local standBase = RUNOFF + WALL_T
		-- broadcast cameras atop the two side stands, trained on the centre spot
		local camY = FIELD.GroundY + 24
		for _, sx in ipairs({ -1, 1 }) do
			local x = (sx > 0 and FIELD.MaxX or FIELD.MinX) + sx * (standBase + 18)
			local pos = Vector3.new(x, camY, CZ)
			placeProp(PROP_IDS.tvCamera, 6, CFrame.lookAt(pos, Vector3.new(0, FIELD.GroundY + 2, 0)), parent)
		end
		-- the stadium plaza beyond the -Z end: the club mascot greets arrivals
		-- (offset clear of the jumbotron legs; faces the stadium; Z-up export
		-- needs the +90° pitch — orientation verified live 2026-06-12)
		placeProp(
			PROP_IDS.mascotStatue,
			16,
			CFrame.new(CX - 34, FIELD.GroundY + 20, FIELD.MinZ - 68),
			parent,
			CFrame.Angles(math.rad(90), 0, 0),
			true
		)
	end)
end

-- After a goal the floodlights pulse the scoring team's colour, then settle
-- back to broadcast white (wired from MatchService's goal flow).
function WorldService.goalLightShow(color: Color3)
	pcall(function()
		local TweenService = game:GetService("TweenService")
		local pitch = Workspace:FindFirstChild("Pitch")
		if not pitch then
			return
		end
		for _, lamp in ipairs(pitch:GetChildren()) do
			if lamp.Name == "FloodLamp" then
				local light = lamp:FindFirstChildOfClass("SpotLight")
				if light then
					light.Color = color
					light.Brightness = 5.5
					TweenService:Create(light, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Brightness = 3,
						Color = Color3.fromRGB(255, 250, 235),
					}):Play()
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
	buildCrowd(pitch)
	buildCornerFlags(pitch)
	buildHoardings(pitch)
	buildJumbotrons(pitch)
	buildDugouts(pitch)
	buildHeroProps(pitch)
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
