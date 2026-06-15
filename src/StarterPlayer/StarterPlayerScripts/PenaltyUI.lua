-- PenaltyUI (client)
-- The pick-a-corner penalty aimer, shown ONLY when it's your shootout kick. Pick
-- left / centre / right, then HOLD the shoot button to power up and release to
-- strike. One kick — the server plants the ball, so this never dribbles. The rest
-- of the time it's hidden, and it hides the normal touch controls while it's up so
-- the screen stays clear for the moment.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local UiTheme = require(script.Parent.UiTheme)
local C = UiTheme.Colors
local GOLD = Color3.fromRGB(245, 196, 60)
local CHARGE_TIME = 1.2

local PenaltyUI = {}

local gui, prompt, powerFill, kickBtn
local cornerBtns: { [number]: TextButton } = {}
local selected = 0 -- -1 left / 0 centre / 1 right
local charging = false
local chargeStart = 0
local kicked = false

-- Hide/show our own on-screen touch controls so they don't compete with the kick UI.
local function setTouchControls(on: boolean)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touch = pg and pg:FindFirstChild("GnarlyTouch")
	if touch and touch:IsA("ScreenGui") then
		touch.Enabled = on
	end
end

local function selectCorner(c: number)
	selected = math.clamp(c, -1, 1)
	for k, btn in pairs(cornerBtns) do
		local on = (k == selected)
		btn.BackgroundColor3 = on and GOLD or C.PanelDark
		btn.TextColor3 = on and C.Ink or C.Panel
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = on and 4 or 1
		end
	end
end

local function fire()
	if kicked then
		return
	end
	local power = math.clamp((os.clock() - chargeStart) / CHARGE_TIME, 0.15, 1)
	charging = false
	kicked = true
	if kickBtn then
		kickBtn.Text = "⚽ STRUCK!"
		kickBtn.BackgroundColor3 = C.Track
	end
	Remotes.get(Remotes.RequestPenaltyKick):FireServer(selected, power)
end

function PenaltyUI.mount(playerGui)
	local touch = UserInputService.TouchEnabled
	gui = UiTheme.make("ScreenGui", {
		Name = "GnarlyPenalty",
		ResetOnSpawn = false,
		DisplayOrder = 9,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = playerGui,
	})

	prompt = UiTheme.make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.13, 0),
		Size = UDim2.fromOffset(620, 34),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = touch and 18 or 22,
		TextColor3 = GOLD,
		Text = "⚽ PICK A CORNER  —  then HOLD to power up!",
		Parent = gui,
	})
	UiTheme.stroke(C.Ink, 2, prompt)

	local function cornerButton(c: number, xScale: number)
		local size = touch and 76 or 92
		local b = UiTheme.make("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(xScale, 0, 0.33, 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = C.PanelDark,
			BackgroundTransparency = 0.1,
			Font = UiTheme.Header,
			TextSize = 30,
			TextColor3 = C.Panel,
			Text = "◎",
			AutoButtonColor = true,
			Parent = gui,
		})
		UiTheme.corner(14, b)
		UiTheme.stroke(GOLD, 1, b)
		b.MouseButton1Click:Connect(function()
			if not kicked then
				selectCorner(c)
			end
		end)
		cornerBtns[c] = b
	end
	cornerButton(-1, 0.34)
	cornerButton(0, 0.5)
	cornerButton(1, 0.66)

	local powerBg = UiTheme.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, touch and -122 or -118),
		Size = UDim2.fromOffset(280, 18),
		BackgroundColor3 = C.Track,
		Parent = gui,
	})
	UiTheme.corner(9, powerBg)
	powerFill = UiTheme.make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(120, 210, 120),
		Parent = powerBg,
	})
	UiTheme.corner(9, powerFill)

	kickBtn = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, touch and -42 or -46),
		Size = UDim2.fromOffset(280, 64),
		BackgroundColor3 = C.Red,
		Font = UiTheme.Header,
		TextSize = 22,
		TextColor3 = C.Panel,
		Text = "HOLD TO SHOOT",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(14, kickBtn)

	-- press to charge, release (anywhere — a finger can slide off) to strike
	kickBtn.MouseButton1Down:Connect(function()
		if kicked then
			return
		end
		charging = true
		chargeStart = os.clock()
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not charging or kicked then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			fire()
		end
	end)
	-- desktop: arrow / A-D nudges the corner marker
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or kicked or not gui or not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			selectCorner(selected - 1)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			selectCorner(selected + 1)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if charging and powerFill then
			local p = math.clamp((os.clock() - chargeStart) / CHARGE_TIME, 0, 1)
			powerFill.Size = UDim2.new(p, 0, 1, 0)
			powerFill.BackgroundColor3 = (p > 0.85) and Color3.fromRGB(255, 170, 70) or Color3.fromRGB(120, 210, 120)
		end
	end)
end

-- It's my kick: reset and show.
function PenaltyUI.show()
	if not gui then
		return
	end
	kicked = false
	charging = false
	if powerFill then
		powerFill.Size = UDim2.new(0, 0, 1, 0)
	end
	if kickBtn then
		kickBtn.Text = "HOLD TO SHOOT"
		kickBtn.BackgroundColor3 = C.Red
	end
	selectCorner(0)
	setTouchControls(false)
	gui.Enabled = true
end

function PenaltyUI.hide()
	charging = false
	if gui then
		gui.Enabled = false
	end
	setTouchControls(true)
end

return PenaltyUI
