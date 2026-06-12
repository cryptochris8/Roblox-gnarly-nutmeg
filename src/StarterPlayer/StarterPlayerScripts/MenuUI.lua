-- MenuUI (client)
-- A compact team-picker (applies between matches), THE NUTMEG TROPHY nation
-- picker, and a controls hint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Nations = require(Shared:WaitForChild("Nations"))

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

	-- THE NUTMEG TROPHY: launch a tournament run as your chosen nation
	local startEvent = Remotes.get(Remotes.StartTournament)
	local gold = Color3.fromRGB(245, 196, 60)
	local trophyBtn = UiTheme.make("TextButton", {
		Position = UDim2.fromOffset(18, 122),
		Size = UDim2.fromOffset(184, 40),
		BackgroundColor3 = gold,
		Font = UiTheme.Header,
		TextSize = 15,
		TextColor3 = C.Ink,
		Text = "🏆 NUTMEG TROPHY",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(12, trophyBtn)

	-- scale-based with a hard cap so the picker also fits phone screens
	local picker = UiTheme.make("Frame", {
		Name = "NationPicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 0),
		Size = UDim2.new(0.92, 0, 0.78, 0),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(540, 380)
	sizeCap.Parent = picker
	UiTheme.corner(18, picker)
	local pickerTitle = UiTheme.make("TextLabel", {
		Name = "PickerTitle",
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 20,
		TextColor3 = gold,
		Text = "🏆 PICK YOUR NATION",
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = picker,
	})
	local closeBtn = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.Track,
		Font = UiTheme.Header,
		TextSize = 16,
		TextColor3 = C.Panel,
		Text = "✕",
		Parent = picker,
	})
	UiTheme.corner(8, closeBtn)
	closeBtn.MouseButton1Click:Connect(function()
		picker.Visible = false
	end)

	local grid = UiTheme.make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 1, -64),
		Parent = picker,
	})
	local layout = Instance.new("UIGridLayout")
	-- scale cells: always a 4-wide grid, so the 16 nations fit ANY screen
	layout.CellSize = UDim2.new(0.25, -6, 0.25, -6)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid

	for _, nation in ipairs(Nations.List) do
		local c = nation.color
		local bright = c.R * 0.299 + c.G * 0.587 + c.B * 0.114 > 0.55
		local b = UiTheme.make("TextButton", {
			BackgroundColor3 = c,
			Font = UiTheme.Header,
			TextSize = 14,
			TextScaled = true,
			TextColor3 = bright and C.Ink or C.Panel,
			Text = nation.name,
			AutoButtonColor = true,
			Parent = grid,
		})
		UiTheme.corner(10, b)
		b.MouseButton1Click:Connect(function()
			startEvent:FireServer(nation.name)
			picker.Visible = false
		end)
	end

	trophyBtn.MouseButton1Click:Connect(function()
		picker.Visible = not picker.Visible
	end)

	-- someone is hosting a cup: pop the picker for EVERYONE with a countdown,
	-- so friends in the server can claim their nation and join the bracket
	local lobbyGen = 0
	Remotes.get(Remotes.TournamentLobby).OnClientEvent:Connect(function(info)
		lobbyGen += 1
		local gen = lobbyGen
		if type(info) == "table" and info.open then
			picker.Visible = true
			local deadline = os.clock() + (tonumber(info.seconds) or 20)
			local host = tostring(info.host or "Someone")
			task.spawn(function()
				while gen == lobbyGen and picker.Parent do
					local left = math.max(0, math.ceil(deadline - os.clock()))
					pickerTitle.Text = ("🏆 %s IS HOSTING — CLAIM A NATION!  (%ds)"):format(host, left)
					if left <= 0 then
						break
					end
					task.wait(0.25)
				end
			end)
		else
			picker.Visible = false
			pickerTitle.Text = "🏆 PICK YOUR NATION"
		end
	end)

	-- Desktop controls hint (hidden on touch devices, which have on-screen buttons)
	if not UserInputService.TouchEnabled then
		UiTheme.make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -44),
			Size = UDim2.fromOffset(680, 22),
			BackgroundTransparency = 1,
			Font = UiTheme.Body,
			TextSize = 15,
			TextColor3 = C.Panel,
			Text = "Hold LMB = Shoot   •   E = Pass   •   Q = Nutmeg   •   F = Tackle   •   Shift = Sprint",
			Parent = gui,
		}).TextStrokeTransparency = 0.4
	end
end

return MenuUI
