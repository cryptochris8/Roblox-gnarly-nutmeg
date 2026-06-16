-- InputController (client)
-- Reads input and forwards INTENTS to the server over RemoteEvents (the server
-- validates + acts). Movement uses the built-in Humanoid controller. Bindings use
-- ContextActionService so mobile gets on-screen touch buttons for free, and
-- gamepad works too.
--   Shoot  : hold LMB / R2 / touch -> charge, release to fire
--   Pass   : E / L1 / touch
--   Tackle : F / X / touch
--   Nutmeg : Q / Y / touch (poke the ball through a close defender)
--   Sprint : LeftShift / L2 / touch (hold)
--   Skills : R = Elastico Dash, T = Roulette, G = Rainbow Flick (level-gated
--            server-side; locked presses get a teaching toast)

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Skills = require(Shared:WaitForChild("Skills"))

local InputController = {}

local CHARGE_SECONDS = GameConfig.Kick.ChargeSeconds
local passEvent, shootEvent, tackleEvent, nutmegEvent, sprintEvent, skillEvent
local chargeStart = nil
local hudRef = nil

-- The roulette spin is played by US (the client owns its character's physics;
-- a server-driven per-frame spin would stutter). The server grants the actual
-- tackle immunity.
local function spinLocal()
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	task.spawn(function()
		hum.AutoRotate = false
		local t0 = os.clock()
		local startCf = root.CFrame - root.CFrame.Position
		while os.clock() - t0 < 0.45 do
			local a = math.clamp((os.clock() - t0) / 0.45, 0, 1) * math.pi * 2
			root.CFrame = CFrame.new(root.Position) * startCf * CFrame.Angles(0, a, 0)
			task.wait()
		end
		hum.AutoRotate = true
	end)
end

