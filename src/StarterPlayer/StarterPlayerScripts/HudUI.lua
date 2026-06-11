-- HudUI (client)
-- The in-match HUD: scoreboard + clock, stamina bar, shot charge meter, a big
-- kickoff countdown, a goal flash, a possession chip, toasts, and the full-time
-- result banner. All driven by the server via ClientController.

local TweenService = game:GetService("TweenService")

local UiTheme = require(script.Parent.UiTheme)
local C = UiTheme.Colors

local HudUI = {}

local gui
local scoreLabel, timerLabel, phaseLabel
local scoreScale
local staminaFill
local chargeHolder, chargeFill
local countdownLabel
local goalFrame, goalLabel
local megLabel
local toastLabel
local resultFrame, resultLabel
local ballChip

local function fmtClock(t)
	t = math.max(0, math.floor(t))
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function HudUI.mount(playerGui)
	gui = UiTheme.make("ScreenGui", {
		Name = "GnarlyHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})

	-- Scoreboard panel (top centre)
	local panel = UiTheme.make("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(380, 84),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.1,
		Parent = gui,
	})
	UiTheme.corner(16, panel)
	UiTheme.stroke(Color3.fromRGB(0, 0, 0), 2, panel).Transparency = 0.6
	scoreScale = Instance.new("UIScale")
	scoreScale.Parent = panel

	scoreLabel = UiTheme.make("TextLabel", {
		Name = "Score",
		BackgroundTransparency = 1,
		RichText = true,
		Font = UiTheme.Header,
		TextSize = 30,
		TextColor3 = C.Panel,
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 38),
		Text = "RED  0 : 0  BLUE",
		Parent = panel,
	})
	phaseLabel = UiTheme.make("TextLabel", {
		Name = "Phase",
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 15,
		TextColor3 = C.Sub,
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(0.55, 0, 0, 26),
		Text = "Get Ready",
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})
	timerLabel = UiTheme.make("TextLabel", {
		Name = "Timer",
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 18,
		TextColor3 = C.Panel,
		Position = UDim2.new(0.55, 8, 0, 48),
		Size = UDim2.new(0.45, -8, 0, 26),
		Text = "0:00",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	-- Stamina bar (bottom left)
	local staminaBg = UiTheme.make("Frame", {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(220, 20),
		BackgroundColor3 = C.Track,
		Parent = gui,
	})
	UiTheme.corner(10, staminaBg)
	staminaFill = UiTheme.make("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.Stamina,
		Parent = staminaBg,
	})
	UiTheme.corner(10, staminaFill)
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 12,
		TextColor3 = C.Ink,
		Text = "STAMINA",
		Size = UDim2.new(1, 0, 1, 0),
		Parent = staminaBg,
	})

	-- Charge meter (bottom centre, only while charging a shot)
	chargeHolder = UiTheme.make("Frame", {
		Name = "Charge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(260, 16),
		BackgroundColor3 = C.Track,
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(8, chargeHolder)
	chargeFill = UiTheme.make("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = C.Charge,
		Parent = chargeHolder,
	})
	UiTheme.corner(8, chargeFill)

	-- Possession chip (above the stamina bar)
	ballChip = UiTheme.make("TextLabel", {
		Name = "BallChip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -46),
		Size = UDim2.fromOffset(220, 24),
		BackgroundColor3 = C.Charge,
		Font = UiTheme.Header,
		TextSize = 14,
		TextColor3 = C.Ink,
		Text = "⚽ You have the ball!",
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(8, ballChip)

	-- Big kickoff countdown
	countdownLabel = UiTheme.make("TextLabel", {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.fromOffset(220, 220),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 120,
		TextColor3 = C.Panel,
		Text = "",
		Visible = false,
		Parent = gui,
	})
	UiTheme.stroke(C.Ink, 3, countdownLabel)

	-- Goal flash overlay
	goalFrame = UiTheme.make("Frame", {
		Name = "GoalFlash",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.Red,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	goalLabel = UiTheme.make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.fromOffset(600, 120),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 84,
		TextColor3 = C.Panel,
		Text = "GOAL!",
		Visible = false,
		Parent = goalFrame,
	})
	UiTheme.stroke(C.Ink, 3, goalLabel)

	-- NUTMEG! splash (a quick flashy stamp when anyone pulls one off)
	megLabel = UiTheme.make("TextLabel", {
		Name = "NutmegSplash",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.fromOffset(520, 90),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 64,
		TextColor3 = C.Charge,
		Text = "NUTMEG!",
		Visible = false,
		Parent = gui,
	})
	UiTheme.stroke(C.Ink, 3, megLabel)

	-- Toast (under the scoreboard)
	toastLabel = UiTheme.make("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(420, 30),
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 20,
		TextColor3 = C.Panel,
		Text = "",
		Visible = false,
		Parent = gui,
	})
	UiTheme.stroke(C.Ink, 2, toastLabel)

	-- Full-time result banner
	resultFrame = UiTheme.make("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(520, 120),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(20, resultFrame)
	resultLabel = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 30,
		TextColor3 = C.Panel,
		Text = "",
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.fromOffset(12, 12),
		TextWrapped = true,
		Parent = resultFrame,
	})
end

local PHASE_TEXT = {
	Waiting = "Get Ready",
	Countdown = "Kickoff!",
	Playing = "Playing",
	GoalPause = "GOAL!",
	HalfTime = "Half Time",
	Shootout = "PENALTY SHOOTOUT",
	Finished = "Full Time",
}

function HudUI.updateMatch(snap)
	if not gui then
		return
	end
	scoreLabel.Text = string.format(
		'<font color="rgb(225,70,70)">RED</font>  %d : %d  <font color="rgb(70,110,225)">BLUE</font>',
		snap.red or 0,
		snap.blue or 0
	)
	local phase = snap.phase or "Waiting"
	local text = PHASE_TEXT[phase] or phase
	if phase == "Playing" then
		if snap.half == 3 then
			text = "⚡ GOLDEN GOAL"
		else
			text = (snap.half == 2) and "2nd Half" or "1st Half"
		end
	end
	phaseLabel.Text = text
	timerLabel.Text = fmtClock(snap.timeLeft or 0)

	if phase == "Finished" and snap.result then
		resultLabel.Text = snap.result
		resultFrame.Visible = true
	else
		resultFrame.Visible = false
	end
end

function HudUI.countdown(n)
	if not gui then
		return
	end
	if n and n > 0 then
		countdownLabel.Text = tostring(n)
		countdownLabel.Visible = true
		countdownLabel.TextTransparency = 0
	else
		countdownLabel.Text = "GO!"
		countdownLabel.Visible = true
		task.delay(0.7, function()
			countdownLabel.Visible = false
		end)
	end
end

function HudUI.goal(info)
	if not gui then
		return
	end
	local team = info and info.team or ""
	goalFrame.BackgroundColor3 = (team == "Red") and C.Red or C.Blue
	goalLabel.Text = string.upper(team) .. " GOAL!"
	if info and info.scorer then
		HudUI.toast("⚽ " .. tostring(info.scorer) .. " scores!")
	end
	-- score bug pop
	if scoreScale then
		scoreScale.Scale = 1.25
		TweenService:Create(scoreScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	goalLabel.Visible = true
	goalFrame.BackgroundTransparency = 0.45
	TweenService:Create(goalFrame, TweenInfo.new(0.3), { BackgroundTransparency = 0.7 }):Play()
	task.delay(2.4, function()
		goalLabel.Visible = false
		TweenService:Create(goalFrame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	end)
end

function HudUI.nutmeg(info)
	if not gui then
		return
	end
	local name = info and info.name or "Someone"
	megLabel.Rotation = -8
	megLabel.Visible = true
	TweenService:Create(
		megLabel,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = 0 }
	):Play()
	HudUI.toast(name .. " pulled off a NUTMEG! 🔥")
	task.delay(1.6, function()
		megLabel.Visible = false
	end)
end

function HudUI.stamina(frac)
	if not staminaFill then
		return
	end
	frac = math.clamp(frac or 1, 0, 1)
	staminaFill.Size = UDim2.new(frac, 0, 1, 0)
	staminaFill.BackgroundColor3 = (frac < 0.25) and C.Charge or C.Stamina
end

function HudUI.setCharge(frac)
	if not chargeHolder then
		return
	end
	frac = math.clamp(frac or 0, 0, 1)
	if frac <= 0 then
		chargeHolder.Visible = false
		chargeFill.Size = UDim2.new(0, 0, 1, 0)
	else
		chargeHolder.Visible = true
		chargeFill.Size = UDim2.new(frac, 0, 1, 0)
		-- past the sweet spot the shot balloons — warn with a red meter
		chargeFill.BackgroundColor3 = (frac > 0.85) and Color3.fromRGB(235, 80, 60) or C.Charge
	end
end

function HudUI.possession(mine)
	if ballChip then
		ballChip.Visible = mine and true or false
	end
end

function HudUI.toast(text)
	if not toastLabel then
		return
	end
	toastLabel.Text = text or ""
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	task.delay(2.6, function()
		if toastLabel.Text == text then
			toastLabel.Visible = false
		end
	end)
end

return HudUI
