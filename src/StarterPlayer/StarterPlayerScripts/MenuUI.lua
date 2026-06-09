-- MenuUI (client)
-- A compact team-picker (applies between matches) plus a controls hint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local UiTheme = require(script.Parent.UiTheme)
local C = UiTheme.Colors

local MenuUI = {}

function MenuUI.mount(playerGui)
	local gui = UiTheme.make("ScreenGui", {
		Name = "GnarlyMenu",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		Parent = playerGui,
	})

	local panel = UiTheme.make("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 18, 0, 18),
		Size = UDim2.fromOffset(184, 96),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.15,
		Parent = gui,
	})
	UiTheme.corner(14, panel)

	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 14,
		TextColor3 = C.Panel,
		Text = "PICK YOUR TEAM",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = panel,
	})

	local selectEvent = Remotes.get(Remotes.SelectTeam)

	local function teamButton(name, color, x)
		local b = UiTheme.make("TextButton", {
			Position = UDim2.fromOffset(x, 34),
			Size = UDim2.fromOffset(78, 46),
			BackgroundColor3 = color,
			Font = UiTheme.Header,
			TextSize = 18,
			TextColor3 = C.Panel,
			Text = name,
			AutoButtonColor = true,
			Parent = panel,
		})
		UiTheme.corner(12, b)
		b.MouseButton1Click:Connect(function()
			selectEvent:FireServer(name)
		end)
		return b
	end

	teamButton("RED", C.Red, 12)
	teamButton("BLUE", C.Blue, 94)

	-- Desktop controls hint (hidden on touch devices, which have on-screen buttons)
	if not UserInputService.TouchEnabled then
		UiTheme.make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -44),
			Size = UDim2.fromOffset(560, 22),
			BackgroundTransparency = 1,
			Font = UiTheme.Body,
			TextSize = 15,
			TextColor3 = C.Panel,
			Text = "Hold LMB = Shoot   •   E = Pass   •   F = Tackle   •   Shift = Sprint",
			Parent = gui,
		}).TextStrokeTransparency = 0.4
	end
end

return MenuUI