local function onPass(_, state)
	if state == Enum.UserInputState.Begin then
		passEvent:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function onTackle(_, state)
	if state == Enum.UserInputState.Begin then
		tackleEvent:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function onNutmeg(_, state)
	if state == Enum.UserInputState.Begin then
		nutmegEvent:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function onSprint(_, state)
	if state == Enum.UserInputState.Begin then
		sprintEvent:FireServer(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		sprintEvent:FireServer(false)
	end
	return Enum.ContextActionResult.Pass
end

local function onShoot(_, state)
	if state == Enum.UserInputState.Begin then
		chargeStart = os.clock()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if chargeStart then
			local frac = math.clamp((os.clock() - chargeStart) / CHARGE_SECONDS, 0, 1)
			shootEvent:FireServer(frac)
			chargeStart = nil
			if hudRef then
				hudRef.setCharge(0)
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

-- glyph + word so a non-reader can still tell the skills apart
local TOUCH_TITLES =
	{ elastico = "💫\nDash", roulette = "🌀\nSpin", rainbow = "🌈\nFlick", chop = "✂\nChop", fakeshot = "🎭\nFake" }

-- CUSTOM TOUCH CONTROLS: a deliberate bottom-right thumb-fan (Shoot at the
-- corner, the core four on an arc) plus skill buttons that appear ONLY once
-- unlocked — a brand-new player sees a clean five-button cluster, not ten.
-- Replaces ContextActionService's auto touch buttons, which scatter
-- unpredictably across phones.
local function buildTouchControls()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "GnarlyTouch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local cam = workspace.CurrentCamera
	local shortSide = cam and math.min(cam.ViewportSize.X, cam.ViewportSize.Y) or 720
	local phone = shortSide < 600
	-- bigger targets + a wider arc so the enlarged buttons don't crowd (the 6-8yo
	-- audience has small hands; word-only circles were also unreadable to non-readers)
	local R = phone and 140 or 170
	local shootPx = phone and 92 or 110
	local corePx = phone and 70 or 82
	local skillPx = phone and 58 or 64
	local cx, cy = -92, -92 -- Shoot centre, offset from the bottom-right corner

	local function makeBtn(label, sizePx, offX, offY, bg)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(1, offX, 1, offY)
		b.Size = UDim2.fromOffset(sizePx, sizePx)
		b.BackgroundColor3 = bg or Color3.fromRGB(28, 32, 42)
		b.BackgroundTransparency = 0.18
		b.Text = label
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.TextColor3 = Color3.fromRGB(245, 247, 252)
		b.TextStrokeTransparency = 0.5
		b.AutoButtonColor = true
		Instance.new("UICorner").Parent = b
		local cc = b:FindFirstChildOfClass("UICorner")
		if cc then cc.CornerRadius = UDim.new(1, 0) end
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.08, 0)
		pad.PaddingRight = UDim.new(0.08, 0)
		pad.PaddingTop = UDim.new(0.14, 0)
		pad.PaddingBottom = UDim.new(0.14, 0)
		pad.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.72
		stroke.Thickness = 1.5
		stroke.Parent = b
		b.Parent = gui
		return b
	end

	local function touchOf(input)
		return input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
	end
	local function onTap(btn, fn)
		btn.InputBegan:Connect(function(input)
			if touchOf(input) then
				fn()
			end
		end)
	end
	local function onHold(btn, down, up)
		btn.InputBegan:Connect(function(input)
			if not touchOf(input) then
				return
			end
			down()
			local conn
			conn = UserInputService.InputEnded:Connect(function(ended)
				if ended == input then
					up()
					conn:Disconnect()
				end
			end)
		end)
	end

	-- core fan
	local shoot = makeBtn("⚽\nSHOOT", shootPx, cx, cy, Color3.fromRGB(70, 150, 95))
	onHold(shoot, function()
		onShoot(nil, Enum.UserInputState.Begin)
	end, function()
		onShoot(nil, Enum.UserInputState.End)
	end)
	local function arc(deg)
		return cx - R * math.cos(math.rad(deg)), cy - R * math.sin(math.rad(deg))
	end
	local ax, ay = arc(0)
	onTap(makeBtn("👟\nPASS", corePx, ax, ay), function()
		onPass(nil, Enum.UserInputState.Begin)
	end)
	ax, ay = arc(30)
	onTap(makeBtn("🛡\nTACKLE", corePx, ax, ay), function()
		onTackle(nil, Enum.UserInputState.Begin)
	end)
	ax, ay = arc(60)
	onTap(makeBtn("✨\nNUTMEG", corePx, ax, ay), function()
		onNutmeg(nil, Enum.UserInputState.Begin)
	end)
	ax, ay = arc(90)
	local sprint = makeBtn("🏃\nSPRINT", corePx, ax, ay, Color3.fromRGB(60, 95, 130))
	onHold(sprint, function()
		onSprint(nil, Enum.UserInputState.Begin)
	end, function()
		onSprint(nil, Enum.UserInputState.End)
	end)

	-- skills: hidden until unlocked, packed leftward in a row above the fan
	local skillY = cy - R - skillPx * 0.6 - 14
	local entries = {}
	for _, s in ipairs(Skills.List) do
		local b = makeBtn(TOUCH_TITLES[s.id] or s.id, skillPx, -64, skillY, Color3.fromRGB(50, 80, 120))
		b.Visible = false
		onTap(b, function()
			skillEvent:FireServer(s.id)
			if s.id == "roulette" then
				spinLocal()
			end
		end)
		entries[#entries + 1] = { btn = b, skill = s }
	end
	local function layoutSkills(level)
		local slot = 0
		for _, e in ipairs(entries) do
			if level >= e.skill.unlockLevel then
				e.btn.Visible = true
				e.btn.Position = UDim2.new(1, -64 - slot * (skillPx + 12), 1, skillY)
				slot += 1
			else
				e.btn.Visible = false
			end
		end
	end
	layoutSkills(1)
	Remotes.get(Remotes.ProgressionSync).OnClientEvent:Connect(function(data)
		layoutSkills(tonumber(data and data.level) or 1)
	end)
end

function InputController.start(hud)
	hudRef = hud
	passEvent = Remotes.get(Remotes.RequestPass)
	shootEvent = Remotes.get(Remotes.RequestShoot)
	tackleEvent = Remotes.get(Remotes.RequestTackle)
	nutmegEvent = Remotes.get(Remotes.RequestNutmeg)
	sprintEvent = Remotes.get(Remotes.SetSprint)
	skillEvent = Remotes.get(Remotes.RequestSkill)

	-- Bindings drive keyboard + gamepad; touch uses the custom buttons below
	-- (createTouchButton = false so CAS never spawns its own scattered set).
	ContextActionService:BindAction("GN_Shoot", onShoot, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("GN_Pass", onPass, false, Enum.KeyCode.E, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("GN_Tackle", onTackle, false, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("GN_Nutmeg", onNutmeg, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("GN_Sprint", onSprint, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

	for _, s in ipairs(Skills.List) do
		local id = s.id
		ContextActionService:BindAction("GN_Skill_" .. id, function(_, state)
			if state == Enum.UserInputState.Begin then
				skillEvent:FireServer(id)
				if id == "roulette" then
					spinLocal()
				end
			end
			return Enum.ContextActionResult.Pass
		end, false, s.key, s.pad)
	end

	if UserInputService.TouchEnabled then
		pcall(buildTouchControls)
	end

	-- Live-update the charge meter while holding shoot.
	RunService.RenderStepped:Connect(function()
		if chargeStart and hudRef then
			hudRef.setCharge(math.clamp((os.clock() - chargeStart) / CHARGE_SECONDS, 0, 1))
		end
	end)
end

return InputController
