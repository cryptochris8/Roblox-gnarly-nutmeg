-- GoalMarker (client)
-- A subtle world-space "⬇ SCORE" tag floating over the goal YOU attack, so a
-- new player — or a 6-year-old — instantly knows which way to score. It lives
-- in the WORLD at the goal end (not on the HUD), so it never clutters the play
-- screen. Client-only: each player sees only their own target.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local FIELD = GameConfig.Field
local GOAL = GameConfig.Goal

local GoalMarker = {}

local player = Players.LocalPlayer
local part, label, billboard
local baseY = 0 -- the marker's resting height; RenderStepped bobs the part around it

local function ensure()
	if part then
		return
	end
	part = Instance.new("Part")
	part.Name = "GNGoalMarker"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Name = "Marker"
	bb.Size = UDim2.fromOffset(190, 104)
	bb.MaxDistance = 320 -- the pitch is 240 long; keep it visible from anywhere
	bb.Parent = part
	billboard = bb

	-- A solid dark PILL behind the text — the old gold-on-green pulsing label was
	-- the least legible thing on screen, yet it's the only "which way do I score"
	-- cue. The pill gives constant contrast; a gentle bob (below) draws the eye
	-- instead of a transparency flicker (which read as broken to young players).
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.Size = UDim2.fromOffset(190, 58)
	pill.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	pill.BackgroundTransparency = 0.12
	pill.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(245, 196, 60)
	stroke.Thickness = 2.5
	stroke.Parent = pill

	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "SCORE HERE"
	label.TextColor3 = Color3.fromRGB(245, 196, 60)
	label.TextStrokeColor3 = Color3.fromRGB(20, 22, 28)
	label.TextStrokeTransparency = 0.2
	label.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = label

	-- a big arrow under the pill, pointing down at the actual goal mouth
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 1)
	arrow.Position = UDim2.fromScale(0.5, 1)
	arrow.Size = UDim2.fromOffset(60, 44)
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.Text = "▼"
	arrow.TextColor3 = Color3.fromRGB(245, 196, 60)
	arrow.TextStrokeColor3 = Color3.fromRGB(20, 22, 28)
	arrow.TextStrokeTransparency = 0.2
	arrow.Parent = bb

	RunService.RenderStepped:Connect(function()
		if part and part.Parent then
			part.Position = Vector3.new(part.Position.X, baseY + 1.4 * math.sin(os.clock() * 2.2), part.Position.Z)
		end
	end)
end

-- Position the marker over the goal the local player attacks (Blue defends the
-- -Z end so attacks +Z; Red the reverse). Hidden until the team is known.
function GoalMarker.refresh()
	local team = (player.Team and player.Team.Name) or nil
	if not team then
		local char = player.Character
		team = char and (char:GetAttribute("Team") :: string?) or nil
	end
	if team ~= "Red" and team ~= "Blue" then
		if billboard then
			billboard.Enabled = false
		end
		return
	end
	ensure()
	billboard.Enabled = true
	local targetZ = (team == "Blue") and FIELD.MaxZ or FIELD.MinZ
	baseY = FIELD.GroundY + GOAL.Height + 6
	part.Position = Vector3.new(FIELD.CenterX, baseY, targetZ)
end

function GoalMarker.init()
	player.CharacterAdded:Connect(function()
		task.wait(1)
		GoalMarker.refresh()
	end)
	pcall(function()
		player:GetPropertyChangedSignal("Team"):Connect(GoalMarker.refresh)
	end)
	task.delay(2.5, GoalMarker.refresh)
end

return GoalMarker
