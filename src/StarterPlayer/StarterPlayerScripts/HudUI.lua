-- HudUI (client)
-- The in-match HUD: scoreboard + clock, stamina bar, shot charge meter, a big
-- kickoff countdown, a goal flash, a possession chip, toasts, and the full-time
-- result banner. All driven by the server via ClientController.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Skills = require(Shared:WaitForChild("Skills"))

local UiTheme = require(script.Parent.UiTheme)
local C = UiTheme.Colors

-- The soonest NAMED reward the player hasn't reached yet (boots / trail /
-- celebration / skill), so the full-time card always dangles a concrete next goal
-- — the highest-ROI retention nudge from the eval.
local function nextUnlock(level: number)
	local best: { level: number, label: string }? = nil
	local function consider(list, emoji)
		for _, item in ipairs(list) do
			if item.unlockLevel > level and (not best or item.unlockLevel < best.level) then
				best = { level = item.unlockLevel, label = emoji .. " " .. item.name }
			end
		end
	end
	consider(Cosmetics.Boots, "👟")
	consider(Cosmetics.Trails, "✨")
	consider(Cosmetics.Celebrations, "🎉")
	consider(Skills.List, "⚡")
	return best
end

local HudUI = {}

local gui
local scoreLabel, timerLabel, phaseLabel
local scoreScale
local boardFrame, boardLabel
local xpFill, xpText, levelLabel, dingSound
local lastLevel = nil
local staminaFill
local chargeHolder, chargeFill
local countdownLabel
local goalFrame, goalLabel
local megLabel
local toastLabel
local resultFrame, resultLabel, summaryLabel
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
		TextScaled = true, -- nation names can be long (NETHERLANDS vs ARGENTINA)
		TextColor3 = C.Panel,
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 38),
		Text = "▲ RED  0 : 0  ● BLUE",
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
		Size = UDim2.new(0.92, 0, 0, 110),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextScaled = true,
		TextColor3 = C.Panel,
		Text = "GOAL!",
		Visible = false,
		Parent = goalFrame,
	})
	local goalCap = Instance.new("UITextSizeConstraint")
	goalCap.MaxTextSize = 92
	goalCap.Parent = goalLabel
	UiTheme.stroke(C.Ink, 3, goalLabel)

	-- XP bar + level (bottom right)
	local xpBg = UiTheme.make("Frame", {
		Name = "XpBar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(240, 20),
		BackgroundColor3 = C.Track,
		Parent = gui,
	})
	UiTheme.corner(10, xpBg)
	xpFill = UiTheme.make("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(245, 196, 60),
		Parent = xpBg,
	})
	UiTheme.corner(10, xpFill)
	xpText = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 12,
		TextColor3 = C.Ink,
		Text = "LV 1",
		Size = UDim2.new(1, 0, 1, 0),
		Parent = xpBg,
	})
	-- LEVEL UP! splash
	levelLabel = UiTheme.make("TextLabel", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.22, 0),
		Size = UDim2.fromOffset(520, 80),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 52,
		TextColor3 = Color3.fromRGB(245, 196, 60),
		Text = "",
		Visible = false,
		Parent = gui,
	})
	UiTheme.stroke(C.Ink, 3, levelLabel)
	dingSound = Instance.new("Sound")
	dingSound.SoundId = "rbxasset://sounds/electronicpingshort.wav" -- built-in, always available
	dingSound.Volume = 0.6
	dingSound.Parent = gui

	-- Tournament board (bracket results between matches)
	boardFrame = UiTheme.make("Frame", {
		Name = "TournamentBoard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 110),
		Size = UDim2.fromOffset(300, 250),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(14, boardFrame)
	boardLabel = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 14,
		TextColor3 = C.Panel,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 1, -20),
		Text = "",
		Parent = boardFrame,
	})

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
	-- a dark pill that hugs the text: white-on-grass was failing contrast
	toastLabel = UiTheme.make("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.15,
		Font = UiTheme.Body,
		TextSize = 20,
		TextColor3 = C.Panel,
		Text = "",
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(12, toastLabel)
	local toastPad = Instance.new("UIPadding")
	toastPad.PaddingLeft = UDim.new(0, 16)
	toastPad.PaddingRight = UDim.new(0, 16)
	toastPad.Parent = toastLabel
	local toastCap = Instance.new("UISizeConstraint")
	toastCap.MaxSize = Vector2.new(640, math.huge)
	toastCap.Parent = toastLabel
	UiTheme.stroke(C.Ink, 2, toastLabel)

	-- Full-time result banner (team line on top, your personal card below)
	resultFrame = UiTheme.make("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(540, 190),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(20, resultFrame)
	resultLabel = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 28,
		TextColor3 = C.Panel,
		Text = "",
		Size = UDim2.new(1, -24, 0, 80),
		Position = UDim2.fromOffset(12, 16),
		TextWrapped = true,
		Parent = resultFrame,
	})
	-- your own match: "+85 XP   ⚽ 2   🪄 1   •   Level 4" (set by HudUI.matchSummary)
	summaryLabel = UiTheme.make("TextLabel", {
		Name = "Summary",
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(245, 196, 60),
		Text = "",
		Visible = false,
		Size = UDim2.new(1, -24, 0, 76),
		Position = UDim2.fromOffset(12, 100),
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

-- lift dark kit colours so they stay readable on the dark scoreboard
local function vivid(c)
	return Color3.new(
		c.R + (1 - c.R) * 0.35,
		c.G + (1 - c.G) * 0.35,
		c.B + (1 - c.B) * 0.35
	)
end

local function rgbTag(c)
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

function HudUI.updateMatch(snap)
	if not gui then
		return
	end
	local redName = snap.redName or "RED"
	local blueName = snap.blueName or "BLUE"
	local redC = vivid(snap.redColor or C.Red)
	local blueC = vivid(snap.blueColor or C.Blue)
	-- a SHAPE per side (▲ red / ● blue) rides alongside the colour so the score reads
	-- with any colour vision (the two kit colours are near-equal luminance)
	scoreLabel.Text = string.format(
		'<font color="%s">▲ %s</font>  %d : %d  <font color="%s">● %s</font>',
		rgbTag(redC), redName,
		snap.red or 0,
		snap.blue or 0,
		rgbTag(blueC), blueName
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
	if snap.roundLabel and (phase == "Playing" or phase == "Countdown") then
		text = snap.roundLabel .. " — " .. text
	end
	phaseLabel.Text = text
	timerLabel.Text = fmtClock(snap.timeLeft or 0)

	-- the tournament board shows between phases of play
	if boardFrame then
		local lines = snap.board
		local quietPhase = phase == "Waiting" or phase == "Finished" or phase == "HalfTime"
		if lines and #lines > 0 and quietPhase then
			boardLabel.Text = table.concat(lines, "\n")
			boardFrame.Visible = true
		else
			boardFrame.Visible = false
		end
	end

	if phase == "Finished" and snap.result then
		resultLabel.Text = snap.result
		resultFrame.Visible = true
	else
		resultFrame.Visible = false
		if summaryLabel then
			summaryLabel.Visible = false -- reset; the next full-time sets it fresh
		end
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
	goalLabel.Text = ((team == "Red") and "▲ " or "● ") .. tostring(info and info.teamName or string.upper(team)) .. " GOAL!"
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

function HudUI.possession(mine, team)
	if not ballChip then
		return
	end
	if mine then
		ballChip.Text = "⚽ You have the ball!"
		ballChip.Visible = true
	elseif team == "Red" or team == "Blue" then
		ballChip.Text = (team == "Red") and "⚽ ▲ RED have it" or "⚽ ● BLUE have it"
		ballChip.Visible = true
	else
		ballChip.Visible = false -- loose ball: it's anyone's
	end
end

function HudUI.progression(data)
	if not gui or not data then
		return
	end
	local need = tonumber(data.xpNeed) or 1
	local into = tonumber(data.xpInto) or 0
	local frac = math.clamp(need > 0 and into / need or 1, 0, 1)
	TweenService:Create(xpFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(frac, 0, 1, 0),
	}):Play()
	local leagueName = data.league and data.league.name or nil
	xpText.Text = leagueName
		and ("%s  •  LV %d   %d / %d XP"):format(leagueName, data.level or 1, into, need)
		or ("LV %d   %d / %d XP"):format(data.level or 1, into, need)
	if lastLevel and (data.level or 1) > lastLevel then
		levelLabel.Text = ("⬆ LEVEL %d!"):format(data.level)
		levelLabel.Rotation = -6
		levelLabel.Visible = true
		TweenService:Create(levelLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		if dingSound then
			dingSound:Play()
		end
		task.delay(2.2, function()
			levelLabel.Visible = false
		end)
	end
	lastLevel = data.level or 1
end

-- toasts queue instead of overwriting (a goal + a nutmeg in the same second
-- used to eat each other); the queue stays short so messages never lag play
local toastQueue = {}
local toastShowing = false
local function showNextToast()
	local nextText = table.remove(toastQueue, 1)
	if nextText == nil then
		toastShowing = false
		if toastLabel then
			toastLabel.Visible = false
		end
		return
	end
	toastShowing = true
	toastLabel.Text = nextText
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	task.delay(2.1, showNextToast)
end

-- Full-time personal card: your own gains line, shown beneath the team result.
-- Always positive (you always earn at least the match-played XP), so even a loss
-- ends on progress. Lives inside the result banner, which only shows between
-- matches — it never touches the live play screen.
function HudUI.matchSummary(data)
	if not summaryLabel or not resultFrame or type(data) ~= "table" then
		return
	end
	local bits = {}
	if (tonumber(data.xpEarned) or 0) > 0 then
		bits[#bits + 1] = ("✨ +%d XP"):format(data.xpEarned)
	end
	if (tonumber(data.goals) or 0) > 0 then
		bits[#bits + 1] = ("⚽ %d"):format(data.goals)
	end
	if (tonumber(data.nutmegs) or 0) > 0 then
		bits[#bits + 1] = ("🪄 %d"):format(data.nutmegs)
	end
	bits[#bits + 1] = ("Level %d"):format(tonumber(data.level) or 1)
	summaryLabel.Text = table.concat(bits, "    ")
	-- dangle the next named unlock on its own line so even a loss ends with a reason
	-- to play one more
	local lvl = tonumber(data.level) or 1
	local nu = nextUnlock(lvl)
	if nu then
		local togo = nu.level - lvl
		summaryLabel.Text = summaryLabel.Text
			.. ("\n🔜 %s — %d level%s to go!"):format(nu.label, togo, (togo == 1) and "" or "s")
	end
	summaryLabel.Visible = true
	resultFrame.Visible = true
end

function HudUI.toast(text)
	if not toastLabel then
		return
	end
	if #toastQueue >= 3 then
		table.remove(toastQueue, 1) -- drop the oldest; stay current
	end
	table.insert(toastQueue, text or "")
	if not toastShowing then
		showNextToast()
	end
end

-- A transient "+N REASON" reward chip that rises from just above the XP bar and
-- fades out — it celebrates the big moments (goals, wins, nutmegs, promotions,
-- streaks) and then leaves NOTHING on screen, so the pitch stays clear. Quick
-- back-to-back rewards stagger upward so they never overlap.
local xpChipStack = 0
function HudUI.xpGain(amount, reason)
	if not gui or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local slot = xpChipStack
	xpChipStack += 1
	task.delay(0.85, function()
		xpChipStack = math.max(0, xpChipStack - 1)
	end)
	-- start just above the XP bar (which sits at bottom-right, -18 inset, 20 tall)
	local startY = -44 - slot * 28
	local chip = UiTheme.make("TextLabel", {
		Name = "XpChip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, startY),
		Size = UDim2.fromOffset(240, 28),
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(245, 196, 60),
		Text = ("+%d  %s"):format(amount, tostring(reason or "XP")),
		Parent = gui,
	})
	local s = UiTheme.stroke(C.Ink, 2.5, chip)
	local info = TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(chip, info, {
		Position = UDim2.new(1, -18, 1, startY - 52),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(s, info, { Transparency = 1 }):Play()
	task.delay(1.4, function()
		chip:Destroy()
	end)
end

return HudUI
