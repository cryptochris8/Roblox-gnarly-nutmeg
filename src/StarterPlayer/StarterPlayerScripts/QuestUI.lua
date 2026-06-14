-- QuestUI (client)
-- The daily quests panel: three rotating dailies with live progress, the login
-- streak, and the skill-move unlock list. Toggled by the 📋 button; data comes
-- from the server's ProgressionSync snapshots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared:WaitForChild("Skills"))

local UiTheme = require(script.Parent.UiTheme)
local C = UiTheme.Colors

local QuestUI = {}

local panel
local streakLabel
local leagueLabel
local careerLine1
local careerLine2
local rows = {}
local skillLabels = {}
local lastData = nil

function QuestUI.mount(playerGui)
	local gui = UiTheme.make("ScreenGui", {
		Name = "GnarlyQuests",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = playerGui,
	})

	-- mobile: a compact 📋 icon in the top-left row; desktop: a labelled button
	-- below the Locker (was colliding with the Locker button at y=170)
	local touch = UserInputService.TouchEnabled
	local toggle = UiTheme.make("TextButton", {
		Position = UDim2.fromOffset(touch and 110 or 18, touch and 82 or 218),
		Size = UDim2.fromOffset(touch and 44 or 184, 40),
		BackgroundColor3 = Color3.fromRGB(90, 200, 140),
		Font = UiTheme.Header,
		TextSize = touch and 20 or 15,
		TextColor3 = C.Ink,
		Text = touch and "📋" or "📋 DAILY QUESTS",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(12, toggle)

	-- anchored to the vertical middle so it also fits short phone screens
	panel = UiTheme.make("Frame", {
		Name = "QuestPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.52, 0),
		Size = UDim2.fromOffset(320, 446),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.06,
		Visible = false,
		Parent = gui,
	})
	UiTheme.corner(16, panel)

	streakLabel = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 170, 80),
		Text = "🔥 Login streak: —",
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	leagueLabel = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(245, 196, 60),
		Text = "🏅 League: —",
		Position = UDim2.fromOffset(16, 32),
		Size = UDim2.new(1, -32, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	for i = 1, 3 do
		local y = 62 + (i - 1) * 64
		local rowText = UiTheme.make("TextLabel", {
			BackgroundTransparency = 1,
			Font = UiTheme.Body,
			TextSize = 15,
			TextColor3 = C.Panel,
			Text = "",
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -90, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = panel,
		})
		local xpTag = UiTheme.make("TextLabel", {
			BackgroundTransparency = 1,
			Font = UiTheme.Header,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(245, 196, 60),
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, y),
			Size = UDim2.fromOffset(70, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = panel,
		})
		local barBg = UiTheme.make("Frame", {
			Position = UDim2.fromOffset(16, y + 24),
			Size = UDim2.new(1, -90, 0, 12),
			BackgroundColor3 = C.Track,
			Parent = panel,
		})
		UiTheme.corner(6, barBg)
		local barFill = UiTheme.make("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(90, 200, 140),
			Parent = barBg,
		})
		UiTheme.corner(6, barFill)
		local progText = UiTheme.make("TextLabel", {
			BackgroundTransparency = 1,
			Font = UiTheme.Body,
			TextSize = 13,
			TextColor3 = C.Panel,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, y + 22),
			Size = UDim2.fromOffset(70, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = panel,
		})
		rows[i] = { text = rowText, xp = xpTag, fill = barFill, prog = progText }
	end

	-- skill unlock list
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 14,
		TextColor3 = C.Sub,
		Text = "SKILL MOVES",
		Position = UDim2.fromOffset(16, 256),
		Size = UDim2.new(1, -32, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	for i, s in ipairs(Skills.List) do
		skillLabels[i] = UiTheme.make("TextLabel", {
			BackgroundTransparency = 1,
			Font = UiTheme.Body,
			TextSize = 14,
			TextColor3 = C.Sub,
			Text = ("🔒 %s — Level %d  [%s]"):format(s.name, s.unlockLevel, s.key.Name),
			Position = UDim2.fromOffset(16, 274 + (i - 1) * 22),
			Size = UDim2.new(1, -32, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = panel,
		})
	end

	-- career cabinet: lifetime numbers from the persisted profile
	-- (sits below the skill list, which is 5 rows tall now)
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 14,
		TextColor3 = C.Sub,
		Text = "CAREER",
		Position = UDim2.fromOffset(16, 388),
		Size = UDim2.new(1, -32, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	careerLine1 = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 14,
		TextColor3 = C.Panel,
		Text = "",
		Position = UDim2.fromOffset(16, 406),
		Size = UDim2.new(1, -32, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	careerLine2 = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 14,
		TextColor3 = C.Panel,
		Text = "",
		Position = UDim2.fromOffset(16, 424),
		Size = UDim2.new(1, -32, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	toggle.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible and lastData then
			QuestUI.progression(lastData)
		end
	end)
end

function QuestUI.progression(data)
	lastData = data
	if not panel then
		return
	end
	streakLabel.Text = ("🔥 Login streak: Day %d"):format(tonumber(data.streak) or 0)
	local lg = data.league
	if lg and leagueLabel then
		local needW = math.max((lg.promoteAt or 3) - (lg.wins or 0), 0)
		leagueLabel.Text = ("🏅 League: %s — %d more win%s to climb"):format(
			tostring(lg.name), needW, needW == 1 and "" or "s")
	end
	for i = 1, 3 do
		local q = data.quests and data.quests[i]
		local row = rows[i]
		if q then
			row.text.Text = (q.done and "✅ " or "• ") .. tostring(q.text)
			row.xp.Text = ("+%d XP"):format(q.xp or 0)
			row.prog.Text = q.done and "DONE" or ("%d / %d"):format(q.progress or 0, q.target or 1)
			row.fill.Size = UDim2.new(math.clamp((q.progress or 0) / math.max(q.target or 1, 1), 0, 1), 0, 1, 0)
			row.fill.BackgroundColor3 = q.done and Color3.fromRGB(245, 196, 60) or Color3.fromRGB(90, 200, 140)
		else
			row.text.Text = ""
			row.xp.Text = ""
			row.prog.Text = ""
			row.fill.Size = UDim2.new(0, 0, 1, 0)
		end
	end
	local level = tonumber(data.level) or 1
	for i, s in ipairs(Skills.List) do
		local unlocked = level >= s.unlockLevel
		skillLabels[i].Text = ("%s %s — Level %d  [%s]"):format(unlocked and "🔓" or "🔒", s.name, s.unlockLevel, s.key.Name)
		skillLabels[i].TextColor3 = unlocked and C.Panel or C.Sub
	end
	local c = data.career
	if c and careerLine1 and careerLine2 then
		careerLine1.Text = ("📊 %dW - %dD - %dL  •  %d goal%s"):format(
			tonumber(c.wins) or 0, tonumber(c.draws) or 0, tonumber(c.losses) or 0,
			tonumber(c.goals) or 0, (tonumber(c.goals) or 0) == 1 and "" or "s")
		careerLine2.Text = ("👟 %d nutmegs  •  🏆 %d troph%s  •  %d matches"):format(
			tonumber(c.nutmegs) or 0, tonumber(c.trophies) or 0,
			(tonumber(c.trophies) or 0) == 1 and "y" or "ies", tonumber(c.matches) or 0)
	end
end

return QuestUI
