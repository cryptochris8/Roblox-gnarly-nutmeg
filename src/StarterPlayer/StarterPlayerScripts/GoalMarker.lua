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
local part, label

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
	bb.Size = UDim2.fromOffset(150, 60)
	bb.MaxDistance = 320 -- the pitch is 240 long; keep it visible from anywhere
	bb.Parent = part

	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "⬇ SCORE"
	label.TextColor3 = Color3.fromRGB(245, 196, 60)
	label.TextStrokeColor3 = Color3.fromRGB(20, 22, 28)
	label.TextStrokeTransparency = 0.3
	label.Parent = bb

	RunService.RenderStepped:Connect(function()
		if label and label.Parent then
			label.TextTransparency = 0.1 + 0.18 * (0.5 + 0.5 * math.sin(os.clock() * 2.6))
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
		if label then
			label.Visible = false
		end
		return
	end
	ensure()
	label.Visible = true
	local targetZ = (team == "Blue") and FIELD.MaxZ or FIELD.MinZ
	part.Position = Vector3.new(FIELD.CenterX, FIELD.GroundY + GOAL.Height + 6, targetZ)
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
