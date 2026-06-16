-- CornerUI (client)
-- The pick-a-target corner aimer, shown ONLY when it's your corner to take. Pick a
-- delivery — NEAR POST / FAR POST / SPOT / SHORT — then HOLD the cross button to
-- power the ball up and release to whip it in. One delivery; the server plants the
-- ball at the flag, so this never dribbles. Mirrors PenaltyUI: it hides the normal
-- touch controls while it's up so the screen stays clear for the moment.

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

local CornerUI = {}

-- the four targets in screen order, each a big glyph + word so a non-reader still
-- gets it. `id` is what we send the server.
local TARGETS = {
	{ id = "near", glyph = "🥅", label = "NEAR POST" },
	{ id = "spot", glyph = "⊕", label = "THE SPOT" },
	{ id = "far", glyph = "🥅", label = "FAR POST" },
	{ id = "short", glyph = "👟", label = "SHORT" },
}

local gui, prompt, powerFill, kickBtn
local targetBtns: { [string]: TextButton } = {}
local selected = "spot"
local charging = false
local chargeStart = 0
local kicked = false

-- Hide/show our own on-screen touch controls so they don't compete with the aimer.
local function setTouchControls(on: boolean)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touch = pg and pg:FindFirstChild("GnarlyTouch")
	if touch and touch:IsA("ScreenGui") then
		touch.Enabled = on
	end
end

local function selectTarget(id: string)
	selected = id
	for k, btn in pairs(targetBtns) do
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
		kickBtn.Text = "⚽ WHIPPED IN!"
		kickBtn.BackgroundColor3 = C.Track
	end
	Remotes.get(Remotes.RequestCornerKick):FireServer(selected, power)
end

function CornerUI.mount(playerGui)
	local touch = UserInputService.TouchEnabled
	gui = UiTheme.make("ScreenGui", {
		Name = "GnarlyCorner",
		ResetOnSpawn = false,
		DisplayOrder = 9,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = playerGui,
	})

	prompt = UiTheme.make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.fromOffset(640, 34),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = touch and 18 or 22,
		TextColor3 = GOLD,
		Text = "⛳ CORNER!  Pick a target — then HOLD to whip it in!",
		Parent = gui,
	})
	UiTheme.stroke(C.Ink, 2, prompt)

	-- a centred row of four big target buttons
	local row = UiTheme.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.32, 0),
		Size = UDim2.fromOffset(touch and 560 or 640, touch and 92 or 104),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, touch and 10 or 14)
	layout.Parent = row

	for i, t in ipairs(TARGETS) do
		local w = touch and 128 or 148
		local b = UiTheme.make("TextButton", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(w, touch and 88 or 100),
			BackgroundColor3 = C.PanelDark,
			BackgroundTransparency = 0.08,
			Font = UiTheme.Header,
			TextSize = touch and 18 or 20,
			TextColor3 = C.Panel,
			Text = t.glyph .. "\n" .. t.label,
			AutoButtonColor = true,
			Parent = row,
		})
		UiTheme.corner(14, b)
		UiTheme.stroke(GOLD, 1, b)
		b.MouseButton1Click:Connect(function()
			if not kicked then
				selectTarget(t.id)
			end
		end)
		targetBtns[t.id] = b
	end

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
		Text = "HOLD TO CROSS",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(14, kickBtn)

	-- press to charge, release (anywhere — a finger can slide off) to deliver
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
	-- desktop: 1-4 keys (or arrows) pick a target fast
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or kicked or not gui or not gui.Enabled then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.One then
			selectTarget("near")
		elseif k == Enum.KeyCode.Two then
			selectTarget("spot")
		elseif k == Enum.KeyCode.Three then
			selectTarget("far")
		elseif k == Enum.KeyCode.Four then
			selectTarget("short")
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

-- It's my corner: reset and show.
function CornerUI.show()
	if not gui then
		return
	end
	kicked = false
	charging = false
	if powerFill then
		powerFill.Size = UDim2.new(0, 0, 1, 0)
	end
	if kickBtn then
		kickBtn.Text = "HOLD TO CROSS"
		kickBtn.BackgroundColor3 = C.Red
	end
	selectTarget("spot")
	setTouchControls(false)
	gui.Enabled = true
end

function CornerUI.hide()
	charging = false
	if gui then
		gui.Enabled = false
	end
	setTouchControls(true)
end

return CornerUI
